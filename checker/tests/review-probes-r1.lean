-- INDEPENDENT REVIEW PROBES (reviewer-authored, not builder).
-- Each probe labeled with the expectation under review.
import Dagcheck.Consist
import Dagcheck.Graph
import Dagcheck.Dates

namespace Dagcheck
open Dagcheck

def P : Form := .atom "P"
def Q : Form := .atom "Q"
def R : Form := .atom "R"
def Fresh : Form := .atom "Fresh" -- deliberately NOT in any premise

def reg1 : List (String × Form) := [("A1", .imp P Q), ("H1", P), ("A2", .imp Q R)]

-- R1 regression: valid MP chain accepted
theorem rv_valid : (checkDeriv reg1
  [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
   { id := "T2", conclusion := R, rule := .mp, cites := ["A2", "T1"] }]).isSome = true := by decide

-- R2 wrong rule rejected
theorem rv_wrong : checkDeriv reg1 [{ id := "T1", conclusion := R, rule := .mp, cites := ["A1", "H1"] }] = none := by decide

-- R3 unknown premise rejected
theorem rv_unknown : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A9", "H1"] }] = none := by decide

-- R4 forward reference (cycle shape) rejected
theorem rv_cycle : checkDeriv reg1
  [{ id := "T1", conclusion := Q, rule := .mp, cites := ["T2", "H1"] },
   { id := "T2", conclusion := Q, rule := .mp, cites := ["A1", "H1"] }] = none := by decide

-- R5 PROBE: bare core ACCEPTS a disjIntro whose conclusion carries an atom
-- present in NO premise and NO atom table (coverage enforcement is bridge-side only,
-- and the bridge is not in this snapshot).
theorem rv_fresh_disj : (checkDeriv reg1
  [{ id := "T9", conclusion := .disj P Fresh, rule := .disjIntroL, cites := ["H1"] }]).isSome = true := by decide

-- R6 PROBE: duplicate step IDs inside one derivation silently shadow (lookupF first-match).
def stepsDup : List Step :=
  [ { id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
    { id := "T1", conclusion := .disj Q Q, rule := .disjIntroL, cites := ["T1"] } ]
#eval match checkDeriv reg1 stepsDup with
  | some env => reprStr (lookupF env "T1")   -- reviewer expectation: some (disj Q Q) = NEWER shadows OLDER
  | none => "rejected"

-- R7 consistency verdicts
#eval consistent [("A1", P), ("A2", .neg P)] 4  -- expect Except.ok false
#eval consistent reg1 4                          -- expect Except.ok true
#eval consistent reg1 0  -- expect explicit refusal error

-- R8 PROBE: duplicate atom occurrences inflate the enumeration dimension.
-- One tautological premise P->P already counts atom P TWICE.
#eval atomsOf [("A1", .imp P P)]                       -- expect ["P", "P"]
#eval consistent [("A1", .imp P P)] 1                  -- cap 1: REFUSED although 1 distinct atom suffices
#eval (List.range 25).map (fun i => (s!"H{i}", Form.imp P P)) |> atomsOf |>.length  -- 50 atoms for ONE distinct name
#eval consistent ((List.range 25).map (fun i => (s!"H{i}", Form.imp P P))) 20        -- refused: 50 > 20

-- R9 PROBE: graph closures silently truncate when edges reference nodes outside `nodes`.
def chainEdges : List GEdge :=
  [⟨.cites, "u", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "x4"⟩, ⟨.cites, "x4", "v"⟩]
#eval upstreamOf ["u"] chainEdges depKinds "u"                 -- fuel = 1+1 = 2 -> expect TRUNCATED [x1, x2]; true closure is x1..x4,v
#eval upstreamOf ["u","x1","x2","x3","x4","v"] chainEdges depKinds "u"  -- full node list -> full closure

-- R10 PROBE: dependency cycle hidden when it routes through >=3 unlisted nodes.
def cycEdges : List GEdge :=
  [⟨.cites, "a", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "a"⟩]
#eval depCycleNodes ["a"] cycEdges                  -- expect [] : cycle MISSED
#eval depCycleNodes ["a","x1","x2","x3"] cycEdges   -- expect [a, x1, x2, x3] : detected with full nodes

-- R11 cite order is significant: swapped MP premises rejected (document, bridge must canonicalize or explain)
theorem rv_order : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["H1", "A1"] }] = none := by decide

-- R12 dates
#eval parseDate "2026-02-29"   -- expect none (2026 not leap)
#eval parseDate "2024-02-29"   -- expect some
#eval parseDate "2026-1-15"    -- expect none (strict 4-2-2)
#eval parseDate "2026-02-30"   -- expect none
#eval daysFromCivil 1970 1 1   -- expect 0
#eval daysFromCivil 2026 10 31 -- expect 20757 (python cross-check)
#eval daysFromCivil 1900 3 1   -- python: (1900-03-01 - 1970-01-01).days = -25507
#eval staleBy ⟨2026, 1, 31⟩ ⟨2026, 1, 1⟩ 30  -- 30 > 30 = false (not yet stale)
#eval staleBy ⟨2026, 2, 1⟩ ⟨2026, 1, 1⟩ 30   -- 31 > 30 = true (stale)

-- R13 explosion discipline: one failed MP attempt from {P, ~P}; rejection, nothing more
theorem rv_expl : checkDeriv [("A1", P), ("A2", .neg P)]
  [{ id := "T1", conclusion := R, rule := .mp, cites := ["A1", "A2"] }] = none := by decide

-- R14 self-citation rejected (id not yet known)
theorem rv_self : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "T1"] }] = none := by decide

-- R15 wrong arity rejected
theorem rv_arity : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1", "A2"] }] = none := by decide

-- R16 empty premise set is (vacuously) consistent
#eval consistent ([] : List (String × Form)) 0

-- R17 more date cross-checks (python-verified values in review notes)
#eval daysFromCivil 2024 2 29
#eval daysFromCivil 2000 2 29
#eval daysFromCivil 1900 3 1

end Dagcheck
