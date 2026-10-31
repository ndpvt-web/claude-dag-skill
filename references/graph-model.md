# The graph model (provenance.json)

The registry is a labelled graph. The type files are the only source of truth;
`dagcheck graph <registry-dir> --out <dir>/provenance.json` derives this artifact (atomic temp+rename; never shell-redirect onto a live baseline - `>` truncates before the binary runs).
It is never independently writable - regenerate it after any registry change and
commit it as the freshness baseline (see verified-checker.md).

## Nodes and edges

- **Node** = registry entry: `{id, type, status, label, fingerprint}`.
  `fingerprint` is a non-cryptographic hash over the entry's CONTENT fields (type,
  statement, created_by, citations, rule, confidence, form) - the fields a derivation
  depends on. Label edits never drift it; status transitions are state, not content.
  IDs are permanent by policy and are never renamed.
- **Dependency edges**: `cites` (from `derived_from`) and `depends` (from
  `depends_on`), directed citer -> cited.
- **History edges**: `supersedes` (from a tombstone's `superseded_by`), directed
  successor -> retired entry. History edges are *never* followed by dependency
  closures or dependency cycle detection; they are checked for cycles separately.

## Derived closures

For every node id:

- `upstream[id]`: everything id transitively depends on, over dependency edges.
  The full justification chain.
- `blast_radius[id]`: everything that transitively cites id. When id's fingerprint
  drifts from the committed baseline, exactly this set **needs recheck**. The label
  means recheck only - never "invalid", never "runtime behavior changed".

Both closures are complete by construction: traversal is endpoint-driven (a caller
never supplies the node universe) with fuel bounded by the edge count + 1, so no
simple path can be silently truncated. Dangling endpoints are loud citation errors at
load time, not silent drops.

## Cycles

- `cycles.dependency`: nodes on a dependency cycle (cites/depends). Each is an
  error-severity finding in `dagcheck check`.
- `cycles.supersedes`: nodes on a history cycle. Reported as its own finding class,
  never mixed into the dependency result.

## Consumers

- `dagcheck check` diffs live fingerprints against the committed baseline
  (`stale-fingerprint` findings).
- `graph/index.html` renders this file locally (self-contained; no network fetches -
  private reasoning never leaves the machine).
- The skill uses `blast_radius` for /dag review impact lists and `upstream` for
  justification chains.
