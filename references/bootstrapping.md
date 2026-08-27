# Bootstrapping Workflow — /dag init

## The Nous Principle

First principles cannot be derived — they must be directly grasped by the human through accumulated project experience. The skill's role during bootstrapping is Socratic midwife: probe, surface, challenge, scaffold. The human supplies the epistemic foundations. The skill cannot generate axioms on behalf of the user and have the user simply accept them — every axiom that passes without friction is a risk.

## Phase -1: Project Sizing Gate (runs BEFORE existing-registry check)

Ask two questions. Route to mode based on answers.

**Question 1:**
> "How long will this project run?
> (A) Less than 1 week
> (B) 1–4 weeks
> (C) 1 month or longer"

**Question 2:**
> "If a reasoning decision turns out to be wrong, how bad is it?
> (A) Annoying — easily reversed, low cost
> (B) Costly — significant rework or wasted effort
> (C) Critical — irreversible, compliance risk, or major business impact"

**Mode routing:**

| Q1 answer | Q2 answer | Mode |
|-----------|-----------|------|
| A (< 1 week) | A (annoying) | NANO |
| A (< 1 week) | B or C | STANDARD |
| B (1–4 weeks) | A or B | STANDARD |
| B (1–4 weeks) | C (critical) | FULL |
| C (1+ month) | any | FULL |

Print the selected mode and its constraints before proceeding:

**NANO mode** (for short, low-stakes projects):
- Axioms only — no definitions, no hypotheses, no session scratchpads
- Contradiction check (cross-model) still runs on every write
- `/dag prove` and `/dag derive` available; confidence bands required
- Staleness guard: not applicable (no H-type entries)
- Bootstrapping: Phase 3 only (axiom elicitation). Keep the axiom set minimum-sufficient for the task.
- Upgrade path: user can re-run `/dag init` at any time to add definitions and hypotheses and move to STANDARD or FULL

**STANDARD mode** (for medium projects):
- Full structure (D, H, A, T) but relaxed: definitions are optional if terms are unambiguous, hypotheses are recommended but not required
- All guards active but soft: derivability probe, contradiction check, confidence bands
- Staleness review_log required on H-type entries; staleness period set per hypothesis
- Bootstrapping: Phases 0–3, with definitions and hypotheses marked optional

**FULL mode** (for long, high-stakes projects):
- Complete protocol as specified throughout this skill
- All guards hard: mandatory definitions, mandatory hypotheses with falsification, mandatory review_log, staleness period set per hypothesis
- Bootstrapping: Phases 0–3, all phases mandatory

**Upgrade is always allowed.** A user can re-run `/dag init` to upgrade from NANO → STANDARD → FULL. New entries are added; existing entries remain.

Store the selected mode in `registry.json` under `"mode": "nano|standard|full"`.

**File structure created on first init:**
```
.dag/
  registry/
    axioms.json         # populated during bootstrapping — one JSON object, all entries keyed by ID
    definitions.json    # populated during bootstrapping (STANDARD/FULL only)
    hypotheses.json     # populated during bootstrapping (STANDARD/FULL only)
    theorems.json       # empty object {} at init — populated as proofs are derived
    deprecated.json     # empty object {} at init
  meta/
    registry.json
    provenance.json
  sessions/
```

---

## Pre-Bootstrap Check

Before asking anything:

```
if .dag/registry/axioms.json exists AND contains entries:
    Read .dag/meta/registry.json → print summary: entry counts, last-modified, consistency status, current mode
    ask: (a) continue building  (b) review existing  (c) upgrade mode  (d) start fresh
    NEVER silently overwrite
```

## Phase 0: Domain Scoping

Ask one question:

> "Describe this project in 2-3 sentences. What are you trying to prove, decide, or build? Who are the key actors? What is the domain?"

Use the answer to:
1. Identify candidate terms for definition
2. Identify potential scope hypotheses
3. Pre-populate coverage_domains in registry.json

Do not advance to Phase 1 until the description names at least two domain-specific terms that would benefit from formal definition.

## Phase 1: Definition Elicitation

**Completeness principle:** Define every project-specific term that could mean different things to different people or in different contexts. Stop when no remaining terms would be confused by a careful reader. There is no fixed count — the task determines the right number.

**Signals that you need more definitions:**
- An axiom uses a term that two people might interpret differently
- A hypothesis's falsification criterion references an undefined metric or actor

**Signals that you have too many definitions:**
- You're defining words with standard, unambiguous meanings (e.g., "user" when there's only one kind of user in the project)
- Two definitions cover the same distinction

For each candidate term:

> "When you say [TERM], what exactly do you mean in this project?
> Be precise enough that two people could apply this definition and agree on every edge case.
> What does [TERM] explicitly exclude?"

Then:

> "Is there a related term someone might confuse with [TERM]? If so, how are they different here?"

**Consistency check:** Does every term in a proposed definition appear in an existing D-type entry or in general language? If a definition uses an undefined project-specific term, elicit that definition first.

**Anti-pattern to catch:** Definition that makes causal or normative claims. Example: "Engineering velocity is the rate of business metric improvement." This smuggles a causal claim into a definition. Flag it. Split: D-type = meaning of velocity, A-type = causal relationship between velocity and metrics.

