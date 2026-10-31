#!/usr/bin/env python3
"""Generate adversarial fixture registries. Each fixture dir gets registry JSON files +
EXPECTED.json (exit code, required findings, required verdicts, graph assertions).
Fixtures only: nothing here touches a real user registry."""
import json, os, shutil, copy

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

def entry(id, typ, **kw):
    e = {"id": id, "type": typ, "label": kw.pop("label", id.lower()),
         "statement": kw.pop("statement", f"Statement of {id}."),
         "created": kw.pop("created", "2026-05-01"), "created_by": kw.pop("created_by", "human"),
         "status": kw.pop("status", "active")}
    if typ == "definition":
        e.setdefault("term", id.lower()); e.setdefault("scope", "project-wide")
        e.setdefault("distinguishes_from", ["other-term"]); e.setdefault("rationale", "Disambiguation matters.")
    if typ == "axiom":
        e.setdefault("domain", ["strategy"]); e.setdefault("hardness", "hard")
    if typ == "hypothesis":
        e.setdefault("scope_claim", "current quarter")
    e.update(kw)
    return e

BASE = {
  "axioms.json": {"A1": entry("A1","axiom", rationale="Founder decision.",
                    form={"imp":[{"atom":"P"},{"atom":"Q"}]}),
                  "A2": entry("A2","axiom", rationale="Second.",
                    form={"atom":"R"})},
  "definitions.json": {"D1": entry("D1","definition", form={"atom":"P"})},
  "hypotheses.json": {"H1": entry("H1","hypothesis",
                        falsification="Churn persists after fixes.", review_trigger="Monthly.",
                        form={"atom":"P"}, staleness_period_days=30,
                        review_log=[{"date":"2026-10-01","verdict":"valid","note":"ok"}])},
  "theorems.json": {"T1": entry("T1","theorem", derived_from=["A1","H1"],
                      inference_rule="modus ponens",
                      derivation_note="A1: P->Q; H1: P; so Q.",
                      proof_confidence="CERTAIN", form={"atom":"Q"},
                      session_derived="2026-05-17")},
  "deprecated.json": {"A9": {"id":"A9","type":"axiom","original_statement":"Old belief.",
                        "deprecated_on":"2026-06-01","reason":"Contradicted.",
                        "superseded_by":"A1"}},
  "logic.json": {"P":"Onboarding quality sufficient","Q":"Retention improves","R":"Costs fall"},
}

def make(name, mutate, expected, base=None):
    d = os.path.join(ROOT, name)
    if os.path.exists(d): shutil.rmtree(d)
    os.makedirs(d)
    files = copy.deepcopy(base or BASE)
    mutate(files)
    for fname, content in files.items():
        if content is None: continue
        with open(os.path.join(d, fname), "w") as f:
            f.write(content if isinstance(content, str) else json.dumps(content, indent=1))
    with open(os.path.join(d, "EXPECTED.json"), "w") as f:
        json.dump(expected, f, indent=1)
    # the exponent attack must be a RAW JSON number, not a string
    if name == "exponent-attack":
        p = os.path.join(d, "hypotheses.json")
        src = open(p).read().replace('"staleness_period_days": "1e1000000"',
                                     '"staleness_period_days": 1e1000000')
        open(p, "w").write(src)

def drop(fname): return lambda files: files.__setitem__(fname, None)

# 1. valid baseline
make("valid", lambda f: None,
     {"exit": 0, "verdicts": {"T1": "verified"},
      # D9: --premises must cover every citation; a narrower set is a loud error
      "check_step": {"premises": ["A1"],
                     "step": {"id":"T9","conclusion":{"atom":"Q"},
                              "rule":"modus ponens","cites":["A1","H1"]},
                     "exit": 2},
      "graph": {"upstream": {"T1": ["A1","H1"]}, "blast_radius": {"A1": ["T1"]},
                "dependency_cycles": [], "supersedes_cycles": [],
                "nodes": {"T1": {"rule": "modus ponens", "confidence": "CERTAIN",
                                 "verdict": "verified"},
                          "A1": {"rule": None, "confidence": None}}},
      "coverage": {"entries_active": 5, "tombstones": 1, "theorems_total": 1,
                   "verified_share_of_machine_checkable": "1/1"}})

