# Measurement protocol

This directory exists so that any claim about what the DAG skill saves is a measured
number, not a borrowed headline. No result is quoted in the repo docs until it comes
from this protocol on a real model.

## What can be measured deterministically (no model needed)

`measure_tokens.py` measures the context-load cost of a registry: bytes/chars of each
artifact and the load sizes of the skill's three token modes (summary index, targeted
type load, full load). Token figures it prints are labeled estimates (chars/4
heuristic); the byte numbers are the measured values.

```
python3 benchmarks/measure_tokens.py path/to/.dag/registry
python3 benchmarks/measure_tokens.py path/to/.dag/registry --meta path/to/.dag/meta/registry.json
```

## The paired token protocol (needs a real model)

The skill's claim is that citing IDs beats restating premises. Measure it:

1. Pick N real tasks against a project that has a registry (N >= 10; record each task).
2. For each task, run twice on the same model, fresh sessions:
   - WITHOUT the registry: the prompt must restate every premise the answer needs.
   - WITH the registry: Mode 1 summary index + Mode 2 targeted loads for cited types.
3. Record the model's own reported input/output token counts (API usage fields, not
   estimates) for both arms.
4. Report median and range per arm, the task list, model, and date. A saving you
   cannot reproduce with this table is not a saving.

## The quality rubric (tokens saved are worthless if answers degrade)

Score each paired answer blind (shuffled, scorer does not see which arm) on:

- citation fidelity: every claim in the answer traces to a premise that was actually
  provided (registry ID or restated text). Any claim with no parent counts as a
  fabrication.
- stale-premise use: did the answer rely on a premise the checker marks stale or
  under-review? With-registry answers must not.
- task outcome: did the answer resolve the task (binary, judged against a
  pre-written acceptance note per task).

Report the quality scores next to the token table. A result is only quotable as
"saves tokens" when the with-registry arm is not worse on citation fidelity and
task outcome.

## What NOT to do

- Do not quote another tool's headline numbers as evidence for this skill.
- Do not report chars/4 estimates as "measured tokens".
- Do not run one arm on a stronger model or a warmer session than the other.
