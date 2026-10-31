-- Hardened propositional core for the DAG skill verified checker.
-- Differences from the R7 research mirror (E17_dag_seam.lean):
--   * atoms are NAMES (String), not indices - no manual index alignment between
--     encodings, so index divergence/collision between files is impossible by construction
--   * evaluation is PARTIAL: an unassigned atom yields `none`, never a silent default
--     `false` (the R7 `getD ... false` hole, where a too-small valuation could make an
--     inconsistent registry report consistent, is closed by construction)
--   * soundness is stated with an explicit COVERAGE hypothesis: the conclusion's atoms
--     must be assigned in the valuation. Only disjunction-intro introduces atoms not
--     present in its premises; coverage makes that gap explicit instead of hidden.
namespace Dagcheck

inductive Form where
  | atom (name : String)
  | neg  (a : Form)
  | imp  (a b : Form)
  | conj (a b : Form)
  | disj (a b : Form)
  deriving DecidableEq, Repr

/-- A valuation: assoc list from atom name to truth value. -/
abbrev Assign := List (String × Bool)

def lookupA : Assign → String → Option Bool
  | [], _ => none
  | (k, b) :: rest, n => if k == n then some b else lookupA rest n

/-- Partial evaluation: `none` when any atom is unassigned. -/
def evalOpt (v : Assign) : Form → Option Bool
  | .atom n   => lookupA v n
  | .neg a    => match evalOpt v a with
    | some x => some (!x)
    | none   => none
  | .imp a b  => match evalOpt v a, evalOpt v b with
    | some x, some y => some (!x || y)
    | _, _ => none
  | .conj a b => match evalOpt v a, evalOpt v b with
    | some x, some y => some (x && y)
    | _, _ => none
  | .disj a b => match evalOpt v a, evalOpt v b with
    | some x, some y => some (x || y)
    | _, _ => none

-- Boolean algebra helpers, one per rule's semantic content (from R7, unchanged).
theorem b_mp {x y : Bool} (h1 : (!x || y) = true) (h2 : x = true) : y = true := by cases x <;> simp_all
theorem b_mt {x y : Bool} (h1 : (!x || y) = true) (h2 : (!y) = true) : (!x) = true := by cases y <;> simp_all
theorem b_trans {x y z : Bool} (h1 : (!x || y) = true) (h2 : (!y || z) = true) : (!x || z) = true := by cases y <;> simp_all
theorem b_conjI {x y : Bool} (h1 : x = true) (h2 : y = true) : (x && y) = true := by rw [h1, h2]; rfl
theorem b_conjL {x y : Bool} (h : (x && y) = true) : x = true := by cases x <;> simp_all
theorem b_conjR {x y : Bool} (h : (x && y) = true) : y = true := by cases x <;> simp_all
theorem b_disjL {x : Bool} (y : Bool) (h : x = true) : (x || y) = true := by rw [h]; rfl
theorem b_disjR (x : Bool) {y : Bool} (h : y = true) : (x || y) = true := by rw [h]; cases x <;> rfl
theorem b_contra {x y : Bool} (h : (!x || y) = true) : (!(!y) || (!x)) = true := by cases x <;> cases y <;> simp_all
theorem b_dilemma {x y z : Bool} (h1 : (x || y) = true) (h2 : (!x || z) = true) (h3 : (!y || z) = true) : z = true := by
  cases x <;> cases y <;> simp_all

-- Lifted semantic lemmas: rule-wise semantic content at the (partial) Form level.

theorem e_mp {v : Assign} {a b : Form}
    (h1 : evalOpt v (.imp a b) = some true) (h2 : evalOpt v a = some true) :
    evalOpt v b = some true := by
  simp only [evalOpt] at h1
  split at h1
  · rename_i x y hx hy
    injection h1 with h1
    rw [hx] at h2
    injection h2 with h2
    have hb := b_mp h1 h2
    subst hb
    exact hy
  · simp at h1

theorem e_mt {v : Assign} {a b : Form}
    (h1 : evalOpt v (.imp a b) = some true) (h2 : evalOpt v (.neg b) = some true) :
    evalOpt v (.neg a) = some true := by
  simp only [evalOpt] at h1
  split at h1
  · rename_i x y hx hy
    injection h1 with h1
    simp only [evalOpt] at h2
    split at h2
    · rename_i y2 hy2
      injection h2 with h2
      rw [hy] at hy2
      injection hy2 with hyy
      subst hyy
      have hb := b_mt h1 h2
      simp only [evalOpt]
      rw [hx]
      exact congrArg some hb
    · simp at h2
  · simp at h1

