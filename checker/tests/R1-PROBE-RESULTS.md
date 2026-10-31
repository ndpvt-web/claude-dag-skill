# Review R1 probes: original failures -> fixed behavior

The independent reviewer's probe file is preserved verbatim at
`tests/review-probes-r1.lean`. It was written against the R1 snapshot API; the fixes
changed two signatures (below), so the verbatim file no longer compiles - that is
expected and the mapping here keeps every original probe and its result honest.
`tests/R1FixCheck.lean` re-runs every probe against the fixed library and compiles
clean (`lake env lean tests/R1FixCheck.lean`); its `theorem ... := by decide` probes are
kernel-checked, not just evaluated.

| Probe | What it tested | R1 result (defect) | Fixed result |
|---|---|---|---|
| rv_valid | valid mp chain accepted | accepted | accepted (kernel `decide`) |
| rv_wrong | wrong conclusion rejected | rejected | rejected (kernel `decide`) |
| rv_unknown | unknown cite rejected | rejected | rejected (kernel `decide`) |
| rv_cycle | step citation cycle rejected | rejected | rejected (kernel `decide`) |
| rv_fresh_disj | disjIntro with fresh atom in BARE CORE | accepted | still accepted **by design**; bridge enforces the atom-table contract (see verified-checker.md; fixture `unmapped-atom` errors, fixture `disj-declared-fresh-atom` verifies with a declared atom) |
| rv_order | mp with cites in wrong order | rejected | rejected (kernel `decide`); order semantics clarified in verified-checker.md |
| R6 stepsDup | duplicate step ids in one derivation | silently shadowed (D3) | `checkDeriv` returns `none`; fixture `duplicate-id` covers the registry-level twin |
| R8 atomsOf | occurrences vs distinct atoms (D1) | `["P","P"]`, cap miscounted, 25 one-atom premises counted 50 | distinct: `["P"]`, cap 1 suffices, 25 premises count 1 |
| R9 upstreamOf | caller node list truncated dangling chains (D2) | partial closure | signature changed: node-list parameter REMOVED; traversal is endpoint-driven with fuel `edges+1`; probe chain returns full `x1..x4,v` |
| R10 cyclicNodes | cycle through unlisted nodes (D2) | missed | found: `[a,x1,x2,x3]`; `depCycleNodes`/`supersedesCycleNodes` take only edges |
| R11 consistent contradictions | `{P, ~P}` unsat | detected | still detected |
| R12 dates | leap/format strictness, epoch 2026-10-31 = 20757 | all correct (reviewer cross-checked vs Python) | unchanged, kept as regression probes |

Defects D4 (fresh-atom coverage) and D5 (citation order) are bridge-contract items:
their resolution is documented in `references/verified-checker.md` and enforced by the
fixture suite (`tests/fixtures/`, runner `tests/run_fixtures.py`, 32 cases).