# 2. duplicate key inside JSON object (strict parser must refuse)
make("duplicate-key",
     lambda f: f.__setitem__("axioms.json",
        '{"A1": {"id":"A1","type":"axiom","label":"x","statement":"s","rationale":"r",'
        '"created":"2026-05-01","status":"active","label":"dup"}'),
     {"exit": 1, "findings": [("error","parse")]})

# 3. trailing garbage after the JSON value
make("trailing-garbage",
     lambda f: f.__setitem__("definitions.json",
        json.dumps(f["definitions.json"]) + "  {extra}"),
     {"exit": 1, "findings": [("error","parse")]})

# 4. citation order wrong for the rule shape -> rejected, never silently reordered
def m_wrong_order(f):
    f["theorems.json"]["T1"]["derived_from"] = ["H1","A1"]
make("wrong-order-cites", m_wrong_order,
     {"exit": 1, "verdicts": {"T1": "rejected"},
      # D11: a rejected theorem can never serve as a check-step premise
      "check_step": {"premises": ["T1","A2"],
                     "step": {"id":"T9","conclusion":{"conj":[{"atom":"Q"},{"atom":"R"}]},
                              "rule":"conjunction introduction","cites":["T1","A2"]},
                     "exit": 2, "verdict": "unchecked",
                     "reason_contains": "verdict is rejected"}})

# 5. dangling citation -> citation error + blocked verdict
def m_dangling(f):
    f["theorems.json"]["T1"]["derived_from"] = ["A1","H7"]
make("dangling-cite", m_dangling,
     {"exit": 1, "findings": [("error","citation")], "verdicts": {"T1": "blocked"},
      "export": [{"format": "graphml", "exit": 1, "node_count": 6, "edge_count": 2,
                  "comment_contains": "1 edge(s) skipped"},
                 {"format": "cypher", "exit": 1, "node_count": 6, "edge_count": 2,
                  "comment_contains": "1 edge(s) skipped"}]})

# 6. dependency cycle T1 <-> T2 -> cycle error naming nodes
def m_dep_cycle(f):
    f["theorems.json"]["T1"]["derived_from"] = ["T2"]
    f["theorems.json"]["T2"] = entry("T2","theorem", derived_from=["T1"],
        inference_rule="modus ponens", derivation_note="x", proof_confidence="CERTAIN",
        form={"atom":"Q"}, session_derived="2026-05-18")
make("dep-cycle", m_dep_cycle,
     {"exit": 1, "findings": [("error","cycle")]})

# 7. supersedes cycle kept SEPARATE from dependency cycles
def m_sup_cycle(f):
    f["deprecated.json"]["A8"] = {"id":"A8","type":"axiom","original_statement":"Older A.",
        "deprecated_on":"2026-06-01","reason":"Replaced.","superseded_by":"A9"}
    f["deprecated.json"]["A9"]["superseded_by"] = "A8"
make("supersedes-cycle", m_sup_cycle,
     {"exit": 1, "findings": [("error","supersession-cycle")],
      "absent_codes": ["cycle"]})

# 8. history edges never enter dependency closures: A9 -(superseded_by)-> A1; T1 cites A1.
#    upstream(T1) must NOT contain A9; blast(A9) must NOT contain T1 via the history edge.
make("history-not-dependency", lambda f: None,
     {"exit": 0,
      "graph": {"upstream_not": {"T1": ["A9"]}, "blast_not": {"A9": ["T1"]},
                "upstream": {"T1": ["A1","H1"]}}})

