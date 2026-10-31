import Dagcheck.Deriv
namespace Dagcheck

/-- Atoms occurring in a formula (duplicates kept: enumeration cost only, no semantic effect). -/
def atomsOfForm : Form → List String
  | .atom n => [n]
  | .neg a => atomsOfForm a
  | .imp a b => atomsOfForm a ++ atomsOfForm b
  | .conj a b => atomsOfForm a ++ atomsOfForm b
  | .disj a b => atomsOfForm a ++ atomsOfForm b

/-- Atoms occurring across a premise set. -/
def atomsOf (ps : List (String × Form)) : List String := ps.flatMap (fun p => atomsOfForm p.2)

/-- Every valuation over exactly the given atom names. -/
def allValsOver : List String → List Assign
  | [] => [[]]
  | n :: rest => (allValsOver rest).flatMap (fun v => [(n, true) :: v, (n, false) :: v])

/-- Do all premises hold under this valuation? -/
def satAll (v : Assign) (ps : List (String × Form)) : Bool :=
  ps.all (fun p => evalOpt v p.2 == some true)

/-- Bounded consistency over EXACTLY the atoms of the premises. Auto-dimensioned: there is
    no caller-supplied size to get wrong (the R7 hole was a caller-supplied n smaller than
    the highest atom index, making `getD ... false` silently fabricate values). Over the
    cap: explicit refusal, never a silent wrong answer. -/
def consistent (ps : List (String × Form)) (cap : Nat) : Except String Bool :=
  let atoms := atomsOf ps
  if atoms.length > cap then
    .error s!"consistency check refused: {atoms.length} atoms exceed cap {cap} (2^n enumeration); re-run with an explicit higher cap"
  else
    .ok ((allValsOver atoms).any (fun v => satAll v ps))

-- ---------- small list/option helpers (local, to avoid name roulette) ----------

theorem exists_of_any {α} {p : α → Bool} : ∀ {l : List α}, l.any p = true → ∃ x ∈ l, p x = true
  | [], h => by simp at h
  | x :: xs, h => by
    rw [List.any_cons] at h
    cases hx : p x with
    | true => exact ⟨x, List.Mem.head _, hx⟩
    | false =>
      rw [hx] at h; simp only [Bool.false_or] at h
      obtain ⟨y, hy, hpy⟩ := exists_of_any h
      exact ⟨y, List.Mem.tail _ hy, hpy⟩

theorem all_of_all {α} {p : α → Bool} : ∀ {l : List α}, l.all p = true → ∀ x ∈ l, p x = true
  | [], _, _, h => by cases h
  | x :: xs, h, y, hy => by
    rw [List.all_cons] at h
    simp only [Bool.and_eq_true] at h
    cases hy with
    | head => exact h.1
    | tail _ hmem => exact all_of_all h.2 _ hmem

theorem all_false_of_any_eq_false {α} {p : α → Bool} : ∀ {l : List α}, l.any p = false → ∀ x ∈ l, p x = false
  | [], _, _, h => by cases h
  | x :: xs, h, y, hy => by
    rw [List.any_cons] at h
    cases hx : p x with
    | true => rw [hx] at h; simp at h
    | false =>
      rw [hx] at h; simp only [Bool.false_or] at h
      cases hy with
      | head => exact hx
      | tail _ hmem => exact all_false_of_any_eq_false h _ hmem

theorem exists_of_all_eq_false {α} {p : α → Bool} : ∀ {l : List α}, l.all p = false → ∃ x ∈ l, p x = false
  | [], h => by simp at h
  | x :: xs, h => by
    rw [List.all_cons] at h
    cases hx : p x with
    | false => exact ⟨x, List.Mem.head _, hx⟩
    | true =>
      rw [hx] at h; simp only [Bool.true_and] at h
      obtain ⟨y, hy, hpy⟩ := exists_of_all_eq_false h
      exact ⟨y, List.Mem.tail _ hy, hpy⟩

-- ---------- evaluation depends only on the formula's own atoms ----------

theorem evalOpt_some_of_assigned {v : Assign} {f : Form}
    (h : ∀ a ∈ atomsOfForm f, (lookupA v a).isSome = true) :
    ∃ x, evalOpt v f = some x := by
  induction f with
  | atom n =>
    rcases Option.isSome_iff_exists.mp (h n (List.Mem.head _)) with ⟨b, hb⟩
    exact ⟨b, hb⟩
  | neg a ih =>
    rcases ih (fun a' ha' => h a' ha') with ⟨x, hx⟩
    exact ⟨!x, by simp [evalOpt, hx]⟩
  | imp a b iha ihb =>
    rcases iha (fun a' ha' => h a' (List.mem_append_left _ ha')) with ⟨x, hx⟩
    rcases ihb (fun b' hb' => h b' (List.mem_append_right _ hb')) with ⟨y, hy⟩
    exact ⟨!x || y, by simp [evalOpt, hx, hy]⟩
  | conj a b iha ihb =>
    rcases iha (fun a' ha' => h a' (List.mem_append_left _ ha')) with ⟨x, hx⟩
    rcases ihb (fun b' hb' => h b' (List.mem_append_right _ hb')) with ⟨y, hy⟩
    exact ⟨x && y, by simp [evalOpt, hx, hy]⟩
  | disj a b iha ihb =>
    rcases iha (fun a' ha' => h a' (List.mem_append_left _ ha')) with ⟨x, hx⟩
    rcases ihb (fun b' hb' => h b' (List.mem_append_right _ hb')) with ⟨y, hy⟩
    exact ⟨x || y, by simp [evalOpt, hx, hy]⟩

