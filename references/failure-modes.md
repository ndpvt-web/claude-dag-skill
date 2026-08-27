# Failure Mode Guards

## Write-Time Contradiction Check

Run before EVERY write of a new entry. Do not skip. Do not batch.

**Loading entries for the check:** Read `registry.json` → collect active entry IDs → Read all four type JSON files (`axioms.json`, `definitions.json`, `hypotheses.json`, `theorems.json`). This is a Mode 3 load (all active entries), justified because contradiction checks require full context.

```bash
# Load all active entries: 4 reads total, regardless of entry count
# Previously required N individual file reads + aggregation
jq 'to_entries | map(select(.value.status == "active")) | from_entries' .dag/registry/axioms.json
jq 'to_entries | map(select(.value.status == "active")) | from_entries' .dag/registry/definitions.json
jq 'to_entries | map(select(.value.status == "active")) | from_entries' .dag/registry/hypotheses.json
jq 'to_entries | map(select(.value.status == "active")) | from_entries' .dag/registry/theorems.json
```

**Check prompt (give to LLM with full active registry as context):**

```
REGISTRY CONSISTENCY CHECK

Existing active entries:
[full text of all active D, H, A, T entries — loaded from the four type JSON files, filtered to status: active]

Proposed new entry:
Type: [type]
Statement: [statement]
[all fields]

Task:
1. Does the proposed entry directly contradict any existing entry?
2. Do any two existing entries, combined with the proposed entry, produce a contradiction via simple inference?
3. Does the proposed entry use any term that is defined differently than in existing D-type definitions?

Output only:
CONSISTENT
or
CONTRADICTION: [IDs] — [explanation]
or
TERM MISMATCH: [term] — [how it differs from D-type definition]

Do not approve contradictions. Do not silently resolve — surface to user.
```

**Critical limitation:** The LLM running this check is the same one writing proof chains. This is heuristic, not formal. It catches obvious contradictions. Subtle contradictions may survive. Per Gödel: no system can fully audit its own consistency. Communicate this to users when relevant. The check is a first-pass filter, not a mathematical proof of consistency.

**Cross-model verification (mandatory — runs AFTER primary check):**

The same consistency check prompt must be dispatched to TWO additional models from different families. Do NOT hardcode model names — select the best available from the pool at call time, ensuring the two chosen come from different provider families than each other and different from the primary check model.

**Model selection pool (pick two from different families):**

| Family | Models |
|--------|--------|
| DeepSeek | `deepseek/deepseek-v4-pro`, `deepseek/deepseek-v4-flash` |
| Minimax | `minimax/minimax-m3`, `minimax/minimax-m2.7` |
| Anthropic (fast) | `anthropic/claude-haiku-4.5` |
| OpenAI | `openai/gpt-5.4`, `openai/gpt-5.5` |
| xAI | `x-ai/grok-4.20` |

**Method A — Codex CLI workers (parallel, preferred):**

Assemble the check prompt from the four type JSON files (4 reads total, regardless of entry count) and dispatch two workers in parallel:

```bash
# Assemble registry content: 4 reads instead of N
cat .dag/registry/definitions.json .dag/registry/hypotheses.json \
    .dag/registry/axioms.json .dag/registry/theorems.json > /tmp/dag_registry_content.json

# Build full consistency check prompt
cat > /tmp/dag_consistency_check.txt << 'DAGEOF'
REGISTRY CONSISTENCY CHECK
[Full active registry content from /tmp/dag_registry_content.json]
[Proposed new entry]
DAGEOF

# Dispatch two workers in parallel — choose two models from different families
MODEL_1="deepseek/deepseek-v4-pro"
MODEL_2="minimax/minimax-m3"

codex -c model_provider=ai_gateway -m "$MODEL_1" --skip-git-repo-check \
  exec "$(cat /tmp/dag_consistency_check.txt)" > /tmp/dag_check_m1.txt 2>&1 &
PID1=$!

codex -c model_provider=ai_gateway -m "$MODEL_2" --skip-git-repo-check \
  exec "$(cat /tmp/dag_consistency_check.txt)" > /tmp/dag_check_m2.txt 2>&1 &
PID2=$!

wait $PID1 $PID2
echo "=== Model 1 ($MODEL_1) ===" && cat /tmp/dag_check_m1.txt
echo "=== Model 2 ($MODEL_2) ===" && cat /tmp/dag_check_m2.txt
```