theorem e_trans {v : Assign} {a b c : Form}
    (h1 : evalOpt v (.imp a b) = some true) (h2 : evalOpt v (.imp b c) = some true) :
    evalOpt v (.imp a c) = some true := by
  simp only [evalOpt] at h1
  split at h1
  · rename_i x y hx hy
    injection h1 with h1
    simp only [evalOpt] at h2
    split at h2
    · rename_i y2 z hy2 hz
      injection h2 with h2
      rw [hy] at hy2
      injection hy2 with hyy
      subst hyy
      have hb := b_trans h1 h2
      simp only [evalOpt]
      rw [hx, hz]
      exact congrArg some hb
    · simp at h2
  · simp at h1

theorem e_conjI {v : Assign} {a b : Form}
    (h1 : evalOpt v a = some true) (h2 : evalOpt v b = some true) :
    evalOpt v (.conj a b) = some true := by
  cases ha : evalOpt v a with
  | none => rw [ha] at h1; simp at h1
  | some x =>
    cases hb : evalOpt v b with
    | none => rw [hb] at h2; simp at h2
    | some y =>
      rw [ha] at h1; injection h1 with h1
      rw [hb] at h2; injection h2 with h2
      have hc := b_conjI h1 h2
      simp only [evalOpt]
      rw [ha, hb]
      exact congrArg some hc

theorem e_conjL {v : Assign} {a b : Form}
    (h : evalOpt v (.conj a b) = some true) : evalOpt v a = some true := by
  simp only [evalOpt] at h
  split at h
  · rename_i x y hx hy
    injection h with h
    have hx' := b_conjL h
    rw [hx]
    exact congrArg some hx'
  · simp at h

theorem e_conjR {v : Assign} {a b : Form}
    (h : evalOpt v (.conj a b) = some true) : evalOpt v b = some true := by
  simp only [evalOpt] at h
  split at h
  · rename_i x y hx hy
    injection h with h
    have hy' := b_conjR h
    rw [hy]
    exact congrArg some hy'
  · simp at h

theorem e_disjL {v : Assign} {a b : Form}
    (h : evalOpt v a = some true) (hcov : evalOpt v (.disj a b) ≠ none) :
    evalOpt v (.disj a b) = some true := by
  cases ha : evalOpt v a with
  | none => rw [ha] at h; simp at h
  | some x =>
    rw [ha] at h; injection h with h
    cases hb : evalOpt v b with
    | none =>
      simp only [evalOpt] at hcov
      rw [ha, hb] at hcov
      simp at hcov
    | some y =>
      have hb2 := b_disjL y h
      simp only [evalOpt]
      rw [ha, hb]
      exact congrArg some hb2

theorem e_disjR {v : Assign} {a b : Form}
    (h : evalOpt v b = some true) (hcov : evalOpt v (.disj a b) ≠ none) :
    evalOpt v (.disj a b) = some true := by
  cases hb : evalOpt v b with
  | none => rw [hb] at h; simp at h
  | some y =>
    rw [hb] at h; injection h with h
    cases ha : evalOpt v a with
    | none =>
      simp only [evalOpt] at hcov
      rw [ha, hb] at hcov
      simp at hcov
    | some x =>
      have hb2 := b_disjR x h
      simp only [evalOpt]
      rw [ha, hb]
      exact congrArg some hb2

theorem e_contra {v : Assign} {a b : Form}
    (h : evalOpt v (.imp a b) = some true) :
    evalOpt v (.imp (.neg b) (.neg a)) = some true := by
  simp only [evalOpt] at h
  split at h
  · rename_i x y hx hy
    injection h with h
    have hb := b_contra h
    simp only [evalOpt]
    rw [hx, hy]
    exact congrArg some hb
  · simp at h

theorem e_dilemma {v : Assign} {a b c : Form}
    (h1 : evalOpt v (.disj a b) = some true) (h2 : evalOpt v (.imp a c) = some true)
    (h3 : evalOpt v (.imp b c) = some true) : evalOpt v c = some true := by
  simp only [evalOpt] at h1
  split at h1
  · rename_i x y hx hy
    injection h1 with h1
    simp only [evalOpt] at h2
    split at h2
    · rename_i x2 z hx2 hz
      injection h2 with h2
      rw [hx] at hx2; injection hx2 with hxx; subst hxx
      simp only [evalOpt] at h3
      split at h3
      · rename_i y2 z2 hy2 hz2
        injection h3 with h3
        rw [hy] at hy2; injection hy2 with hyy; subst hyy
        rw [hz] at hz2; injection hz2 with hzz; subst hzz
        have hb := b_dilemma h1 h2 h3
        rw [hz]; exact congrArg some hb
      · simp at h3
    · simp at h2
  · simp at h1

end Dagcheck
