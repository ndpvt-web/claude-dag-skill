---
name: DAG
description: Persistent axiom registry + formal proof prompt builder. Transforms any project into a DAG-structured knowledge base where every conclusion cites parent axioms and inference rules. Axioms co-built with user, saved to .dag/ files, referenced by ID (A1, T1, D1, H1) to save tokens and prevent drift. Use when user says "/dag", "/dag init", "/dag prove", "/dag derive", "formal proof mode", or wants traceable auditable reasoning across sessions. All prose output uses caveman compression.
---

# DAG — Persistent Axiom Registry + Formal Proof Builder

Every project gets a `.dag/` directory. Axioms live there. Future proofs reference by ID — not re-stated. Nothing drifts. Everything traces.

## Caveman Rules (all prose output from this skill)

Drop: "I would like to", "please note", "it's worth mentioning", "in order to"
Use fragments. "No session store. JWT only." not "You should not use a session store."
Keep exact: code, IDs, field names, inference rules, statements — never compressed.
Target: 50-65% fewer tokens on prose. Technical accuracy: unchanged.

## Registry Structure

```
{project-root}/
  .dag/
    registry/
      axioms.json         # A-type: structural ground truths — one JSON object keyed by ID
      definitions.json    # D-type: what terms mean — one JSON object keyed by ID
      hypotheses.json     # H-type: scope/existence claims (empirical, falsifiable) — one JSON object keyed by ID
      theorems.json       # T-type: derived conclusions with proof chains — one JSON object keyed by ID
      deprecated.json     # Tombstones: superseded entries, never deleted — one JSON object keyed by ID
    meta/
      registry.json       # Machine index + consistency state (no file paths — ID prefix maps to type file)
      provenance.json     # Full derivation graph
    sessions/
      YYYY-MM-DD-N.md     # Per-session typed scratchpads (markdown — working documents, not structured data)
```

One file per type. All entries of a given type live in a single JSON object keyed by ID. `registry.json` is the summary index: ID → one-liner + status + deps. Agent loads only the type files it needs — max 4 reads for any operation, regardless of entry count.

## Why JSON Type Files, Not Per-Entry Markdown

The three Aristotelian types fail differently:
- D-type: term meaning shifts (drift) → audited as a group in `definitions.json`
- H-type: world changes, scope assumptions go stale → each needs falsification criterion, tracked in `hypotheses.json`
- A-type: can contradict each other → write-time contradiction check needs ALL active axioms at once
- T-type: derived conclusions — stay theorems permanently; if content needs to become foundational, human writes a new A-type from scratch

Type separation matters for auditing. But per-entry separation does not. The dominant operations (contradiction check, cross-model verification, proof chains citing 3+ entries) are all cross-entry — they need multiple entries of the same type simultaneously. Loading `axioms.json` gives you every axiom in one read; the contradiction check no longer aggregates N individual files. JSON structure also enables schema validation, `jq` queries, deterministic lookup by ID key, and no frontmatter parsing edge cases.

## ID Scheme

| Prefix | Type | Example |
|--------|------|---------|
| D | Definition | D1, D2 |
| H | Hypothesis | H1, H2 |
| A | Axiom | A1, A2 |
| T | Theorem | T1, T2 |

IDs are permanent. Never reused after deprecation. Deprecated entries get tombstones added to `registry/deprecated.json` as JSON objects keyed by their original ID.

## Entry Format

Every entry lives as a JSON object inside its type file, keyed by ID. Universal mandatory fields:

```json
{
  "A3": {
    "id": "A3",
    "type": "axiom",
    "label": "short-human-name",
    "statement": "The full formal statement. One sentence. No ambiguity.",
    "created": "YYYY-MM-DD",
    "created_by": "human",
    "status": "active"
  }
}
```

Type-specific additional fields — see references/registry-spec.md.

**Mandatory rules:**
- A-type: `rationale` field required. Cannot be empty. Axiom without rationale = hypothesis in disguise.
- T-type: `derived_from` field required. Theorem without provenance = orphaned claim.
- H-type: `falsification` field required. Hypothesis without falsification = belief, not science.

## Commands

| Command | What it does |
|---------|-------------|
| `/dag init` | Bootstrapping — co-build registry with user (see Bootstrapping section) |
| `/dag prove [claim]` | Build formal proof chain against registry |
| `/dag derive [claim] from [IDs]` | Add new theorem after 5-check validation |
| `/dag add axiom` | Add A-type after contradiction check + derivability probe |
| `/dag add definition` | Add D-type; flags dependent axioms as under-review |
| `/dag add hypothesis` | Add H-type with mandatory falsification criterion |
| `/dag review [H-ID]` | Review an H-type entry — log verdict (valid / amended / deprecated), reset staleness clock |
| `/dag deprecate [ID]` | Deprecate entry; creates tombstone; checks downstream theorems first |
| `/dag status` | Consistency report from registry.json |
| `/dag audit` | Full consistency re-check, all entries |
| `/dag session` | Print current session scratchpad |

