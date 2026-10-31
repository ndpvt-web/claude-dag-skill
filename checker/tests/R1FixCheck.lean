import Dagcheck.Consist
import Dagcheck.Graph
import Dagcheck.Dates
namespace Dagcheck
def P : Form := .atom "P"
def Q : Form := .atom "Q"
def R : Form := .atom "R"
def Fresh : Form := .atom "Fresh"
def reg1 : List (String × Form) := [("A1", .imp P Q), ("H1", P), ("A2", .imp Q R)]

-- unchanged regressions from reviewer probes
theorem rv_valid : (checkDeriv reg1
  [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
   { id := "T2", conclusion := R, rule := .mp, cites := ["A2", "T1"] }]).isSome = true := by decide
theorem rv_wrong : checkDeriv reg1 [{ id := "T1", conclusion := R, rule := .mp, cites := ["A1", "H1"] }] = none := by decide
theorem rv_unknown : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["A9", "H1"] }] = none := by decide
theorem rv_cycle : checkDeriv reg1
  [{ id := "T1", conclusion := Q, rule := .mp, cites := ["T2", "H1"] },
   { id := "T2", conclusion := Q, rule := .mp, cites := ["A1", "H1"] }] = none := by decide
theorem rv_fresh_disj : (checkDeriv reg1
  [{ id := "T9", conclusion := .disj P Fresh, rule := .disjIntroL, cites := ["H1"] }]).isSome = true := by decide
theorem rv_order : checkDeriv reg1 [{ id := "T1", conclusion := Q, rule := .mp, cites := ["H1", "A1"] }] = none := by decide

-- D3 fixed: duplicate step ids now REJECTED (was: silent shadow)
def stepsDup : List Step :=
  [ { id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
    { id := "T1", conclusion := .disj Q Q, rule := .disjIntroL, cites := ["T1"] } ]
#eval match checkDeriv reg1 stepsDup with | some _ => "ACCEPTED (bad)" | none => "rejected (fixed D3)"

-- D1 fixed: distinct atoms drive the dimension
#eval atomsOf [("A1", .imp P P)]                       -- fixed: ["P"]
#eval consistent [("A1", .imp P P)] 1                  -- fixed: ok true
#eval (List.range 25).map (fun i => (s!"H{i}", Form.imp P P)) |> atomsOf |>.length  -- fixed: 1
#eval consistent ((List.range 25).map (fun i => (s!"H{i}", Form.imp P P))) 20       -- fixed: ok true
#eval consistent [("A1", P), ("A2", .neg P)] 4         -- still: ok false
#eval consistent reg1 4                                -- still: ok true
#eval consistent reg1 0                                -- still: loud refusal

-- D2 fixed: closures complete regardless of caller node list (param removed)
def chainEdges : List GEdge :=
  [⟨.cites, "u", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "x4"⟩, ⟨.cites, "x4", "v"⟩]
#eval upstreamOf chainEdges depKinds "u"               -- fixed: full x1..x4,v
#eval blastRadiusOf chainEdges depKinds "x2"           -- u and x1 depend on x2
def cycEdges : List GEdge :=
  [⟨.cites, "a", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "a"⟩]
#eval depCycleNodes cycEdges                           -- fixed: [a, x1, x2, x3]

-- dates (reviewer cross-checked, kept as regressions)
#eval parseDate "2026-02-29"
#eval parseDate "2024-02-29"
#eval parseDate "2026-1-15"
#eval parseDate "2026-02-30"
#eval daysFromCivil 1970 1 1
#eval daysFromCivil 2026 10 31
end Dagcheck
