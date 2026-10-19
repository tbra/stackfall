"""Dead-weight recurrence guard (reorg P7).

Usage: python tools/lint_dead.py [--path <checkout>] [--report] [--update-baseline] [--today YYYY-MM-DD]

Enforces the rules "a test never keeps code alive", "files mentioned only in comments or docs are
dead" and "no dead weight left behind". Four checks, one finding per line as `path:line: id: message`:

  dead-file       a game file (not tests/tools/addons/docs/.claude/source_art) unreachable from project.godot
                  or export_presets.cfg through real edges (load/preload/ext_resource/class_name use/shader
                  include/autoload/uid, plus the folder scans in FOLDER_SCANS). Edges from comment lines,
                  from tests/tools/addons and the dep_graph "dynamic" prefix guesses do not count.
  test-only-func  a func in a game .gd not reachable (strict call graph, from engine virtuals, rpc, signal
                  handlers and top-level code of reachable files) except through tests, or only through
                  name-ambiguous calls (those need an allow-list line with a reason).
  stale-path      a res:// or repo-relative path in a comment/string of a tracked text file that does not exist.
                  A line containing `lint-dead: ignore` is skipped.
  undated-legacy  legacy | kept for one release | compat(ibility) | deprecated in a game .gd comment or
                  identifier without `(expires YYYY-MM-DD)` on the line, or past its expiry. The older
                  `(Bontago-<id>, expires YYYY-MM-DD)` form still passes until the code pass converts it.

tools/dead_baseline.json holds today's findings per check (`checks`) and reviewed exceptions (`allow`:
[{"id","entry","reason"}]). Only findings outside both fail the run (exit 1); baseline entries that no longer
occur are reported as stale so the baseline only shrinks (`--update-baseline` rewrites it, keeping `allow`
entries that still match). `--report` prints counts per check and folder. Graph building reuses
tools/dep_graph.py (about 15 s).
"""
import argparse
import collections
import datetime
import json
import os
import re
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import dep_graph  # noqa: E402

BASELINE_NAME = "dead_baseline.json"
NON_GAME_PREFIXES = ("tests/", "tools/", "addons/", "docs/", ".claude/", "source_art/")
CHECKS = ("dead-file", "test-only-func", "stale-path", "undated-legacy")
ROOT_FILES = ("project.godot", "export_presets.cfg")

# Folder scans the game really performs at runtime (DirAccess listing or a "<dir>/%s.ext" build): the scanning
# file reaches the folder's files. dep_graph's own "dynamic" prefix guesses are ignored; add a row only for a
# scan the code performs, with the site named. (scanning file, folder, recursive, extensions)
FOLDER_SCANS = (
    ("config/blocks/BlockShape.gd", "config/blocks", False, (".tres",)),             # load_all_shapes list_dir
    ("config/gifts/specials/SpecialDef.gd", "config/gifts/specials", False, (".tres",)),  # load_all list_dir
    ("config/weather/WeatherTuning.gd", "config/weather", False, (".tres",)),        # list_dir over WEATHER_DIR
    ("autoload/Settings.gd", "config/graphics/presets", False, (".tres",)),          # PRESETS_DIR loads
    ("autoload/Sfx.gd", "assets/audio/sfx", True, (".wav", ".ogg", ".mp3")),         # get_files_at(_root_dir)
    ("ui/hud/HUD.gd", "assets/ui/block_previews", False, (".png",)),                 # "%s.png" % shape.id
)
# Letter-bounded (not a word boundary) so identifiers such as compat_mode or legacy_path match too.
LEGACY_RE = re.compile(r"(?<![A-Za-z])(legacy|kept for one release|compat(?:ibility)?|deprecated)(?![A-Za-z])", re.I)
EXPIRY_RE = re.compile(r"\((?:Bontago-[\w.]+,\s*)?expires\s+(\d{4}-\d{2}-\d{2})\)")
IGNORE_MARK = "lint-dead: ignore"
STALE_TOP = ("autoload", "config", "core", "game", "net", "ui", "shaders", "assets", "tests", "tools",
             "docs", "addons", "source_art", "vfx", "sfx", "scenes", "scripts")