theorem evalOpt_agree {v1 v2 : Assign} {f : Form}
    (h : ∀ a ∈ atomsOfForm f, lookupA v1 a = lookupA v2 a) :
    evalOpt v1 f = evalOpt v2 f := by
  induction f with
  | atom n => exact h n (List.Mem.head _)
  | neg a ih => simp only [evalOpt, ih (fun a' ha' => h a' ha')]
  | imp a b iha ihb =>
    simp only [evalOpt,
      iha (fun a' ha' => h a' (List.mem_append_left _ ha')),
      ihb (fun b' hb' => h b' (List.mem_append_right _ hb'))]
  | conj a b iha ihb =>
    simp only [evalOpt,
      iha (fun a' ha' => h a' (List.mem_append_left _ ha')),
      ihb (fun b' hb' => h b' (List.mem_append_right _ hb'))]
  | disj a b iha ihb =>
    simp only [evalOpt,
      iha (fun a' ha' => h a' (List.mem_append_left _ ha')),
      ihb (fun b' hb' => h b' (List.mem_append_right _ hb'))]

theorem mem_atomsOf {ps : List (String × Form)} {p : String × Form} {a : String}
    (hp : p ∈ ps) (ha : a ∈ atomsOfForm p.2) : a ∈ atomsOf ps :=
  List.mem_flatMap.mpr ⟨p, hp, ha⟩

theorem mem_allValsOver {atoms : List String} {v : Assign}
    (h : ∀ a ∈ atoms, (lookupA v a).isSome = true) :
    (atoms.map (fun a => (a, (lookupA v a).getD false))) ∈ allValsOver atoms := by
  induction atoms with
  | nil => exact List.Mem.head _
  | cons n rest ih =>
    rcases Option.isSome_iff_exists.mp (h n (List.Mem.head _)) with ⟨b, hb⟩
    have ih' := ih (fun a ha => h a (List.Mem.tail _ ha))
    simp only [allValsOver, List.map]
    apply List.mem_flatMap.mpr
    refine ⟨_, ih', ?_⟩
    rw [hb]
    cases b with
    | true => exact List.Mem.head _
    | false => exact List.Mem.tail _ (List.Mem.head _)

theorem lookupA_map_restrict {atoms : List String} {v : Assign} {a : String}
    (ha : a ∈ atoms) (hsome : (lookupA v a).isSome = true) :
    lookupA (atoms.map (fun a' => (a', (lookupA v a').getD false))) a = lookupA v a := by
  induction atoms with
  | nil => cases ha
  | cons n rest ih =>
    simp only [List.map, lookupA]
    split
    · rename_i hna
      rw [beq_iff_eq] at hna
      subst hna
      rcases Option.isSome_iff_exists.mp hsome with ⟨b, hb⟩
      rw [hb]
      rfl
    · rename_i hna
      rw [beq_iff_eq] at hna
      cases ha with
      | head => exact absurd rfl hna
      | tail _ hmem => exact ih hmem

-- ---------- the two directions ----------

/-- Sound: a `true` verdict is witnessed by a real satisfying valuation. A registry can
    NEVER be reported consistent when no satisfying valuation exists - regardless of any
    dimensioning choice, because the checker makes none. -/
theorem consistent_sound {ps : List (String × Form)} {cap : Nat}
    (h : consistent ps cap = .ok true) :
    ∃ v : Assign, ∀ p ∈ ps, evalOpt v p.2 = some true := by
  simp only [consistent] at h
  split at h
  · simp at h
  · rename_i hcap
    injection h with h
    obtain ⟨v, hv, hsv⟩ := exists_of_any h
    exact ⟨v, fun p hp => beq_iff_eq.mp (all_of_all hsv p hp)⟩

/-- Complete (within the fragment): a `false` verdict means NO valuation that assigns the
    premises' atoms can satisfy them all. False "inconsistent" verdicts are impossible. -/
theorem consistent_complete {ps : List (String × Form)} {cap : Nat}
    (h : consistent ps cap = .ok false) :
    ∀ v : Assign, (∀ a ∈ atomsOf ps, (lookupA v a).isSome = true) →
      ∃ p ∈ ps, evalOpt v p.2 ≠ some true := by
  intro v hv
  simp only [consistent] at h
  split at h
  · simp at h
  · rename_i hcap
    injection h with h
    have hany : (allValsOver (atomsOf ps)).any (fun w => satAll w ps) = false := h
    have hmem : ((atomsOf ps).map (fun a => (a, (lookupA v a).getD false))) ∈ allValsOver (atomsOf ps) :=
      mem_allValsOver hv
    have hfalse := all_false_of_any_eq_false hany _ hmem
    obtain ⟨p, hp, hpfalse⟩ := exists_of_all_eq_false hfalse
    refine ⟨p, hp, ?_⟩
    have hagree : evalOpt ((atomsOf ps).map (fun a => (a, (lookupA v a).getD false))) p.2 = evalOpt v p.2 := by
      apply evalOpt_agree
      intro a ha
      have hmem' := mem_atomsOf hp ha
      exact lookupA_map_restrict hmem' (hv a hmem')
    rw [← hagree]
    intro hc
    rw [hc] at hpfalse
    simp at hpfalse

end Dagcheck