# 9. form uses atom absent from logic.json -> unmapped-atom error (bridge coverage)
def m_unmapped(f):
    f["theorems.json"]["T1"]["form"] = {"disj":[{"atom":"Q"},{"atom":"Fresh"}]}
    f["theorems.json"]["T1"]["inference_rule"] = "disjunction intro"
    f["theorems.json"]["T1"]["derived_from"] = ["H1"]
make("unmapped-atom", m_unmapped,
     {"exit": 1, "findings": [("error","unmapped-atom")]})

# 10. disjIntro with DECLARED fresh atom is fine: declared-in-table != absent-from-premises.
def m_disj_declared(f):
    f["logic.json"]["Fresh"] = "A declared extra atom"
    f["theorems.json"]["T1"]["form"] = {"disj":[{"atom":"P"},{"atom":"Fresh"}]}
    f["theorems.json"]["T1"]["inference_rule"] = "disjunction intro"
    f["theorems.json"]["T1"]["derived_from"] = ["H1"]
make("disj-declared-fresh-atom", m_disj_declared,
     {"exit": 0, "verdicts": {"T1": "verified"}, "absent_codes": ["unmapped-atom"]})

# 11. duplicate id across files (incl. tombstones) -> hard error
def m_dup_id(f):
    f["deprecated.json"]["A1"] = {"id":"A1","type":"axiom","original_statement":"Old A1.",
        "deprecated_on":"2026-06-01","reason":"Replaced."}
make("duplicate-id", m_dup_id,
     {"exit": 1, "findings": [("error","duplicate-id")]})

# 12. object key != id field -> parse error
def m_key_mismatch(f):
    a1 = f["axioms.json"].pop("A1")
    a1["id"] = "A1"
    f["axioms.json"]["A7"] = a1
make("key-id-mismatch", m_key_mismatch,
     {"exit": 1, "findings": [("error","parse")]})

# 13. id scheme violation (X prefix)
def m_bad_id(f):
    f["axioms.json"]["X1"] = entry("X1","axiom", rationale="r")
    del f["axioms.json"]["A1"]
make("bad-id-scheme", m_bad_id,
     {"exit": 1, "findings": [("error","parse")]})

# 14. theorem without derived_from -> schema-level parse error
def m_no_provenance(f):
    del f["theorems.json"]["T1"]["derived_from"]
make("theorem-no-derived-from", m_no_provenance,
     {"exit": 1, "findings": [("error","parse")]})

# 15. UNCERTAIN confidence -> registry invalid
def m_uncertain(f):
    f["theorems.json"]["T1"]["proof_confidence"] = "UNCERTAIN"
make("uncertain-confidence", m_uncertain,
     {"exit": 1, "findings": [("error","confidence")]})

# 16. analogy capped at PROBABLE
def m_analogy(f):
    f["theorems.json"]["T1"]["inference_rule"] = "analogy"
    f["theorems.json"]["T1"]["proof_confidence"] = "CERTAIN"
make("analogy-certain", m_analogy,
     {"exit": 1, "findings": [("error","confidence")], "verdicts": {"T1": "unchecked"}})

# 17. prose rule outside the fragment -> explicitly UNCHECKED, not rejected
#     (legacy registries used prose rules like "conjunction + modus ponens")
def m_prose(f):
    f["theorems.json"]["T1"]["inference_rule"] = "conjunction + modus ponens"
make("prose-rule-unchecked", m_prose,
     {"exit": 0, "verdicts": {"T1": "unchecked"}})

# 18. encoded active subset inconsistent -> consistency error, loud wording
def m_inconsistent(f):
    f["axioms.json"]["A1"]["form"] = {"neg":{"atom":"P"}}
    f["theorems.json"]["T1"]["derived_from"] = ["A2"]
    f["theorems.json"]["T1"]["form"] = {"atom":"R"}
    f["theorems.json"]["T1"]["inference_rule"] = "disjunction intro right"
    f["theorems.json"]["T1"]["derived_from"] = ["A2"]
    f["theorems.json"]["T1"]["form"] = {"disj":[{"atom":"R"},{"atom":"Q"}]}
