import Dagcheck.Graph
import Dagcheck.Dates
import Dagcheck.JsonStrict
import Dagcheck.Consist
-- Registry model + validation for .dag/registry/*.json. The checker NEVER mutates the
-- registry: it reads, validates, verifies derivations, and reports. All writes stay with
-- the skill's checked commands.
namespace Dagcheck

open Lean (Json JsonNumber)

inductive EntryType where
  | definition | hypothesis | axiom | theorem | tombstone
  deriving DecidableEq, BEq, Repr

def EntryType.typeName : EntryType → String
  | .definition => "definition" | .hypothesis => "hypothesis" | .axiom => "axiom"
  | .theorem => "theorem" | .tombstone => "tombstone"

inductive Status where
  | active | underReview | deprecated
  deriving DecidableEq, BEq, Repr

def Status.statusName : Status → String
  | .active => "active" | .underReview => "under-review" | .deprecated => "deprecated"

structure Entry where
  id : String
  type : EntryType
  status : Status
  label : String
  statement : String
  derivedFrom : List String := []
  dependsOn : List String := []
  supersededBy : Option String := none
  inferenceRule : Option String := none
  proofConfidence : Option String := none
  form : Option Form := none
  created : Option Date := none
  stalenessDays : Option Nat := none
  lastReview : Option Date := none
  staleNow : Bool := false
  deriving Repr

structure Finding where
  level : String   -- "error" | "warning" | "info"
  code : String
  detail : String
  deriving Repr

def ferr (code detail : String) : Finding := ⟨"error", code, detail⟩
def fwarn (code detail : String) : Finding := ⟨"warning", code, detail⟩
def finfo (code detail : String) : Finding := ⟨"info", code, detail⟩

-- ---------- JSON form encoding (explicit translation artifact per entry) ----------
-- {"atom":"P"} | {"neg":F} | {"imp":[F,G]} | {"conj":[F,G]} | {"disj":[F,G]}

partial def formOfJson (j : Json) : Except String Form := do
  let keys := (["atom", "neg", "imp", "conj", "disj"] : List String).filter
    (fun k => (j.getObjVal? k).toOption.isSome)
  match keys with
  | ["atom"] =>
    let n ← (j.getObjVal? "atom" >>= Json.getStr?).mapError (fun e => s!"form.atom: {e}")
    .ok (.atom n)
  | ["neg"] => .neg <$> formOfJson (← j.getObjVal? "neg")
  | ["imp"] =>
    let arr ← (← j.getObjVal? "imp").getArr?
    match arr[0]?, arr[1]?, arr[2]? with
    | some a, some b, none => .imp <$> formOfJson a <*> formOfJson b
    | _, _, _ => .error "form.imp expects exactly [a, b]"
  | ["conj"] =>
    let arr ← (← j.getObjVal? "conj").getArr?
    match arr[0]?, arr[1]?, arr[2]? with
    | some a, some b, none => .conj <$> formOfJson a <*> formOfJson b
    | _, _, _ => .error "form.conj expects exactly [a, b]"
  | ["disj"] =>
    let arr ← (← j.getObjVal? "disj").getArr?
    match arr[0]?, arr[1]?, arr[2]? with
    | some a, some b, none => .disj <$> formOfJson a <*> formOfJson b
    | _, _, _ => .error "form.disj expects exactly [a, b]"
  | _ => .error "form: object with exactly one of atom/neg/imp/conj/disj required"

def atomsOfJsonForm (f : Form) : List String := atomsOfForm f

-- ---------- rule names (registry-spec table) ----------

inductive RuleSpec where
  | single (r : Rule)
  | conjElimEither
  | disjIntroEither
  | outside (name : String)
  deriving Repr

/-- Map registry-spec rule names to the verified fragment. Anything else - including
    instantiation and analogy, which the repo's table lists but the fragment does not
    cover - is OUTSIDE: reported as unchecked, never silently certified. -/
def ruleSpecOfName (s : String) : RuleSpec :=
  match s.toLower with
  | "modus ponens" => .single .mp
  | "modus tollens" => .single .mt
  | "transitivity" => .single .trans
  | "conjunction intro" | "conjunction introduction" => .single .conjIntro
  | "conjunction elim" | "conjunction elim left" => .conjElimEither
  | "conjunction elim right" => .single .conjElimR
  | "disjunction intro" | "disjunction introduction" => .disjIntroEither
  | "disjunction intro right" => .single .disjIntroR
  | "contrapositive" => .single .contra
  | "dilemma" => .single .dilemma
  | name => .outside name

-- ---------- entry parsing ----------

private def reqStr (ctx : String) (j : Json) (k : String) : Except String String :=
  (j.getObjVal? k >>= Json.getStr?).mapError (fun e => s!"{ctx}: field '{k}': {e}")

private def optStrList (j : Json) (k : String) : Except String (List String) :=
  match (j.getObjVal? k).toOption with
  | none => .ok []
  | some v =>
    match v.getArr? with
    | .error e => .error s!"field '{k}': {e}"
    | .ok arr =>
      arr.toList.mapM (fun x => x.getStr?.mapError (fun e => s!"field '{k}': {e}"))

def idSchemeOk (id : String) (pre : Char) : Bool :=
  match id.toList with
  | c :: rest => c == pre && rest.length ≥ 1 && rest.all Char.isDigit
  | [] => false

def prefixOf : EntryType → Char
  | .definition => 'D' | .hypothesis => 'H' | .axiom => 'A' | .theorem => 'T' | .tombstone => ' '

def parseStatus (ctx : String) (s : String) : Except String Status :=
  match s with
  | "active" => .ok .active
  | "under-review" => .ok .underReview
  | other => .error s!"{ctx}: bad status '{other}' (expected active | under-review)"

/-- Parse one entry of a type file. `ctx` names the file for error messages. -/
partial def parseEntry (ctx : String) (t : EntryType) (key : String) (j : Json) : Except String Entry := do
  let ectx := s!"{ctx}[{key}]"
  let id ← reqStr ectx j "id"
  if id != key then throw s!"{ectx}: object key '{key}' does not match id field '{id}'"
  let typeStr ← reqStr ectx j "type"
  if typeStr != t.typeName then
    throw s!"{ectx}: type '{typeStr}' in {t.typeName} file"
  if !idSchemeOk id (prefixOf t) then
    throw s!"{ectx}: id '{id}' violates the {prefixOf t}<digits> scheme"
  let label ← reqStr ectx j "label"
  let statement ← reqStr ectx j "statement"
  let status ← parseStatus ectx (← reqStr ectx j "status")
  let createdS ← reqStr ectx j "created"
  let created ← match parseDate createdS with
    | some d => .ok d
    | none => .error s!"{ectx}: bad created date '{createdS}' (strict YYYY-MM-DD)"
  let derivedFrom ← optStrList j "derived_from"
  let dependsOn ← optStrList j "depends_on"
  let inferenceRule := (j.getObjVal? "inference_rule").toOption.bind (·.getStr?.toOption)
  let proofConfidence := (j.getObjVal? "proof_confidence").toOption.bind (·.getStr?.toOption)
  let form ← match (j.getObjVal? "form").toOption with
    | none => .ok none
    | some fj => some <$> formOfJson fj |>.mapError (fun e => s!"{ectx}: {e}")
  -- type-specific mandatory fields
  match t with
  | .axiom =>
    let r ← reqStr ectx j "rationale"
    if r.isEmpty then throw s!"{ectx}: axiom rationale must be non-empty"
  | .hypothesis =>
    let f ← reqStr ectx j "falsification"
    if f.isEmpty then throw s!"{ectx}: hypothesis falsification must be non-empty"
    let _ ← reqStr ectx j "review_trigger"
  | .theorem =>
    if derivedFrom.isEmpty then throw s!"{ectx}: theorem derived_from must be non-empty"
    match inferenceRule with
    | none => throw s!"{ectx}: theorem inference_rule required"
    | some _ => pure ()
  | _ => pure ()
  -- H staleness inputs
  let stalenessDays ← match (j.getObjVal? "staleness_period_days").toOption with
    | none => .ok none
    | some v =>
      if v.isNull then .ok none
      else match v.getNum? with
        | .error e => .error s!"{ectx}: staleness_period_days: {e}"
        | .ok n =>
          if n.exponent == 0 && n.mantissa ≥ 0 then .ok (some n.mantissa.toNat)
          else .error s!"{ectx}: staleness_period_days must be a non-negative integer or null"
  let lastReview ← match (j.getObjVal? "review_log").toOption with
    | none => .ok none
    | some v =>
      match v.getArr? with
      | .error e => .error s!"{ectx}: review_log: {e}"
      | .ok arr =>
        arr.toList.foldlM (fun (acc : Option Date) x => do
          let ds ← reqStr ectx x "date"
          match parseDate ds with
          | none => .error s!"{ectx}: bad review_log date '{ds}'"
          | some d =>
            match acc with
            | none => .ok (some d)
            | some a => .ok (some (if daysFromCivil d.y d.m d.d > daysFromCivil a.y a.m a.d then d else a))) none
  return { id, type := t, status, label, statement, derivedFrom, dependsOn,
           inferenceRule, proofConfidence, form, created := some created,
           stalenessDays, lastReview }

/-- Parse a tombstone from deprecated.json (different field set; status fixed deprecated). -/
def parseTombstone (ctx : String) (key : String) (j : Json) : Except String Entry := do
  let ectx := s!"{ctx}[{key}]"
  let id ← reqStr ectx j "id"
  if id != key then throw s!"{ectx}: object key '{key}' does not match id field '{id}'"
  let typeStr ← reqStr ectx j "type"
  let origType ← match typeStr with
    | "definition" => .ok EntryType.definition
    | "hypothesis" => .ok EntryType.hypothesis
    | "axiom" => .ok EntryType.axiom
    | "theorem" => .ok EntryType.theorem
    | other => .error s!"{ectx}: bad tombstone type '{other}'"
  if !idSchemeOk id (prefixOf origType) then
    throw s!"{ectx}: id '{id}' violates the {prefixOf origType}<digits> scheme"
  let statement ← reqStr ectx j "original_statement"
  let _ ← reqStr ectx j "deprecated_on" >>= fun ds =>
    match parseDate ds with
    | some _ => .ok ""
    | none => .error s!"{ectx}: bad deprecated_on date '{ds}'"
  let _ ← reqStr ectx j "reason"
  let supersededBy := (j.getObjVal? "superseded_by").toOption.bind (·.getStr?.toOption)
  return { id, type := .tombstone, status := .deprecated, label := "", statement,
           supersededBy }

def objEntries (j : Json) : Except String (List (String × Json)) :=
  (·.toList) <$> j.getObj?

partial def parseTypeFile (fname : String) (t : EntryType) (content : String) : Except String (List Entry) := do
  let j ← parseJsonStrict content |>.mapError (fun e => s!"{fname}: {e}")
  let entries ← objEntries j |>.mapError (fun e => s!"{fname}: top level must be an object keyed by ID: {e}")
  entries.mapM (fun (k, v) => parseEntry fname t k v)

def parseDeprecatedFile (fname : String) (content : String) : Except String (List Entry) := do
  let j ← parseJsonStrict content |>.mapError (fun e => s!"{fname}: {e}")
  let entries ← objEntries j |>.mapError (fun e => s!"{fname}: top level must be an object keyed by ID: {e}")
  entries.mapM (fun (k, v) => parseTombstone fname k v)

def parseAtomTable (fname : String) (content : String) : Except String (List (String × String)) := do
  let j ← parseJsonStrict content |>.mapError (fun e => s!"{fname}: {e}")
  let entries ← objEntries j |>.mapError (fun e => s!"{fname}: top level must be an object: {e}")
  entries.mapM (fun (k, v) => do
    let s ← v.getStr?.mapError (fun e => s!"{fname}[{k}]: {e}")
    return (k, s))

structure RawFiles where
  axioms : String
  definitions : String
  hypotheses : String
  theorems : String
  deprecated : Option String := none
  logic : Option String := none

structure Registry where
  entries : List Entry
  tombstones : List Entry
  atomTable : List (String × String)
  deriving Repr

def Registry.all (r : Registry) : List Entry := r.entries ++ r.tombstones

/-- Parse all files; per-file parse failures become error findings (other files still load). -/
partial def loadRegistry (files : RawFiles) : Registry × List Finding :=
  let go (fname : String) (t : EntryType) (content : String) : List Entry × List Finding :=
    match parseTypeFile fname t content with
    | .ok es => (es, [])
    | .error e => ([], [ferr "parse" e])
  let (as, f1) := go "axioms.json" .axiom files.axioms
  let (ds, f2) := go "definitions.json" .definition files.definitions
  let (hs, f3) := go "hypotheses.json" .hypothesis files.hypotheses
  let (ts, f4) := go "theorems.json" .theorem files.theorems
  let (tombs, f5) := match files.deprecated with
    | none => ([], [])
    | some c =>
      match parseDeprecatedFile "deprecated.json" c with
      | .ok es => (es, [])
      | .error e => ([], [ferr "parse" e])
  let (table, f6) := match files.logic with
    | none => ([], [])
    | some c =>
      match parseAtomTable "logic.json" c with
      | .ok ps => (ps, [])
      | .error e => ([], [ferr "parse" e])
  (⟨as ++ ds ++ hs ++ ts, tombs, table⟩, f1 ++ f2 ++ f3 ++ f4 ++ f5 ++ f6)

-- ---------- global validation ----------

/-- Apply the staleness policy against `today`; returns updated entries + transition findings. -/
def applyStaleness (today : Date) (es : List Entry) : List Entry × List Finding :=
  es.foldl (fun (acc : List Entry × List Finding) e =>
    let (done, fs) := acc
    match e.type, e.status, e.stalenessDays, e.created with
    | .hypothesis, .active, some period, some created =>
      let lastActivity := e.lastReview.getD created
      if staleBy today lastActivity period then
        (done ++ [{ e with staleNow := true }],
         fs ++ [finfo "staleness" s!"{e.id}: auto-transition to under-review (last activity {lastActivity.y}-{lastActivity.m}-{lastActivity.d} + {period}d < today); blocked from citation until /dag review"])
      else (done ++ [e], fs)
    | _, _, _, _ => (done ++ [e], fs)) ([], [])

def Registry.effectiveStatus (e : Entry) : Status :=
  if e.staleNow then .underReview else e.status

/-- Global structural checks. Edge-type discipline: dependency cycles over cites+depends
    only; supersedes checked separately as history. -/
def globalChecks (r : Registry) : List Finding :=
  let all := r.all
  let ids := all.map Entry.id
  -- ID uniqueness across ALL files including tombstones (R7 shadowing gap, now hard error)
  let dupFindings :=
    ids.foldl (fun (acc : List String × List Finding) id =>
      let (seen, fs) := acc
      if id ∈ seen then (seen, fs ++ [ferr "duplicate-id" s!"id '{id}' appears more than once across registry files (including deprecated.json); IDs are permanent and never reused"])
      else (id :: seen, fs)) ([], []) |>.2
  let activeById (id : String) : Option Entry := all.find? (fun e => e.id == id)
  -- citation integrity: cited IDs must exist and be citable (active, not stale, not tombstoned)
  let citeFindings := r.entries.flatMap (fun e =>
    (e.derivedFrom ++ e.dependsOn).flatMap (fun d =>
      match activeById d with
      | none => [ferr "citation" s!"{e.id} cites unknown id '{d}'"]
      | some t =>
        if t.type == .tombstone then
          [ferr "citation" s!"{e.id} cites deprecated id '{d}' (tombstoned); blocked"]
        else if Registry.effectiveStatus t != .active then
          [ferr "citation" s!"{e.id} cites '{d}' which is { (Registry.effectiveStatus t).statusName }; blocked from citation"]
        else []))
  -- supersession integrity
  let supFindings := r.tombstones.flatMap (fun t =>
    match t.supersededBy with
    | none => []
    | some s =>
      match r.entries.find? (fun e => e.id == s) with
      | some _ => []
      | none => [ferr "supersession" s!"tombstone {t.id}: superseded_by '{s}' does not name an active entry"])
  -- edges: cites/depends from every entry; supersedes from tombstones
  let edges : List GEdge :=
    all.flatMap (fun e =>
      (e.derivedFrom.map (fun d => ⟨EdgeKind.cites, e.id, d⟩)) ++
      (e.dependsOn.map (fun d => ⟨EdgeKind.depends, e.id, d⟩)) ++
      (match e.supersededBy with | some s => [⟨EdgeKind.supersedes, s, e.id⟩] | none => []))
  let cycleFs := (depCycleNodes edges).map (fun u => ferr "cycle" s!"dependency cycle involving '{u}' (cites/depends edges)")
  let supCycleFs := (supersedesCycleNodes edges).map (fun u => ferr "supersession-cycle" s!"supersedes cycle involving '{u}' (history edges)")
  -- confidence plumbing
  let confFs := r.entries.flatMap (fun e =>
    match e.type with
    | .theorem =>
      let base :=
        match e.proofConfidence with
        | some "CERTAIN" | some "PROBABLE" => []
        | some "UNCERTAIN" => [ferr "confidence" s!"{e.id}: UNCERTAIN blocks write; a registry containing it is invalid"]
        | some other => [ferr "confidence" s!"{e.id}: bad proof_confidence '{other}'"]
        | none => [ferr "confidence" s!"{e.id}: theorem missing proof_confidence"]
      let analogyCap :=
        match e.inferenceRule with
        | some name =>
          match ruleSpecOfName name with
          | .outside "analogy" =>
            if e.proofConfidence == some "CERTAIN" then
              [ferr "confidence" s!"{e.id}: analogy is capped at PROBABLE; CERTAIN not permitted"]
            else []
          | _ => []
        | none => []
      base ++ analogyCap
    | _ => [])
  dupFindings ++ citeFindings ++ supFindings ++ cycleFs ++ supCycleFs ++ confFs

/-- Atom-table coverage: the bridge-level enforcement of the soundness theorem's coverage
    hypothesis. Any form using an atom missing from logic.json is an ERROR, so no checked
    step can ever evaluate an unassigned atom. Same statement under two names: warn only
    (possible encoding collision; faithfulness itself stays outside the kernel). -/
def atomTableChecks (r : Registry) : List Finding :=
  let names := r.atomTable.map Prod.fst
  let missing := r.entries.flatMap (fun e =>
    match e.form with
    | none => []
    | some f =>
      (atomsOfForm f).filter (fun a => a ∉ names) |>.map (fun a =>
        ferr "unmapped-atom" s!"{e.id}: form uses atom '{a}' with no entry in logic.json; encoding incomplete"))
  let statements := r.atomTable.map Prod.snd
  let collisions := r.atomTable.flatMap (fun (n, s) =>
    if (r.atomTable.any (fun (n2, s2) => n2 != n && s2 == s)) then
      [fwarn "encoding-collision" s!"atom '{n}' shares its statement text with another atom name; possible encoding collision"]
    else [])
  let _ := statements
  missing ++ collisions

-- ---------- derivation verification ----------

structure Verdict where
  id : String
  verdict : String       -- "verified" | "rejected" | "unchecked" | "blocked"
  reason : String
  rule : Option String
  assumptions : List String
  deriving Repr

/-- Topological passes over active theorems (cycles already rejected upstream).
    Deterministic: does not depend on JSON object key order (review D5). -/
def orderTheorems (allTs : List Entry) (baseIds : List String) : List Entry :=
  let tIds := allTs.map Entry.id
  let rec go : Nat → List String → List Entry → List Entry
    | 0, _, acc => acc
    | n + 1, doneIds, acc =>
      let remaining := allTs.filter (fun e => e.id ∉ acc.map Entry.id)
      let (ready, _) := remaining.partition (fun e => e.derivedFrom.all (fun d => d ∈ doneIds || d ∉ tIds))
      if ready.isEmpty then acc ++ remaining
      else go n (doneIds ++ ready.map Entry.id) (acc ++ ready)
  go (allTs.length + 1) baseIds []

/-- Verify each active theorem as a single rule step against the active encoded environment.
    CITATION ORDER: the derived_from JSON array order IS the citation order handed to the
    rule (JSON arrays are ordered and the strict parser preserves them); a rule whose
    premises arrive in the wrong order for its shape is REJECTED with reason - the agent
    writing the entry must order cites per the registry-spec rule table (review D5: no
    silent reordering, no unsupported narrowing).
    VERIFIED requires: rule inside the fragment, all cites active and encoded, and (for
    cited theorems) themselves verified. Anything else is explicit: rejected (defect),
    unchecked (outside fragment or missing encoding), or blocked (bad citations). -/
def verifyTheorems (r : Registry) : List Verdict :=
  let activeNonT := r.entries.filter (fun e => e.type != .theorem && Registry.effectiveStatus e == .active)
  let activeTs := r.entries.filter (fun e => e.type == .theorem && e.status == .active && !e.staleNow)
  let ordered := orderTheorems activeTs (activeNonT.map Entry.id)
  let env0 : List (String × Form) := activeNonT.filterMap (fun e => e.form.map (fun f => (e.id, f)))
  let step (env : List (String × Form)) (verifiedIds : List String) (e : Entry) : Verdict × List (String × Form) × List String :=
    let cites := e.derivedFrom
    let bad := cites.filter (fun c =>
      match r.all.find? (fun x => x.id == c) with
      | none => true
      | some t => t.type == .tombstone || Registry.effectiveStatus t != .active)
    if !bad.isEmpty then
      (⟨e.id, "blocked", s!"cites blocked ids: {bad}", e.inferenceRule, cites⟩, env, verifiedIds)
    else
      match e.inferenceRule with
      | none => (⟨e.id, "unchecked", "no inference_rule recorded", none, cites⟩, env, verifiedIds)
      | some name =>
        match ruleSpecOfName name with
        | .outside out =>
          (⟨e.id, "unchecked", s!"rule '{out}' is outside the verified propositional fragment; left explicitly unchecked", some name, cites⟩, env, verifiedIds)
        | spec =>
          let missingForm := cites.filter (fun c => !(env.any (fun p => p.1 == c)))
          if !missingForm.isEmpty then
            (⟨e.id, "unchecked", s!"cited entries lack checkable encodings or verified status: {missingForm}", some name, cites⟩, env, verifiedIds)
          else
            match e.form with
            | none => (⟨e.id, "unchecked", "theorem has no encoded form", some name, cites⟩, env, verifiedIds)
            | some concl =>
              let mkStep (rule : Rule) : Step := ⟨e.id, concl, rule, cites⟩
              let attempt : Option Rule := match spec with
                | .single rule => if applyRule env (mkStep rule) == some concl then some rule else none
                | .conjElimEither =>
                  if applyRule env (mkStep .conjElimL) == some concl then some .conjElimL
                  else if applyRule env (mkStep .conjElimR) == some concl then some .conjElimR
                  else none
                | .disjIntroEither =>
                  if applyRule env (mkStep .disjIntroL) == some concl then some .disjIntroL
                  else if applyRule env (mkStep .disjIntroR) == some concl then some .disjIntroR
                  else none
                | .outside _ => none
              match attempt with
              | some _ =>
                (⟨e.id, "verified", "rule step checks against the encoded active environment (conditional on premise encodings and the atom table)", some name, cites⟩,
                 env ++ [(e.id, concl)], verifiedIds ++ [e.id])
              | none =>
                (⟨e.id, "rejected", s!"rule '{name}' does not derive the stated conclusion from the cited premises", some name, cites⟩, env, verifiedIds)
  let rec loop (env : List (String × Form)) (vids : List String) : List Entry → List Verdict
    | [] => []
    | e :: rest =>
      let (v, env', vids') := step env vids e
      v :: loop env' vids' rest
  loop env0 [] ordered

/-- Consistency of the encoded active subset, bounded and auto-dimensioned. -/
def consistencyCheck (r : Registry) (cap : Nat) : String × List Finding :=
  let encoded := r.entries.filterMap (fun e =>
    if Registry.effectiveStatus e == .active then e.form.map (fun f => (e.id, f)) else none)
  if encoded.isEmpty then ("skipped-no-encodings", [finfo "consistency" "no encoded entries; consistency check skipped"])
  else
    match consistent encoded cap with
    | .ok true => ("consistent", [finfo "consistency" s!"encoded active subset ({encoded.length} entries) is consistent"])
    | .ok false =>
      ("inconsistent", [ferr "consistency" s!"ENCODED ACTIVE SUBSET INCONSISTENT: no valuation over its own atoms satisfies all of {encoded.map Prod.fst}. This says the encodings cannot all hold; it does NOT license deriving arbitrary conclusions (single failed derivations prove no nonderivability)."])
    | .error msg => ("refused-over-cap", [fwarn "consistency-over-cap" msg])

/-- Non-cryptographic content fingerprint for freshness binding (staleness detection, not
    security). 64-bit polynomial hash over the exact file text. -/
def hashText (s : String) : Nat :=
  s.toList.foldl (fun h c => (h * 131 + c.toNat) % 0x10000000000000000) 5381

end Dagcheck
