#!/usr/bin/env python3
"""Tests for measure_tokens.py: the numbers must be REAL (byte sizes on disk),
deterministic, and every estimate must be labeled as an estimate."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
VALID = os.path.join(ROOT, "checker", "tests", "fixtures", "valid")

failures = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  {detail}" if not cond else ""))
    if not cond: failures.append((name, detail))

def run():
    r = subprocess.run([sys.executable, os.path.join(HERE, "measure_tokens.py"), VALID],
                       capture_output=True, text=True)
    return r.returncode, json.loads(r.stdout)

rc, r = run()
check("runs-clean", rc == 0)
files = r["measured"]["files"]
ok = True
for f, info in files.items():
    p = os.path.join(VALID, f)
    if os.path.exists(p):
        if info["bytes"] != os.path.getsize(p):
            ok = False
check("byte-counts-match-disk", ok)
check("all-type-files-measured",
      all(files[f]["exists"] for f in
          ["axioms.json", "definitions.json", "hypotheses.json", "theorems.json", "deprecated.json"]))
check("mode3-is-sum-of-type-files",
      r["measured"]["mode3_full_load_bytes"] ==
      sum(files[f]["bytes"] for f in
          ["axioms.json", "definitions.json", "hypotheses.json", "theorems.json", "deprecated.json"]))
m2 = r["measured"]["mode2_targeted_load_per_theorem"]
check("mode2-t1-loads-three-type-files",
      m2.get("T1", {}).get("files") == ["axioms.json", "hypotheses.json", "theorems.json"],
      str(m2))
check("estimates-labeled",
      "heuristic" in r["estimates"]["method"] and "authoritative" in r["estimates"]["method"])
_, r2 = run()
check("deterministic", r == r2)
# no summary index in the fixture: Mode 1 must be reported as absent, not invented
check("missing-meta-reported-absent",
      r["measured"]["mode1_summary_index_bytes"] is None
      and r["measured"]["meta_registry_json"]["exists"] is False)

print()
for n, e in failures:
    print(f"FAIL {n}: {e}")
print(f"{len(failures)} failure(s)" if failures else "ALL MEASUREMENT TESTS PASS")
sys.exit(1 if failures else 0)
