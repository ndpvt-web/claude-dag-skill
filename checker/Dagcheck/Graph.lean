-- Dependency graph over registry entries. Edge-type discipline (per design review):
--   * `cites` / `depends` are PROOF-DEPENDENCY edges. Impact closures (upstream chain,
--     blast radius) and the dependency-cycle check use ONLY these.
--   * `supersedes` is a HISTORY edge: rendered in the graph for audit navigation and
--     checked for its own acyclicity, but never mixed into dependency closures.
-- Closure/cycle code is executable registry hygiene, not part of the soundness theorems.
-- The adversarial fixture suite ships with the CLI (checker/tests); until then no test
-- coverage is claimed for this module beyond the review probes reproduced there.
namespace Dagcheck

inductive EdgeKind where
  | cites | depends | supersedes
  deriving DecidableEq, Repr

structure GEdge where
  kind : EdgeKind
  src  : String   -- the entry that cites / depends on / supersedes
  dst  : String   -- the entry cited / depended on / superseded
  deriving Repr

/-- Proof-dependency edge kinds: the only kinds impact and cycle rules may follow. -/
def depKinds : List EdgeKind := [.cites, .depends]

def stepOut (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  es.filterMap (fun e => if (kinds.contains e.kind) && e.src == u then some e.dst else none)

def stepIn (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  es.filterMap (fun e => if (kinds.contains e.kind) && e.dst == u then some e.src else none)

/-- Bounded BFS. Fuel = node count + 1 suffices: any reachable node has a simple path. -/
def bfs : Nat → (String → List String) → List String → List String → List String
  | 0, _, _, visited => visited
  | fuel + 1, step, frontier, visited =>
    let next := (frontier.flatMap step).filter (fun w => w ∉ visited)
    if next.isEmpty then visited else bfs fuel step next (visited ++ next)

/-- All endpoints mentioned by edges. Traversal and cycle detection are driven by THIS
    set, never by a caller-supplied node list: review defect D2 showed fuel keyed to a
    partial node list silently truncated closures and hid cycles routing through
    unlisted endpoints. Fuel = edge count + 1 is complete: any simple path has length
    at most the number of edges. The bridge additionally reports every edge endpoint
    that is not a registry entry as an error (dangling endpoints are invalid input,
    surfaced loudly - but traversal itself no longer depends on that validation). -/
def edgeEndpoints (es : List GEdge) : List String :=
  (es.flatMap (fun e => [e.src, e.dst])).eraseDups

/-- Upstream chain: everything u is based on (transitive premises), following edges outward. -/
def upstreamOf (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  (bfs (es.length + 1) (stepOut es kinds) [u] [u]).erase u

/-- Blast radius: everything that depends on u (transitive dependents), edges reversed. -/
def blastRadiusOf (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  (bfs (es.length + 1) (stepIn es kinds) [u] [u]).erase u

/-- Nodes lying on a cycle within `kinds` (including plain self-citation). -/
def cyclicNodes (es : List GEdge) (kinds : List EdgeKind) : List String :=
  let nodes := edgeEndpoints (es.filter (fun e => e.kind ∈ kinds))
  nodes.filter (fun u =>
    let out := stepOut es kinds u
    out.contains u ||
    (bfs (es.length + 1) (stepOut es kinds) (out.filter (· ≠ u)) (out.filter (· ≠ u))).contains u)

/-- Dependency-cycle check over proof-dependency edges only. -/
def depCycleNodes (es : List GEdge) : List String := cyclicNodes es depKinds

/-- History-edge acyclicity, checked separately (a supersedes loop is data corruption). -/
def supersedesCycleNodes (es : List GEdge) : List String := cyclicNodes es [.supersedes]

end Dagcheck
