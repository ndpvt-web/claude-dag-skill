# DAG Skill for Claude Code

A skill that gives Claude a **memory of facts and proofs** for your project — so it stops re-explaining the same things over and over, and stops contradicting itself between chats.

## What problem does this solve?

When you work with Claude across many sessions, it forgets what was already decided. It re-derives the same conclusions, sometimes differently each time. This skill fixes that by keeping a small, permanent file of **agreed facts**, and making Claude point back to those facts instead of restating them.

## How it works, in plain words

Think of it like a shared notebook that never gets thrown away:

1. You and Claude agree on some basic facts about your project. These are saved with simple IDs, like `A1`, `D1`, `H1`.
2. When Claude reaches a new conclusion, it has to show its work — which facts it used to get there. That conclusion also gets an ID, like `T1`.
3. Next time, Claude just says "based on A1 and T1" instead of explaining everything again.
4. If something changes later, old facts get marked as outdated (not deleted), so nothing quietly breaks.

Everything is stored in a folder called `.dag/` inside your project, as simple JSON files. Claude reads only what it needs, not the whole history.

## The four kinds of facts

| Short code | What it means | Example |
|---|---|---|
| **D** | Definition — what a word means here | "By 'user' we mean a signed-in account" |
| **H** | Hypothesis — something assumed true for this project | "We only support US customers for now" |
| **A** | Axiom — a ground-truth fact that isn't up for debate | "Payments go through Stripe" |
| **T** | Theorem — a conclusion, built from the facts above, with the reasoning shown | "Because of A1 and A2, refunds must be async" |

## Commands you can use

| Command | What it does |
|---|---|
| `/dag init` | First-time setup — Claude asks you questions to build the starting facts |
| `/dag prove [claim]` | Ask Claude to check if a claim actually follows from the saved facts |
| `/dag derive [claim] from [IDs]` | Add a new conclusion, built from specific facts |
| `/dag status` | Quick health check — are all the facts still consistent? |
| `/dag audit` | A deeper check across everything, looking for contradictions |
| `/dag deprecate [ID]` | Retire an old fact without deleting it, and check what depended on it |


## Checking the notebook with a real proof checker

This repo also ships `checker/` — a small, independent program (written in Lean 4, a
proof-checking language) that reads the `.dag/registry/` files and actually verifies
them:

- Every conclusion that uses a checkable rule is re-derived by the checker. If the
  cited facts do not produce the conclusion, the entry is **rejected**, not excused.
- Reasoning the checker cannot machine-check (free-form prose rules, analogies) is
  marked **unchecked** — never silently passed.
- It draws the dependency graph: for any fact, the **upstream chain** (everything it
  rests on) and the **blast radius** (everything that would need a recheck if it
  changed). Changed facts never stay "old green" — a committed fingerprint baseline
  makes any edit show up as "needs recheck" for exactly its blast radius.
- It never edits your files. It reads, checks, and reports.

```
cd checker && lake build
.lake/build/bin/dagcheck check path/to/.dag/registry --today 2026-10-31
.lake/build/bin/dagcheck graph path/to/.dag/registry > path/to/.dag/registry/provenance.json
```

Open `graph/index.html` in any browser and load that `provenance.json` to see the
graph (fully offline; nothing is sent anywhere). Details:
`references/verified-checker.md` and `references/graph-model.md`.

## Running the tests

The checker ships with a test suite under `checker/tests/`: 48 fixture registries
(each with an `EXPECTED.json` the checker output must match exactly) plus a
label-edit check confirming that renaming a fact never marks it as changed.
After `lake build`:

```
python3 checker/tests/run_fixtures.py
```

The fixtures include hostile inputs - oversized numbers, duplicate keys, tombstone
cycles, drifted fingerprints - so a passing run means bad registries are rejected
loudly instead of guessed at. The suite is read-only: it never edits your `.dag/`
files.

## How to install it

1. Copy this whole folder into `~/.claude/skills/DAG/`
2. That's it — Claude Code will pick it up automatically
3. Inside a project, run `/dag init` to get started

## Why JSON files instead of one file per fact

Most of the time, Claude needs to look at *all* the facts of one type at once — for example, to check nothing contradicts. Storing all axioms in one `axioms.json` file (instead of 50 separate small files) means Claude can read everything it needs in a handful of file reads, no matter how big your project's fact list grows.

```
.dag/
  registry/
    axioms.json         # ground-truth facts
    definitions.json    # word meanings
    hypotheses.json     # working assumptions
    theorems.json       # conclusions + their reasoning
    deprecated.json     # retired facts, kept for history
  meta/
    registry.json       # quick index + health status
    provenance.json      # full map of what was derived from what
  sessions/
    YYYY-MM-DD-N.md      # notes from each working session
```

## Who this is for

Anyone using Claude Code on a project that spans many sessions, where you're tired of re-explaining decisions or catching Claude contradicting an earlier answer.

## License

MIT — see [LICENSE](LICENSE).
