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
  -- CONTENT identity only: the fields a derivation actually depends on. Identity (id)
  -- and presentation (label) are excluded: a label edit must not stale anything, and
  -- IDs are permanent by policy (never renamed), so id stability is not implied here.
  -- Status is excluded: an under-review transition is registry state, not content drift.
  let canon := String.intercalate "\n"
    [e.type.typeName, e.statement, e.createdBy,
     toString e.derivedFrom, toString e.dependsOn, e.inferenceRule.getD "",
     e.proofConfidence.getD "", reprStr e.form]
  toString (hashText canon)

def findingJson (f : Finding) : String :=
  jObj [("level", jStr f.level), ("code", jStr f.code), ("detail", jStr f.detail)]

def verdictJson (v : Verdict) : String := jObj
  [("id", jStr v.id), ("verdict", jStr v.verdict), ("reason", jStr v.reason),
   ("rule", jOptStr v.rule), ("assumptions", jStrArr v.assumptions)]

/-- Entries whose upstream chain contains a drifted entry: their conditional derivations
    are unchanged (still valid given their premises), but the CURRENT accepted dependency
    state no longer supports them. They must never read as green. -/
def upstreamStale (edges : List GEdge) (staleIds : List String) : List String :=
  ((staleIds.flatMap (fun s => blastRadiusOf edges depKinds s)).eraseDups).filter (· ∉ staleIds)

def freshnessOf (staleIds upStale : List String) (baseline : Bool) (id : String) : String :=
  if id ∈ staleIds then "stale"
  else if id ∈ upStale then "upstream-stale"
  else if baseline then "current" else "untracked"

/-- What a consumer may act on: a drifted entry's prior verdict NEVER reads as green.
    The original verdict is preserved inside the reason. -/
def displayVerdict (staleIds upStale : List String) (v : Verdict) : Verdict :=
  if v.id ∈ staleIds then
    { v with verdict := "stale",
             reason := s!"content changed after the provenance baseline; prior verdict '{v.verdict}' no longer covers the new content - needs recheck (not a claim of invalidity)" }
  else if v.id ∈ upStale then
    { v with verdict := "upstream-stale",
             reason := s!"an upstream dependency changed after the provenance baseline; the conditional derivation is unchanged and remains valid given its premises, but the current accepted dependency state no longer supports it - needs recheck (prior verdict '{v.verdict}' preserved as context, not a current green; not a claim of invalidity)" }
  else v

def entryJson (staleIds upStale : List String) (baseline : Bool) (e : Entry) (verdict? : Option Verdict) : String := jObj
  [("id", jStr e.id), ("type", jStr e.type.typeName),
   ("status", jStr (Registry.effectiveStatus e).statusName),
   ("label", jStr e.label),
   ("fingerprint", jStr (entryFingerprint e)),
   ("freshness", jStr (freshnessOf staleIds upStale baseline e.id)),
   ("stale_now", if e.staleNow then "true" else "false"),
   ("verdict", match verdict? with | some v => jStr v.verdict | none => jNull)]

/-- All graph edges, same construction as globalChecks (kept in sync: derived_from and
    depends_on are dependency edges; superseded_by is a history edge, src = successor). -/
def registryEdges (r : Registry) : List GEdge :=
  r.all.flatMap (fun e =>
    (e.derivedFrom.map (fun d => ⟨EdgeKind.cites, e.id, d⟩)) ++
    (e.dependsOn.map (fun d => ⟨EdgeKind.depends, e.id, d⟩)) ++
    (match e.supersededBy with | some s => [⟨EdgeKind.supersedes, s, e.id⟩] | none => []))

/-- Coverage self-report: how much of the LIVE registry the checker can and did verify.
    Counts come from the type files (never the provenance baseline); tombstones are
    excluded from every active denominator; drifted theorems count under stale /
    upstream-stale (display verdicts), never as verified. -/
def coverageJson (r : Registry) (staleIds upStale : List String) (verdicts : List Verdict) : String :=
  let active := r.entries.filter (fun e => Registry.effectiveStatus e == .active)
  let underReview := r.entries.filter (fun e => Registry.effectiveStatus e == .underReview)
  let theorems := r.entries.filter (fun e => e.type == .theorem)
  let disp := verdicts.map (displayVerdict staleIds upStale)
  let cnt (s : String) : Nat := (disp.filter (fun v => v.verdict == s)).length
  let nVerified := cnt "verified"
  let machineCheckable := theorems.filter (fun e =>
    e.form.isSome && match e.inferenceRule with
      | some rn => (match ruleSpecOfName rn with | .outside _ => false | _ => true)
      | none => false)
  let usedAtoms := (active.flatMap (fun e => match e.form with | some f => atomsOfForm f | none => [])).eraseDups
  let declared := r.atomTable.map Prod.fst
  let unused := declared.filter (fun a => a ∉ usedAtoms)
  jObj
    [("scope", jStr "computed from the live registry type files (never the provenance baseline); tombstones excluded from active denominators; drifted theorems count as stale/upstream-stale, never as verified; unchecked is an honest non-verdict, not a pass"),
     ("entries_active", jNum active.length),
     ("entries_under_review", jNum underReview.length),
     ("tombstones", jNum r.tombstones.length),
     ("theorems_total", jNum theorems.length),
     ("theorem_verdicts", jObj
        [("verified", jNum nVerified), ("rejected", jNum (cnt "rejected")),
         ("blocked", jNum (cnt "blocked")), ("unchecked", jNum (cnt "unchecked")),
         ("stale", jNum (cnt "stale")), ("upstream_stale", jNum (cnt "upstream-stale")),
         ("no_verdict", jNum (theorems.length - disp.length))]),
     ("theorems_machine_checkable", jNum machineCheckable.length),
     ("machine_checkable_share_of_theorems", jStr (toString machineCheckable.length ++ "/" ++ toString theorems.length)),
     ("verified_share_of_machine_checkable", jStr (toString nVerified ++ "/" ++ toString machineCheckable.length)),
     ("atoms_declared", jNum declared.length),
     ("atoms_used_in_active_forms", jNum usedAtoms.length),
     ("atoms_declared_unused", jStrArr unused)]

