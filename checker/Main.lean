/-
dagcheck CLI. READ-ONLY over the registry: it never writes, renames or deletes files.

  dagcheck check <registry-dir> [--today YYYY-MM-DD]
  dagcheck graph <registry-dir> [--today YYYY-MM-DD]
  dagcheck check-step <registry-dir> --premises '["A1","H1"]'
      --step '{"id":"T9","conclusion":<form-json>,"rule":"modus ponens","cites":["A1","H1"]}'
-/
import Dagcheck.Bridge

namespace Dagcheck

def getFlag : List String → String → Option String
  | a :: b :: tail, name => if a == name then some b else getFlag (b :: tail) name
  | _, _ => none

def getToday (args : List String) : Except String (Option Date) :=
  match getFlag args "--today" with
  | none => .ok none
  | some s => match parseDate s with
    | some d => .ok (some d)
    | none => .error s!"invalid --today '{s}'; expected strict YYYY-MM-DD"

def stripFlags : List String → List String
  | "--today" :: _ :: rest => stripFlags rest
  | "--premises" :: _ :: rest => stripFlags rest
  | "--step" :: _ :: rest => stripFlags rest
  | "--cap" :: _ :: rest => stripFlags rest
  | a :: rest => a :: stripFlags rest
  | [] => []

/-- Read the six registry files from a directory. Missing required type file = error
    finding with empty object content; deprecated/logic are optional. -/
def readRawFiles (dir : String) : IO (RawFiles × List Finding) := do
  let readReq (fname : String) : IO (String × List Finding) := do
    let path := s!"{dir}/{fname}"
    if ← System.FilePath.pathExists path then
      return (← IO.FS.readFile path, [])
    else
      return ("{}", [ferr "missing-file" s!"required registry file '{fname}' not found in {dir}"])
  let readOpt (fname : String) : IO (Option String) := do
    let path := s!"{dir}/{fname}"
    if ← System.FilePath.pathExists path then some <$> IO.FS.readFile path else return none
  let (ax, f1) ← readReq "axioms.json"
  let (df, f2) ← readReq "definitions.json"
  let (hy, f3) ← readReq "hypotheses.json"
  let (th, f4) ← readReq "theorems.json"
  let dep ← readOpt "deprecated.json"
  let log ← readOpt "logic.json"
  return (⟨ax, df, hy, th, dep, log⟩, f1 ++ f2 ++ f3 ++ f4)

/-- Load + validate a registry directory: parse, apply staleness for `today?`, return the
    effective registry and the load-time findings. -/
def loadDir (dir : String) (today? : Option Date) : IO (Registry × List Finding) := do
  let (raw, missFs) ← readRawFiles dir
  let (reg0, parseFs) := loadRegistry raw
  let (es, staleFs) := match today? with
    | some today => applyStaleness today reg0.entries
    | none => (reg0.entries, [])
  return ({ reg0 with entries := es }, missFs ++ parseFs ++ staleFs)

/-- Freshness drift: compare live content fingerprints against the committed provenance
    baseline (<dir>/provenance.json). Drift NEVER claims invalidity; it names exactly which
    entries changed and whose verification therefore needs recheck. -/