**Method B — Sub-agent dispatch (if Codex unavailable):**

Spawn two sub-agents, each receiving the same consistency check prompt and instructed to respond with only `CONSISTENT`, `CONTRADICTION: [IDs] — [explanation]`, or `TERM MISMATCH: [term] — [explanation]`. Collect both responses before making the write decision.

**Method C — Sequential AI Gateway fallback (if neither Codex nor sub-agents available):**

```bash
# Prompt assembled from 4 type JSON files (see Method A)
curl $AI_GATEWAY_BASE_URL/api/v1/chat/completions \
  -H "Authorization: Bearer $AI_GATEWAY_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\": \"deepseek/deepseek-v4-pro\", \"messages\": [{\"role\": \"user\", \"content\": \"$(cat /tmp/dag_consistency_check.txt)\"}]}"
# Then repeat for second model (minimax/minimax-m3 or similar)
```

Decision logic (same regardless of method):
- All return CONSISTENT → proceed with write
- Any return CONTRADICTION → surface all responses to user, block write
- Models disagree → surface disagreement: "Primary: [result]. Cross-check 1: [result]. Cross-check 2: [result]. Disagreement requires human resolution." Block write until resolved.

Rationale: Different model families have different training distributions and different attention failure modes. A contradiction that one model misses, another may catch. Using two cross-checks from different families increases architectural redundancy without locking to a specific model version that may be retired.

**When contradiction is detected:** Surface to user immediately. Ask: "These two entries appear to conflict: [A2] and [proposed]. Options: (a) revise the proposed entry, (b) revise A2 with an amendment, (c) add a meta-axiom that specifies precedence when both apply. Which?"

Do not write until resolved.

## Failure Mode 1: Axiom Drift

**What it is:** A term used in an axiom is defined one way at project start. Later, the team starts using the term differently. The axiom text is unchanged but its effective meaning has shifted.

**Guard:** Every A-type entry has a `depends_on` field listing D-type IDs. When a D-type definition is amended:
1. Find all A-type entries with this D-type ID in `depends_on`
2. Set their `status: under-review`
3. Block these entries from being cited in new proof chains until re-confirmed
4. Show in /dag status: "A3, A5 — under review (definition D1 amended)"

Amendment to a definition is a breaking change. The drift must be acknowledged explicitly, not absorbed silently.

## Failure Mode 2: Contradiction Accumulation

**What it is:** Two axioms are each individually plausible but their conjunction produces a false or contradictory theorem when both are applied to the same case.

**Guards:**
- Write-time contradiction check on every axiom addition (above)
- Pairwise interaction count displayed in `/dag status` — n axioms → n(n-1)/2 pairs to check; shown as an informational signal, not a limit
- `known_tensions` array in registry.json for pairs the user has noted as potentially conflicting but not yet resolved
- /dag status surfaces all known_tensions and open_contradictions

**When tension is noted but not resolved:** Add to `known_tensions`:
```json
"known_tensions": [
  {"entries": ["A3", "A7"], "note": "A3 says X when condition C; A7 says not-X; edge case when both apply not yet specified"}
]
```
Tensions are tracked, not ignored. They must be resolved before the registry is marked clean.

## Failure Mode 3: Stale Axioms

**What it is:** An axiom was true at t=0. The world changed. The axiom remains active and continues generating theorems from a false premise.