STALE_EXTS = (".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".json", ".py", ".ps1", ".md", ".cfg",
              ".png", ".svg", ".wav", ".ogg", ".mp3", ".glb", ".ttf", ".txt", ".uid", ".res", ".import")
PATH_RE = re.compile(r"(?<![\w./:-])(res://|(?:%s)/)([\w./-]*)" % "|".join(STALE_TOP))
STALE_FILES = ("CLAUDE.md", "README.md", "docs/SPEC.md")
STALE_SUFFIX = (".gd", ".gdshader", ".gdshaderinc", ".tscn", ".tres", ".cfg", ".py", ".ps1")
# .claude/worktrees holds agent isolation checkouts, not this tree.
STALE_SKIP_DIRS = ("addons/", "docs/archive/", ".godot/", ".git/", "tools/test_", ".claude/worktrees/")
# Paths that legitimately do not exist in a checkout: per-developer addon, generated at build/run time.
# Ignored paths that exist only in some checkouts (override.cfg in agent worktrees, docs/archive
# in the main one): their presence varies by checkout, so the result must not.
STALE_GENERATED = ("addons/godotsteam", "build_info.cfg", "tests/.gut_targeted", "override.cfg", "docs/archive")
ENGINE_FUNC_PREFIX = ("_on_",)


def rd(root, rel):
    try:
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def game_candidate(path):
    return not path.startswith(NON_GAME_PREFIXES)


# ---- shared graph -------------------------------------------------------

class Lines(object):
    """Per-file cache of raw lines and (for .gd) the comment/string-blanked lines."""

    def __init__(self, root):
        self.root = root
        self.raw = {}
        self.code = {}
        self.strs = {}

    def get(self, rel):
        if rel not in self.raw:
            text = rd(self.root, rel)
            self.raw[rel] = text.split("\n")
            if rel.endswith(".gd"):
                stripped, strings = dep_graph.lex_gdscript(text)
                self.code[rel] = stripped.split("\n")
                by_line = collections.defaultdict(list)
                for s in strings:
                    by_line[s["line"]].append(s["value"])
                self.strs[rel] = by_line
            elif rel.endswith((".gdshader", ".gdshaderinc")):
                self.code[rel] = [re.sub(r"//.*", "", ln) for ln in self.raw[rel]]
                self.strs[rel] = {}
        return self.raw[rel]

    def code_line(self, rel, n):
        self.get(rel)
        c = self.code.get(rel)
        if c is None:
            return None
        return c[n - 1] if 0 < n <= len(c) else ""


def real_edge(e, g, lines):
    """True when the file edge is a genuine reference: not from non-game files, comments or dynamic guesses."""
    src, dst, kind, n = e["src"], e["dst"], e["kind"], e.get("line")
    if kind == "dynamic" or src.startswith(NON_GAME_PREFIXES):
        return False
    if not n or not src.endswith((".gd", ".gdshader", ".gdshaderinc")):
        return True
    code = lines.code_line(src, n)
    if code is None or not code.strip():
        return False  # comment-only line
    if kind in ("class", "autoload_use"):
        name = (g["files"].get(dst) or {}).get("class_name")
        if not name:
            name = next((k for k, v in g["autoloads"].items() if v == dst), None)
        return bool(name) and re.search(r"\b%s\b" % re.escape(name), code) is not None
    if kind in ("path", "preload") and src.endswith(".gd"):
        base = os.path.basename(dst)
        return any(base in s or dst in s or "uid://" in s for s in lines.strs.get(src, {}).get(n, ()))
    return True


