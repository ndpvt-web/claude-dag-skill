# DAG — Persistent Axiom Registry + Formal Proof Builder

## Executive Summary

**DAG** is a Claude Code skill that transforms any multi-session project into a persistent, formally-typed knowledge base where every conclusion traces back to its foundational assumptions. Instead of regenerating reasoning from scratch in each session, DAG stores project axioms, definitions, and hypotheses in a `.dag/` directory and references them by ID (A1, T1, D1, H1). Every proof, decision, and derivation must cite these entries or explicitly surface unstated assumptions. This prevents reasoning drift, catches contradictions before they propagate, keeps stale assumptions from poisoning proof chains, and creates an auditable record of why each decision was made.

### Who Should Use This

- **Architects & Strategy Teams**: Formalize product principles, market assumptions, and architectural axioms once. Refer to them by ID across sessions. When the market shifts, update one hypothesis entry and automatically surface all downstream conclusions that need re-verification.
- **Compliance & Legal Teams**: Encode regulatory requirements and interpretive principles as axioms. Every architectural or business decision then traces explicitly to those rules.
- **Research & Academic Teams**: Formalize theoretical frameworks. Define domain terms precisely. Derive testable predictions. When an experiment challenges an axiom, identify all dependent theorems via the derivation graph.
- **Long-Running Infrastructure or Software Projects**: Store architectural principles as axioms. When proposing a new technology or pattern, prove it consistent with existing axioms or explicitly add a new axiom to the registry.
- **Multi-disciplinary Teams**: When team members have different assumptions, DAG forces those assumptions to surface and be either shared or explicitly noted as team-specific hypotheses.

### Key Benefits

1. **No Session Drift**: Definitions, principles, and assumptions don't silently shift between sessions. They live in the registry.
2. **Contradiction Detection**: Cross-model consistency checking at write time catches two axioms that individually sound plausible but whose conjunction is false.
3. **Stale Assumption Blocking**: Hypotheses that were true at start can be marked with a staleness period. After that period, they're automatically flagged for re-review before being used in new proofs.
4. **Auditable Reasoning**: Every theorem traces its derivation chain. Clients, auditors, or future team members can see exactly why a decision was made and what assumptions it rested on.
5. **Hidden Assumption Surfacing**: Proofs that silently absorb unstated assumptions instead get flagged. Those assumptions become candidates for new hypothesis entries, making the registry more complete over time.
6. **Token Efficiency**: After initial setup, proofs reference axioms by ID (e.g., "A3") rather than re-stating them. This saves tokens and prevents the re-statement from drifting.

### Real-World Examples

**Example 1: Product Strategy at a Startup**

A founding team uses DAG to formalize their retention model:
- **D1**: "User" means a human with a specific task intent (not a bot, not an admin)
- **H1**: "Churn is primarily a product quality problem, not pricing" — with falsification criterion: "If >40% of exit survey respondents cite price or mention a competitor's feature, this is false"
- **A1**: "Sustainable revenue growth requires LTV > CAC, only achievable through retained users"
- **T1**: "Improving onboarding completion is higher-leverage than feature depth at current stage" (derived from A1 + market data)

When the company considers a pricing experiment 6 months later, H1's staleness trigger fires. The team re-verifies: "Is it still true that churn is quality-driven?" Once confirmed, T1 can be cited in new strategic proofs. If H1 becomes false, T1 is automatically flagged for re-evaluation.

**Example 2: Infrastructure Architecture**

A platform team encodes architectural principles:
- **A1**: "No session store. JWT only."
- **A2**: "All services must be stateless."
- **D1**: "Stateless" means no in-memory mutable state shared across requests; external caches are allowed.

When a new service design is proposed, `/dag prove [service design is consistent with architecture]` forces every claim to cite A1, A2, D1, or surface as a hidden assumption. If the design relies on session affinity, that hidden assumption is surfaced. The team then chooses: add a new axiom ("session affinity is acceptable for this service") or redesign.

**Example 3: Compliance & Security**

A team building a HIPAA-compliant system uses DAG to formalize the compliance axioms:
- **H1**: "All user data must be encrypted at rest." Falsification: regulatory change permits unencrypted storage.
- **H2**: "Audit logs must be immutable after 90 days." Falsification: HIPAA audit guidance changes.
- **A1**: "Every architectural decision must trace to a HIPAA requirement or company policy."

Every new service design then goes through `/dag prove [this service complies with H1 + H2 + A1]`. Proofs that can't close gaps are rejected before deployment. When regulations change, H1 and H2 are reviewed and updated, and affected theorems are automatically flagged.