make("inconsistent-premises", m_inconsistent,
     {"exit": 1, "findings": [("error","consistency")]})

# 19. over-cap consistency: 21 distinct atoms -> loud refusal, never silent pass
def m_overcap(f):
    hs = {}
    for i in range(1, 12):
        hs[f"H{i}"] = entry(f"H{i}","hypothesis", falsification="f", review_trigger="r",
            form={"imp":[{"atom":f"X{i}"},{"atom":f"Y{i}"}]})
        f["logic.json"][f"X{i}"] = f"x{i}"; f["logic.json"][f"Y{i}"] = f"y{i}"
    f["hypotheses.json"] = hs
    f["theorems.json"] = {}
make("consistency-over-cap", m_overcap,
     {"exit": 0, "findings": [("warning","consistency-over-cap")],
      "absent_codes": ["consistency"]})

# 19b. D10: --cap plumbs through the CLI (downward here: 18 atoms, cap 12 -> refusal)
def m_nine_hyp(f):
    hs = {}
    for i in range(1, 10):
        hs[f"H{i}"] = entry(f"H{i}","hypothesis", falsification="f", review_trigger="r",
            form={"imp":[{"atom":f"X{i}"},{"atom":f"Y{i}"}]})
        f["logic.json"][f"X{i}"] = f"x{i}"; f["logic.json"][f"Y{i}"] = f"y{i}"
    f["hypotheses.json"] = hs
    f["theorems.json"] = {}
make("cap-flag", m_nine_hyp,
     {"exit": 0, "cap": 12, "findings": [("warning","consistency-over-cap")]})

# 19c. D6-class: --cap above the memory ceiling is a loud refusal, never an OOM
make("cap-ceiling", m_nine_hyp,
     {"exit": 2, "cap": 25})

# 20. stale hypothesis auto-transitions and blocks citation
def m_stale(f):
    f["hypotheses.json"]["H1"]["review_log"] = [{"date":"2026-08-01","verdict":"valid","note":"old"}]
make("stale-hypothesis", m_stale,
     {"exit": 1, "today": "2026-10-31",
      "findings": [("info","staleness"),("error","citation")],
      "verdicts": {"T1": "blocked"}})

# 21. bad date formats rejected loudly
make("bad-date",
     lambda f: f["axioms.json"]["A1"].__setitem__("created","2026-5-1"),
     {"exit": 1, "findings": [("error","parse")]})
make("bad-date-nonexistent",
     lambda f: f["axioms.json"]["A1"].__setitem__("created","2026-02-30"),
     {"exit": 1, "findings": [("error","parse")]})

# 22. citing a deprecated (tombstoned) id -> blocked
def m_cite_tomb(f):
    f["theorems.json"]["T1"]["derived_from"] = ["A9","H1"]
make("cite-tombstone", m_cite_tomb,
     {"exit": 1, "findings": [("error","citation")], "verdicts": {"T1": "blocked"}})

# 23. multi-level chain closures: T2 cites T1 (verified chain); closures transitive
def m_chain(f):
    f["theorems.json"]["T2"] = entry("T2","theorem", derived_from=["T1","A2"],
        inference_rule="conjunction introduction", derivation_note="Q and R.",
        proof_confidence="CERTAIN", form={"conj":[{"atom":"Q"},{"atom":"R"}]},
        session_derived="2026-05-18")
make("verified-chain", m_chain,
     {"exit": 0, "verdicts": {"T1": "verified", "T2": "verified"},
      # D11 positive: a VERIFIED theorem is a usable check-step premise
      "check_step": {"premises": ["T1","A2"],
                     "step": {"id":"T9","conclusion":{"conj":[{"atom":"Q"},{"atom":"R"}]},
                              "rule":"conjunction introduction","cites":["T1","A2"]},
                     "exit": 0, "verdict": "verified"},
      "graph": {"blast_radius": {"A1": ["T1","T2"]},
                "upstream": {"T2": ["T1","A1","H1","A2"]}}})

