# Registry Entry Specifications

## D-type (Definition)

```yaml
---
id: D1
type: definition
label: "short-name"
term: "the exact term being defined"
statement: "Single sentence. What the term means in this project."
scope: "where this definition applies — name the domains"
distinguishes_from: ["related term 1", "related term 2"]
created: YYYY-MM-DD
created_by: human
status: active
---

Rationale: Why this disambiguation matters — what breaks if the term is left ambiguous.
```

Guard: Definitions fix meaning only. If a proposed definition asserts causality, correlation, or normative claims — it is smuggling in an axiom. Flag it. Split it.

Example:
```yaml
---
id: D1
type: definition
label: user
term: "user"
statement: "A user is a human operating the product interface with intent to accomplish a task."
scope: "applies to all product and retention reasoning"
distinguishes_from: ["automated agent", "admin", "API consumer"]
created: 2026-05-17
created_by: human
status: active
---
```

## H-type (Hypothesis)

```yaml
---
id: H1
type: hypothesis
label: "short-name"
statement: "Single sentence. What is assumed to be true about the world right now."
scope_claim: "what this hypothesis asserts exists or applies"
falsification: "what observation would render this hypothesis invalid — specific and measurable"
review_trigger: "event or condition that mandates re-checking this hypothesis"
staleness_period_days: null   # optional — set to an integer (e.g. 30, 90, 180) to enable time-based staleness.
                              # omit or null = event-only staleness via review_trigger.
created: YYYY-MM-DD
created_by: human
status: active             # active | under-review | deprecated
review_log: []             # Required. Appended on every /dag review invocation.
---
```

**review_log entry format:**
```yaml
review_log:
  - date: YYYY-MM-DD
    verdict: valid          # valid | amended | deprecated
    note: "optional — what was checked or changed"
```

**Staleness rule (automatic, no user trigger required):**
- Applies only when `staleness_period_days` is set to a non-null integer
- If `review_log` is empty AND today > `created` + `staleness_period_days` → `status` auto-set to `under-review`
- If `review_log` is non-empty AND today > most recent review_log date + `staleness_period_days` → `status` auto-set to `under-review`
- When `staleness_period_days` is null/omitted: staleness is event-driven only via `review_trigger` — no automatic time-based transition
- `under-review` entries are **BLOCKED from citation** in new proof chains (see failure-modes.md, Failure Mode 8)
- Only `/dag review [H-ID]` can reset status to `active`

**Setting staleness_period_days:** The human who writes the hypothesis knows how quickly its underlying assumption can decay. Fast-changing market or behavioral assumptions → short period (14–30 days). Slow-changing structural assumptions → longer period (90–365 days). Timeless structural claims → null (event-only review).

Guard: If the user cannot state a falsification criterion, the entry is either a definition (definitional, not empirical) or a belief. Do not accept as H-type without a falsification criterion.

Example:
```yaml
---
id: H1
type: hypothesis
label: churn-is-product-problem
statement: "User churn at current stage is primarily caused by product quality gaps, not pricing or competition."
scope_claim: "applies to retention strategy for the next 2 quarters"
falsification: "Exit survey data shows > 40% of churned users cite price or competitor as primary reason."
review_trigger: "Any quarterly cohort analysis; any pricing experiment launch."
created: 2026-05-17
created_by: human
status: active
---
```

## A-type (Axiom)

```yaml
---
id: A1
type: axiom
label: "short-name"
statement: "Single sentence. The structural ground truth."
domain: ["domain1", "domain2"]
hardness: hard         # hard = violation is contradiction | defeasible = strong default, overridable
depends_on: ["D1", "D2"]
rationale: "Why this is not derivable from other entries. The source of confidence."
created: YYYY-MM-DD
created_by: human
status: active
---
```

Guard: `rationale` is mandatory and cannot be empty. An axiom without rationale is a hypothesis disguised. The act of writing rationale often reveals the entry is actually derivable — which means it should be T-type, not A-type.

`hardness` values:
- `hard` — formal constraint. Any output that violates this is contradictory by definition.
- `defeasible` — strong default. Can be overridden with explicit stated warrant.

Example:
```yaml
---
id: A1
type: axiom
label: retention-drives-growth
statement: "Sustainable revenue growth requires that LTV exceeds CAC, which is only achievable at scale through retained customers, not solely new acquisition."
domain: ["strategy", "growth"]
hardness: hard
depends_on: ["D1"]
rationale: "Unit economics principle. Not derivable from other axioms in this registry — it establishes the causal relationship between retention and growth that all product-value theorems depend on."
created: 2026-05-17
created_by: human
status: active
---
```

## T-type (Theorem)

```yaml
---
id: T1
type: theorem
label: "short-name"
statement: "Single sentence. The derived conclusion."
derived_from: ["A1", "D2", "H1"]
inference_rule: "name of the inference rule(s) applied — see reference table or name any valid rule"
derivation_note: "How the premises combine to produce this conclusion."
proof_confidence: "CERTAIN | PROBABLE"    # UNCERTAIN blocks write — resolve first
session_derived: YYYY-MM-DD
status: active
---
```

Guard: `derived_from` is mandatory. Theorem without provenance = orphaned claim. Never permitted.

