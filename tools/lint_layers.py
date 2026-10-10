"""Layer / cycle lint on top of tools/dep_graph.py (Bontago-1pi.11.77.4, plan section 6).

Report-only until S4b hooks it into tools/full_gate.py. Rules:

* L1 protected names: low-level sources (core, config, game/specials, game/world, vfx and a
  list of game/ files) must not have a compile edge (class, autoload_use, extends, preload,
  ext_resource) to Match, Net, net/** or autoload/match/**. `path` edges are info only.
* L2 SCC ratchet on the file graph (same edges as cycles.md): the largest SCC may not grow and an
  SCC containing an autoload may only contain baselined autoloads (allow-listed pairs).
* L3 autoload closure: the static compile closure of the [autoload] scripts may not gain files.

Baseline tools/layer_baseline.json (under --root):
  {"largest_scc": int, "autoload_scc_pairs": [[autoload file, ...]], "closure": [file, ...],
   "l1_exceptions": ["src -> dst", ...]}

  python tools/lint_layers.py [--root PATH] [--report] [--list] [--update] [--allow-new PATH]

Exit 1 on violation unless --report. --update only lowers/removes baseline entries (a missing
baseline is created); additions need --allow-new PATH (a source file for L1, a closure file or an
autoload file for L2/L3). Prints LAYER LINT GREEN|RED as the last line.
"""
from __future__ import print_function

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE_NAME = "layer_baseline.json"

COMPILE_KINDS = frozenset(["class", "autoload_use", "extends", "preload", "ext_resource"])
SOURCE_PREFIXES = ("core/", "config/", "game/specials/", "game/world/", "vfx/")
SOURCE_FILES = frozenset("game/%s.gd" % n for n in (
    "Block", "BlockFactory", "BlockRegistry", "BlockStepBatch", "Field", "GhostPreview", "GiftCrate",
    "HoleDissolver", "StableBlockManager", "SandboxConeAdapter", "BlockEffectsManager", "Skybox"))
FORBIDDEN_FILES = frozenset(["autoload/Match.gd", "autoload/Net.gd"])
FORBIDDEN_PREFIXES = ("net/", "autoload/match/")
REPORT_SCC_MIN = 5
# autoload/LateScripts.gd names late-built scripts by path STRING (runtime load(), never a compile
# edge); dep_graph records them as `path` edges, which would otherwise fuse the autoloads back into
# one SCC. They are left out of the SCC measurement (L2) only.
LATE_SCRIPTS_FILE = "autoload/LateScripts.gd"


def is_source(path):
    return path.startswith(SOURCE_PREFIXES) or path in SOURCE_FILES


def is_forbidden(path):
    return path in FORBIDDEN_FILES or path.startswith(FORBIDDEN_PREFIXES)


def exc_key(src, dst):
    return "%s -> %s" % (src, dst)


def _adjacency(graph, kinds, skip_src=()):
    files = graph["files"]
    adj = {}
    for e in graph["file_edges"]:
        if e["src"] not in files or e["dst"] not in files or e["src"] in skip_src:
            continue
        if kinds is None:
            if e["kind"] == "dynamic":
                continue
        elif e["kind"] not in kinds:
            continue
        adj.setdefault(e["src"], set()).add(e["dst"])
    return adj


def measure(graph):
    """Current state: L1 hits, SCCs, closure. Pure function of the graph."""
    import dep_graph
    files = graph["files"]
    l1 = []
    for e in graph["file_edges"]:
        if e["kind"] not in COMPILE_KINDS or e["src"] not in files:
            continue
        if is_source(e["src"]) and is_forbidden(e["dst"]):
            l1.append({"src": e["src"], "dst": e["dst"], "kind": e["kind"], "line": e["line"]})
    l1.sort(key=lambda v: (v["src"], v["dst"], v["kind"]))
    autoload_files = sorted(set(graph["autoloads"].values()))
    sccs = [c for c in dep_graph.tarjan_scc(_adjacency(graph, None, (LATE_SCRIPTS_FILE,))) if len(c) >= 2]
    sccs.sort(key=lambda c: (-len(c), c[0]))
    auto_sccs = []
    for c in sccs:
        members = sorted(set(c) & set(autoload_files))
        if members:
            auto_sccs.append({"size": len(c), "autoloads": members})
    cadj = _adjacency(graph, COMPILE_KINDS)
    closure = sorted(dep_graph._bfs([a for a in autoload_files if a in files], cadj))
    scripts = [p for p in closure if files[p]["kind"] == "script"]
    return {"l1": l1, "sccs": sccs, "largest_scc": len(sccs[0]) if sccs else 0, "auto_sccs": auto_sccs,
            "closure": closure, "closure_scripts": len(scripts),
            "closure_lines": sum(files[p].get("loc", 0) for p in scripts)}


def evaluate(cur, base):
    """Compare measure() output with a baseline dict. Returns list of violation strings."""
    out = []
    exc = set(base.get("l1_exceptions", []))
    for v in cur["l1"]:
        if exc_key(v["src"], v["dst"]) not in exc:
            out.append("L1 %s:%d %s edge to %s (protected name)" % (v["src"], v["line"], v["kind"], v["dst"]))
    if cur["largest_scc"] > base.get("largest_scc", 0):
        out.append("L2 largest SCC %d exceeds baseline %d" % (cur["largest_scc"], base.get("largest_scc", 0)))
    allowed = [set(p) for p in base.get("autoload_scc_pairs", [])]
    for s in cur["auto_sccs"]:
        if not any(set(s["autoloads"]) <= a for a in allowed):
            out.append("L2 SCC of %d files contains non-allow-listed autoloads %s" % (
                s["size"], ", ".join(s["autoloads"])))
    known = set(base.get("closure", []))
    for p in cur["closure"]:
        if p not in known:
            out.append("L3 %s entered the autoload closure" % p)
    return out