# 24. theorem citing a REJECTED theorem cannot verify
def m_bad_chain(f):
    f["theorems.json"]["T1"]["derived_from"] = ["H1","A1"]  # wrong order -> rejected
    f["theorems.json"]["T2"] = entry("T2","theorem", derived_from=["T1","A2"],
        inference_rule="conjunction introduction", derivation_note="x",
        proof_confidence="CERTAIN", form={"conj":[{"atom":"Q"},{"atom":"R"}]},
        session_derived="2026-05-18")
make("chain-on-rejected", m_bad_chain,
     {"exit": 1, "verdicts": {"T1": "rejected", "T2": "unchecked"}})

# 24b. superseded_by on an ACTIVE entry: loud rejection, not a silent drop
def m_active_sup(f):
    f["theorems.json"]["T1"]["superseded_by"] = "T2"
make("superseded-by-on-active", m_active_sup,
     {"exit": 1, "findings": [("error","parse")]})

# 24c. unknown typo field is loud
def m_typo(f):
    f["axioms.json"]["A1"]["statment"] = "typo field"
make("unknown-field-typo", m_typo,
     {"exit": 1, "findings": [("error","parse")]})

# 24d. fingerprint drift vs committed provenance baseline -> needs-recheck warning naming
#      the blast radius; never an invalidity claim; exit stays 0 (warning class)
def m_drift(f):
    f["provenance.json"] = json.dumps({"spec":"dagcheck-provenance/v1","nodes":[
        {"id":"A1","fingerprint":"000STALE000"},
        {"id":"D1","fingerprint":"x"},{"id":"H1","fingerprint":"x"},
        {"id":"T1","fingerprint":"x"},{"id":"A9","fingerprint":"x"},
        {"id":"A2","fingerprint":"x"}]})
make("fingerprint-drift", m_drift,
     {"exit": 0, "findings": [("warning","stale-fingerprint")]})

# 25. missing required file -> error, other files still validated
make("missing-file", drop("theorems.json"),
     {"exit": 1, "findings": [("error","missing-file")]})

# 26. non-integer staleness_period_days -> parse error (number regression: 30 must stay 30)
def m_stale_period(f):
    f["hypotheses.json"]["H1"]["staleness_period_days"] = 3.5
make("bad-staleness-number", m_stale_period,
     {"exit": 1, "findings": [("error","parse")]})

# 27. integer preservation regression: period 30 with review 2026-09-15 is stale on
#     2026-10-31 ONLY if 30 is parsed as 30 (the old reversed-digits bug parsed it as 3,
#     which would ALSO be stale; instead check NOT stale with period 30 vs recent review)
def m_period30(f):
    f["hypotheses.json"]["H1"]["review_log"] = [{"date":"2026-10-15","verdict":"valid","note":"recent"}]
make("staleness-period-intact", m_period30,
     {"exit": 0, "today": "2026-10-31", "absent_codes": ["staleness"]})