def driftFindings (dir : String) (reg : Registry) : IO (List Finding × List String) := do
  let path := s!"{dir}/provenance.json"
  if !(← System.FilePath.pathExists path) then
    return ([finfo "no-baseline" "no provenance.json baseline; run `dagcheck graph <dir> --out <dir>/provenance.json` and commit it to enable freshness tracking (atomic; never shell-redirect onto a live baseline)"], [])
  let content ← IO.FS.readFile path
  match parseJsonStrict content with
  | .error e => return ([fwarn "bad-baseline" s!"provenance.json is not strict JSON ({e}); regenerate it with `dagcheck graph`"], [])
  | .ok j =>
    let nodes := match (j.getObjVal? "nodes").toOption with
      | some (.arr arr) => arr.toList
      | _ => []
    let base : List (String × String) := nodes.filterMap (fun n =>
      match (n.getObjVal? "id").toOption.bind (·.getStr?.toOption),
            (n.getObjVal? "fingerprint").toOption.bind (·.getStr?.toOption) with
      | some id, some fp => some (id, fp)
      | _, _ => none)
    let edges := registryEdges reg
    let cur := reg.all.map (fun e => (e.id, entryFingerprint e))
    let drifted := cur.filter (fun (id, fp) =>
      match base.find? (fun b => b.1 == id) with
      | some (_, bfp) => bfp != fp
      | none => false)
    let removed := base.filter (fun (id, _) => !(cur.any (fun c => c.1 == id)))
    let newIds := cur.filter (fun (id, _) => !(base.any (fun b => b.1 == id)))
    let driftFs := drifted.map (fun (id, _) =>
      let blast := blastRadiusOf edges depKinds id
      fwarn "stale-fingerprint" s!"{id}: content changed after the provenance baseline; {id} and its blast radius {blast} need recheck - drift says nothing about validity, only that prior verification no longer covers the new content")
    let remFs := removed.map (fun (id, _) =>
      fwarn "stale-fingerprint" s!"{id}: present in baseline but gone from the registry; entries that cited it need recheck")
    let newFs := newIds.map (fun (id, _) =>
      finfo "new-since-baseline" s!"{id}: not in the provenance baseline yet; regenerate provenance.json after review")
    return (driftFs ++ remFs ++ newFs, drifted.map Prod.fst)

/-- Decode a check-step --step object. -/
def parseStepArg (s : String) : Except String (String × Form × String × List String) := do
  let j ← parseJsonStrict s
  let id ← (j.getObjVal? "id" >>= Lean.Json.getStr?).mapError (fun e => s!"step.id: {e}")
  let cj ← (j.getObjVal? "conclusion").mapError (fun e => s!"step.conclusion: {e}")
  let concl ← (Prod.fst <$> formOfJson formBudget cj) |>.mapError (fun e => s!"step.conclusion: {e}")
  let rule ← (j.getObjVal? "rule" >>= Lean.Json.getStr?).mapError (fun e => s!"step.rule: {e}")
  let cites ← match (j.getObjVal? "cites").toOption with
    | none => .error "step.cites: required"
    | some v =>
      match v.getArr? with
      | .error e => .error s!"step.cites: {e}"
      | .ok arr => arr.toList.mapM (fun x => x.getStr?.mapError (fun e => s!"step.cites: {e}"))
  return (id, concl, rule, cites)

def usage : String := String.intercalate "\n"
  ["dagcheck - verified checker for the DAG registry (read-only)",
   "  dagcheck check <registry-dir> [--today YYYY-MM-DD] [--cap N]",
   "  dagcheck graph <registry-dir> [--today YYYY-MM-DD] [--out PATH (atomic temp+rename; shell > redirection onto a live baseline truncates it before this binary runs - never do that)]",
   "  dagcheck check-step <registry-dir> --premises '<json-array-of-ids>' --step '<json-object>'"]

end Dagcheck