def lowered(cur, base):
    """Baseline reduced to what still holds in `cur` (never adds)."""
    cur_exc = set(exc_key(v["src"], v["dst"]) for v in cur["l1"])
    cur_closure = set(cur["closure"])
    cur_autos = set(x for s in cur["auto_sccs"] for x in s["autoloads"])
    pairs = []
    for a in base.get("autoload_scc_pairs", []):
        keep = sorted(set(a) & cur_autos)
        if keep and keep not in pairs:
            pairs.append(keep)
    return {"largest_scc": min(base.get("largest_scc", cur["largest_scc"]), cur["largest_scc"]),
            "autoload_scc_pairs": pairs,
            "closure": sorted(set(base.get("closure", [])) & cur_closure),
            "l1_exceptions": sorted(set(base.get("l1_exceptions", [])) & cur_exc)}


def apply_allow_new(new, cur, allow_new):
    """Add the entries `--allow-new` names (source file / closure file / autoload file)."""
    for path in allow_new:
        for v in cur["l1"]:
            if v["src"] == path:
                new["l1_exceptions"] = sorted(set(new["l1_exceptions"]) | set([exc_key(v["src"], v["dst"])]))
        if path in cur["closure"]:
            new["closure"] = sorted(set(new["closure"]) | set([path]))
        for s in cur["auto_sccs"]:
            if path in s["autoloads"]:
                new["autoload_scc_pairs"].append(list(s["autoloads"]))
                new["largest_scc"] = max(new["largest_scc"], s["size"])
    return new


def initial_baseline(cur):
    return {"largest_scc": cur["largest_scc"],
            "autoload_scc_pairs": [list(s["autoloads"]) for s in cur["auto_sccs"]],
            "closure": list(cur["closure"]),
            "l1_exceptions": sorted(set(exc_key(v["src"], v["dst"]) for v in cur["l1"]))}


def render_report(cur, base, list_all):
    exc = set(base.get("l1_exceptions", []))
    new_hits = [v for v in cur["l1"] if exc_key(v["src"], v["dst"]) not in exc]
    L = ["LAYER REPORT",
         "L1 protected-name edges: %d (%d not baselined)" % (len(cur["l1"]), len(new_hits))]
    by_src = {}
    for v in cur["l1"]:
        by_src.setdefault(v["src"], []).append(v)
    for src in sorted(by_src):
        dsts = sorted(set(v["dst"] for v in by_src[src]))
        L.append("  %s -> %s" % (src, ", ".join(dsts)))
        if list_all:
            for v in by_src[src]:
                L.append("      %s:%d %s -> %s" % (v["src"], v["line"], v["kind"], v["dst"]))
    L.append("L2 largest SCC: %d (baseline %s); SCCs >= %d: %s" % (
        cur["largest_scc"], base.get("largest_scc", "none"), REPORT_SCC_MIN,
        ", ".join(str(len(c)) for c in cur["sccs"] if len(c) >= REPORT_SCC_MIN) or "none"))
    for s in cur["auto_sccs"]:
        L.append("  SCC of %d contains autoloads: %s" % (s["size"], ", ".join(s["autoloads"])))
    L.append("L3 autoload closure: %d files, %d .gd, %d lines" % (
        len(cur["closure"]), cur["closure_scripts"], cur["closure_lines"]))
    return L


def run(root, report=False, list_all=False, update=False, allow_new=(), baseline_path=None, graph=None):
    """CLI core. Returns (exit_code, lines)."""
    import dep_graph
    if graph is None:
        graph = dep_graph.build_graph(root)
    cur = measure(graph)
    path = baseline_path or os.path.join(root, "tools", BASELINE_NAME)
    base = None
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            base = json.load(fh)
    lines = []
    if update:
        new = initial_baseline(cur) if base is None else apply_allow_new(lowered(cur, base), cur, allow_new)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(new, fh, indent=1, sort_keys=True)
            fh.write("\n")
        lines.append("baseline written: %s" % path)
        base = new
    base = base or {}
    lines.extend(render_report(cur, base, list_all or report))
    viol = evaluate(cur, base) if base else ["no baseline at %s (run --update)" % path]
    for v in viol:
        lines.append("VIOLATION " + v)
    red = bool(viol) and not report
    lines.append("LAYER LINT %s%s" % ("RED" if red else "GREEN", " (report-only)" if report and viol else ""))
    return (1 if red else 0), lines


def build_parser():
    ap = argparse.ArgumentParser(description="Layer / cycle lint (Bontago-1pi.11.77.4)")
    ap.add_argument("--root", "--path", dest="root", default=REPO)
    ap.add_argument("--report", action="store_true", help="print findings, always exit 0")
    ap.add_argument("--list", action="store_true", dest="list_all", help="include per-edge line numbers")
    ap.add_argument("--update", action="store_true", help="lower the baseline only")
    ap.add_argument("--allow-new", action="append", default=[], metavar="PATH")
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    code, lines = run(os.path.abspath(args.root), args.report, args.list_all, args.update, args.allow_new)
    print("\n".join(lines))
    return code


if __name__ == "__main__":
    sys.exit(main())