# 28. SPEC-VERBATIM entries (judge D8): the spec's own examples must load clean
def m_spec_verbatim(f):
    f["definitions.json"] = {"D1": {
        "id":"D1","type":"definition","label":"user","term":"user",
        "statement":"A user is a human operating the product interface with intent to accomplish a task.",
        "scope":"applies to all product and retention reasoning",
        "distinguishes_from":["automated agent","admin","API consumer"],
        "rationale":"Without this definition, retention metrics may conflate human users with API consumers.",
        "created":"2026-05-17","created_by":"human","status":"active"}}
    f["axioms.json"] = {"A1": {
        "id":"A1","type":"axiom","label":"retention-drives-growth",
        "statement":"Sustainable revenue growth requires that LTV exceeds CAC, achievable at scale through retained customers.",
        "domain":["strategy","growth"],"hardness":"hard","depends_on":["D1"],
        "rationale":"Unit economics principle. Not derivable from other axioms in this registry.",
        "created":"2026-05-17","created_by":"human","status":"active",
        "form":{"imp":[{"atom":"P"},{"atom":"Q"}]}}}
    f["hypotheses.json"] = {"H1": {
        "id":"H1","type":"hypothesis","label":"churn-is-product-problem",
        "statement":"User churn at current stage is primarily caused by product quality gaps.",
        "scope_claim":"applies to retention strategy for the next 2 quarters",
        "falsification":"Exit survey data shows > 40% of churned users cite price or competitor.",
        "review_trigger":"Any quarterly cohort analysis.",
        "staleness_period_days":90,"created":"2026-05-17","created_by":"human","status":"active",
        "review_log":[],"form":{"atom":"P"}}}
    f["theorems.json"] = {"T1": {
        "id":"T1","type":"theorem","label":"onboarding-is-retention-lever",
        "statement":"Improving onboarding completion rate is a higher-leverage retention investment than feature depth.",
        "derived_from":["A1","H1"],"inference_rule":"modus ponens",
        "derivation_note":"A1: P->Q; H1: P; so Q.",
        "proof_confidence":"CERTAIN","session_derived":"2026-05-17","created":"2026-05-17",
        "created_by":"human","status":"active","form":{"atom":"Q"}}}
make("spec-verbatim", m_spec_verbatim,
     {"exit": 0, "today": "2026-06-01", "verdicts": {"T1": "verified"}})

# 29. missing created_by (universal mandatory) -> parse error
make("missing-created-by",
     lambda f: f["axioms.json"]["A1"].pop("created_by"),
     {"exit": 1, "findings": [("error","parse")]})

# 30. bad hardness value
make("bad-hardness",
     lambda f: f["axioms.json"]["A1"].__setitem__("hardness","squishy"),
     {"exit": 1, "findings": [("error","parse")]})

# 31. D6: exponent blowup attempt -> loud error, and it must return FAST
make("exponent-attack",
     lambda f: f["hypotheses.json"]["H1"].__setitem__("staleness_period_days", "1e1000000"),
     {"exit": 1, "findings": [("error","parse")]})

# 32. D6: mantissa flood -> loud error
make("digit-flood",
     lambda f: f["hypotheses.json"]["H1"].__setitem__("staleness_period_days", int("1"*50)),
     {"exit": 1, "findings": [("error","parse")]})

# 33. D6: absurd-but-parseable staleness period -> semantic bound error
make("staleness-too-large",
     lambda f: f["hypotheses.json"]["H1"].__setitem__("staleness_period_days", 99999),
     {"exit": 1, "findings": [("error","parse")]})

# 34. D12: A1 drifts after baseline -> A1 stale, downstream T1 upstream-stale (never old green)
# upstream-stale needs a REAL baseline: write the unmutated registry, capture
# provenance with the built binary, then drift A1's statement.
d = os.path.join(ROOT, "upstream-stale")
if os.path.exists(d): shutil.rmtree(d)
os.makedirs(d)
for fname, content in BASE.items():
    with open(os.path.join(d, fname), "w") as f:
        f.write(json.dumps(content, indent=1))
import subprocess as _sp
BIN = os.environ.get("DAGCHECK_BIN",
    os.path.abspath(os.path.join(ROOT, "..", "..", ".lake", "build", "bin", "dagcheck")))
prov = _sp.run([BIN, "graph", d, "--today", "2026-10-31"], capture_output=True, text=True)
assert prov.returncode == 0 and prov.stdout.startswith("{"), prov.stderr[:300]
with open(os.path.join(d, "provenance.json"), "w") as f:
    f.write(prov.stdout)
_ax = copy.deepcopy(BASE["axioms.json"])
_ax["A1"]["statement"] = "Statement of A1, CHANGED after baseline."
with open(os.path.join(d, "axioms.json"), "w") as f:
    f.write(json.dumps(_ax, indent=1))