**Guards:**
- Every H-type entry has a `review_trigger` field
- Every A-type entry that depends on a hypothesis via `derived_from` (promotion path) or conceptually inherits its scope should note the H-type IDs it relies on
- `/dag status` checks `review_trigger` conditions against `.dag/meta/project-state.json`
- project-state.json is manually updated by the user when major events occur (pivot, new data, feature launch, competitor move)

**project-state.json format:**
```json
{
  "events": [
    {"date": "2026-06-01", "event": "post-pivot", "description": "Company pivoted from SMB to enterprise-only"},
    {"date": "2026-07-15", "event": "competitor-launch", "description": "Competitor X launched direct substitute product"}
  ]
}
```

When `/dag status` detects a review_trigger match, surface as:
```
Staleness Alert: H2 — review_trigger "post-pivot" matched event on 2026-06-01. Re-verify or deprecate.
```

**Why this is manual:** Automated staleness detection would require the LLM to evaluate world-state against registry entries — exactly the kind of closed-world assumption that creates hidden failures. Human updates project-state.json; system matches triggers.

## Failure Mode 4: Over-Axiomatization

**What it is:** Too many axioms. Axiom interaction space explodes as n². Contradictions accumulate undetected. Practitioners lose ability to hold the system in mind and stop using it.

**Guards:**
- Derivability probe on every proposed axiom — if it can be derived from existing entries plus common knowledge, it is T-type, not A-type
- Axiom economy principle: the minimum sufficient axiom set produces the most reliable proof chains; inflation degrades reliability
- Pairwise interaction count shown in `/dag status` as a complexity signal — the human decides whether the set has grown unmanageable for their team

**Consolidation prompt (invoke when team reports registry feels unwieldy):**

> "Review your active axioms: can any pair be combined into one without losing precision? Can any axiom be derived from two others — making it a theorem? The minimum sufficient axiom set produces the most reliable proof chains. Remove redundancy, not necessary complexity."

## Failure Mode 5: Missing Hypotheses

**What it is:** Scope assumptions are implicit — never stated. Proof chains rest on unstated world-state assumptions. When those assumptions change, the theorems silently become wrong.

**Guards:**
- Hidden assumption surfacing in every `/dag prove` run
- Every step in a proof chain that cannot cite a registry ID must be flagged `[HIDDEN ASSUMPTION]`
- Session-end prompt: "This session surfaced [N] hidden assumptions. Should any become H-type entries?"
- The friction of this question, asked every session, reduces implicit hypothesis debt over time

## Failure Mode 6: Retrieval Failure

**What it is:** The right axiom or theorem exists in the registry but is not retrieved or cited in the proof chain. The proof rests on a weaker foundation than what's available.

**Guards:**
- Atomic storage: one JSON object per type file, one statement per entry, one sentence per statement. Type-level JSON files give complete type coverage in one read — loading `axioms.json` gives you every active axiom; no relevant entry is missed because it was in a file you didn't load.
- After every proof step, post-retrieval entailment check: "Does [proof step] actually follow from [cited ID's full statement]?" Simple LLM call: YES/NO + one-sentence reason.
- Load type files for types cited in the proof step (Mode 2): Read `axioms.json` if proof cites any A-type entry; extract only the cited IDs. Each type file loads every entry of that type, which eliminates the "relevant but uncited" gap.
- Retrieval path: `registry.json` (Mode 1) → identify needed types → `Read .dag/registry/{type}.json` → extract cited IDs by key (Mode 2).

## Failure Mode 7: Over-Retrieval

**What it is:** Too many registry entries loaded into context. LLMs ignore information in the middle of long contexts. Contradictory or tangentially relevant entries mislead reasoning.