open Dagcheck in
def main (args : List String) : IO UInt32 := do
  match args with
  | cmd :: rest =>
    if cmd != "check" && cmd != "graph" && cmd != "check-step" then
      IO.eprintln usage; return 2
    let dir? := (stripFlags rest).head?
    match dir?, getToday rest with
    | _, .error e => IO.eprintln e; return 2
    | none, _ => IO.eprintln usage; return 2
    | some dir, .ok today? =>
      if cmd == "check-step" then
        match getFlag rest "--premises", getFlag rest "--step" with
        | some pjson, some sjson =>
          match parseJsonStrict pjson with
          | .error e => IO.eprintln s!"--premises: {e}"; return 2
          | .ok pj =>
            let pids? := match pj.getArr? with
              | .ok arr => some (arr.toList.filterMap (fun (x : Lean.Json) => x.getStr?.toOption))
              | .error _ => none
            match pids?, parseStepArg sjson with
            | none, _ => IO.eprintln "--premises must be a JSON array of entry ids"; return 2
            | _, .error e => IO.eprintln e; return 2
            | some pids, .ok (sid, concl, rname, cites) =>
              let (reg, loadFs) ← loadDir dir today?
              if loadFs.any (fun f => f.level == "error") then
                IO.eprintln "registry has load errors; fix them before check-step"
                return 2
              -- D9: --premises is the declared environment for this step. Every cite must
              -- be listed there; the check uses exactly those premises, never more.
              let undeclared := cites.filter (fun c => c ∉ pids)
              if !undeclared.isEmpty then
                IO.eprintln s!"--step cites {undeclared} not listed in --premises; the declared premise set must cover every citation"
                return 2
              -- D12: a step resting on drifted content is never green. A stale premise
              -- (or one downstream of stale content) makes the step needs-recheck: the
              -- conditional rule check would still be valid given the premises, but the
              -- current accepted dependency state no longer supports it.
              let (_, staleIds) ← driftFindings dir reg
              let upStale := upstreamStale (registryEdges reg) staleIds
              let staleP := pids.filter (fun p => p ∈ staleIds)
              let upStaleP := pids.filter (fun p => p ∈ upStale)
              if !staleP.isEmpty then
                IO.println (jObj [("verdict", jStr "stale"),
                  ("reason", jStr s!"premises {staleP} changed after the provenance baseline - needs recheck (not a claim of invalidity)"),
                  ("assumptions", jStrArr cites)])
                return 1
              if !upStaleP.isEmpty then
                IO.println (jObj [("verdict", jStr "upstream-stale"),
                  ("reason", jStr s!"premises {upStaleP} depend on content that changed after the provenance baseline; the conditional check would be valid given the premises, but the current accepted dependency state no longer supports it - needs recheck"),
                  ("assumptions", jStrArr cites)])
                return 1
              match ruleSpecOfName rname with
              | .outside out =>
                IO.println (jObj [("verdict", jStr "unchecked"),
                  ("reason", jStr s!"rule '{out}' is outside the verified propositional fragment")])
                return 2
              | spec =>
                let table := reg.atomTable.map Prod.fst
                let stepAtoms := atomsOfForm concl
                let undeclared := stepAtoms.filter (fun a => a ∉ table)
                if !undeclared.isEmpty then
                  IO.println (jObj [("verdict", jStr "rejected"),
                    ("reason", jStr s!"unmapped atom(s) {undeclared}: absent from logic.json; encoding incomplete")])
                  return 1
                -- D11: the environment is exactly the --premises entries, and a theorem
                -- enters it ONLY with a verified derivation - the same prerequisite
                -- discipline as the full checker. No green chains on rejected work.
                let verdicts := verifyTheorems reg
                let usable (e : Entry) : Bool :=
                  Registry.effectiveStatus e == Status.active &&
                  match e.type with
                  | .theorem => verdicts.any (fun v => v.id == e.id && v.verdict == "verified")
                  | _ => true
                let envAll := pids.filterMap (fun pid =>
                  match reg.entries.find? (fun e => e.id == pid) with
                  | some e => if usable e then e.form.map (fun f => (e.id, f)) else none
                  | none => none)
                let missing := cites.filter (fun c => !(envAll.any (fun p => p.1 == c)))
                if !missing.isEmpty then
                  let why := missing.map (fun c =>
                    match reg.entries.find? (fun e => e.id == c) with
                    | none => s!"{c}: unknown id"
                    | some e =>
                      if Registry.effectiveStatus e != Status.active then
                        s!"{c}: {(Registry.effectiveStatus e).statusName}, blocked from citation"
                      else if e.type == EntryType.theorem then
                        match verdicts.find? (fun v => v.id == c) with
                        | some v => s!"{c}: theorem verdict is {v.verdict}, not verified"
                        | none => s!"{c}: theorem has no verdict"
                      else s!"{c}: no checkable encoding (form)")
                  IO.println (jObj [("verdict", jStr "unchecked"),
                    ("reason", jStr ("premises unusable: " ++ String.intercalate "; " why))])
                  return 2
                let attempt : Option Rule := match spec with
                  | .single rule =>
                    if applyRule envAll ⟨sid, concl, rule, cites⟩ == some concl then some rule else none
                  | .conjElimEither =>
                    if applyRule envAll ⟨sid, concl, .conjElimL, cites⟩ == some concl then some .conjElimL
                    else if applyRule envAll ⟨sid, concl, .conjElimR, cites⟩ == some concl then some .conjElimR
                    else none
                  | .disjIntroEither =>
                    if applyRule envAll ⟨sid, concl, .disjIntroL, cites⟩ == some concl then some .disjIntroL
                    else if applyRule envAll ⟨sid, concl, .disjIntroR, cites⟩ == some concl then some .disjIntroR
                    else none
                  | .outside _ => none
                match attempt with
                | some _ =>
                  IO.println (jObj [("verdict", jStr "verified"),
                    ("reason", jStr "rule step checks against the encoded active environment (conditional on premise encodings and the atom table)"),
                    ("assumptions", jStrArr cites)])
                  return 0
                | none =>
                  IO.println (jObj [("verdict", jStr "rejected"),
                    ("reason", jStr s!"rule '{rname}' does not derive the stated conclusion from the cited premises (citation order is rule-argument order)")])
                  return 1
        | _, _ => IO.eprintln usage; return 2
      else
        let (reg, loadFs) ← loadDir dir today?
        if cmd == "check" then
          let capRaw := match getFlag rest "--cap" with
            | some s => s.toNat?.getD 20
            | none => 20
          -- ceiling: enumeration is 2^n and materialized; never let a flag turn the
          -- checker into a memory bomb (same defect class as the exponent attack)
          if capRaw > 20 then
            IO.eprintln s!"--cap {capRaw} unsupported: ceiling is 20 (2^20 enumeration is the memory bound); split the registry or reduce distinct atoms"
            return 2
          let cap := capRaw
          let (driftFs, staleIds) ← driftFindings dir reg
          let baseline := ← System.FilePath.pathExists s!"{dir}/provenance.json"
          IO.println (reportJson reg (loadFs ++ driftFs) [] staleIds baseline cap today? dir)
          -- loadFs already includes parse/stale; count errors across full finding set
          let structural := globalChecks reg
          let atomFs := atomTableChecks reg
          let (_, consFs) := consistencyCheck reg cap
          let verdicts := verifyTheorems reg
          let allFs := loadFs ++ driftFs ++ structural ++ atomFs ++ consFs
          let nErr := (allFs.filter (fun f => f.level == "error")).length
          let nBad := (verdicts.filter (fun v => v.verdict == "rejected" || v.verdict == "blocked")).length
          return if nErr + nBad > 0 then 1 else 0
        else
          -- fail closed: an empty/missing registry must never emit an "empty" artifact
          -- that a redirect could mistake for a real provenance baseline
          if reg.entries.isEmpty && reg.tombstones.isEmpty then
            IO.eprintln s!"no registry entries loaded from {dir} (missing or empty registry); refusing to emit a provenance artifact"
            return 2
          let (_, staleIds) ← driftFindings dir reg
          let prov := provenanceJson reg staleIds today? dir
          match getFlag rest "--out" with
          | some outPath =>
            -- atomic: temp file + rename on success only. A failed generation never
            -- truncates an existing baseline (shell `>` redirection would, BEFORE this
            -- binary runs - never redirect onto a live provenance.json).
            let tmp := outPath ++ ".tmp"
            IO.FS.writeFile tmp prov
            IO.FS.rename tmp outPath
            IO.eprintln s!"wrote {outPath} ({reg.all.length} nodes)"
            return 0
          | none =>
            IO.println prov
          return if loadFs.any (fun f => f.level == "error") then 1 else 0
  | [] => IO.eprintln usage; return 2
