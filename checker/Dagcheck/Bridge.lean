/-
Dagcheck.Bridge: JSON report and provenance builders over the validated Registry.
Both artifacts are DERIVED from the type files; they are never independently writable.
-/
import Dagcheck.Registry

namespace Dagcheck

/-- Minimal JSON quoting (control chars below 0x20 become spaces). -/
def jStr (s : String) : String :=
  let esc := s.foldl (fun acc c => acc ++ match c with
    | '"' => "\\\"" | '\\' => "\\\\" | '\n' => "\\n" | '\r' => "\\r" | '\t' => "\\t"
    | c => if c.val < 0x20 then " " else String.singleton c) ""
  "\"" ++ esc ++ "\""

def jArr (xs : List String) : String := "[" ++ String.intercalate "," xs ++ "]"
def jStrArr (xs : List String) : String := jArr (xs.map jStr)
def jObj (ps : List (String × String)) : String :=
  "{" ++ String.intercalate "," (ps.map fun p => jStr p.1 ++ ":" ++ p.2) ++ "}"
def jNum (n : Nat) : String := toString n
def jNull : String := "null"
def jOptStr : Option String → String | some s => jStr s | none => jNull

def kindName : EdgeKind → String
  | .cites => "cites" | .depends => "depends" | .supersedes => "supersedes"

def dateJson (d : Date) : String :=
  jStr s!"{d.y}-{if d.m < 10 then "0" else ""}{d.m}-{if d.d < 10 then "0" else ""}{d.d}"

/-- Per-entry content fingerprint: hashText over the entry's authoritative content fields.
    Freshness binding only (staleness/recheck), not security. Derived, never stored. -/
def entryFingerprint (e : Entry) : String :=
  let canon := String.intercalate "\n"
    [e.id, e.type.typeName, e.status.statusName, e.label, e.statement,
     toString e.derivedFrom, toString e.dependsOn, e.inferenceRule.getD "",
     e.proofConfidence.getD "", reprStr e.form]
  toString (hashText canon)

def findingJson (f : Finding) : String :=
  jObj [("level", jStr f.level), ("code", jStr f.code), ("detail", jStr f.detail)]

def verdictJson (v : Verdict) : String := jObj
  [("id", jStr v.id), ("verdict", jStr v.verdict), ("reason", jStr v.reason),
   ("rule", jOptStr v.rule), ("assumptions", jStrArr v.assumptions)]

def entryJson (e : Entry) (verdict? : Option Verdict) : String := jObj
  [("id", jStr e.id), ("type", jStr e.type.typeName),
   ("status", jStr (Registry.effectiveStatus e).statusName),
   ("label", jStr e.label),
   ("fingerprint", jStr (entryFingerprint e)),
   ("stale_now", if e.staleNow then "true" else "false"),
   ("verdict", match verdict? with | some v => jStr v.verdict | none => jNull)]

/-- All graph edges, same construction as globalChecks (kept in sync: derived_from and
    depends_on are dependency edges; superseded_by is a history edge, src = successor). -/
def registryEdges (r : Registry) : List GEdge :=
  r.all.flatMap (fun e =>
    (e.derivedFrom.map (fun d => ⟨EdgeKind.cites, e.id, d⟩)) ++
    (e.dependsOn.map (fun d => ⟨EdgeKind.depends, e.id, d⟩)) ++
    (match e.supersededBy with | some s => [⟨EdgeKind.supersedes, s, e.id⟩] | none => []))

/-- Full check report. `parseFs` are load/parse findings; everything else is derived here. -/
def reportJson (r : Registry) (parseFs staleFs : List Finding) (today? : Option Date)
    (dir : String) : String :=
  let structural := globalChecks r
  let atomFs := atomTableChecks r
  let (consResult, consFs) := consistencyCheck r 20
  let verdicts := verifyTheorems r
  let allFs := parseFs ++ staleFs ++ structural ++ atomFs ++ consFs
  let nErr := (allFs.filter (fun f => f.level == "error")).length
  let nWarn := (allFs.filter (fun f => f.level == "warning")).length
  let nBad := (verdicts.filter (fun v => v.verdict == "rejected" || v.verdict == "blocked")).length
  let edges := registryEdges r
  jObj
    [("report", jStr "dagcheck/v1"), ("registry_dir", jStr dir),
     ("today", match today? with | some d => dateJson d | none => jNull),
     ("entries_loaded", jNum r.entries.length), ("tombstones", jNum r.tombstones.length),
     ("atom_table_entries", jNum r.atomTable.length),
     ("counts", jObj [("errors", jNum nErr), ("warnings", jNum nWarn),
        ("rejected_or_blocked_verdicts", jNum nBad)]),
     ("consistency", jStr consResult),
     ("findings", jArr (allFs.map findingJson)),
     ("verdicts", jArr (verdicts.map verdictJson)),
     ("entries", jArr (r.all.map fun e =>
        entryJson e (verdicts.find? (fun v => v.id == e.id)))),
     ("graph", jObj [("nodes", jNum r.all.length), ("edges", jNum edges.length),
        ("dependency_cycle_nodes", jStrArr (depCycleNodes edges)),
        ("supersedes_cycle_nodes", jStrArr (supersedesCycleNodes edges))])]

/-- provenance.json: the canonical serialization of the derivation graph (graph model). -/
def provenanceJson (r : Registry) (today? : Option Date) (dir : String) : String :=
  let edges := registryEdges r
  let ids := r.all.map Entry.id
  let edgeJson (g : GEdge) : String :=
    jObj [("kind", jStr (kindName g.kind)), ("from", jStr g.src), ("to", jStr g.dst)]
  let nodeJson (e : Entry) : String := jObj
    [("id", jStr e.id), ("type", jStr e.type.typeName),
     ("status", jStr (Registry.effectiveStatus e).statusName),
     ("label", jStr e.label), ("fingerprint", jStr (entryFingerprint e))]
  jObj
    [("spec", jStr "dagcheck-provenance/v1"), ("generated_from", jStr dir),
     ("today", match today? with | some d => dateJson d | none => jNull),
     ("nodes", jArr (r.all.map nodeJson)),
     ("edges", jArr (edges.map edgeJson)),
     ("upstream", jObj (ids.map fun n => (n, jStrArr (upstreamOf edges depKinds n)))),
     ("blast_radius", jObj (ids.map fun n => (n, jStrArr (blastRadiusOf edges depKinds n)))),
     ("cycles", jObj [("dependency", jStrArr (depCycleNodes edges)),
        ("supersedes", jStrArr (supersedesCycleNodes edges))]),
     ("notes", jStrArr
        ["DERIVED artifact: regenerate after any registry change; authoritative content lives in the type-file fields. This file is never independently writable.",
         "cites/depends are dependency edges; supersedes (superseded_by) is a HISTORY edge and never enters dependency closures or dependency cycles.",
         "upstream[id]: everything id transitively depends on. blast_radius[id]: everything that transitively cites id. A changed fingerprint means the blast radius NEEDS RECHECK - never a claim of invalidity or of changed runtime behavior.",
         "fingerprint: non-cryptographic hashText over the entry's authoritative content fields; identical content keeps its fingerprint across label/id renames."])]
end Dagcheck