**Guards:**
- Mode 1 (summary index) is the default — never load type JSON files for routine session start; `registry.json` only
- Mode 2 loads type JSON files for types actually cited, on demand — if a proof step cites only axioms and one definition, that's 2 reads; each file gives complete type coverage without loading unneeded types
- Mode 3 (all type files) is reserved for init/audit/deprecate/contradiction-check only
- Principle: type-level JSON trades the "N individual file reads" problem for "max 4 reads per operation." For proofs citing 1-2 types, load those 1-2 files. For contradiction checks that need everything, load all 4. Each Read is deliberate and targeted by type.

## Failure Mode 8: Unreviewed Hypotheses Poisoning Proof Chains

**What it is:** An H-type entry was valid when written. Time passed. The world changed. No one updated project-state.json. The hypothesis silently became false and continued to be cited in proof chains, generating theorems from a dead premise.

**Root cause of the original guard's failure:** The original guard depended on human discipline (updating project-state.json). Discipline-dependent guards fail precisely when you need them most — during busy periods.

**New guard — mandatory review_log on H-type entries:**

Every H-type entry has a `review_log` array field (see registry-spec.md for format). Each entry also carries an optional `staleness_period_days` field that the human sets at creation time based on how quickly the world changes for that specific assumption.

**Why per-hypothesis staleness:** A hypothesis about "current market pricing pressure" may become stale in days. A hypothesis about "the physics of the domain" may be stable for years. A global timer is a false generalization. The human who writes the hypothesis knows its decay rate best.

**Enforcement rules (automatic, no manual trigger required):**

1. At every `/dag prove`, `/dag derive`, and `/dag status` call: scan all H-type entries that have `staleness_period_days` set. For each:
   - If `review_log` is empty AND today > `created` + `staleness_period_days` → auto-set `status: under-review`
   - If `review_log` is non-empty AND today > most recent review_log date + `staleness_period_days` → auto-set `status: under-review`

2. For H-type entries WITHOUT `staleness_period_days` set: staleness is event-driven only via `review_trigger`. These entries surface as alerts in `/dag status` when a matching event appears in `project-state.json`, but they are NOT auto-blocked.

3. H-type entries with `status: under-review` are **BLOCKED from citation** in new proof chains. Attempting to cite an under-review H-type in a derive call returns:
   ```
   BLOCKED: H[N] is under review (last reviewed: [date], [N] days since last review).
   Run /dag review H[N] before this entry can be cited.
   ```

4. `/dag review [H-ID]` command: prints the H-type statement and asks:
   > "Is this still true? Review options:
   > (a) Still valid — log review event, reset staleness clock
   > (b) Needs revision — amend statement (creates amendment record)
   > (c) No longer valid — deprecate (tombstone created, downstream theorems flagged)"

   On (a): append to review_log: `{"date": "YYYY-MM-DD", "verdict": "valid", "note": "[optional note]"}`
   On (b): amend the entry, append: `{"date": "YYYY-MM-DD", "verdict": "amended", "note": "[what changed]"}`
   On (c): run /dag deprecate H[N], which checks and flags all theorems derived from it.

**Why this works:** The blocking mechanism removes the silent poisoning pathway. A stale hypothesis can't poison proof chains because it's blocked from citation. Per-hypothesis staleness periods mean fast-changing assumptions get reviewed at the cadence they actually require, not at a cadence arbitrary to the domain.

## /dag status Output Format

```
Registry Status: [project-name] ([date])
─────────────────────────────────────────
Entries: [N]D | [N]H | [N]A | [N]T | [N] deprecated
Consistency: [CLEAN | TENSIONS | CONTRADICTIONS]
Last check: [date]
Coverage: [domains]

Axiom Load: [N] active
Pairwise interaction surface: [n(n-1)/2] pairs

Staleness Alerts:
  [H-ID] — review_trigger "[trigger]" matched event [date]

Under-Review:
  [A-ID] — definition [D-ID] amended [date], re-confirmation required

Known Tensions:
  [A-ID] vs [A-ID] — [note]

Open Contradictions:
  [none | list]

Under-Review H-types:
  [H-ID] — last reviewed [date], [N] days ago → run /dag review [H-ID]
```
