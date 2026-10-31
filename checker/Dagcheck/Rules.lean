import Dagcheck.Form

-- Rule checking, ported from the R7 research mirror (E17_dag_seam.lean, audited and
-- independently reproduced) to the hardened partial-evaluation core in Dagcheck.Form.
-- applyRule returns `some conclusion` exactly when the step cites well-shaped premises
-- (by name) and the rule table accepts the combination; `none` otherwise.
namespace Dagcheck

set_option maxRecDepth 8192

inductive Rule where
  | mp | mt | trans | conjIntro | conjElimL | conjElimR | disjIntroL | disjIntroR | contra | dilemma
  deriving DecidableEq, Repr

structure Step where
  id         : String
  conclusion : Form
  rule       : Rule
  cites      : List String
  deriving Repr

/-- assoc lookup we control, with its own membership lemma. -/
def lookupF : List (String × Form) → String → Option Form
  | [], _ => none
  | (k, f) :: rest, id => if k == id then some f else lookupF rest id

theorem lookupF_mem {known : List (String × Form)} {id : String} {f : Form}
    (h : lookupF known id = some f) : ∃ k, (k, f) ∈ known := by
  induction known with
  | nil => simp [lookupF] at h
  | cons p rest ih =>
    simp only [lookupF] at h
    split at h
    · injection h with h1; subst h1; exact ⟨p.1, List.Mem.head _⟩
    · rcases ih h with ⟨k, hk⟩; exact ⟨k, List.Mem.tail _ hk⟩

