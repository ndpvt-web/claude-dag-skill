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
