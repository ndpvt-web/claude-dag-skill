import Dagcheck.Rules

-- Derivation-chain checking: sequential fold over steps, each extending the known
-- environment. Forward citations and citation cycles are rejected structurally (a cited
-- ID must already be known when the step is checked).
namespace Dagcheck

/-- Sequential derivation check. Returns the extended environment on success.
    A step whose id is ALREADY known is rejected (review defect D3: reusing an id
    silently shadowed the earlier entry through lookupF first-match). -/
def checkDeriv (known : List (String × Form)) : List Step → Option (List (String × Form))
  | [] => some known
  | s :: rest =>
    match applyRule known s with
    | some c =>
      if c == s.conclusion && !(known.any (fun p => p.1 == s.id)) then
        checkDeriv ((s.id, s.conclusion) :: known) rest
      else none
    | none   => none

/-- Chain soundness: every entry the checker accepts (premises + derived steps) holds in
    every valuation satisfying the premises, PROVIDED every step's conclusion has all its
    atoms assigned (coverage). This is derive-check-3 (inference validity) made
    machine-checkable for the propositional fragment - CONDITIONAL on the premises. -/
theorem checkDeriv_sound (known : List (String × Form)) (steps : List Step) (out : List (String × Form))
    (h : checkDeriv known steps = some out) (v : Assign)
    (hknown : ∀ p ∈ known, evalOpt v p.2 = some true)
    (hcov : ∀ s ∈ steps, evalOpt v s.conclusion ≠ none) :
    ∀ p ∈ out, evalOpt v p.2 = some true := by
  induction steps generalizing known out with
  | nil => injection h with h1; subst h1; exact hknown
  | cons s rest ih =>
    simp only [checkDeriv] at h
    split at h
    · rename_i c happ
      split at h
      · rename_i hcc
        simp only [Bool.and_eq_true] at hcc
        obtain ⟨hcc1, -⟩ := hcc
        rw [beq_eq] at hcc1
        subst hcc1
        have hs : evalOpt v s.conclusion = some true :=
          applyRule_sound known s v hknown (hcov s (List.Mem.head _)) happ
        exact ih _ _ h (by
          intro p hp
          cases hp with
          | head => exact hs
          | tail _ hp' => exact hknown _ hp') (fun s' hs' => hcov s' (List.Mem.tail _ hs'))
      · rename_i hcc; cases h
    · rename_i happ; cases h

end Dagcheck