def folder_edges(files):
    out = []
    for src, folder, recursive, exts in FOLDER_SCANS:
        if src not in files:
            continue
        pre = folder.rstrip("/") + "/"
        for p in files:
            if not p.startswith(pre) or not p.endswith(exts):
                continue
            if not recursive and "/" in p[len(pre):]:
                continue
            out.append((src, p))
    return out


def reachable_files(g, lines):
    adj = collections.defaultdict(set)
    for e in g["file_edges"]:
        if real_edge(e, g, lines):
            adj[e["src"]].add(e["dst"])
    for s, d in folder_edges(g["files"]):
        adj[s].add(d)
    seen = set(r for r in ROOT_FILES if r in g["files"] or r == "project.godot")
    stack = list(seen)
    while stack:
        f = stack.pop()
        for d in adj.get(f, ()):
            if d not in seen and not d.startswith(NON_GAME_PREFIXES):
                seen.add(d)
                stack.append(d)
    return seen


def check_dead_files(g, reached):
    out = []
    sidecars = set(sc["path"] for sc in g["sidecars"])
    for p, n in sorted(g["files"].items()):
        if n["kind"] == "config" or p in sidecars or p in reached or not game_candidate(p):
            continue
        if p.endswith((".uid", ".import")):
            continue
        out.append((p, 1, "dead-file", "unreachable from project.godot/export_presets.cfg (comments, tests and docs do not count)"))
    return out


# ---- functions ----------------------------------------------------------

def descendants(files):
    """file -> every file below it through `extends` (class_name or res:// path), transitively."""
    by_class = {n["class_name"]: p for p, n in files.items() if n.get("class_name")}
    kids = collections.defaultdict(set)
    for p, n in files.items():
        ext = n.get("extends") or ""
        parent = ext[len("res://"):] if ext.startswith("res://") else by_class.get(ext.split(".")[0])
        if parent and parent != p and parent in files:
            kids[parent].add(p)
    out = {}
    for base in kids:
        seen, stack = set(), [base]
        while stack:
            for k in kids.get(stack.pop(), ()):
                if k not in seen:
                    seen.add(k)
                    stack.append(k)
        out[base] = seen
    return out


def override_family_calls(g, funcs):
    """(src, line, dst) of ambiguous call edges whose candidates are one base function plus its overrides.

    The receiver's type is lost (`port().f()`), but every candidate is the base or a subclass override of it,
    so the call is not really name-ambiguous: it reaches each of them."""
    desc = descendants(g["files"])
    groups = collections.defaultdict(set)
    for e in g["call_edges"]:
        if (e.get("amb") or e["kind"] == "ambiguous") and e["src"] in funcs.keys() | {e["src"]}:
            groups[(e["src"], e.get("line"))].add(e["dst"])
    out = set()
    for (src, line), dsts in groups.items():
        fs = [funcs[d] for d in dsts if d in funcs]
        if len(fs) != len(dsts) or len(set(f["name"] for f in fs)) != 1:
            continue
        files = set(f["file"] for f in fs)
        if any(files <= {b} | desc.get(b, set()) for b in files):
            out.update((src, line, d) for d in dsts)
    return out


