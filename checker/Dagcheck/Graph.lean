-- Dependency graph over registry entries. Edge-type discipline (per design review):
--   * `cites` / `depends` are PROOF-DEPENDENCY edges. Impact closures (upstream chain,
--     blast radius) and the dependency-cycle check use ONLY these.
--   * `supersedes` is a HISTORY edge: rendered in the graph for audit navigation and
--     checked for its own acyclicity, but never mixed into dependency closures.
-- Closure/cycle code is executable and adversarially tested (kernel `decide` tests in
-- Dagcheck.Tests); it is registry hygiene, not part of the soundness theorems.
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

/-- Upstream chain: everything u is based on (transitive premises), following edges outward. -/
def upstreamOf (nodes : List String) (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  (bfs (nodes.length + 1) (stepOut es kinds) [u] [u]).erase u

/-- Blast radius: everything that depends on u (transitive dependents), edges reversed. -/
def blastRadiusOf (nodes : List String) (es : List GEdge) (kinds : List EdgeKind) (u : String) : List String :=
  (bfs (nodes.length + 1) (stepIn es kinds) [u] [u]).erase u

/-- Nodes lying on a cycle within `kinds` (including plain self-citation). -/
def cyclicNodes (nodes : List String) (es : List GEdge) (kinds : List EdgeKind) : List String :=
  nodes.filter (fun u =>
    let out := stepOut es kinds u
    out.contains u ||
    (bfs (nodes.length + 1) (stepOut es kinds) (out.filter (· ≠ u)) (out.filter (· ≠ u))).contains u)

/-- Dependency-cycle check over proof-dependency edges only. -/
def depCycleNodes (nodes : List String) (es : List GEdge) : List String :=
  cyclicNodes nodes es depKinds

/-- History-edge acyclicity, checked separately (a supersedes loop is data corruption). -/
def supersedesCycleNodes (nodes : List String) (es : List GEdge) : List String :=
  cyclicNodes nodes es [.supersedes]

end Dagcheck
