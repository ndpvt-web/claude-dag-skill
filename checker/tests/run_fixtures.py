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
for name in sorted(os.listdir(FX)):
    d = os.path.join(FX, name)
    exp = json.load(open(os.path.join(d, "EXPECTED.json")))
    today = exp.get("today", "2026-10-31")
    r = run([BIN, "check", d, "--today", today])
    errs = []
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
    status = "PASS" if not errs else "FAIL"
    print(f"{status} {name}")
    for e in errs:
        print("   ", e)
        failures.append((name, e))

print()
print(f"{len(failures)} failure(s)" if failures else "ALL FIXTURES PASS")
sys.exit(1 if failures else 0)