**Promotion abolished:** Theorems are NEVER mechanically promoted to axioms. If a theorem's content needs to be treated as a structural ground truth, the human writes a NEW A-type entry from scratch in their own words. Theorems stay theorems permanently. The `promoted` and `promotion_date` fields are removed — do not add them.

Example:
```yaml
---
id: T1
type: theorem
label: onboarding-is-retention-lever
statement: "Improving onboarding completion rate is a higher-leverage retention investment than feature depth improvements at current stage."
derived_from: ["A1", "A3", "H1"]
inference_rule: "conjunction + modus ponens: A1 establishes retention as growth driver; A3 establishes month-1 churn as onboarding failure; H1 establishes product quality as current churn cause. Together: fixing onboarding addresses the cause (H1) via the highest-leverage retention mechanism (A1+A3)."
proof_confidence: PROBABLE
session_derived: 2026-05-17
status: active
---
```

## Tombstone Format (deprecated.md)

```yaml
---
id: A2
type: axiom
deprecated_on: 2026-06-01
reason: "Stale — assumption about market segment no longer holds post-pivot."
superseded_by: A7
original_statement: "Enterprise buyers evaluate tools primarily on integration breadth."
---
```

Never delete entries. Only tombstone. The original statement must be preserved so derivation chains that cited this ID can be audited.

## registry.json Structure

```json
{
  "project": "project-name",
  "version": "1.0",
  "created": "YYYY-MM-DD",
  "last_modified": "YYYY-MM-DD",
  "mode": "nano|standard|full",
  "counts": {
    "definitions": 4,
    "hypotheses": 3,
    "axioms": 7,
    "theorems": 12,
    "deprecated": 2
  },
  "consistency": {
    "last_check": "YYYY-MM-DD",
    "status": "clean",
    "known_tensions": [],
    "open_contradictions": []
  },
  "coverage_domains": ["domain1", "domain2"],
  "entry_index": {
    "D1": {
      "label": "user",
      "status": "active",
      "statement": "A user is a human operating the product interface with intent to accomplish a task.",
      "file": "registry/definitions/D1.md"
    },
    "A1": {
      "label": "retention-drives-growth",
      "status": "active",
      "statement": "Sustainable revenue growth requires LTV > CAC, achievable at scale only through retained customers.",
      "depends_on": ["D1"],
      "domain": ["strategy", "growth"],
      "file": "registry/axioms/A1.md"
    },
    "T1": {
      "label": "onboarding-lever",
      "status": "active",
      "statement": "Improving onboarding completion rate is a higher-leverage retention investment than feature depth at current stage.",
      "derived_from": ["A1", "A3"],
      "file": "registry/theorems/T1.md"
    }
  }
}
```

The `file` field is mandatory for every entry_index entry. It is the relative path from the project root `.dag/` directory to the entry's individual file. Agents resolve full entry text by: `Read {project-root}/.dag/{file}`.

**File naming convention:** `registry/{type-dir}/{ID}.md`
- Axioms: `registry/axioms/A1.md`, `registry/axioms/A2.md`
- Definitions: `registry/definitions/D1.md`
- Hypotheses: `registry/hypotheses/H1.md`
- Theorems: `registry/theorems/T1.md`
- Deprecated tombstones: `registry/deprecated/{original-ID}.md`
```

## Inference Rules Reference

Common rules — not an exclusive list. Any valid named inference rule from logic, mathematics, or domain-specific reasoning is acceptable. If using a rule not in this table, name it explicitly in the `inference_rule` field and describe the form in `derivation_note`.

| Rule | Form | Use |
|------|------|-----|
| Modus ponens | A→B, A ∴ B | Direct consequence |
| Modus tollens | A→B, ¬B ∴ ¬A | Deny the consequent |
| Transitivity | A→B, B→C ∴ A→C | Chained implication |
| Conjunction intro | A, B ∴ A∧B | Both required together |
| Conjunction elim | A∧B ∴ A | Extract one conjunct |
| Disjunction intro | A ∴ A∨B | Extend to disjunction |
| Contrapositive | A→B ∴ ¬B→¬A | Negation flip |
| Instantiation | ∀x.P(x) ∴ P(c) | Universal applied to specific case |
| Dilemma | A∨B, A→C, B→C ∴ C | Cases exhausted |
| Analogy | Structure(A)=Structure(B), P(A) ∴ P(B) | Structural correspondence — use with PROBABLE confidence |

## Anti-Patterns

| Anti-pattern | Problem | Fix |
|-------------|---------|-----|
| Definition with causal claim | "velocity is the rate of metric improvement" — smuggles causation | Split into D-type (meaning) + A-type (causal claim) |
| Axiom-shaped hypothesis | Sounds foundational but is empirically falsifiable | Add falsification criterion → move to H-type |
| Theorem without derived_from | Orphaned claim — not traceable | Mandatory field. Block write without it. |
| Axiom without rationale | Cannot verify it's non-derivable | Mandatory field. Block write without it. |
| Registry inflation | Adding one-session claims to the registry | Registry = load-bearing only. Session claims go in scratchpad. |
| Orphaned deprecation | Deprecating without checking downstream theorems | /dag deprecate checks provenance.json first |