## Workflow 1: First Run — `/dag init`

Check `.dag/registry/axioms.json` first. If the file exists and has entries → load `registry.json` for summary, ask: continue / review / start fresh. Never silently overwrite.

Then run bootstrapping in strict order (definitions → hypotheses → axioms). See references/bootstrapping.md for full dialogue.

**Phase order is mandatory.** You cannot write a well-formed axiom before fixing the meaning of the terms it uses.

**Key rule during bootstrapping:** For every proposed axiom, run the derivability probe:
> "Could this be derived from the definitions and hypotheses you've already stated, plus common knowledge?"

If yes → it's a theorem candidate, not an axiom. Derive it, add as T-type.
If no → write it as A-type with a mandatory rationale.

**Completeness checks (qualitative — no fixed counts):**
- Definitions: have you named every project-specific term that could mean different things to different people? If any axiom uses a term someone could reasonably misread, it needs a definition.
- Hypotheses: have you made explicit every assumption about the world that, if false, would change your conclusions?
- Axioms: is every entry genuinely non-derivable from existing entries plus common knowledge? The minimum sufficient set is the goal — neither too few (gaps in reasoning) nor inflated (n² contradiction surface).

After bootstrapping, write all type-level JSON files atomically — one file per type (`registry/definitions.json`, `registry/axioms.json`, etc.), each containing all entries of that type keyed by ID. Update `registry.json` last, after every type file exists. Print summary:
```
Registry initialized for [project]:
  N definitions (D1-DN)
  N hypotheses (H1-HN)
  N axioms (A1-AN)
  0 theorems
Consistency: CLEAN
```

## Workflow 2: Proof Chain — `/dag prove [claim]`

**The LLM is the translator. The registry is the verifier.**

The LLM does not generate truths. It translates the claim into derivation steps that cite registry IDs. Steps that cannot cite a registry ID must be flagged — not resolved silently.

**Session system prompt for every proof chain:**
> "You are constructing a derivation, not generating a position. Every step must cite a specific registry ID. Steps that cannot cite a registry ID must be flagged as HIDDEN ASSUMPTION. Do not resolve hidden assumptions — surface them."

**Proof output format (always):**
```
AXIOM LAYER (active entries used)
───────────────────────────────────────────────────────
A1: [statement]    [active]
D2: [statement]    [active]

THEOREM LAYER
───────────────────────────────────────────────────────
T_new: [conclusion]
    because: A1, D2
    rule: modus ponens
    confidence: CERTAIN | PROBABLE | UNCERTAIN
    therefore: [concrete decision]

HIDDEN ASSUMPTIONS SURFACED
───────────────────────────────────────────────────────
[HIDDEN ASSUMPTION] [text] → Candidate H-type entry

VERIFICATION
───────────────────────────────────────────────────────
[check] [decision]    traces to [ID]
[X] [decision]        NO PARENT → MISSING AXIOM: [what would justify this]

PROOF CONFIDENCE SUMMARY
───────────────────────────────────────────────────────
[CERTAIN N] [PROBABLE N] [UNCERTAIN N]
Weakest link: [step with lowest confidence + reason]
```

**Confidence band definitions (mandatory per proof step):**

| Band | Meaning | When to assign |
|------|---------|----------------|
| CERTAIN | Direct logical consequence; no assumptions beyond stated premises; formal rule applies cleanly | Modus ponens / transitivity where premise-to-conclusion match is unambiguous |
| PROBABLE | Follows with standard domain reasoning; requires one unstated assumption that is common knowledge or industry standard | Step needs a bridging premise not in registry — flag it as [HIDDEN ASSUMPTION] candidate |
| UNCERTAIN | Logical gap present; cannot close without adding an H-type or A-type entry; the step may be wrong | Premises do not entail conclusion without additional claims that are NOT common knowledge |

**Confidence rules:**
- A proof chain where ALL steps are CERTAIN → can be written as T-type without qualification
- A proof chain with PROBABLE steps → can be written as T-type IF all PROBABLE steps have their hidden assumption flagged and user confirms
- A proof chain with ANY UNCERTAIN step → BLOCK write. Must add missing H-type or A-type entry first, then re-derive
- The proof confidence summary is mandatory at the end of every /dag prove or /dag derive output

After proof: ask "Should any hidden assumptions be added as H-type entries?"

## Workflow 3: Add Theorem — `/dag derive [claim] from [IDs]`

Five checks before writing a new theorem entry to `theorems.json`:

1. **Premise existence**: all cited IDs exist and are `status: active`
2. **Term consistency**: all terms in statement have D-type definitions or are general language
3. **Inference validity**: LLM evaluates whether claim follows from premises. Hidden assumptions surfaced as H-type candidates, not silently absorbed.
4. **Contradiction check**: new theorem checked against all active entries (see references/failure-modes.md for check prompt)
5. **Loop check**: no circular dependencies in `derived_from` chain

If check 3 surfaces hidden assumptions → pause. Ask: "Add as H-type entry or revise derivation?" Do not write theorem until resolved.

## Workflow 4: Session Scratchpad

Every session creates `.dag/sessions/YYYY-MM-DD-N.md`. All working claims are typed:

```markdown
[AXIOM-REF A3] statement cited from registry
[HYPOTHESIS-REF H1] statement cited from registry
[ASSUMPTION] unstated assumption — candidate H-type
[DERIVED] conclusion with cited IDs
[CONTRADICTION FLAG] conflict with [IDs] — requires resolution
[THEOREM CANDIDATE] T_n: candidate for /dag derive
[QUESTION] open question
```

No untagged entries in the formal scratchpad section.

## Token Load Modes

**Mode 1 — Summary Index (default):**
Read `registry.json` entry_index — one-liner + status + type per entry. Use at session start, for scoping. Never load type JSON files in this mode.

**Mode 2 — Targeted Type Load (during active proof):**
Read the type-level JSON file for each type cited in the current proof step. Parse the JSON to extract only the cited ID entries. Example: `Read .dag/registry/axioms.json` → extract `A3` by key. If proof cites axioms + one definition, that's 2 reads total. Each type file loads every entry of that type — which is exactly what cross-entry reasoning needs.

**Mode 3 — Full Registry Load:**
Only for: /dag init, /dag audit, /dag deprecate.
Read all four type JSON files + deprecated.json.
Never for routine proof chains.

**Load decision:**
- Session start → Mode 1 (registry.json only)
- /dag prove or /dag derive → Mode 1 + Read type JSON files for cited types on demand (Mode 2)
- /dag status → Read registry.json only (no type file loads)
- /dag init / audit / deprecate → Mode 3 (all type files)
- Contradiction check (every add) → Mode 3 (needs all active entries anyway)

**Why this works:** The contradiction check — which runs on every axiom/theorem/definition addition and cross-model verification — needs ALL active entries of ALL types. With per-entry markdown, that was N individual file reads + aggregation. With type-level JSON: 4 reads (`axioms.json`, `definitions.json`, `hypotheses.json`, `theorems.json`) give you the complete active registry. For proof chains citing a few entries across 2-3 types: 2-3 reads instead of potentially missing relevant uncited entries (the retrieval recall problem documented in Failure Mode 6). JSON also enables `jq` queries for precise field extraction without loading full entry text into context when only specific fields are needed.

## What This Skill Must NOT Do

- Auto-generate axioms without human confirmation of each
- Silently absorb hidden assumptions surfaced during proof chains
- Delete any entry without creating a tombstone in `deprecated.json`
- Add theorem without `derived_from` field
- Add axiom without `rationale` field
- Promote theorems to axioms mechanically — if a theorem's content needs to be foundational, the human writes a NEW A-type entry from scratch with their own words; do not copy-promote
- Load Mode 3 for routine `/dag status` or `/dag session` calls (Mode 3 reserves to init/audit/deprecate/contradiction-check)
- Re-use deprecated IDs
- Write entries as individual markdown files — all entries go into their type-level JSON file

## Verified Checker (mechanical verification)

The `checker/` directory is a Lean 4 verified checker for this registry. It is the
authoritative verdict on anything machine-checkable; the agent's own judgment is not.

- After any `/dag derive` that uses a rule from the machine-checkable fragment, run
  `dagcheck check-step` (see `references/verified-checker.md`) before writing, and
  `dagcheck check` after writing. A rejected verdict blocks the write, same as any
  other guard.
- `/dag audit` includes: `dagcheck check` (validation + verdicts) and, when a
  committed `provenance.json` baseline exists, its `stale-fingerprint` findings are
  the impact list — entries named there need recheck. Never present a drifted entry
  as verified.
- Regenerate `provenance.json` with `dagcheck graph` after every accepted change and
  commit it with the registry. It is a derived artifact; the type files stay the only
  source of truth.
- Verdict vocabulary: verified / rejected / blocked / unchecked / stale. Unchecked is
  an honest non-verdict for prose rules, instantiation, and analogy — say so plainly,
  never imply the checker passed them.
- The checker never mutates the registry. Citation order is rule-argument order for
  machine-checkable rules (see references/verified-checker.md for the contract and
  migration note).

## References

- **Entry format specs + example registry**: references/registry-spec.md
- **Bootstrapping dialogue in full**: references/bootstrapping.md
- **Failure mode guards + contradiction check prompt**: references/failure-modes.md
