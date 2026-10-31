#!/usr/bin/env python3
"""Run dagcheck against every fixture and assert EXPECTED.json. Read-only."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.environ.get("DAGCHECK_BIN",
    os.path.abspath(os.path.join(HERE, "..", ".lake", "build", "bin", "dagcheck")))
FX = os.path.join(HERE, "fixtures")

def run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)

failures = []
import time
for name in sorted(os.listdir(FX)):
    d = os.path.join(FX, name)
    exp = json.load(open(os.path.join(d, "EXPECTED.json")))
    today = exp.get("today", "2026-10-31")
    t0 = time.time()
    cap_args = ["--cap", str(exp["cap"])] if "cap" in exp else []
    r = run([BIN, "check", d, "--today", today] + cap_args)
    elapsed = time.time() - t0
    if name in ("exponent-attack", "digit-flood") and elapsed > 5:
        failures.append((name, f"parser took {elapsed:.1f}s on adversarial number (bound breached)"))
    errs = []
    if exp["exit"] == 2:   # usage-level refusal: stderr message, no JSON expected
        rep = None
        if not r.stderr.strip():
            errs.append("exit 2 without an explanatory stderr message")
    else:
        try:
            rep = json.loads(r.stdout)
        except Exception as e:
            errs.append(f"check output not JSON: {e}; stderr={r.stderr[:200]}")
            rep = None
    if r.returncode != exp["exit"]:
        errs.append(f"exit {r.returncode} != expected {exp['exit']}")
    if rep:
        got = {(f["level"], f["code"]) for f in rep["findings"]}
        for lv, code in exp.get("findings", []):
            if (lv, code) not in got:
                errs.append(f"missing finding ({lv},{code}); got {sorted(got)}")
        for code in exp.get("absent_codes", []):
            if any(c == code for _, c in got):
                errs.append(f"finding code '{code}' must not appear; got {sorted(got)}")
        vd = {v["id"]: v["verdict"] for v in rep["verdicts"]}
        for tid, want in exp.get("verdicts", {}).items():
            if vd.get(tid) != want:
                errs.append(f"verdict {tid}={vd.get(tid)} != {want}")
        fr = {e["id"]: e.get("freshness") for e in rep.get("entries", [])}
        for tid, want in exp.get("freshness", {}).items():
            if fr.get(tid) != want:
                errs.append(f"freshness {tid}={fr.get(tid)} != {want}")
    cov = exp.get("coverage")
    if cov and rep:
        def subset(want, got, path="coverage"):
            errs_ = []
            if isinstance(want, dict):
                for k, v in want.items():
                    if not isinstance(got, dict) or k not in got:
                        errs_.append(f"{path}.{k} missing")
                    else:
                        errs_ += subset(v, got[k], f"{path}.{k}")
            elif want != got:
                errs_.append(f"{path}={got!r} != {want!r}")
            return errs_
        errs += subset(cov, rep.get("coverage"))
    cstep = exp.get("check_step")
    if cstep:
        cr = run([BIN, "check-step", d, "--today", today,
                  "--premises", json.dumps(cstep["premises"]), "--step", json.dumps(cstep["step"])])
        want_exit = cstep["exit"]
        if cr.returncode != want_exit:
            errs.append(f"check-step exit {cr.returncode} != {want_exit}; stderr={cr.stderr[:200]}")
        if "verdict" in cstep:
            try:
                cv = json.loads(cr.stdout)
                if cv.get("verdict") != cstep["verdict"]:
                    errs.append(f"check-step verdict {cv.get('verdict')} != {cstep['verdict']}")
                if "reason_contains" in cstep and cstep["reason_contains"] not in cv.get("reason",""):
                    errs.append(f"check-step reason missing '{cstep['reason_contains']}': {cv.get('reason','')[:160]}")
            except Exception as e:
                errs.append(f"check-step output not JSON: {e}")
    gout = exp.get("graph_out")
    if gout:
        out_path = os.path.join(d, gout.get("target", "provenance.json"))
        gr = run([BIN, "graph", d, "--today", today, "--out", out_path])
        if gr.returncode != gout["exit"]:
            errs.append(f"graph --out exit {gr.returncode} != {gout['exit']}; stderr={gr.stderr[:200]}")
        if "sentinel" in gout:
            try:
                actual = open(out_path).read()
            except Exception as e:
                actual = f"<unreadable: {e}>"
            if actual != gout["sentinel"]:
                errs.append(f"sentinel baseline overwritten by failed generation: {actual[:80]!r}")
        if gout.get("written_contains"):
            try:
                actual = open(out_path).read()
            except Exception as e:
                actual = ""
            if gout["written_contains"] not in actual:
                errs.append(f"--out artifact missing {gout['written_contains']!r}: {actual[:80]!r}")
    gexp = exp.get("graph")
    if gexp:
        g = run([BIN, "graph", d, "--today", today])
        try:
            gv = json.loads(g.stdout)
        except Exception as e:
            errs.append(f"graph output not JSON: {e}")
            gv = None
        if gv:
            for nid, want in gexp.get("upstream", {}).items():
                if sorted(gv["upstream"].get(nid, [])) != sorted(want):
                    errs.append(f"upstream[{nid}]={sorted(gv['upstream'].get(nid,[]))} != {sorted(want)}")
            for nid, bad in gexp.get("upstream_not", {}).items():
                for b in bad:
                    if b in gv["upstream"].get(nid, []):
                        errs.append(f"upstream[{nid}] must not contain {b}")
            for nid, want in gexp.get("blast_radius", {}).items():
                if sorted(gv["blast_radius"].get(nid, [])) != sorted(want):
                    errs.append(f"blast[{nid}]={sorted(gv['blast_radius'].get(nid,[]))} != {sorted(want)}")
            for nid, bad in gexp.get("blast_not", {}).items():
                for b in bad:
                    if b in gv["blast_radius"].get(nid, []):
                        errs.append(f"blast[{nid}] must not contain {b}")
            if "dependency_cycles" in gexp and sorted(gv["cycles"]["dependency"]) != sorted(gexp["dependency_cycles"]):
                errs.append(f"dep cycles {gv['cycles']['dependency']} != {gexp['dependency_cycles']}")
            if "supersedes_cycles" in gexp and sorted(gv["cycles"]["supersedes"]) != sorted(gexp["supersedes_cycles"]):
                errs.append(f"sup cycles {gv['cycles']['supersedes']} != {gexp['supersedes_cycles']}")
            for nid, want in gexp.get("nodes", {}).items():
                node = next((n for n in gv.get("nodes", []) if n.get("id") == nid), None)
                if node is None:
                    errs.append(f"provenance node {nid} missing")
                    continue
                for field, wv in want.items():
                    if node.get(field) != wv:
                        errs.append(f"provenance node {nid}.{field}={node.get(field)!r} != {wv!r}")
    xps = exp.get("export")
    if xps:
        import hashlib
        def registry_hashes():
            return {f: hashlib.sha256(open(os.path.join(d, f), "rb").read()).hexdigest()
                    for f in sorted(os.listdir(d)) if f.endswith(".json")}
        def cypher_esc(s):  # independent reference escaper
            out = []
            for c in s:
                if c == "\\": out.append("\\\\")
                elif c == "'": out.append("\\'")
                elif c == "\n": out.append("\\n")
                elif c == "\r": out.append("\\r")
                elif c == "\t": out.append("\\t")
                elif ord(c) < 0x20: out.append(" ")
                else: out.append(c)
            return "".join(out)
        for xp in xps:
            before = registry_hashes()
            cmd = [BIN, "export", d, "--today", today]
            if xp.get("format") is not None:
                cmd += ["--format", xp["format"]]
            xr1 = run(cmd)
            xr2 = run(cmd)
            after = registry_hashes()
            tag = f"export[{xp.get('format')}]"
            if xr1.returncode != xp["exit"]:
                errs.append(f"{tag}: exit {xr1.returncode} != {xp['exit']}; stderr={xr1.stderr[:200]}")
            if xp.get("exit") == 0 and xr1.stdout != xr2.stdout:
                errs.append(f"{tag}: not deterministic (two runs differ)")
            if before != after:
                errs.append(f"{tag}: registry files changed by a READ-ONLY export")
            out = xr1.stdout
            if xp.get("format") == "graphml" and xp["exit"] == 0:
                try:
                    import xml.etree.ElementTree as ET
                    root = ET.fromstring(out)
                    ns = "{http://graphml.graphdrawing.org/xmlns}"
                    nodes = root.iter(ns + "node")
                    edges = root.iter(ns + "edge")
                    nn = len(list(nodes)); ne = len(list(edges))
                    if nn != xp.get("node_count"):
                        errs.append(f"{tag}: {nn} nodes != {xp.get('node_count')}")
                    if ne != xp.get("edge_count"):
                        errs.append(f"{tag}: {ne} edges != {xp.get('edge_count')}")
                    # label roundtrip: escaped form must decode back to the exact source label
                    th = json.load(open(os.path.join(d, "theorems.json")))
                    for n in root.iter(ns + "node"):
                        nid = n.get("id")
                        for data in n.iter(ns + "data"):
                            if data.get("key") == "d_label":
                                src_label = None
                                for f in ("axioms.json", "definitions.json", "hypotheses.json", "theorems.json"):
                                    obj = json.load(open(os.path.join(d, f)))
                                    if nid in obj:
                                        src_label = obj[nid].get("label", "")
                                if src_label is not None and data.text != src_label:
                                    errs.append(f"{tag}: label roundtrip failed for {nid}: {data.text!r} != {src_label!r}")
                except Exception as e:
                    errs.append(f"{tag}: graphml not well-formed XML: {e}")
            if xp.get("format") == "cypher" and xp["exit"] == 0:
                lines = [l for l in out.splitlines() if l.startswith("CREATE")]
                n_nodes = len([l for l in lines if ")-[" not in l])
                n_edges = len([l for l in lines if ")-[" in l])
                if n_nodes != xp.get("node_count"):
                    errs.append(f"{tag}: {n_nodes} cypher nodes != {xp.get('node_count')}")
                if n_edges != xp.get("edge_count"):
                    errs.append(f"{tag}: {n_edges} cypher edges != {xp.get('edge_count')}")
                th = json.load(open(os.path.join(d, "theorems.json")))
                for tid, e in th.items():
                    want = "label: '" + cypher_esc(e.get("label", "")) + "'"
                    if not any(want in l for l in lines):
                        errs.append(f"{tag}: escaped label for {tid} not found; want {want!r}")
                for l in lines:
                    if ")-[" in l and not __import__("re").match(r"^CREATE \(n\d+\)-\[:(CITES|DEPENDS_ON|SUPERSEDES)\]->\(n\d+\)$", l):
                        errs.append(f"{tag}: malformed relationship line: {l!r}")
            if xp.get("comment_contains") and xp["comment_contains"] not in out and xp["comment_contains"] not in xr1.stderr:
                errs.append(f"{tag}: missing comment {xp['comment_contains']!r}")
            for want in xp.get("stderr_contains", []):
                if want not in xr1.stderr:
                    errs.append(f"{tag}: stderr missing {want!r}: {xr1.stderr[:200]}")
            if xp.get("out_refused"):
                import tempfile
                op = os.path.join(tempfile.mkdtemp(prefix="dagcheck-outrefused-"), "out.xml")
                xr3 = run(cmd + ["--out", op])
                if xr3.returncode != xp["exit"]:
                    errs.append(f"{tag} --out: exit {xr3.returncode} != {xp['exit']}")
                if os.path.exists(op):
                    errs.append(f"{tag} --out: REFUSED export still wrote {op}")
    status = "PASS" if not errs else "FAIL"
    print(f"{status} {name}")
    for e in errs:
        print("   ", e)
        failures.append((name, e))

# D7: a label-only edit must NOT stale fingerprints. Build a baseline from `valid`,
# then change only labels in a copy and check for absence of stale-fingerprint.
import shutil, tempfile
src = os.path.join(FX, "valid")
tmp = tempfile.mkdtemp(prefix="dagcheck-label-edit-")
shutil.copytree(src, tmp, dirs_exist_ok=True)
base = run([BIN, "graph", tmp, "--today", "2026-10-31"])
if base.returncode != 0:
    failures.append(("label-edit-no-drift", "could not generate baseline: " + base.stderr[:200]))
else:
    with open(os.path.join(tmp, "provenance.json"), "w") as f:
        f.write(base.stdout)
    for fname in os.listdir(tmp):
        if fname.endswith(".json") and fname != "provenance.json":
            p = os.path.join(tmp, fname)
            import re
            s = re.sub(r'"label":\s*"[^"]*"', '"label": "renamed-label"', open(p).read())
            open(p, "w").write(s)
    chk = run([BIN, "check", tmp, "--today", "2026-10-31"])
    rep = json.loads(chk.stdout)
    stale = [f for f in rep["findings"] if f["code"] == "stale-fingerprint"]
    if stale:
        failures.append(("label-edit-no-drift", f"label-only edit staled {len(stale)} entries"))
    else:
        print("PASS label-edit-no-drift")
shutil.rmtree(tmp, ignore_errors=True)

print()
for n, e in failures:
    print(f"FAIL {n}: {e}")
print(f"{len(failures)} failure(s)" if failures else "ALL FIXTURES PASS")
sys.exit(1 if failures else 0)
