/-
Dagcheck.Export: read-only exports of the provenance graph (GraphML, Cypher).
Both formats are DERIVED serializations over the same registryEdges construction as
provenance.json. Exports never write registry files; an optional --out target is
written atomically (temp file + rename), same discipline as `dagcheck graph --out`.

Edge direction follows provenance.json: `from` is the entry that cites / depends on /
supersedes, `to` is the entry cited / depended on / superseded. In GraphML that is
edge source -> target; in Cypher, (from)-[:KIND]->(to). Supersedes stays a HISTORY
edge in exports exactly as in the graph model: it is serialized and labeled, and the
export performs NO closures, so nothing is silently derived from it here either.

Output is deterministic: node and edge order is the registry's fixed construction
order (type files in fixed read order, JSON object order preserved by the strict
parser), and edge ids are positional.
-/
import Dagcheck.Bridge

namespace Dagcheck

/-- XML escaping for GraphML attributes and data values. -/
def xmlEsc (s : String) : String :=
  s.foldl (fun acc c => acc ++ match c with
    | '&' => "&amp;" | '<' => "&lt;" | '>' => "&gt;" | '"' => "&quot;" | '\'' => "&apos;"
    | c => String.singleton c) ""

/-- Cypher single-quoted string literal escaping. Control characters below 0x20
    become spaces: a raw newline inside a string literal would break the statement. -/
def cypherEsc (s : String) : String :=
  s.foldl (fun acc c => acc ++ match c with
    | '\\' => "\\\\" | '\'' => "\\'" | '\n' => "\\n" | '\r' => "\\r" | '\t' => "\\t"
    | c => if c.val < 0x20 then " " else String.singleton c) ""

def relName : EdgeKind → String
  | .cites => "CITES" | .depends => "DEPENDS_ON" | .supersedes => "SUPERSEDES"

/-- Cypher label for a registry type: fixed vocabulary, safe as a bare identifier. -/
def cypherTypeLabel : EntryType → String
  | .definition => "Definition" | .hypothesis => "Hypothesis" | .axiom => "Axiom"
  | .theorem => "Theorem" | .tombstone => "Tombstone"

/-- Node properties shared by both exports. verdict/confidence are omitted (not null)
    when absent, so consumers can distinguish "no verdict" from an empty string. -/
private def nodeProps (e : Entry) (verdict? : Option Verdict) : List (String × String) :=
  [("type", e.type.typeName), ("status", (Registry.effectiveStatus e).statusName),
   ("label", e.label), ("fingerprint", entryFingerprint e)] ++
  (match e.inferenceRule with | some rn => [("rule", rn)] | none => []) ++
  (match e.proofConfidence with | some c => [("confidence", c)] | none => []) ++
  (match verdict? with | some v => [("verdict", v.verdict)] | none => [])

/-- Edges whose endpoints both exist as exported nodes. Dangling endpoints are load
    errors reported by check; here they are skipped (never silently turned into
    references to undeclared nodes) and counted for the header comment. -/
private def exportableEdges (es : List GEdge) (ids : List String) : List GEdge × Nat :=
  let ok := es.filter (fun e => e.src ∈ ids && e.dst ∈ ids)
  (ok, es.length - ok.length)

/-- GraphML 1.0 serialization. Nodes carry data keys; edges are directed source->target
    with the edge kind as a data value (GraphML has no edge-label attribute). -/
