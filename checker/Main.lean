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
def driftFindings (dir : String) (reg : Registry) : IO (List Finding) := do
  let path := s!"{dir}/provenance.json"
  if !(← System.FilePath.pathExists path) then
    return [finfo "no-baseline" "no provenance.json baseline; run `dagcheck graph <dir> > <dir>/provenance.json` and commit it to enable freshness tracking"]
  let content ← IO.FS.readFile path
  match parseJsonStrict content with
  | .error e => return [fwarn "bad-baseline" s!"provenance.json is not strict JSON ({e}); regenerate it with `dagcheck graph`"]
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
    return driftFs ++ remFs ++ newFs

/-- Decode a check-step --step object. -/
def parseStepArg (s : String) : Except String (String × Form × String × List String) := do
  let j ← parseJsonStrict s
  let id ← (j.getObjVal? "id" >>= Lean.Json.getStr?).mapError (fun e => s!"step.id: {e}")
  let cj ← (j.getObjVal? "conclusion").mapError (fun e => s!"step.conclusion: {e}")
  let concl ← formOfJson cj |>.mapError (fun e => s!"step.conclusion: {e}")
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
   "  dagcheck check <registry-dir> [--today YYYY-MM-DD]",
   "  dagcheck graph <registry-dir> [--today YYYY-MM-DD]",
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
                let envAll := reg.entries.filterMap (fun (e : Entry) =>
                  if Registry.effectiveStatus e == Status.active then e.form.map (fun f => (e.id, f)) else none)
                let missing := cites.filter (fun c => !(envAll.any (fun p => p.1 == c)))
                if !missing.isEmpty then
                  IO.println (jObj [("verdict", jStr "unchecked"),
                    ("reason", jStr s!"cited ids lack active checkable encodings: {missing}")])
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
          let driftFs ← driftFindings dir reg
          IO.println (reportJson reg (loadFs ++ driftFs) [] today? dir)
          -- loadFs already includes parse/stale; count errors across full finding set
          let structural := globalChecks reg
          let atomFs := atomTableChecks reg
          let (_, consFs) := consistencyCheck reg 20
          let verdicts := verifyTheorems reg
          let allFs := loadFs ++ driftFs ++ structural ++ atomFs ++ consFs
          let nErr := (allFs.filter (fun f => f.level == "error")).length
          let nBad := (verdicts.filter (fun v => v.verdict == "rejected" || v.verdict == "blocked")).length
          return if nErr + nBad > 0 then 1 else 0
        else
          IO.println (provenanceJson reg today? dir)
          return if loadFs.any (fun f => f.level == "error") then 1 else 0
  | [] => IO.eprintln usage; return 2
