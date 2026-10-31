#!/usr/bin/env python3
"""Doc-code drift tests: the documentation must not name things the code does not
have, and the code must not drop things the documentation promises. Modeled on the
pattern of parsing the docs and checking the symbols exist, so a stale doc or a
dropped feature fails loudly instead of being discovered by a user.

Each check cross-verifies INDEPENDENT artifacts (docs vs code vs fixtures), so the
test is never tautological: the expected value is parsed from one file and verified
against a different one. Read-only: nothing here writes to the repo or a registry.
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CHECKER = os.path.join(ROOT, "checker")
FX = os.path.join(HERE, "fixtures")

def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as f:
        return f.read()

failures = []
def check(name, cond, detail=""):
    if cond:
        print(f"PASS {name}")
    else:
        print(f"FAIL {name}  {detail}")
        failures.append((name, detail))

README = read("README.md")
SKILL = read("SKILL.md")
VC = read("references/verified-checker.md")
GM = read("references/graph-model.md")
SPEC = read("references/registry-spec.md")
MAIN = read("checker/Main.lean")
REG = read("checker/Dagcheck/Registry.lean")
BRIDGE = read("checker/Dagcheck/Bridge.lean")
GRAPH_LEAN = read("checker/Dagcheck/Graph.lean")
VIEWER = read("graph/index.html")
LEAN_ALL = "\n".join(read(os.path.join("checker/Dagcheck", f))
                     for f in sorted(os.listdir(os.path.join(ROOT, "checker/Dagcheck")))
                     if f.endswith(".lean")) + MAIN

# 1+2. Commands and flags are cross-checked BIDIRECTIONALLY between the docs and
# the CLI: docs may not name anything the code lacks (fictional flags fail), and
# the code may not keep anything the docs dropped (deleting a feature's docs
# fails instead of silently narrowing the checked set). Flags are extracted
# generically from `dagcheck <cmd> ...` usage lines - never a whitelist.
CMD_RE = r"(check-step|check|graph|export)"
def doc_usage(texts):
    """(commands, {cmd: flags}) parsed from actual dagcheck usage lines in the
    given doc texts, with shell line continuations joined first."""
    cmds, flags = set(), {}
    for t in texts:
        joined = re.sub(r"\\\n", " ", t)
        for line in joined.splitlines():
            m = re.search(r"\bdagcheck\s+" + CMD_RE + r"\b(.*)", line)
            if m:
                cmds.add(m.group(1))
                flags.setdefault(m.group(1), set()).update(
                    re.findall(r"(?<![\w-])--[a-z][a-z0-9-]*", m.group(2)))
    return cmds, flags
doc_cmds, doc_flag_map = doc_usage([README, VC])
dispatched = set(re.findall(r'cmd\s*!=\s*"([a-z-]+)"', MAIN))
check("documented-commands-implemented",
      doc_cmds <= dispatched and doc_cmds != set(),
      f"docs name {sorted(doc_cmds)}, dispatch has {sorted(dispatched)}")
check("implemented-commands-documented",
      dispatched <= doc_cmds,
      f"dispatch has {sorted(dispatched)}, docs cover {sorted(doc_cmds)}")

doc_flags = set().union(*doc_flag_map.values()) if doc_flag_map else set()
consumed = set(re.findall(r'"(--[a-z]+)"', MAIN))
check("documented-flags-consumed",
      doc_flags <= consumed,
      f"docs name {sorted(doc_flags)}, Main.lean consumes {sorted(consumed)}")
check("consumed-flags-documented",
      consumed <= doc_flags,
      f"Main.lean consumes {sorted(consumed)}, docs cover {sorted(doc_flags)}")

# 3. Verdict vocabulary documented in verified-checker.md exists in the Lean sources.
verdict_words = set(re.findall(r"\*\*(verified|rejected|blocked|unchecked|stale|upstream-stale)(?:\s*/|\*\*)", VC))
missing_v = [w for w in verdict_words if f'"{w}"' not in LEAN_ALL]
check("verdict-vocabulary-implemented", verdict_words and not missing_v,
      f"docs name {sorted(verdict_words)}, missing in Lean: {missing_v}")

# 4. README's fixture-count claim matches the real fixture directory count.
m = re.search(r"(\d+)\s+fixture registries", README)
real_count = len([d for d in os.listdir(FX) if os.path.isdir(os.path.join(FX, d))])
check("readme-fixture-count-matches",
      m is not None and int(m.group(1)) == real_count,
      f"README claims {m.group(1) if m else None}, fixtures dir has {real_count}")

# 5. Every fixture named in the docs (word 'fixture(s)' followed by a dashed name) exists.
named = set()
for doc in (README, VC, SKILL):
    named |= set(re.findall(r"fixtures?\s+([a-z][a-z0-9]+(?:-[a-z0-9]+)+)", doc))
    named |= set(re.findall(r"fixture[s]?\s+(?:\w+\s+)?([a-z][a-z0-9]+(?:-[a-z0-9]+)+)\s*/\s*([a-z][a-z0-9]+(?:-[a-z0-9]+)+)", doc) and
                 {t for pair in re.findall(r"fixtures?\s+([a-z][a-z0-9-]+)\s*/\s*([a-z][a-z0-9-]+)", doc) for t in pair})
named = {n for n in named if "-" in n and not n.endswith((".json", ".md"))}
missing_fx = [n for n in named if not os.path.isdir(os.path.join(FX, n))]
check("documented-fixtures-exist", not missing_fx,
      f"docs name fixtures {sorted(named)}, missing: {missing_fx}")

# 6. registry-spec.md field names per type are all handled by the strict parser.
def spec_fields(header):
    sec = SPEC.split(header, 1)[1]
    block = re.search(r"```json(.*?)```", sec, re.S).group(1)
    return set(re.findall(r'"([a-z_]+)":', block))
parser_missing = []
for header, tag in [("## D-type", "D"), ("## H-type", "H"), ("## A-type", "A"),
                    ("## T-type", "T"), ("## Tombstone Format", "tombstone")]:
    for field in spec_fields(header):
        if f'"{field}"' not in REG:
            parser_missing.append(f"{tag}:{field}")
check("spec-fields-parsed", not parser_missing,
      f"spec fields absent from parser: {parser_missing}")

# 7. Every rule in the registry-spec inference table is either matched by
#    ruleSpecOfName or explicitly documented as outside the verified fragment.
table_rules = set()
in_table = False
for line in SPEC.splitlines():
    if line.startswith("## Inference Rules Reference"):
        in_table = True
    elif in_table and line.startswith("## "):
        in_table = False
    elif in_table and line.startswith("|") and "---" not in line and "Rule |" not in line:
        table_rules.add(line.split("|")[1].strip().lower())
rulesec = REG.split("def ruleSpecOfName", 1)[1].split("def ", 1)[0] if "def ruleSpecOfName" in REG else ""
unhandled = [r for r in table_rules
             if f'"{r}"' not in rulesec.lower()
             and not re.search(rf"\b{re.escape(r)}\b", VC.lower())]
check("spec-rule-table-classified", table_rules and not unhandled,
      f"spec rules neither matched in ruleSpecOfName nor documented as outside: {unhandled}")

# 8. Edge kinds agree across graph-model.md, the Lean serializer, and the viewer validator.
gm_kinds = set(re.findall(r"`(cites|depends|supersedes)`", GM))
lean_kinds = set(re.findall(r'\| \.(cites|depends|supersedes) =>', BRIDGE))
vm = re.search(r"const kinds = \{([^}]*)\}", VIEWER)
viewer_kinds = set(re.findall(r"(cites|depends|supersedes):1", vm.group(1))) if vm else set()
check("edge-kinds-consistent",
      gm_kinds == lean_kinds == viewer_kinds == {"cites", "depends", "supersedes"},
      f"graph-model {sorted(gm_kinds)}, Lean {sorted(lean_kinds)}, viewer {sorted(viewer_kinds)}")

# 9. The provenance spec token is identical in the emitter (Bridge.lean) and the
#    viewer's validator - a version bump on one side must move the other.
emit = re.findall(r'"(dagcheck-provenance/v\d+)"', BRIDGE)
accept = re.findall(r'"(dagcheck-provenance/v\d+)"', VIEWER)
check("provenance-spec-token-synced",
      len(set(emit)) == 1 and set(emit) == set(accept),
      f"Bridge emits {emit}, viewer accepts {accept}")

# 10. The documented atomic-baseline discipline is real: `graph --out` is the only
#     write path in Main.lean besides export --out, and both are temp+rename, and
#     no hook script may regenerate the baseline.
hook_post = read("hooks/post-commit") if os.path.exists(os.path.join(ROOT, "hooks/post-commit")) else ""
hook_pre = read("hooks/pre-commit") if os.path.exists(os.path.join(ROOT, "hooks/pre-commit")) else ""
writes = re.findall(r"IO\.FS\.(writeFile|rename)", MAIN)
# A hook may PRINT the manual re-baseline command for a human to run; it must never
# EXECUTE it. Distinguish invocation lines from echo/comment lines.
def hook_executes_graph(s):
    """True if s runs the graph subcommand on an executable line. Permissive
    about quoting ($BIN graph, "$BIN" graph, dagcheck graph) so a quoting
    variant cannot slip a baseline rewrite past this test; echo/printf/comment
    lines are messages to a human, not invocations."""
    for line in s.splitlines():
        t = line.strip()
        if t.startswith("#") or t.startswith("echo ") or t.startswith('echo"') or t.startswith("printf "):
            continue
        if re.search(r'"?(?:\$BIN|dagcheck)"?\s+graph\b', t):
            return True
    return False
check("hooks-never-regenerate-baseline",
      hook_post != "" and hook_pre != ""
      and not hook_executes_graph(hook_post) and not hook_executes_graph(hook_pre),
      "hooks must execute check only; baseline regeneration stays a human-reviewed step")
check("main-writes-are-out-only",
      writes.count("writeFile") == 2 and writes.count("rename") == 2,
      f"expected exactly 2 temp+rename write paths (graph --out, export --out); found {writes}")

# 11. The viewer's inline script must parse. (Regression: a doc-driven edit once
#     left a raw newline inside a quoted string and silently broke the whole viewer
#     while every other suite passed.) Uses node when available; skips loudly if not.
import shutil as _sh, subprocess as _sp
if _sh.which("node"):
    probe = _sp.run(["node", "-e",
        "const fs=require('fs');const h=fs.readFileSync(process.argv[1],'utf8');"
        "const m=h.match(/<script>([\\s\\S]*?)<\\/script>/);"
        "new Function(m[1]);console.log('ok');",
        os.path.join(ROOT, "graph", "index.html")],
        capture_output=True, text=True)
    check("viewer-script-parses", probe.stdout.strip() == "ok",
          probe.stderr.strip()[:200])
else:
    print("SKIP viewer-script-parses (node not available)")

# 12. Mutation battery: the cross-checks must actually FAIL when their invariant
#     is violated in-memory. A check that passes on mutated input is vacuous.
def expect_broken(name, invariant_holds, detail):
    check(f"mutation-{name}", not invariant_holds, detail)

# 12a. A fictional flag in the docs must fail documented-flags-consumed.
vc_frob = re.sub(r"(dagcheck check <registry-dir>[^\n]*\[--cap N\])",
                 r"\1 --frob", VC, count=1)
assert vc_frob != VC, "frob mutation anchor missing"
_, frob_flags = doc_usage([vc_frob])
frob_all = set().union(*frob_flags.values())
expect_broken("fictional-flag-fails", frob_all <= consumed,
              "fictional --frob in docs was not flagged")

# 12b. Deleting a command's docs must fail implemented-commands-documented.
no_export_vc = "\n".join(l for l in VC.splitlines() if "dagcheck export" not in l)
no_export_rd = "\n".join(l for l in README.splitlines() if "dagcheck export" not in l)
no_export_cmds, _ = doc_usage([no_export_rd, no_export_vc])
expect_broken("deleted-export-docs-fail", dispatched <= no_export_cmds,
              "deleting export docs silently narrowed the checked set")

# 12c. The judge's quoting-variant attack on the hook must be caught, while the
#      legitimate human-facing re-baseline instructions stay allowed.
attack = hook_pre + '\n"$BIN" graph "$REG" --out "$REG/provenance.json"\n'
expect_broken("quoted-graph-invocation-caught", not hook_executes_graph(attack),
              "'\"$BIN\" graph' invocation bypassed hook_executes_graph")
attack2 = hook_pre + "\ndagcheck graph .dag/registry --out .dag/registry/provenance.json\n"
expect_broken("bare-dagcheck-graph-caught", not hook_executes_graph(attack2),
              "bare 'dagcheck graph' invocation bypassed hook_executes_graph")
echo_line = hook_pre + '\necho "  dagcheck graph .dag/registry --out .dag/registry/provenance.json"\n'
check("mutation-manual-rebaseline-echo-allowed", not hook_executes_graph(echo_line),
      "a human-facing echo of the re-baseline command was misclassified as an invocation")

print()
for n, e in failures:
    print(f"FAIL {n}: {e}")
print(f"{len(failures)} failure(s)" if failures else "ALL DOC-DRIFT CHECKS PASS")
sys.exit(1 if failures else 0)