def check_funcs(g, reached):
    funcs = g["funcs"]

    def game_func(fid):
        f = funcs.get(fid)
        return f is not None and game_candidate(f["file"]) and f["file"].endswith(".gd")

    strict, loose = collections.defaultdict(set), collections.defaultdict(set)
    test_called = set()
    family = override_family_calls(g, funcs)
    for e in g["call_edges"]:
        s, d = e["src"], e["dst"]
        sfile = s.split(":")[0]
        if not game_candidate(sfile):
            if sfile.startswith("tests/") or sfile.startswith("tools/"):
                test_called.add(d)
            continue
        loose[s].add(d)
        if (not e.get("amb") and e["kind"] != "ambiguous") or (s, e.get("line"), d) in family:
            strict[s].add(d)
    roots = set()
    for fid, f in funcs.items():
        if f["file"] in reached and game_func(fid) and (f["root"] in ("engine", "rpc") or f["name"].startswith(ENGINE_FUNC_PREFIX)):
            roots.add(fid)
    for s in list(loose):
        if ":" not in s and s in reached:
            roots.add(s)

    def bfs(adj):
        seen, stack = set(roots), list(roots)
        while stack:
            x = stack.pop()
            for y in adj.get(x, ()):
                if y not in seen:
                    seen.add(y)
                    stack.append(y)
        return seen

    live, loose_live = bfs(strict), bfs(loose)
    out = []
    for fid, f in sorted(funcs.items(), key=lambda kv: (kv[1]["file"], kv[1]["line"])):
        if not game_func(fid) or f["file"] not in reached or fid in live:
            continue
        if fid in loose_live:
            why = "reached only through a name-ambiguous call; allow-list it with a reason or make the call typed"
        elif fid in test_called:
            why = "only tests/tools call it; delete it and its tests"
        else:
            why = "no callers"
        out.append((f["file"], f["line"], "test-only-func", "%s: %s" % (f["name"], why), "%s:%s" % (f["file"], f["name"])))
    return out


# ---- stale paths --------------------------------------------------------

def text_files(root, files):
    """Tracked-ish text files to scan for stale paths: game/tooling files plus the named docs."""
    out = set()
    for p in files:
        if p.endswith(STALE_SUFFIX) and not p.startswith(STALE_SKIP_DIRS) and not p.startswith(".godot/"):
            out.add(p)
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in (".godot", ".git", "__pycache__", "addons", "node_modules", "scratch")]
        rel_dir = os.path.relpath(dirpath, root).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        if rel_dir == ".claude":
            dirnames[:] = [d for d in dirnames if d != "worktrees"]
        for n in filenames:
            rel = (rel_dir + "/" + n) if rel_dir else n
            if rel.startswith(STALE_SKIP_DIRS):
                continue
            if rel.endswith(STALE_SUFFIX) and (rel.startswith(("tools/", ".claude/", "tests/")) or "/" not in rel):
                out.add(rel)
            elif rel in STALE_FILES or (rel.startswith(".claude/") and rel.endswith(".md")):
                out.add(rel)
    return sorted(out)


def check_stale_paths(root, files):
    out = []
    for rel in text_files(root, files):
        for i, line in enumerate(rd(root, rel).split("\n"), 1):
            if IGNORE_MARK in line or "://" not in line and "/" not in line:
                continue
            for m in PATH_RE.finditer(line):
                prefix, rest = m.group(1), m.group(2)
                end = m.end()
                nxt = line[end:end + 1]
                rest = rest.rstrip(".,:;")
                if nxt in ("%", "*", "<", "{", "$", "[", "?") or "*" in rest or "..." in rest:
                    continue
                ref = rest if prefix == "res://" else prefix + rest
                if prefix == "res://" and not ref:
                    continue
                if prefix != "res://":
                    if not (ref.endswith("/") or ref.endswith(STALE_EXTS)):
                        continue
                    if ref.rstrip("/") in STALE_TOP:
                        continue
                if ref.startswith(STALE_GENERATED):
                    continue
                if not os.path.exists(os.path.join(root, ref.rstrip("/"))):
                    shown = ("res://" + ref) if prefix == "res://" else ref
                    out.append((rel, i, "stale-path", "names missing path %s" % shown, "%s: %s" % (rel, shown)))
    return out


# ---- legacy markers -----------------------------------------------------

def check_legacy(root, files, today):
    out = []
    for rel in sorted(files):
        if not rel.endswith(".gd") or not game_candidate(rel):
            continue
        for i, line in enumerate(rd(root, rel).split("\n"), 1):
            m = LEGACY_RE.search(line)
            if not m:
                continue
            e = EXPIRY_RE.search(line)
            if e is None:
                out.append((rel, i, "undated-legacy", "'%s' without (expires YYYY-MM-DD)" % m.group(1),
                            "%s: %s" % (rel, line.strip())))
            elif e.group(1) < today:
                out.append((rel, i, "undated-legacy", "'%s' expired %s" % (m.group(1), e.group(1)),
                            "%s: %s" % (rel, line.strip())))
    return out


