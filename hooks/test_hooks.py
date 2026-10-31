#!/usr/bin/env python3
"""Behavioral tests for hooks/pre-commit and hooks/post-commit in real temp git
repos. Read-only over the source repo; all writes happen in temp dirs.

Invariants under test (from the comparison review and the judge's risk notes):
  - clean registry commit: both hooks pass quietly
  - content drift: pre-commit REPORTS stale and lets the commit through (warning,
    not block); post-commit prints the recheck list + the manual re-baseline
    reminder; provenance.json stays BYTE-IDENTICAL across repeated hook runs
  - rejected verdict: pre-commit BLOCKS (exit 1)
  - missing binary: hooks pass with a skip notice, never disable git
  - no .dag directory: hooks are silent no-ops
"""
import json, os, shutil, subprocess, sys, tempfile, hashlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, ".."))
BIN = os.environ.get("DAGCHECK_BIN",
    os.path.join(ROOT, "checker", ".lake", "build", "bin", "dagcheck"))
VALID = os.path.join(ROOT, "checker", "tests", "fixtures", "valid")

failures = []
def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + (f"  {detail}" if not cond else ""))
    if not cond:
        failures.append((name, detail))

def sh(cmd, cwd, env=None):
    e = dict(os.environ); e.update(env or {})
    return subprocess.run(cmd, cwd=cwd, env=e, shell=True,
                          capture_output=True, text=True)

def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()

def make_repo(with_registry=True, with_baseline=True):
    d = tempfile.mkdtemp(prefix="dagcheck-hooks-")
    sh("git init -q && git config user.email t@t && git config user.name t", d)
    if with_registry:
        reg = os.path.join(d, ".dag", "registry")
        os.makedirs(reg)
        for f in os.listdir(VALID):
            if f.endswith(".json") and f != "EXPECTED.json":
                shutil.copy(os.path.join(VALID, f), os.path.join(reg, f))
        if with_baseline:
            r = subprocess.run([BIN, "graph", reg, "--today", "2026-10-31",
                                "--out", os.path.join(reg, "provenance.json")],
                               capture_output=True, text=True)
            assert r.returncode == 0, r.stderr
    os.makedirs(os.path.join(d, ".git", "hooks"), exist_ok=True)
    for h in ("pre-commit", "post-commit"):
        shutil.copy(os.path.join(HERE, h), os.path.join(d, ".git", "hooks", h))
        os.chmod(os.path.join(d, ".git", "hooks", h), 0o755)
    return d

env = {"DAGCHECK_BIN": BIN, "PATH": "/usr/bin:/bin"}

# --- scenario 1: clean registry ------------------------------------------------
d = make_repo()
r = sh("git add .dag && git commit -qm init; echo RC=$?", d, env)
check("clean-commit-hooks-pass", "RC=0" in r.stdout, r.stdout + r.stderr)
prov = os.path.join(d, ".dag", "registry", "provenance.json")
h0 = sha(prov)
r2 = sh("git add .dag && git commit -qm init2 --allow-empty; echo RC=$?", d, env)
check("baseline-byte-identical-after-idle-commit", sha(prov) == h0)
shutil.rmtree(d, ignore_errors=True)

# --- scenario 2: drift reports but never blocks, never rewrites ----------------
d = make_repo()
sh("git add .dag && git commit -qm init", d, env)
reg = os.path.join(d, ".dag", "registry")
ax = os.path.join(reg, "axioms.json")
data = json.load(open(ax))
data["A1"]["statement"] = "Changed statement after baseline."
json.dump(data, open(ax, "w"), indent=1)
h0 = sha(prov := os.path.join(reg, "provenance.json"))
r = sh("git add .dag && git commit -qm drift > /tmp/o 2>&1; echo RC=$?; cat /tmp/o", d, env)
check("drift-commit-allowed-with-warning", "RC=0" in r.stdout, r.stdout + r.stderr)
check("drift-warning-printed", "stale" in (r.stdout + r.stderr).lower(), r.stderr[:300])
check("baseline-byte-identical-after-drift-commit", sha(prov) == h0)
# run post-commit a second time directly: still read-only, still byte-identical
r2 = sh(".git/hooks/post-commit 2>&1; echo RC=$?", d, env)
check("post-commit-repeat-still-read-only", sha(prov) == h0 and "RC=0" in r2.stdout)
check("post-commit-prints-manual-rebaseline-reminder",
      "--out" in (r2.stdout + r2.stderr) and "never automatic" in (r2.stdout + r2.stderr),
      (r2.stdout + r2.stderr)[:300])
shutil.rmtree(d, ignore_errors=True)

# --- scenario 3: rejected verdict blocks ---------------------------------------
d = make_repo()
sh("git add .dag && git commit -qm init", d, env)
reg = os.path.join(d, ".dag", "registry")
th = os.path.join(reg, "theorems.json")
data = json.load(open(th))
data["T1"]["form"] = {"atom": "R"}   # A1: P->Q, H1: P cannot derive R
json.dump(data, open(th, "w"), indent=1)
r = sh("git add .dag && git commit -qm bad > /tmp/o 2>&1; echo RC=$?; cat /tmp/o", d, env)
check("rejected-verdict-blocks-commit", "RC=1" in r.stdout, r.stdout + r.stderr)
check("block-message-explains", "commit blocked" in (r.stdout + r.stderr),
      (r.stdout + r.stderr)[:300])
shutil.rmtree(d, ignore_errors=True)

# --- scenario 4: missing binary is a skip, not a wall --------------------------
d = make_repo()
r = sh("git add .dag && git commit -qm init; echo RC=$?", d,
       {"DAGCHECK_BIN": "/nonexistent/dagcheck", "PATH": "/usr/bin:/bin",
        "HOME": d})  # HOME=d so the ~/.claude fallback cannot find a binary
check("missing-binary-skips-and-allows", "RC=0" in r.stdout, r.stdout + r.stderr)
check("missing-binary-prints-notice", "binary not found" in r.stderr, r.stderr[:200])
shutil.rmtree(d, ignore_errors=True)

# --- scenario 5: no .dag directory = silent no-op ------------------------------
d = make_repo(with_registry=False)
open(os.path.join(d, "x.txt"), "w").write("hi")
r = sh("git add x.txt && git commit -qm plain; echo RC=$?", d, env)
check("no-registry-is-noop", "RC=0" in r.stdout and r.stderr == "", r.stderr[:200])
shutil.rmtree(d, ignore_errors=True)

print()
for n, e in failures:
    print(f"FAIL {n}: {e}")
print(f"{len(failures)} failure(s)" if failures else "ALL HOOK TESTS PASS")
sys.exit(1 if failures else 0)