json.dump({"exit": 0, "findings": [("warning","stale-fingerprint")],
    "verdicts": {"T1": "upstream-stale"},
    "freshness": {"A1": "stale", "T1": "upstream-stale", "H1": "current"},
    "check_step": {"premises": ["A1","H1"],
                   "step": {"id":"S1","conclusion":{"atom":"Q"},"rule":"modus ponens","cites":["A1","H1"]},
                   "exit": 1, "verdict": "stale"}},
  open(os.path.join(d, "EXPECTED.json"), "w"), indent=1)

# 35. resource bound: JSON nesting beyond 500 -> loud parse error (was SIGKILL class)
def _deep_nest(f):
    f["hypotheses.json"] = "[" * 600 + "1" + "]" * 600
make("nesting-attack", _deep_nest,
     {"exit": 1, "findings": [("error","parse")]})

# 36. resource bound: form beyond 1000 constructors -> loud error (balanced tree, depth ok)
def _big_form(f):
    def tree(d):
        return {"atom":"P"} if d == 0 else {"imp":[tree(d-1), tree(d-1)]}
    f["hypotheses.json"]["H1"]["form"] = tree(10)   # 2^11-1 = 2047 constructors
make("form-too-large", _big_form,
     {"exit": 1, "findings": [("error","parse")]})

# 37. resource bound: total formula size over work budget -> refused, never OOM
def _work(f):
    def tree(d):
        return {"atom":"P"} if d == 0 else {"imp":[tree(d-1), tree(d-1)]}
    f["hypotheses.json"]["H1"]["form"] = tree(8)    # 511 constructors; two forms -> 1022 > 1000 work budget
    f["hypotheses.json"]["H2"] = dict(f["hypotheses.json"]["H1"], id="H2", label="h2")
    f["theorems.json"] = {}   # keep the fixture about the work bound, not T1's derivation
make("consistency-work-budget", _work,
     {"exit": 0, "findings": [("warning","consistency-over-cap")]})

# 38. max accepted cap: 20 atoms at --cap 20 must succeed (measured ~0.2s, ~210MB)
def _cap20(f):
    f["hypotheses.json"] = {}
    f["logic.json"] = {}
    f["axioms.json"] = {}
    f["definitions.json"] = {}
    f["theorems.json"] = {}
    f["deprecated.json"] = {}
    for i in range(20):
        a = f"p{i}"
        f["hypotheses.json"][f"H{i}"] = entry(f"H{i}","hypothesis",
            falsification="f", review_trigger="r", form={"atom": a})
        f["logic.json"][a] = a
make("cap20-max", _cap20, {"exit": 0, "cap": 20,
     "findings": [("info","consistency")]})

# 39. D14: tombstone typo superseded-by must be a loud error, not a dropped history edge
def _tomb_typo(f):
    a9 = f["deprecated.json"]["A9"]
    a9["superseded-by"] = a9.pop("superseded_by")
make("tombstone-typo", _tomb_typo,
     {"exit": 1, "findings": [("error","parse")]})

# 40. D14: unknown tombstone field -> loud error
def _tomb_unknown(f):
    f["deprecated.json"]["A9"]["review_note"] = "someone's note"
make("tombstone-unknown-field", _tomb_unknown,
     {"exit": 1, "findings": [("error","parse")]})

# 41. file safety: a FAILED graph --out must leave an existing baseline untouched
d = os.path.join(ROOT, "graph-out-sentinel")
if os.path.exists(d): shutil.rmtree(d)
os.makedirs(d)
for fname in ["definitions.json","axioms.json","hypotheses.json","theorems.json","deprecated.json","logic.json"]:
    open(os.path.join(d, fname), "w").write("{}")
