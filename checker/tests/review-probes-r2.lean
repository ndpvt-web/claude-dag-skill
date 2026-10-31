-- INDEPENDENT REVIEW PROBES R2 (reviewer-authored, against fixed library).
import Dagcheck.Consist
import Dagcheck.Graph
import Dagcheck.Dates

namespace Dagcheck

def P : Form := .atom "P"
def Q : Form := .atom "Q"
def R : Form := .atom "R"
def reg1 : List (String × Form) := [("A1", .imp P Q), ("H1", P), ("A2", .imp Q R)]

-- K1: D3 fixed - duplicate step id rejected
theorem k1 : checkDeriv reg1
  [ { id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
    { id := "T1", conclusion := .disj Q Q, rule := .disjIntroL, cites := ["T1"] } ] = none := by decide

-- K2: step id colliding with a PREMISE id rejected
theorem k2 : checkDeriv reg1
  [ { id := "A1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] } ] = none := by decide

-- K3: regression - valid chain still accepted
theorem k3 : (checkDeriv reg1
  [ { id := "T1", conclusion := Q, rule := .mp, cites := ["A1", "H1"] },
    { id := "T2", conclusion := R, rule := .mp, cites := ["A2", "T1"] } ]).isSome = true := by decide

-- K4: bare core still accepts fresh-atom disjIntro (bridge contract; documented)
theorem k4 : (checkDeriv reg1
  [ { id := "T9", conclusion := .disj P (.atom "Fresh"), rule := .disjIntroL, cites := ["H1"] } ]).isSome = true := by decide

-- K5: D2 fixed - closures endpoint-driven, no node list
def chainEdges : List GEdge :=
  [⟨.cites, "u", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "x4"⟩, ⟨.cites, "x4", "v"⟩]
theorem k5 : upstreamOf chainEdges depKinds "u" = ["x1", "x2", "x3", "x4", "v"] := by decide

-- K6: D2 fixed - cycle through unlisted nodes detected
def cycEdges : List GEdge :=
  [⟨.cites, "a", "x1"⟩, ⟨.cites, "x1", "x2"⟩, ⟨.cites, "x2", "x3"⟩, ⟨.cites, "x3", "a"⟩]
theorem k6 : depCycleNodes cycEdges = ["a", "x1", "x2", "x3"] := by decide

-- K7: history edges never enter dependency closures
def mixEdges : List GEdge :=
  [⟨.supersedes, "A2", "A1"⟩, ⟨.cites, "T1", "A1"⟩]
theorem k7a : upstreamOf mixEdges depKinds "A2" = [] := by decide
theorem k7b : blastRadiusOf mixEdges depKinds "A1" = ["T1"] := by decide
theorem k7c : depCycleNodes [⟨.supersedes, "A2", "A1"⟩, ⟨.supersedes, "A1", "A2"⟩] = [] := by decide
theorem k7d : supersedesCycleNodes [⟨.supersedes, "A2", "A1"⟩, ⟨.supersedes, "A1", "A2"⟩] = ["A2", "A1"] := by decide

-- K8: D1 fixed - dedup dimension
theorem k8 : atomsOf [("A1", .imp P P)] = ["P"] := by native_decide

-- K9: self-loop cites detected
theorem k9 : depCycleNodes [⟨.cites, "T1", "T1"⟩] = ["T1"] := by decide

end Dagcheck
