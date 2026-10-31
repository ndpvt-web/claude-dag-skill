# The verified checker (dagcheck)

`checker/` is a Lean 4 project implementing a kernel-verified checker for this
registry. It is **read-only**: it never writes, renames or deletes registry files.
All writes stay with the skill's checked commands; the checker validates, verifies
derivations, and reports.

## Commands

```
lake build                                    # in checker/
dagcheck check <registry-dir> [--today YYYY-MM-DD] [--cap N]   # validate + verify; JSON report
dagcheck graph <registry-dir> [--today YYYY-MM-DD]   # emit provenance.json (see graph-model.md)
dagcheck check-step <registry-dir> --premises '["A1","H1"]' \
    --step '{"id":"T9","conclusion":<form-json>,"rule":"modus ponens","cites":["A1","H1"]}'
```

`--cap N` raises the consistency ceiling from the default 20 distinct atoms. N above
20 is refused: enumeration is 2^N and materialized, so an uncapped flag would be a
memory attack, not a feature. Split the registry or reduce distinct atoms instead.

`check-step` checks the step against EXACTLY the `--premises` set: every citation in
`--step.cites` must be listed there (a narrower set is a usage error), and a theorem
enters the environment only when its own derivation is `verified` in the registry -
the same prerequisite discipline as the full checker, so no green chain can stand on
rejected work.

`check` exits 1 when any error-severity finding or any rejected/blocked verdict
exists, else 0. Without `--today`, time-based staleness is skipped and structural
checks still run.

## What "verified" means (and what it does not)

The kernel proves, in Lean, two theorems about the propositional fragment
(modus ponens/tollens, transitivity, conjunction intro/elim, disjunction intro,
contrapositive, dilemma):

- `applyRule_sound` / `checkDeriv_sound`: every accepted rule step is derivable in the
  embedded natural-deduction calculus. Axioms: `propext`, `Quot.sound` only.
- `consistent_sound` / `consistent_complete`: the bounded consistency checker's
  verdict matches the existence of a satisfying valuation over exactly the declared
  premise atoms.

A theorem entry's `verified` verdict therefore means: *if the English statements are
faithfully encoded as the forms in the `form` fields and the atom table, then the
conclusion follows from the cited premises by the named rule.* The translation itself
(English -> form) is a human artifact and stays outside the kernel; the checker makes
that boundary explicit instead of claiming more than it proves. Every report row
carries its assumptions (the cited premise ids).

Verdict classes:

- **verified** - rule step checks against the encoded active environment.
- **rejected** - the cited premises do not produce the conclusion under the named
  rule. A registry defect; exit 1.
- **blocked** - the entry cites an unknown, deprecated, under-review or stale id.
- **unchecked** - outside the machine-checkable fragment: prose rules
  ("conjunction + modus ponens", instantiation, analogy), missing encodings. This is
  an honest non-verdict, never a silent pass. Unsupported reasoning stays unchecked
  by design.
- **stale / needs recheck** - the entry's content changed after the committed
  provenance baseline. A drifted entry's prior verdict is NEVER reported as green:
  the report shows `stale` with the prior verdict preserved inside the reason. Never
  a claim of invalidity.
- **upstream-stale / needs recheck** - an upstream dependency of this entry drifted.
  The entry's conditional derivation is unchanged and remains valid given its
  premises, but the current accepted dependency state no longer supports it. Reports,
  verdicts, check-step and the graph viewer all surface this state; the prior verdict
  is preserved inside the reason as context, never as a current green. Never a claim
  of invalidity.

## The coverage contract (atom table)

`logic.json` maps every atom name to its statement text. Coverage enforcement is
operational, at the bridge:

- A `form` (on any entry, or a `check-step` conclusion) using an atom **absent from
  `logic.json`** is an `unmapped-atom` **error**. No checked step can ever evaluate an
  unassigned atom.
- An atom **declared in the table but not present in the cited premises** is fine when
  the rule genuinely introduces it: `disjunction intro` may conclude `P OR Fresh` from
  `P`. That is logically derivable, the kernel theorem covers it, and the verdict is
  `verified`. Absent-from-premises and absent-from-the-table are different things;
  only the second is a defect.