## Phase 2: Hypothesis Elicitation

**Completeness principle:** Surface every assumption about the world that, if false, would change your conclusions. There is no fixed count — the task's scope uncertainty determines how many are needed. A narrow, well-understood domain may need one. A wide, uncertain one may need many.

**Signals that you need more hypotheses:**
- A proof step relies on a world-state claim not yet in the registry
- Hidden assumptions keep surfacing during `/dag prove` runs

**Signals that you have too many hypotheses:**
- Multiple hypotheses cover the same scope claim from different angles — consolidate
- A hypothesis is so general it could never be falsified

Ask:

> "What has to be true about the world for your reasoning to hold?
> Not what you want to be true — what you're currently assuming is true."

For each candidate:

> "If this turns out to be false, how would it change your conclusions?"

Then:

> "What would you have to observe — specifically and measurably — to know it's false?"

**Hard gate:** If the user cannot answer the falsification question, the entry is either:
- A definition (definitional, not empirical) → move to Phase 1
- A belief (no falsification possible) → flag explicitly, do not add to registry, or add as a BELIEF type with explicit acknowledgment

Do not accept H-type entries without a falsification criterion.

**Also ask:**

> "When should this assumption be re-checked? What event or condition would make you want to verify it?"

This populates `review_trigger`. Hypotheses without review triggers become permanently stale.

## Phase 3: Axiom Elicitation

**Completeness principle:** The goal is the minimum sufficient axiom set — every entry that cannot be derived from existing entries plus common knowledge, and no entry that can. The right number depends entirely on the domain's complexity. After each proposed axiom, the derivability probe is the gate, not a count.

**Complexity awareness (informational, not a limit):** Axiom sets grow pairwise interaction complexity as n(n-1)/2. Report this count in `/dag status` so the human can judge whether the registry is becoming unmanageable for their team. Consolidation is a judgment call, not a triggered rule.

**Signals that you need more axioms:**
- A proof step cannot cite any existing registry entry and the uncited premise is not common knowledge
- Hidden assumptions surfaced during proofs point to structural truths not yet captured

**Signals of over-axiomatization:**
- Two axioms are logically entailed by a third (one is redundant)
- An axiom can be derived from definitions + hypotheses + common knowledge (it's a theorem)
- The team cannot hold all axioms in mind simultaneously — proof chains become too brittle

Ask:

> "What do you believe is structurally true about this domain — something so fundamental that you're willing to treat it as a starting point rather than a conclusion you'd need to prove?"

**Then ask:**

> "Why do you believe this? State where your confidence comes from — not a derivation, but the source: experience, data, first-principles reasoning, etc."

This populates `rationale`. An axiom without a stated rationale is rejected.

**Then ask:**

> "Is this a hard rule — where any conclusion that violates it is wrong by definition — or a strong default that could be overridden in specific cases with explicit justification?"

This sets `hardness`: hard or defeasible.

**Derivability probe:** After each proposed axiom, run: "Could this be derived from the definitions and hypotheses you've already stated, plus widely-accepted general knowledge?" If yes → theorem candidate, not an axiom. If no → proceed.

**Contradiction check during axiom elicitation:** After each proposed axiom, run the consistency check against all existing entries (see failure-modes.md for the check prompt). Do not advance to the next axiom if a contradiction is flagged.

## Phase 4: Review and Confirmation

Print full proposed registry. Ask:

> "Before I write these files, check three things:
> 1. Is any axiom actually derivable from other axioms plus your definitions?
> 2. Do any two axioms feel like they might conflict in edge cases?
> 3. Are there any terms in your axioms that don't have definitions?
>
> Fix any of these now. Once written to disk, changes require explicit amendment with a timestamp."

Only after explicit confirmation: write all type-level JSON files atomically — one file per type (`registry/definitions.json`, `registry/axioms.json`, `registry/hypotheses.json`), each containing all entries of that type keyed by ID. Create empty `registry/theorems.json` and `registry/deprecated.json` as `{}`. Update `registry.json` last, after every type file exists, so the index is never ahead of the files it points to.

## Output After Bootstrapping

Print summary in caveman format:

```
Registry initialized: [project-name]
  D: [N] definitions (D1-DN)
  H: [N] hypotheses (H1-HN)
  A: [N] axioms (A1-AN)
  T: 0 theorems
Coverage: [domains]
Consistency: CLEAN
Last check: [date]

Commands: /dag prove [claim] | /dag derive [claim] from [IDs] | /dag status
```

## What to Do When User Resists Formal Structure

Some users will push back on the formal definition phase. Common objections and responses:

**"These terms are obvious."**
Response: "The terms feel obvious to you because you're deep in the domain. The definitions protect future-you and collaborators when the term starts meaning slightly different things across sessions. Takes 5 minutes. Worth it."

**"I don't know the falsification criterion."**
Response: "That's important information. If you can't falsify an assumption, it's either definitional (in which case it belongs in definitions, not hypotheses) or it's a belief you're committed to regardless of evidence. Which is it?"

**"Can't you just generate the axioms from what I told you?"**
Response: "I can propose candidates, but you need to confirm each one with friction, not just accept them. An axiom I generate and you rubber-stamp is a guess disguised as a foundation. The value is in your judgment about what's actually non-derivable in your domain."