def graphmlExport (r : Registry) (dir : String) : String :=
  let verdicts := verifyTheorems r
  let edges := registryEdges r
  let ids := r.all.map Entry.id
  let (okEdges, nSkipped) := exportableEdges edges ids
  let header :=
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" ++
    "<!-- DERIVED dagcheck export from " ++ xmlEsc dir ++ ". Authoritative content lives in the registry type files.\n" ++
    "     Edge direction: source cites/depends-on/supersedes target (same as provenance.json from->to).\n" ++
    "     supersedes is a HISTORY edge: serialized for audit navigation, never a proof dependency.\n" ++
    (if nSkipped > 0 then
      "     WARNING: " ++ toString nSkipped ++ " edge(s) skipped because an endpoint is not a registry entry (dangling citation - run dagcheck check).\n"
     else "") ++
    "     confidence is the entry author's recorded self-assessment, never a machine verdict. -->\n"
  let keys := String.intercalate "\n"
    ["  <key id=\"d_type\" for=\"node\" attr.name=\"type\" attr.type=\"string\"/>",
     "  <key id=\"d_status\" for=\"node\" attr.name=\"status\" attr.type=\"string\"/>",
     "  <key id=\"d_label\" for=\"node\" attr.name=\"label\" attr.type=\"string\"/>",
     "  <key id=\"d_fingerprint\" for=\"node\" attr.name=\"fingerprint\" attr.type=\"string\"/>",
     "  <key id=\"d_rule\" for=\"node\" attr.name=\"rule\" attr.type=\"string\"/>",
     "  <key id=\"d_confidence\" for=\"node\" attr.name=\"confidence\" attr.type=\"string\"/>",
     "  <key id=\"d_verdict\" for=\"node\" attr.name=\"verdict\" attr.type=\"string\"/>",
     "  <key id=\"d_kind\" for=\"edge\" attr.name=\"kind\" attr.type=\"string\"/>"]
  let nodeXml (e : Entry) : String :=
    let v? := verdicts.find? (fun v => v.id == e.id)
    let data := nodeProps e v? |>.map (fun p =>
      "    <data key=\"d_" ++ p.1 ++ "\">" ++ xmlEsc p.2 ++ "</data>")
    "  <node id=\"" ++ xmlEsc e.id ++ "\">\n" ++ String.intercalate "\n" data ++ "\n  </node>"
  let edgeXml (i : Nat) (g : GEdge) : String :=
    "  <edge id=\"e" ++ toString i ++ "\" source=\"" ++ xmlEsc g.src ++ "\" target=\"" ++ xmlEsc g.dst ++
    "\">\n    <data key=\"d_kind\">" ++ kindName g.kind ++ "</data>\n  </edge>"
  header ++
  "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\">\n" ++ keys ++ "\n" ++
  " <graph id=\"dag-registry\" edgedefault=\"directed\">\n" ++
  String.intercalate "\n" (r.all.map nodeXml) ++
  (if r.all.isEmpty then "" else "\n") ++
  String.intercalate "\n" (okEdges.zipIdx.map (fun p => edgeXml p.2 p.1)) ++
  (if okEdges.isEmpty then "" else "\n") ++
  " </graph>\n</graphml>\n"

/-- Cypher CREATE-script serialization. One CREATE per node (variable n0, n1, ... in
    deterministic registry order) and one per edge. Node ids stay inside the id
    property; variables are positional so arbitrary id characters cannot break or
    collide in the pattern space. -/
def cypherExport (r : Registry) (dir : String) : String :=
  let verdicts := verifyTheorems r
  let edges := registryEdges r
  let ids := r.all.map Entry.id
  let (okEdges, nSkipped) := exportableEdges edges ids
  let header :=
    "// DERIVED dagcheck export from " ++ dir ++ ". Authoritative content lives in the registry type files.\n" ++
    "// Edge direction: (from)-[:KIND]->(to), same as provenance.json. SUPERSEDES is a HISTORY edge, never a proof dependency.\n" ++
    (if nSkipped > 0 then
      "// WARNING: " ++ toString nSkipped ++ " edge(s) skipped: an endpoint is not a registry entry (dangling citation - run dagcheck check).\n"
     else "") ++
    "// confidence is the entry author's recorded self-assessment, never a machine verdict.\n"
  let nodeCypher (i : Nat) (e : Entry) : String :=
    let v? := verdicts.find? (fun v => v.id == e.id)
    let props := ("id", e.id) :: nodeProps e v?
    let propStr := props.map (fun p => p.1 ++ ": '" ++ cypherEsc p.2 ++ "'")
    "CREATE (n" ++ toString i ++ ":Entry:" ++ cypherTypeLabel e.type ++
      " {" ++ String.intercalate ", " propStr ++ "})"
  let varOf (id : String) : Option Nat := ids.idxOf? id
  let edgeCypher (g : GEdge) : Option String :=
    match varOf g.src, varOf g.dst with
    | some i, some j =>
      some ("CREATE (n" ++ toString i ++ ")-[:" ++ relName g.kind ++ "]->(n" ++ toString j ++ ")")
    | _, _ => none
  header ++
  String.intercalate "\n" (r.all.zipIdx.map (fun p => nodeCypher p.2 p.1)) ++
  (if r.all.isEmpty || okEdges.isEmpty then "" else "\n") ++
  String.intercalate "\n" (okEdges.filterMap edgeCypher) ++ "\n"

/-- Supported export formats. Anything else is a usage error, never a guess. -/
def exportFormatOk : String → Bool
  | "graphml" => true | "cypher" => true | _ => false

def exportRun (fmt : String) (r : Registry) (dir : String) : String :=
  match fmt with
  | "graphml" => graphmlExport r dir
  | _ => cypherExport r dir

end Dagcheck