def applyRule (known : List (String × Form)) (s : Step) : Option Form :=
  match s.rule with
  | .mp => match s.cites.map (lookupF known) with
    | [some (.imp a b), some a'] => if a == a' && s.conclusion == b then some b else none
    | _ => none
  | .mt => match s.cites.map (lookupF known) with
    | [some (.imp a b), some (.neg b')] => if b == b' && s.conclusion == .neg a then some (.neg a) else none
    | _ => none
  | .trans => match s.cites.map (lookupF known) with
    | [some (.imp a b), some (.imp b' c)] => if b == b' && s.conclusion == .imp a c then some (.imp a c) else none
    | _ => none
  | .conjIntro => match s.cites.map (lookupF known) with
    | [some a, some b] => if s.conclusion == .conj a b then some (.conj a b) else none
    | _ => none
  | .conjElimL => match s.cites.map (lookupF known) with
    | [some (.conj a _)] => if s.conclusion == a then some a else none
    | _ => none
  | .conjElimR => match s.cites.map (lookupF known) with
    | [some (.conj _ b)] => if s.conclusion == b then some b else none
    | _ => none
  | .disjIntroL => match s.cites.map (lookupF known) with
    | [some a] => match s.conclusion with
      | .disj a' _ => if a == a' then some s.conclusion else none
      | _ => none
    | _ => none
  | .disjIntroR => match s.cites.map (lookupF known) with
    | [some b] => match s.conclusion with
      | .disj _ b' => if b == b' then some s.conclusion else none
      | _ => none
    | _ => none
  | .contra => match s.cites.map (lookupF known) with
    | [some (.imp a b)] => if s.conclusion == .imp (.neg b) (.neg a) then some s.conclusion else none
    | _ => none
  | .dilemma => match s.cites.map (lookupF known) with
    | [some (.disj a b), some (.imp a' c), some (.imp b' c')] =>
      if a == a' && b == b' && c == c' && s.conclusion == c then some c else none
    | _ => none

/-- `(a == b) = true` is just `a = b` for our derived DecidableEq. -/
theorem beq_eq {a b : Form} : (a == b) = true ↔ a = b := by
  show (decide (a = b)) = true ↔ a = b
  exact decide_eq_true_iff

private theorem mem_eval {known : List (String × Form)} {v : Assign}
    (hknown : ∀ p ∈ known, evalOpt v p.2 = some true) {id : String} {f : Form}
    (h : lookupF known id = some f) : evalOpt v f = some true := by
  rcases lookupF_mem h with ⟨k, hk⟩
  exact hknown _ hk

/-- Soundness of a single rule application: a checked step's conclusion holds in every
    valuation where every known entry holds AND the conclusion's atoms are all assigned
    (coverage). Coverage is load-bearing only for disjunction-intro, whose conclusion
    carries an atom not present in its premise; for the other nine rules it is implied
    by the premises holding. Proved by full case analysis on the registry-spec rule table. -/
theorem applyRule_sound (known : List (String × Form)) (s : Step) (v : Assign)
    (hknown : ∀ p ∈ known, evalOpt v p.2 = some true)
    (hcov : evalOpt v s.conclusion ≠ none)
    (h : applyRule known s = some s.conclusion) : evalOpt v s.conclusion = some true := by
  obtain ⟨sid, scon, srule, scites⟩ := s
  cases srule with
  | mp =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil => simp at h
      | cons i2 rest2 =>
        cases rest2 with
        | nil =>
          simp only [List.map_cons, List.map_nil] at h
          generalize h1 : lookupF known i1 = o1
          rw [h1] at h
          cases o1 with
          | none => simp at h
          | some f1 =>
            cases f1 with
            | atom n => simp at h
            | neg a => simp at h
            | conj a b => simp at h
            | disj a b => simp at h
            | imp a b =>
              generalize h2 : lookupF known i2 = o2
              rw [h2] at h
              cases o2 with
              | none => simp at h
              | some f2 =>
                split at h
                · rename_i hcond
                  injection hcond with hc1 hc2
                  injection hc1 with hc1'
                  injection hc1' with ha hb
                  injection hc2 with hc2a hc2b
                  injection hc2a with hf
                  subst ha; subst hb; subst hf
                  split at h
                  · rename_i hcond2
                    rw [Bool.and_eq_true] at hcond2
                    obtain ⟨haa, hcb⟩ := hcond2
                    rw [beq_eq] at haa hcb
                    subst hcb
                    subst haa
                    have e1 := mem_eval hknown h1
                    have e2 := mem_eval hknown h2
                    exact e_mp e1 e2
                  · rename_i hcond2; cases h
                · rename_i hcond; simp_all
                all_goals simp_all
        | cons i3 r3 => simp [List.map_cons] at h
  | mt =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil => simp at h
      | cons i2 rest2 =>
        cases rest2 with
        | nil =>
          simp only [List.map_cons, List.map_nil] at h
          generalize h1 : lookupF known i1 = o1
          rw [h1] at h
          cases o1 with
          | none => simp at h
          | some f1 =>
            cases f1 with
            | atom n => simp at h
            | neg a => simp at h
            | conj a b => simp at h
            | disj a b => simp at h
            | imp a b =>
              generalize h2 : lookupF known i2 = o2
              rw [h2] at h
              cases o2 with
              | none => simp at h
              | some f2 =>
                cases f2 with
                | atom n => simp at h
                | imp a' b' => simp at h
                | conj a' b' => simp at h
                | disj a' b' => simp at h
                | neg b' =>
                  split at h
                  · rename_i hcond
                    injection hcond with hc1 hc2
                    injection hc1 with hc1'
                    injection hc1' with ha hb
                    injection hc2 with hc2a hc2b
                    injection hc2a with hf
                    injection hf with hf1
                    subst ha; subst hb; subst hf1
                    split at h
                    · rename_i hcond2
                      rw [Bool.and_eq_true] at hcond2
                      obtain ⟨hbb, hcs⟩ := hcond2
                      rw [beq_eq] at hbb hcs
                      subst hcs
                      subst hbb
                      have e1 := mem_eval hknown h1
                      have e2 := mem_eval hknown h2
                      exact e_mt e1 e2
                    · rename_i hcond2; cases h
                  · rename_i hcond; exact (hcond a b b' rfl).elim
        | cons i3 r3 => simp [List.map_cons] at h
  | trans =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil => simp at h
      | cons i2 rest2 =>
        cases rest2 with
        | nil =>
          simp only [List.map_cons, List.map_nil] at h
          generalize h1 : lookupF known i1 = o1
          rw [h1] at h
          cases o1 with
          | none => simp at h
          | some f1 =>
            cases f1 with
            | atom n => simp at h
            | neg a => simp at h
            | conj a b => simp at h
            | disj a b => simp at h
            | imp a b =>
              generalize h2 : lookupF known i2 = o2
              rw [h2] at h
              cases o2 with
              | none => simp at h
              | some f2 =>
                cases f2 with
                | atom n => simp at h
                | neg a' => simp at h
                | conj a' b' => simp at h
                | disj a' b' => simp at h
                | imp b' c =>
                  split at h
                  · rename_i hcond
                    injection hcond with hc1 hc2
                    injection hc1 with hc1'
                    injection hc1' with ha hb
                    injection hc2 with hc2a hc2b
                    injection hc2a with hf
                    injection hf with hf1 hf2
                    subst ha; subst hb; subst hf1; subst hf2
                    split at h
                    · rename_i hcond2
                      rw [Bool.and_eq_true] at hcond2
                      obtain ⟨hbb, hcs⟩ := hcond2
                      rw [beq_eq] at hbb hcs
                      subst hcs
                      subst hbb
                      have e1 := mem_eval hknown h1
                      have e2 := mem_eval hknown h2
                      exact e_trans e1 e2
                    · rename_i hcond2; cases h
                  · rename_i hcond; exact (hcond a b b' c rfl).elim
        | cons i3 r3 => simp [List.map_cons] at h
  | conjIntro =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil => simp at h
      | cons i2 rest2 =>
        cases rest2 with
        | nil =>
          simp only [List.map_cons, List.map_nil] at h
          generalize h1 : lookupF known i1 = o1
          rw [h1] at h
          cases o1 with
          | none => simp at h
          | some f1 =>
            generalize h2 : lookupF known i2 = o2
            rw [h2] at h
            cases o2 with
            | none => simp at h
            | some f2 =>
              split at h
              · rename_i hcond
                injection hcond with hc1 hc2
                injection hc1 with hf1
                injection hc2 with hc2a hc2b
                injection hc2a with hf2
                subst hf1; subst hf2
                split at h
                · rename_i hcond2
                  rw [beq_eq] at hcond2
                  subst hcond2
                  have e1 := mem_eval hknown h1
                  have e2 := mem_eval hknown h2
                  exact e_conjI e1 e2
                · rename_i hcond2; cases h
              · rename_i hcond; exact (hcond f1 f2 rfl).elim
        | cons i3 r3 => simp [List.map_cons] at h
  | conjElimL =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil =>
        simp only [List.map_cons, List.map_nil] at h
        generalize h1 : lookupF known i1 = o1
        rw [h1] at h
        cases o1 with
        | none => simp at h
        | some f1 =>
          cases f1 with
          | atom n => simp at h
          | neg a => simp at h
          | imp a b => simp at h
          | disj a b => simp at h
          | conj a b =>
            split at h
            · rename_i hcond
              injection hcond with hc1 hc1b
              injection hc1 with hc1'
              injection hc1' with ha hb
              subst ha; subst hb
              split at h
              · rename_i hcond2
                rw [beq_eq] at hcond2
                subst hcond2
                have e1 := mem_eval hknown h1
                exact e_conjL e1
              · rename_i hcond2; cases h
            · rename_i hcond; exact (hcond a b rfl).elim
      | cons i2 r2 => simp [List.map_cons] at h
  | conjElimR =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil =>
        simp only [List.map_cons, List.map_nil] at h
        generalize h1 : lookupF known i1 = o1
        rw [h1] at h
        cases o1 with
        | none => simp at h
        | some f1 =>
          cases f1 with
          | atom n => simp at h
          | neg a => simp at h
          | imp a b => simp at h
          | disj a b => simp at h
          | conj a b =>
            split at h
            · rename_i hcond
              injection hcond with hc1 hc1b
              injection hc1 with hc1'
              injection hc1' with ha hb
              subst ha; subst hb
              split at h
              · rename_i hcond2
                rw [beq_eq] at hcond2
                subst hcond2
                have e1 := mem_eval hknown h1
                exact e_conjR e1
              · rename_i hcond2; cases h
            · rename_i hcond; exact (hcond a b rfl).elim
      | cons i2 r2 => simp [List.map_cons] at h
  | disjIntroL =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil =>
        simp only [List.map_cons, List.map_nil] at h
        generalize h1 : lookupF known i1 = o1
        rw [h1] at h
        cases o1 with
        | none => simp at h
        | some f1 =>
          split at h
          · rename_i hcond
            injection hcond with hc1 hc1b
            injection hc1 with hf
            subst hf
            split at h
            · split at h
              · rename_i hcond2
                rw [beq_eq] at hcond2
                subst hcond2
                have e1 := mem_eval hknown h1
                exact e_disjL e1 hcov
              · rename_i hcond2; cases h
            · rename_i heq; cases h
          · rename_i hcond; exact (hcond f1 rfl).elim
      | cons i2 r2 => simp [List.map_cons] at h
  | disjIntroR =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil =>
        simp only [List.map_cons, List.map_nil] at h
        generalize h1 : lookupF known i1 = o1
        rw [h1] at h
        cases o1 with
        | none => simp at h
        | some f1 =>
          split at h
          · rename_i hcond
            injection hcond with hc1 hc1b
            injection hc1 with hf
            subst hf
            split at h
            · split at h
              · rename_i hcond2
                rw [beq_eq] at hcond2
                subst hcond2
                have e1 := mem_eval hknown h1
                exact e_disjR e1 hcov
              · rename_i hcond2; cases h
            · rename_i heq; cases h
          · rename_i hcond; exact (hcond f1 rfl).elim
      | cons i2 r2 => simp [List.map_cons] at h
  | contra =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil =>
        simp only [List.map_cons, List.map_nil] at h
        generalize h1 : lookupF known i1 = o1
        rw [h1] at h
        cases o1 with
        | none => simp at h
        | some f1 =>
          cases f1 with
          | atom n => simp at h
          | neg a => simp at h
          | conj a b => simp at h
          | disj a b => simp at h
          | imp a b =>
            split at h
            · rename_i hcond
              injection hcond with hc1 hc1b
              injection hc1 with hc1'
              injection hc1' with ha hb
              subst ha; subst hb
              split at h
              · rename_i hcond2
                rw [beq_eq] at hcond2
                subst hcond2
                have e1 := mem_eval hknown h1
                exact e_contra e1
              · rename_i hcond2; cases h
            · rename_i hcond; exact (hcond a b rfl).elim
      | cons i2 r2 => simp [List.map_cons] at h
  | dilemma =>
    simp only [applyRule] at h
    cases scites with
    | nil => simp at h
    | cons i1 rest =>
      cases rest with
      | nil => simp at h
      | cons i2 rest2 =>
        cases rest2 with
        | nil => simp [List.map_cons] at h
        | cons i3 rest3 =>
          cases rest3 with
          | nil =>
            simp only [List.map_cons, List.map_nil] at h
            generalize h1 : lookupF known i1 = o1
            rw [h1] at h
            cases o1 with
            | none => simp at h
            | some f1 =>
              cases f1 with
              | atom n => simp at h
              | neg a => simp at h
              | imp a b => simp at h
              | conj a b => simp at h
              | disj a b =>
                generalize h2 : lookupF known i2 = o2
                rw [h2] at h
                cases o2 with
                | none => simp at h
                | some f2 =>
                  cases f2 with
                  | atom n => simp at h
                  | neg a' => simp at h
                  | conj a' b' => simp at h
                  | disj a' b' => simp at h
                  | imp a' c =>
                    generalize h3 : lookupF known i3 = o3
                    rw [h3] at h
                    cases o3 with
                    | none => simp at h
                    | some f3 =>
                      cases f3 with
                      | atom n => simp at h
                      | neg a'' => simp at h
                      | conj a'' b'' => simp at h
                      | disj a'' b'' => simp at h
                      | imp b' c' =>
                        split at h
                        · rename_i hcond
                          injection hcond with hc1 hrest
                          injection hc1 with hc1'
                          injection hc1' with ha hb
                          injection hrest with hc2 hrest2
                          injection hc2 with hc2'
                          injection hc2' with ha' hc
                          injection hrest2 with hc3 hrest3
                          injection hc3 with hc3'
                          injection hc3' with hb' hc'
                          subst ha; subst hb; subst ha'; subst hc; subst hb'; subst hc'
                          split at h
                          · rename_i hcond2
                            simp only [Bool.and_eq_true] at hcond2
                            obtain ⟨⟨⟨h1a, h2a⟩, h3a⟩, h4a⟩ := hcond2
                            rw [beq_eq] at h1a h2a h3a h4a
                            subst h1a; subst h2a; subst h3a; subst h4a
                            have e1 := mem_eval hknown h1
                            have e2 := mem_eval hknown h2
                            have e3 := mem_eval hknown h3
                            exact e_dilemma e1 e2 e3
                          · rename_i hcond2
                            cases h
                        · rename_i hcond; exact (hcond a b a' c b' c' rfl).elim
          | cons i4 r4 => simp [List.map_cons] at h