- The same statement text under two atom names is a warning (possible encoding
  collision); faithfulness itself stays outside the kernel.

## Citation order

`derived_from` is a JSON array, and array order is preserved by the strict parser.
**Clarified contract:** for machine-checkable rules the array order IS the rule's
argument order (first cite = first premise of the rule shape, e.g. the implication for
modus ponens). A rule whose cites arrive in the wrong order is **rejected** with the
reason stated.

This clarifies previously unspecified semantics: the original spec never assigned
positional meaning to `derived_from`, and its own examples use prose rules with
unordered cites. No previously *machine-verified* entry exists that could break, since
no checker existed. Prose-rule entries are unaffected (they are `unchecked` either
way). Migration for an entry rejected under the clarified contract: reorder
`derived_from` to match how `derivation_note` actually combines the premises.

## Consistency

The encoded active subset is checked for joint satisfiability over its distinct atoms,
auto-dimensioned. Above 20 distinct atoms the check is a loud refusal
(`consistency-over-cap` warning), never a silent pass. An inconsistent result is
worded carefully: the *encodings* cannot all hold; it does not license deriving
arbitrary conclusions, and a single failed derivation proves no nonderivability.

## Freshness (changed inputs make verification stale)

Each entry has a content fingerprint (non-cryptographic hash over exactly the fields
a derivation depends on: type, statement, created_by, citations, inference rule,
confidence, and the encoded form - computed at report time, never stored in the type
files). Identity and presentation are excluded: editing a `label` never drifts a
fingerprint, and entry IDs are permanent by policy (never renamed), so the fingerprint
says nothing about id stability. Status transitions (active/under-review) are registry
state, not content drift. `dagcheck graph`
emits `provenance.json` carrying those fingerprints; commit it as the freshness
baseline. On later `check` runs, drifted entries produce `stale-fingerprint` warnings
naming the changed entry **and its blast radius** (the transitive citers) as needing
recheck. Removed and new ids are reported likewise. Drift wording is deliberately
narrow: prior verification no longer covers the new content - nothing about validity,
and nothing about runtime behavior.

## Registry schema and adversarial bounds

The parser validates against the field sets of `references/registry-spec.md`
verbatim (`created_by` is universally mandatory; D entries need
term/scope/distinguishes_from/rationale; A entries domain/hardness/rationale; H
entries scope_claim/falsification/review_trigger; T entries
derived_from/inference_rule/derivation_note/proof_confidence/session_derived).
Unknown fields are loud errors. `form` is the checker's own documented extension.
Defensive bounds (each with an adversarial regression fixture): JSON number exponents
beyond |99| and mantissas beyond 40 digits are parse errors; JSON nesting beyond 500
levels is a parse error; one encoded form beyond 1000 constructors is a parse error;
total formula size beyond 1000 constructors refuses the consistency check (all three
were OOM/SIGKILL vectors: the pre-bound imp-tower probe died at 12s); registries beyond
50000 entries are refused; staleness_period_days is bounded to [0, 36500]; the
consistency ceiling is 20 distinct atoms, measured at ~0.2s / ~210MB worst case
(fixture cap20-max). `dagcheck graph` on a missing or empty registry exits 2 and
emits no artifact. IMPORTANT: shell redirection truncates the target BEFORE this binary
runs, so `dagcheck graph DIR > DIR/provenance.json` can destroy a real baseline even on
failure. Regenerate with the atomic form: `dagcheck graph DIR --out DIR/provenance.json`
(temp file + rename on success only; a failed run leaves the existing baseline byte-for-byte
intact - regression fixtures graph-out-sentinel / graph-out-success), or redirect to a
separate temp file and `mv` it into place only after exit 0.

## What the checker does not claim

- It does not prove the English-to-form translation faithful (human artifact).
- It does not check prose rules, instantiation, or analogy (explicitly unchecked).
- It does not mutate the registry, and it never treats `provenance.json` as
  authoritative: the type files are the source of truth; provenance is derived.
- Supersedes edges are history: they never enter dependency closures or cycles.