/-- Full check report. `parseFs` are load/parse findings; everything else is derived here. -/
def reportJson (r : Registry) (parseFs staleFs : List Finding) (staleIds : List String)
    (baseline : Bool) (cap : Nat) (today? : Option Date) (dir : String) : String :=
  let structural := globalChecks r
  let atomFs := atomTableChecks r
  let (consResult, consFs) := consistencyCheck r cap
  let verdicts := verifyTheorems r
  let allFs := parseFs ++ staleFs ++ structural ++ atomFs ++ consFs
  let nErr := (allFs.filter (fun f => f.level == "error")).length
  let nWarn := (allFs.filter (fun f => f.level == "warning")).length
  let nBad := (verdicts.filter (fun v => v.verdict == "rejected" || v.verdict == "blocked")).length
  let edges := registryEdges r
  let upStale := upstreamStale edges staleIds
  jObj
    [("report", jStr "dagcheck/v1"), ("registry_dir", jStr dir),
     ("today", match today? with | some d => dateJson d | none => jNull),
     ("entries_loaded", jNum r.entries.length), ("tombstones", jNum r.tombstones.length),
     ("atom_table_entries", jNum r.atomTable.length),
     ("counts", jObj [("errors", jNum nErr), ("warnings", jNum nWarn),
        ("rejected_or_blocked_verdicts", jNum nBad)]),
     ("consistency", jStr consResult),
     ("findings", jArr (allFs.map findingJson)),
     ("verdicts", jArr ((verdicts.map (displayVerdict staleIds upStale)).map verdictJson)),
     ("entries", jArr (r.all.map fun e =>
        entryJson staleIds upStale baseline e
          ((verdicts.find? (fun v => v.id == e.id)).map (displayVerdict staleIds upStale)))),
     ("graph", jObj [("nodes", jNum r.all.length), ("edges", jNum edges.length),
        ("dependency_cycle_nodes", jStrArr (depCycleNodes edges)),
        ("supersedes_cycle_nodes", jStrArr (supersedesCycleNodes edges))]),
     ("coverage", coverageJson r staleIds upStale verdicts)]

/-- provenance.json: the canonical serialization of the derivation graph (graph model). -/
def provenanceJson (r : Registry) (staleIds : List String) (today? : Option Date) (dir : String) : String :=
  let edges := registryEdges r
  let upStale := upstreamStale edges staleIds
  let ids := r.all.map Entry.id
  let edgeJson (g : GEdge) : String :=
    jObj [("kind", jStr (kindName g.kind)), ("from", jStr g.src), ("to", jStr g.dst)]
  let verdicts := verifyTheorems r
  let nodeJson (e : Entry) : String := jObj
    [("id", jStr e.id), ("type", jStr e.type.typeName),
     ("status", jStr (Registry.effectiveStatus e).statusName),
     ("label", jStr e.label), ("fingerprint", jStr (entryFingerprint e)),
     ("stale_now", if e.staleNow then "true" else "false"),
     ("upstream_stale", if e.id ∈ upStale then "true" else "false"),
     ("freshness", jStr (freshnessOf staleIds upStale true e.id)),
     ("rule", jOptStr e.inferenceRule),
     ("confidence", jOptStr e.proofConfidence),
     ("verdict", match verdicts.find? (fun v => v.id == e.id) with
       | some v => jStr (displayVerdict staleIds upStale v).verdict
       | none => jNull)]
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
         "fingerprint: non-cryptographic hashText over the entry's CONTENT fields (type, statement, created_by, citations, rule, confidence, form) - the fields a derivation depends on. Label edits never drift it. IDs are permanent by policy and are never renamed.",
         "verdict is the checker's current result. confidence is the entry author's recorded self-assessment (CERTAIN/PROBABLE) from the registry type file - never a machine verdict; a verified verdict and a PROBABLE confidence say different things and neither upgrades the other."])]
end Dagcheck