---

## What DAG Does — In Depth

### The Core Problem

Normal LLM-assisted reasoning has a fundamental fragility: it doesn't persist. Each new session, the LLM regenerates project context from your description. Over weeks or months, those regenerations drift. The definition of "user" in month 1 differs subtly from month 6. An axiom that the team agreed on becomes implicit, and future reasoning absorbs a variant. Assumptions about the market or the system that were explicitly discussed get forgotten. When someone proposes a decision, there's no single source of truth to check it against.

DAG externalizes the project's reasoning foundations to the filesystem. Instead of existing only in the context window, they persist. Instead of being re-stated (and drifting), they're referenced by ID. Instead of being implicitly absorbed, unstated assumptions are surfaced.

### The Architecture

DAG creates a `.dag/` directory at your project root with this structure:

```
.dag/
  registry/
    definitions/      # D1.md, D2.md, ... (what terms mean)
    hypotheses/       # H1.md, H2.md, ... (scope/existence assumptions)
    axioms/           # A1.md, A2.md, ... (structural ground truths)
    theorems/         # T1.md, T2.md, ... (derived conclusions)
    deprecated/       # Tombstones (never deleted, never re-used)
  meta/
    registry.json     # Machine index: ID → file path, status, one-liner
    provenance.json   # Full derivation graph (which theorems depend on which axioms)
  sessions/
    YYYY-MM-DD-N.md   # Per-session typed working notes
```

**One file per entry.** This architectural choice prevents context pollution. Retrieving axiom A3 loads only A3.md, not a massive axioms.md containing every axiom.

### The Four Types (DHAT)

Every entry is one of four types, chosen based on what it asserts:

#### **D-type: Definition**
What a project-specific term means in *this* project's context. Definitions fix **meaning only** — no causality, no normativity.

Example: "**User** is a human with a named task intent, not a bot, not an admin, not a service account." This defines the scope. It does **not** say why users matter or what causes retention.

If a proposed definition asserts causality ("User is a person likely to pay"), that's sneaking an axiom into the definition. DAG forces a split: separate D-type for the meaning, separate A-type for the causal claim.

**Guard**: When a D-type is amended, all A-types that depend on it are automatically flagged as `under-review` and blocked from citation until re-confirmed.

#### **H-type: Hypothesis**
A scope or existence claim — something assumed to be true about the world right now, empirically falsifiable.

Example: "Churn is primarily a product quality problem, not pricing." This is empirical (observation-dependent), not structural. If the observation changed (60% of exit surveys cite pricing), the hypothesis is false.

Every H-type **requires a falsification criterion** — what specific observation would prove it wrong. If you can't state one, it's not a hypothesis; it's a belief, and DAG won't store it.

H-types also carry an optional `staleness_period_days`. If set, the entry is automatically flagged `under-review` after that period. If the project-state changes (a market shift, a competitor launch), you manually trigger a `review_trigger` and the entry is flagged. Stale H-types are **blocked from citation** in proof chains until reviewed.

**Guard**: Time-based and event-based auto-staleness prevents old assumptions from silently poisoning new proofs.

#### **A-type: Axiom**
A structural ground truth — genuinely non-derivable from existing definitions, hypotheses, and common knowledge.

Example: "Sustainable revenue growth requires LTV > CAC, achievable only through retained users." This is a structural principle about the business model. It's not a hypothesis (not falsifiable by observation). It's not a definition (it asserts a causal relationship). It's foundational.

Every A-type **requires a non-empty rationale** field — the argument for why this is non-derivable. An axiom without rationale is a hypothesis in disguise.

A-types also carry `hardness: hard | defeasible`. Hard axioms: violating them is a contradiction by definition. Defeasible axioms: strong defaults overridable with explicit justification.

**Guard**: The derivability probe (run during bootstrapping and theorem derivation) challenges every proposed axiom. If it could be derived from existing entries + common knowledge, it's reclassified as a theorem, not added as a new axiom.

#### **T-type: Theorem**
A derived conclusion with a full proof chain.

Example: "Improving onboarding completion is higher-leverage than feature depth at current stage" — derived from A1 (LTV > CAC constraint) + market data on retention curves.

Every T-type **requires**:
- `derived_from`: the list of entry IDs it was derived from (e.g., [A1, H2, D1])
- `inference_rule`: the logic rule applied (e.g., "modus ponens", "instantiation", "analogy")
- `proof_confidence`: CERTAIN, PROBABLE, or UNCERTAIN