open(os.path.join(d, "provenance.json"), "w").write("SENTINEL-BASELINE-DO-NOT-OVERWRITE")
json.dump({"exit": 0,
    "graph_out": {"exit": 2, "sentinel": "SENTINEL-BASELINE-DO-NOT-OVERWRITE"}},
  open(os.path.join(d, "EXPECTED.json"), "w"), indent=1)

# 42. file safety: a SUCCESSFUL graph --out writes a real artifact (temp+rename)
d = os.path.join(ROOT, "graph-out-success")
if os.path.exists(d): shutil.rmtree(d)
os.makedirs(d)
for fname, content in BASE.items():
    open(os.path.join(d, fname), "w").write(json.dumps(content, indent=1))
json.dump({"exit": 0,
    "graph_out": {"exit": 0, "target": "prov-out.json",
                  "written_contains": "dagcheck-provenance/v1"}},
  open(os.path.join(d, "EXPECTED.json"), "w"), indent=1)

# 43. coverage self-report: counts come from the live type files, tombstones are
#     excluded from active denominators, verdict buckets are exact
def _cov(f):
    f["theorems.json"]["T2"] = entry("T2","theorem", derived_from=["A1","D1"],
        inference_rule="conjunction + modus ponens",   # prose rule -> outside fragment
        derivation_note="prose combination", proof_confidence="PROBABLE",
        session_derived="2026-05-18")
    f["theorems.json"]["T3"] = entry("T3","theorem", derived_from=["A9"],
        inference_rule="modus ponens", derivation_note="cites a tombstone",
        proof_confidence="CERTAIN", form={"atom":"Q"}, session_derived="2026-05-18")
    f["hypotheses.json"]["H2"] = entry("H2","hypothesis",
        falsification="F.", review_trigger="R.", status="under-review",
        staleness_period_days=None, review_log=[])
make("coverage-report", _cov,
     {"exit": 1,   # T3 blocked verdict -> exit 1
      "verdicts": {"T1": "verified", "T2": "unchecked", "T3": "blocked"},
      "coverage": {
        "entries_active": 7, "entries_under_review": 1, "tombstones": 1,
        "theorems_total": 3,
        "theorem_verdicts": {"verified": 1, "rejected": 0, "blocked": 1,
                             "unchecked": 1, "stale": 0, "upstream_stale": 0,
                             "no_verdict": 0},
        "theorems_machine_checkable": 2,
        "machine_checkable_share_of_theorems": "2/3",
        "verified_share_of_machine_checkable": "1/2",
        "atoms_declared": 3, "atoms_used_in_active_forms": 3,
        "atoms_declared_unused": []}})

# 44. exports: hostile label/statement must survive escaping; output deterministic;
#     registry untouched (read-only)
HOSTILE_LABEL = 'x"<script>&\'\\\n{templ}'
def _hostile(f):
    f["theorems.json"]["T1"]["label"] = HOSTILE_LABEL
make("export-hostile", _hostile,
     {"exit": 0, "verdicts": {"T1": "verified"},
      "export": [
        {"format": "graphml", "exit": 0, "node_count": 6, "edge_count": 3},
        {"format": "cypher", "exit": 0, "node_count": 6, "edge_count": 3},
        {"format": "yaml", "exit": 2}]})

# 45. XML/Cypher-unsafe codepoints: a control character XML 1.0 cannot represent must
#     make export REFUSE LOUDLY (exit 2, entry + codepoint named, no artifact), never
#     silently corrupt the value
def _ctrl(f):
    f["theorems.json"]["T1"]["label"] = "bad\u0001label"
make("export-control-char", _ctrl,
     {"exit": 0, "verdicts": {"T1": "verified"},
      "export": [
        {"format": "graphml", "exit": 2, "stderr_contains": ["T1", "U+0001", "Refusing"],
         "out_refused": True},
        {"format": "cypher", "exit": 2, "stderr_contains": ["T1", "U+0001"],
         "out_refused": True}]})

print("fixtures generated in", ROOT)
