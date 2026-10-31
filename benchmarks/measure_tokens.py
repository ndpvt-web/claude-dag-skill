#!/usr/bin/env python3
"""Measure the actual context cost of a .dag registry. READ-ONLY.

What this script measures (real, reproducible):
  - byte and character sizes of every registry artifact: each type file,
    provenance.json, and the meta/registry.json summary index when present
  - the load cost of the skill's three token modes for THIS registry:
      Mode 1 (summary index): meta/registry.json only
      Mode 3 (full load): the four type files + deprecated.json
      Mode 2 (targeted load, per theorem): the type files of the types it cites

What it estimates (clearly labeled):
  - rough token counts, as ceil(chars / 4). This is the standard chars-per-token
    heuristic. It is an ESTIMATE: real tokenizers differ per model. The measured
    bytes/chars are the authoritative numbers; estimates exist only for comparison.

What this script does NOT do:
  - it does not measure answer quality, and it does not claim token SAVINGS.
    Savings claims require the paired protocol in benchmarks/README.md (same tasks
    with and without the registry, measured on the real model), plus a quality
    rubric. Run that protocol before quoting any headline number.

Usage: python3 benchmarks/measure_tokens.py <registry-dir> [--meta PATH] [--json]
  <registry-dir>  the .dag/registry directory
  --meta PATH     path to meta/registry.json (default: sibling ../meta/registry.json)
"""
import json, math, os, sys

def size_of(path):
    with open(path, "rb") as f:
        b = f.read()
    return {"path": path, "bytes": len(b), "chars": len(b.decode("utf-8")),
            "exists": True}

TYPE_FILES = ["axioms.json", "definitions.json", "hypotheses.json",
              "theorems.json", "deprecated.json"]
TYPE_OF_PREFIX = {"A": "axioms.json", "D": "definitions.json",
                  "H": "hypotheses.json", "T": "theorems.json"}

def measure(reg_dir, meta_path=None):
    if not os.path.isdir(reg_dir):
        return {"error": f"registry dir not found: {reg_dir}"}
    files = {}
    for f in TYPE_FILES + ["provenance.json"]:
        p = os.path.join(reg_dir, f)
        files[f] = size_of(p) if os.path.exists(p) else {"path": p, "exists": False}
    if meta_path is None:
        meta_path = os.path.join(os.path.dirname(os.path.abspath(reg_dir)),
                                 "meta", "registry.json")
    meta = size_of(meta_path) if os.path.exists(meta_path) else {"path": meta_path, "exists": False}

    mode3 = sum(files[f]["bytes"] for f in TYPE_FILES if files[f]["exists"])
    # Mode 2 per theorem: which type files must load to resolve its derived_from?
    mode2 = {}
    th_path = os.path.join(reg_dir, "theorems.json")
    if os.path.exists(th_path):
        try:
            theorems = json.load(open(th_path))
        except Exception:
            theorems = {}
        for tid, e in theorems.items():
            needed = {TYPE_OF_PREFIX["T"]}  # the theorem entry itself
            for cid in e.get("derived_from", []):
                f = TYPE_OF_PREFIX.get(cid[:1])
                if f:
                    needed.add(f)
            mode2[tid] = {
                "files": sorted(needed),
                "bytes": sum(files[f]["bytes"] for f in sorted(needed) if files[f]["exists"]),
            }
    result = {
        "registry_dir": reg_dir,
        "measured": {
            "files": files,
            "meta_registry_json": meta,
            "mode1_summary_index_bytes": meta["bytes"] if meta["exists"] else None,
            "mode3_full_load_bytes": mode3,
            "mode2_targeted_load_per_theorem": mode2,
        },
        "estimates": {
            "method": "ceil(chars/4); heuristic only - the measured bytes/chars above are authoritative",
        },
    }
    if meta["exists"]:
        result["estimates"]["mode1_summary_index_tokens"] = math.ceil(meta["chars"] / 4)
    result["estimates"]["mode3_full_load_tokens"] = math.ceil(
        sum(files[f]["chars"] for f in TYPE_FILES if files[f]["exists"]) / 4)
    for tid, m in mode2.items():
        chars = sum(files[f]["chars"] for f in m["files"] if files[f]["exists"])
        m["tokens_estimate"] = math.ceil(chars / 4)
    return result

def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    meta = None
    if "--meta" in sys.argv:
        i = sys.argv.index("--meta")
        meta = sys.argv[i + 1]
    if not args:
        print(__doc__)
        return 2
    r = measure(args[0], meta)
    print(json.dumps(r, indent=1))
    return 0 if "error" not in r else 1

if __name__ == "__main__":
    sys.exit(main())