Theorems **stay theorems permanently**. They are never mechanically promoted to axioms. If a team later decides a theorem's content is actually foundational, they write a **new** A-type from scratch with their own words — they don't copy-promote the theorem.

**Guard**: Mandatory traceability prevents orphaned claims.

---

### Three Workflows

#### **Workflow 1: Bootstrapping (`/dag init`)**

Before adding anything to the registry, DAG runs a "Project Sizing Gate" to choose a mode:

- **NANO mode**: Short, low-stakes projects. Axioms only (no D or H types). Minimal structure.
- **STANDARD mode**: Medium projects. Full D/H/A/T structure, but definitions and hypotheses are recommended, not required.
- **FULL mode**: Long or high-stakes projects (compliance, research, architecture). All types mandatory. All guards hard-enforced.

Then the bootstrapping proceeds through **four strict phases**:

**Phase 1 — Domain Scoping**: You describe the project in 2–3 sentences. DAG identifies candidate terms and scope assumptions.

**Phase 2 — Definition Elicitation**: Socratic dialogue. For every project-specific term that could mean different things to different people, define it precisely. Example: In a medical compliance project, "patient data" has a specific meaning. In a B2B SaaS project, "user" means something else. No definition → ambiguity → later axioms will be misunderstood.

**Phase 3 — Hypothesis Elicitation**: Every assumption about the world that, if false, would change your conclusions. Example: "Churn is quality-driven, not price-driven." Hard gate: every H-type must have a falsification criterion. If you can't state what would prove it false, it stays out of the registry.

**Phase 4 — Axiom Elicitation**: For every proposed axiom, DAG runs the **derivability probe**: "Could this be derived from the definitions and hypotheses you've just stated, plus common knowledge?" If yes → it's actually a theorem. If no → it's an axiom. Rationale required.

After Phase 4, a confirmation round reviews the full proposed registry for derivability conflicts and undefined terms. Then all entry files are written atomically (one file per entry), and `registry.json` is written last.

The **Nous Principle** (attributed to Aristotle, foundational to DAG): "First principles cannot be derived — they must be directly grasped by the human through accumulated project experience." DAG is a Socratic midwife: it probes, challenges, scaffolds. But the human supplies the epistemic foundations.

#### **Workflow 2: Proof Chains (`/dag prove [claim]`)**

You state a claim. DAG translates it into derivation steps, each citing a registry ID. Steps that cannot cite an ID are flagged as `[HIDDEN ASSUMPTION]`, not silently resolved.

**Session system prompt for every proof:**
> "You are constructing a derivation, not generating a position. Every step must cite a specific registry ID. Steps that cannot cite a registry ID must be flagged as HIDDEN ASSUMPTION. Do not resolve hidden assumptions — surface them."

**Proof output always includes:**

1. **AXIOM LAYER**: Active A-type and D-type entries used.
2. **THEOREM LAYER**: The derived conclusion, the IDs it cites, the inference rule, and the confidence band.
3. **HIDDEN ASSUMPTIONS SURFACED**: Any step that couldn't cite a registry ID. These are candidates for new H-type entries.
4. **VERIFICATION**: For each major decision, what ID justifies it. If no ID exists, what would need to be added.
5. **PROOF CONFIDENCE SUMMARY**: Count of CERTAIN, PROBABLE, UNCERTAIN steps. Identifies the weakest link.

**Confidence bands:**

| Band | Meaning |
|------|---------|
| **CERTAIN** | Direct logical consequence; formal rule applies cleanly; no unstated premises beyond what's in the registry |
| **PROBABLE** | Follows with standard domain reasoning; requires one bridging premise that's common knowledge or industry standard |
| **UNCERTAIN** | Logical gap present; cannot close without adding a new H or A entry. Blocks theorem write. |

- All CERTAIN steps → theorem can be written without qualification.
- PROBABLE steps → theorem can be written IF all PROBABLE steps have their hidden assumption flagged and user confirms.
- ANY UNCERTAIN step → proof is blocked. You must add the missing H or A entry first.

After proof: DAG asks "Should any hidden assumptions be added as H-type entries?"

#### **Workflow 3: Adding Theorems (`/dag derive [claim] from [IDs]`)**

Five checks run before writing a new theorem:

1. **Premise existence**: All cited IDs exist and are `status: active`.
2. **Term consistency**: All terms in the statement have D-type definitions or are general language.
3. **Inference validity**: Does the claim actually follow from the premises? Hidden assumptions are surfaced, not absorbed.
4. **Contradiction check**: Is the new theorem consistent with all active entries? (Uses cross-model verification — see below.)
5. **Loop check**: No circular dependencies in the `derived_from` chain.

If check 3 surfaces hidden assumptions, the workflow pauses. You decide: add them as H-type entries or revise the derivation. Theorem is not written until resolved.

---

### Write-Time Contradiction Detection

Before **every** write of a new entry, a consistency check runs:

1. The primary LLM (Claude) checks for contradictions.
2. Two additional models from **different provider families** also run the same check in parallel (using separate workers).
3. If all three agree: no contradiction. Write proceeds.
4. If any one flags a contradiction: write is blocked. Human resolution required.

**Why cross-model?** Different LLM families have different training distributions and different attention failure modes. A contradiction one model misses, another may catch. This multi-model approach catches more false theorems than any single model.

---

### Token Load Modes

DAG defines three modes to manage LLM context window efficiently:

| Mode | What Loads | When to Use |
|------|-----------|-----------|
| **Mode 1 — Summary Index** | Only `registry.json` (one-liner + status + file path per entry) | Session start, scoping decisions |
| **Mode 2 — Targeted Full Load** | Individual entry files for IDs actually cited in the current proof step | Active proof chains, derivations |
| **Mode 3 — Full Registry Load** | All individual entry files across all type directories | `/dag init`, `/dag audit`, `/dag deprecate` only |

**Why this matters:** Under a single-file architecture (old approach), reading one axiom means reading axioms.md, which contains every other axiom. With DAG's individual-file approach, reading A3 loads only A3.md. This is the **atomic access guarantee** — zero context pollution.

---

### Session Scratchpad

Every session creates a typed scratchpad at `.dag/sessions/YYYY-MM-DD-N.md`. All working claims use explicit type tags:

```markdown
[AXIOM-REF A3] statement cited from registry
[HYPOTHESIS-REF H1] statement cited from registry
[ASSUMPTION] unstated assumption — candidate H-type
[DERIVED] conclusion with cited IDs
[CONTRADICTION FLAG] conflict with [IDs]
[THEOREM CANDIDATE] T_n: ready for /dag derive
[QUESTION] open question
```

No untagged entries in the formal scratchpad. This forces rigor and makes it easy to spot what still needs registry entry vs. what's speculative.

---

### Entry Lifecycle & Deprecation

Entries are never deleted. When an entry is superseded or becomes false, it is **deprecated**:

1. A tombstone file is created at `registry/deprecated/{original-ID}.md` preserving the original statement.
2. The original ID is never reused.
3. Downstream theorems citing the deprecated entry are flagged for re-derivation.
4. The full derivation graph (provenance.json) is consulted to identify all affected theorems before deprecation is allowed.

This preserves the audit trail and prevents IDs from being silently repurposed.

---

### What DAG Does NOT Do

- **Auto-generate axioms**: Every axiom requires human confirmation. No rubber-stamping.
- **Silently absorb assumptions**: Hidden assumptions are surfaced, never hidden.
- **Delete entries**: Deprecation creates tombstones; deletion is not an option.
- **Orphan claims**: Every theorem requires a `derived_from` field; every axiom requires a `rationale` field.
- **Promote theorems to axioms mechanically**: If content needs to be foundational, the human writes a new A-type from scratch.
- **Load all entries for routine proofs**: Mode 3 is forbidden for proof chains; only Mode 1 + 2.
- **Reuse IDs**: Deprecated IDs stay dead.

---

## File Formats & Specs