# ---- driver -------------------------------------------------------------

def collect(root, today):
    """All findings: (path, line, id, message, key)."""
    g = dep_graph.build_graph(root)
    lines = Lines(root)
    reached = reachable_files(g, lines)
    out = []
    for p, n, cid, msg in check_dead_files(g, reached):
        out.append((p, n, cid, msg, p))
    out += check_funcs(g, reached)
    out += check_stale_paths(root, g["files"])
    out += check_legacy(root, g["files"], today)
    return out


def load_baseline(root):
    path = os.path.join(root, "tools", BASELINE_NAME)
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    return {c: list(data.get("checks", {}).get(c, [])) for c in CHECKS}, list(data.get("allow", []))


def classify(findings, baseline, allow):
    """(new findings, baselined count, stale baseline entries (id, entry), stale allow entries)."""
    base = {c: set(v) for c, v in baseline.items()}
    allowed = set((a.get("id"), a.get("entry")) for a in allow)
    new, seen_base, seen_allow = [], set(), set()
    for f in findings:
        cid, key = f[2], f[4]
        if (cid, key) in allowed:
            seen_allow.add((cid, key))
        elif key in base.get(cid, ()):
            seen_base.add((cid, key))
        else:
            new.append(f)
    stale = sorted((c, k) for c, ks in base.items() for k in ks if (c, k) not in seen_base)
    stale_allow = sorted(a for a in allowed if a not in seen_allow)
    return new, len(seen_base), stale, stale_allow


def write_baseline(root, findings, allow):
    keep = {}
    grouped = {c: sorted(set(f[4] for f in findings if f[2] == c)) for c in CHECKS}
    allowed_now = set((f[2], f[4]) for f in findings)
    for a in allow:
        if (a.get("id"), a.get("entry")) in allowed_now:
            keep[(a["id"], a["entry"])] = a
    for (cid, key) in keep:
        grouped[cid] = [k for k in grouped[cid] if k != key]
    data = {"checks": grouped, "allow": sorted(keep.values(), key=lambda a: (a["id"], a["entry"]))}
    with open(os.path.join(root, "tools", BASELINE_NAME), "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=1)
        fh.write("\n")


def print_report(findings):
    for cid in CHECKS:
        sub = [f for f in findings if f[2] == cid]
        by = collections.Counter((f[0].split("/")[0] if "/" in f[0] else ".") for f in sub)
        print("%-15s %5d  %s" % (cid, len(sub), ", ".join("%s=%d" % kv for kv in by.most_common())))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(TOOLS))
    ap.add_argument("--report", action="store_true", help="print counts per check and folder")
    ap.add_argument("--update-baseline", action="store_true")
    ap.add_argument("--today", default=datetime.date.today().isoformat())
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path).replace("\\", "/")
    findings = collect(root, args.today)
    baseline, allow = load_baseline(root)
    if args.update_baseline:
        write_baseline(root, findings, allow)
        print("lint_dead: baseline rewritten (%d findings)" % len(findings))
        return 0
    if args.report:
        print_report(findings)
    new, n_base, stale, stale_allow = classify(findings, baseline, allow)
    for f in new:
        print("%s:%d: %s: %s" % (f[0], f[1], f[2], f[3]))
    for cid, key in stale:
        print("stale baseline entry (no longer found, run --update-baseline): %s %s" % (cid, key))
    for cid, key in stale_allow:
        print("stale allow entry (no longer found, delete it): %s %s" % (cid, key))
    if new:
        print("LINT DEAD RED: %d new finding(s) (%d baselined, %d stale)" % (len(new), n_base, len(stale) + len(stale_allow)))
        return 1
    print("LINT DEAD GREEN: %d baselined, %d stale" % (n_base, len(stale) + len(stale_allow)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
