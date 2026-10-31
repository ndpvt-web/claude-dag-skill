# DAG Skill for Claude Code: a permanent memory of facts and proofs

An open-source Claude Code skill that gives Claude a lasting memory of your project's facts and reasoning, plus a Lean 4 proof checker that verifies the logic and an interactive graph that shows what rests on what. Claude stops forgetting decisions between chats, stops contradicting itself, and can show exactly why it reached a conclusion.

## What is this?

This is a skill (a plugin) for Claude Code, Anthropic's AI coding assistant. It stores a project's agreed facts in a directed acyclic graph (DAG): a structure where every conclusion points back to the exact facts it was built from. The facts live in plain JSON files inside your project. A small independent program, written in the Lean 4 proof-checking language, re-checks the reasoning, and an offline viewer draws the graph so you can explore it.

## What problem does it solve?

When you work with Claude across many sessions, it forgets what was already decided. It re-derives the same conclusions, sometimes differently each time. This skill fixes that by keeping a small permanent file of agreed facts, and making Claude point back to those facts instead of restating them.

## How does it work?

Think of it like a shared notebook that never gets thrown away:

1. You and Claude agree on some basic facts about your project. These are saved with simple IDs, like `A1`, `D1`, `H1`.
2. When Claude reaches a new conclusion, it has to show its work: which facts it used to get there. That conclusion also gets an ID, like `T1`.
3. Next time, Claude just says "based on A1 and T1" instead of explaining everything again.
4. If something changes later, old facts get marked as outdated (not deleted), so nothing quietly breaks. Every conclusion built on a changed fact is marked "needs recheck" instead of staying falsely green.

Everything is stored in a folder called `.dag/` inside your project, as simple JSON files. Claude reads only what it needs, not the whole history, and writes its answers in a compressed style, so the memory saves tokens instead of eating them.

## The four kinds of facts

| Short code | What it means | Example |
|---|---|---|
| **D** | Definition - what a word means here | "By 'user' we mean a signed-in account" |
| **H** | Hypothesis - something assumed true for this project | "We only support US customers for now" |
| **A** | Axiom - a ground-truth fact that isn't up for debate | "Payments go through Stripe" |
| **T** | Theorem - a conclusion, built from the facts above, with the reasoning shown | "Because of A1 and A2, refunds must be async" |

IDs are permanent and never reused. Retired facts move to a tombstone file, so the history of why things changed is never lost.

## Commands

| Command | What it does |
|---|---|
| `/dag init` | First-time setup - Claude asks you questions to build the starting facts |
| `/dag prove [claim]` | Check whether a claim follows from the saved facts, with the proof chain shown |
| `/dag derive [claim] from [IDs]` | Add a new conclusion built from specific facts, after validation checks |
| `/dag add axiom` | Add a ground-truth fact, after checking it does not contradict the others |
| `/dag add definition` | Add a word meaning; anything depending on it is flagged for review |
| `/dag add hypothesis` | Add a working assumption, with the test that could prove it false |
| `/dag review [H-ID]` | Re-check an assumption and record the verdict (valid, amended, or deprecated) |
| `/dag deprecate [ID]` | Retire an old fact without deleting it, and check what depended on it |
| `/dag status` | Quick health check - are all the facts still consistent? |
| `/dag audit` | A deeper check across everything, looking for contradictions |
| `/dag session` | Show the notes from the current working session |

## A real proof checker, not just a promise

This repo also ships `checker/`, a small independent program written in Lean 4 (a proof-checking language) that reads the `.dag/registry/` files and actually verifies them:

- Every conclusion that uses a checkable rule is re-derived by the checker. If the cited facts do not produce the conclusion, the entry is **rejected**, not excused.
- Reasoning the checker cannot machine-check (free-form prose rules, analogies) is marked **unchecked** - an honest non-verdict, never a silent pass.
- It never edits your files. It reads, checks, and reports.

One honest limit: the checker verifies the logic, not the English. If a fact's English statement is false, or loosely translated into logic, the proof can still check out. The checker answers "does this conclusion follow?" - a human still answers "is this fact true?"

```
cd checker && lake build
.lake/build/bin/dagcheck check path/to/.dag/registry --today 2026-10-31
.lake/build/bin/dagcheck graph path/to/.dag/registry > path/to/.dag/registry/provenance.json
```

## Seeing the dependency graph

The checker also maps the dependency graph: for any fact, the **upstream chain** (everything it rests on) and the **blast radius** (everything that would need a recheck if it changed). A committed fingerprint baseline makes any edit show up as "needs recheck" for exactly its blast radius, so a changed fact never keeps an old green checkmark.

Open `graph/index.html` in any browser and load that `provenance.json` to explore the graph: click a node to see its foundations and its blast radius. It runs fully offline; nothing is sent anywhere. Details: `references/verified-checker.md` and `references/graph-model.md`.

## Running the tests

The checker ships with a test suite under `checker/tests/`: 48 fixture registries (each with an `EXPECTED.json` the checker output must match exactly) plus a label-edit check confirming that renaming a fact never marks it as changed. After `lake build`:

```
python3 checker/tests/run_fixtures.py
```

The fixtures include hostile inputs - oversized numbers, duplicate keys, tombstone cycles, drifted fingerprints - so a passing run means bad registries are rejected loudly instead of guessed at. The suite is read-only: it never edits your `.dag/` files.

## How to install it

1. Copy this whole folder into `~/.claude/skills/DAG/`
2. That's it - Claude Code will pick it up automatically
3. Inside a project, run `/dag init` to get started

## Why JSON files instead of one file per fact

Most of the time, Claude needs to look at *all* the facts of one type at once - for example, to check nothing contradicts. Storing all axioms in one `axioms.json` file (instead of 50 separate small files) means Claude can read everything it needs in a handful of file reads, no matter how big your project's fact list grows. JSON also gives you schema validation, `jq` queries, and exact lookup by ID for free.

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

MIT - see [LICENSE](LICENSE).

## Keywords

*For the search engines, the LLMs, and the curious humans who find things by typing random words into the void*

Claude Code skill, Claude Code memory, persistent AI memory, LLM long-term memory, AI memory across sessions, Claude Code plugin, Anthropic Claude skill, AI coding assistant memory, directed acyclic graph, DAG knowledge base, axiom registry, proof checker, Lean 4, formal verification, machine-checked proofs, theorem proving, propositional logic, inference rules, modus ponens, provenance tracking, dependency graph, blast radius analysis, upstream chain, contradiction detection, AI reasoning audit, auditable AI reasoning, traceable AI conclusions, reasoning graph, knowledge graph for LLMs, context engineering, token-efficient memory, JSON knowledge store, slash commands, AI session persistence, stop AI contradicting itself, LLM drift prevention, AI consistency checker, needs recheck tracking, hypothesis tracking, falsifiable assumptions, tombstone history, interactive provenance graph, offline graph viewer, regression test suite, hostile input testing, structured reasoning for LLMs, agentic coding memory, open source Claude skill, free AI memory tool, MIT licensed