### registry.json (Machine Index)

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
  "entry_index": {
    "D1": {
      "label": "user",
      "status": "active",
      "statement": "...",
      "file": "registry/definitions/D1.md"
    }
  }
}
```

The `file` field is mandatory. Agents resolve full entry text by reading `{project-root}/.dag/{file}`.

### Entry YAML Frontmatter (Universal)

Every entry has:

```yaml
---
id: A3
type: axiom
label: "short-human-name"
statement: "The full formal statement. One sentence. No ambiguity."
created: YYYY-MM-DD
created_by: human | derived
status: active | under-review | deprecated
---
```

**Type-specific additional fields:**

**D-type (Definition):**
```yaml
term: "the project-specific term"
scope: "what contexts this definition applies to"
distinguishes_from: [related_term_1, related_term_2]
```

**H-type (Hypothesis):**
```yaml
scope_claim: "what world state this assumes"
falsification: "specific, measurable observation that would disprove this"
review_trigger: "event that triggers manual re-review"
staleness_period_days: null | integer
review_log: []  # Array of {date, verdict (valid/amended/deprecated), note}
```

**A-type (Axiom):**
```yaml
domain: ["domain1", "domain2"]
hardness: hard | defeasible
depends_on: [D1, D2]  # D-type IDs this axiom uses
rationale: "Why this is non-derivable from existing entries"
```

**T-type (Theorem):**
```yaml
derived_from: [A1, D2, H3]  # IDs that justify this theorem
inference_rule: "modus ponens | transitivity | instantiation | ..."
derivation_note: "How premises combine to yield conclusion"
proof_confidence: CERTAIN | PROBABLE
session_derived: "YYYY-MM-DD"
```

---

## Common Failure Modes & Guards

DAG explicitly guards against these failure modes:

| Failure Mode | What Goes Wrong | DAG's Guard |
|--------------|-----------------|------------|
| **Axiom Drift** | Term meaning shifts; axiom text unchanged but effective meaning differs | `depends_on` field on A-types; amending D-type auto-flags dependent A-types as `under-review` |
| **Contradiction Accumulation** | Two individually plausible axioms produce false theorem when combined | Cross-model write-time contradiction check |
| **Stale Axioms** | Axiom was true at t=0; world changed; axiom still cited in proofs | H-type `staleness_period_days` + `review_trigger`; stale entries blocked from citation |
| **Over-Axiomatization** | Too many axioms; contradiction surface explodes; registry becomes unusable | Derivability probe; axiom counts shown in `/dag status` |
| **Missing Hypotheses** | Scope assumptions implicit; proof chains rest on unstated world-state | Hidden assumption surfacing in every proof; session-end prompt to convert to H-types |
| **Retrieval Failure** | Right axiom exists but isn't retrieved or cited | One-entry-per-file architecture; post-retrieval entailment check; Mode 2 targeted loading |
| **Over-Retrieval** | Too many entries loaded; LLMs ignore middle-of-context information | Mode 1 default; Mode 2 on-demand; Mode 3 only for init/audit/deprecate |
| **Unreviewed Stale Hypotheses** | H-type became false over time; continues to be cited | Mandatory `review_log` field; `under-review` status blocks citation |

---

## Commands Quick Reference

| Command | What it does |
|---------|-------------|
| `/dag init` | Bootstrap the registry (interactive, co-builds with you) |
| `/dag prove [claim]` | Build a formal proof chain against registry; surface hidden assumptions |
| `/dag derive [claim] from [IDs]` | Add a new theorem with 5-check validation |
| `/dag add axiom` | Add A-type after derivability probe + contradiction check |
| `/dag add definition` | Add D-type; flags dependent axioms as `under-review` |
| `/dag add hypothesis` | Add H-type with mandatory falsification criterion |
| `/dag review [H-ID]` | Re-verify a hypothesis; log verdict; reset staleness clock |
| `/dag deprecate [ID]` | Deprecate entry; create tombstone; check downstream theorems |
| `/dag status` | Print consistency report from `registry.json` |
| `/dag audit` | Full consistency re-check (loads all entries) |
| `/dag session` | Print current session scratchpad |

---

## When to Use DAG

**Perfect fit:**
- Long-running projects (months or years) where reasoning foundations need to persist across many sessions
- High-stakes decisions where reasoning must be auditable (compliance, architecture, strategy)
- Multi-disciplinary teams with different implicit assumptions
- Research or theory work that accumulates over time
- Projects where "why did we make this choice?" must be answerable

**Not ideal:**
- One-off, single-session tasks
- Rapid prototyping where foundation shifts constantly
- Projects where informal reasoning is sufficient
- Teams that prefer speed over traceability

---

## Getting Started

1. Run `/dag init` at the start of your project
2. Follow the four-phase bootstrapping dialogue
3. After each session, check the session scratchpad for new hypotheses to formalize
4. When making decisions, use `/dag prove [decision]` to verify it against existing axioms
5. When adding new principles, use `/dag add axiom` (or hypothesis, or definition)
6. Periodically run `/dag status` to monitor registry health and identify stale entries

---

## Philosophy

DAG's core principle comes from Aristotle: **"First principles cannot be derived — they must be directly grasped by the human through accumulated project experience."** The skill doesn't generate your axioms for you. It scaffolds your own reasoning, surfaces hidden assumptions, guards against contradictions, and persists the foundations across sessions. The result: reasoning that is traceable, auditable, and stable.
