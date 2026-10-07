"""List the tests that reference identifiers your change touched (Bontago-fca.45).

Usage: python tools/affected_tests.py [--path <checkout>] [--base <rev>] [--json]

Workers kept missing tests in other packages that asserted values they changed. This diffs the
checkout against --base (default: `git merge-base HEAD main`, working-tree and untracked files
included), collects changed identifiers (GDScript func/var/const/signal/enum/class_name names,
.tres/.tscn property keys and node names, quoted ids such as &"rocket" or "bomb", and changed
script/resource basenames), drops noise (under 4 chars, common GDScript words), and searches
tests/**/*.gd for whole-word references. Tests that are part of the diff are listed and marked
[changed]. Prints a compact list, a totals line and a ready-to-run tools/run_gut.ps1 line.
Exit 0 unless git fails.
"""
import argparse
import json
import os
import re
import subprocess
import sys

GIT_TIMEOUT_S = 120
MIN_LEN = 4
MAX_NAMES_PER_LINE = 8
DEFAULT_MAX_FANOUT = 12
MAX_UNTRACKED_BYTES = 200000
STOPWORDS = frozenset("""
self true false null func var const extends return void bool int float string String Array
Dictionary Vector2 Vector3 Vector2i Vector3i Color Node Node3D Resource Object Callable Signal
StringName NodePath class_name class signal enum static export onready else elif while break
continue pass match await super preload load tool PI TAU INF NAN name type size text path
value values data none null_ with from this that then when have each only into
active high look mode enabled disabled default count index time position rotation scale color
strength visibility level label ready init update process result
_ready _process _physics_process _input _unhandled_input _unhandled_key_input _init _enter_tree
_exit_tree _notification _draw _to_string _get _set _get_property_list
Script script tree Main main current headless live Stackfall status boot test before_each
after_each before_all after_all assert_eq assert_true assert_false assert_not_null
get_tree get_node add_child queue_free emit connect
""".split())

GD_DECL = re.compile(
    r"^\s*(?:@\w+(?:\([^)]*\))?\s+)*(?:static\s+)?(?:func|var|const|signal|enum|class_name|class)\s+(\w+)")
GD_ENUM_BODY = re.compile(r"\benum\b[^{]*\{([^}]*)\}")
TRES_KEY = re.compile(r"^\s*([A-Za-z_][\w/]*)\s*=")
TRES_NAME = re.compile(r'\bname="([^"]+)"')
QUOTED = re.compile(r'&?"([A-Za-z_]\w*)"')
WORD = re.compile(r"[A-Za-z_]\w*")


def _git(repo, *a):
    p = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=GIT_TIMEOUT_S)
    return p.returncode, p.stdout or "", p.stderr or ""


def _ok(repo, *a):
    code, out, err = _git(repo, *a)
    if code != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(a[:2]), err.strip()[:200]))
    return out


def default_base(repo):
    code, out, _ = _git(repo, "merge-base", "HEAD", "main")
    return out.strip() if code == 0 and out.strip() else "HEAD"


def keep(name):
    return len(name) >= MIN_LEN and name not in STOPWORDS


def line_identifiers(path, line):
    """Identifiers declared or quoted on one changed line of `path`."""
    ids = set()
    ext = os.path.splitext(path)[1]
    if ext == ".gd":
        m = GD_DECL.match(line)
        if m:
            ids.add(m.group(1))
        for body in GD_ENUM_BODY.findall(line):
            ids.update(WORD.findall(body))
    elif ext in (".tres", ".tscn"):
        m = TRES_KEY.match(line)
        if m:
            ids.add(m.group(1).split("/")[-1])
            ids.add(m.group(1))
        ids.update(TRES_NAME.findall(line))
    else:
        return ids
    ids.update(QUOTED.findall(line))
    return ids


def changed_lines(repo, base):
    """({path: [changed lines]}, set of changed paths). Includes working tree and untracked files."""
    names = set(_ok(repo, "diff", "--name-only", base).splitlines())
    lines = {}
    cur = None
    for raw in _ok(repo, "diff", "-U0", "--no-color", base).splitlines():
        if raw.startswith("+++ "):
            cur = raw[6:] if raw.startswith("+++ b/") else None
        elif raw.startswith("--- "):
            continue
        elif cur and raw[:1] in "+-":
            lines.setdefault(cur, []).append(raw[1:])
    for rel in _ok(repo, "ls-files", "--others", "--exclude-standard").splitlines():
        names.add(rel)
        full = os.path.join(repo, rel)
        try:
            if os.path.getsize(full) <= MAX_UNTRACKED_BYTES and not rel.endswith((".png", ".import")):
                with open(full, encoding="utf-8", errors="replace") as fh:
                    lines[rel] = fh.read().splitlines()
        except OSError:
            pass
    return lines, {n for n in names if n}


def collect_identifiers(lines, paths):
    """{identifier: source description}. Test files in the diff are skipped as a source."""
    ids = {}
    for path, body in lines.items():
        if path.startswith("tests/"):
            continue
        for line in body:
            for name in line_identifiers(path, line):
                if keep(name):
                    ids.setdefault(name, path)
    for path in paths:
        if os.path.splitext(path)[1] in (".gd", ".tres", ".tscn", ".gdshader") and not path.startswith("tests/"):
            stem = os.path.splitext(os.path.basename(path))[0]
            if keep(stem):
                ids.setdefault(stem, path)
    return ids


def find_tests(repo, ids, changed_paths):
    """[{file, changed, names}] for tests/**/*.gd that reference any identifier as a whole word."""
    pattern = None if not ids else re.compile(r"\b(?:%s)\b" % "|".join(
        re.escape(n) for n in sorted(ids, key=len, reverse=True)))
    out = []
    root = os.path.join(repo, "tests")
    for dirpath, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            try:
                with open(full, encoding="utf-8", errors="replace") as fh:
                    found = sorted(set(pattern.findall(fh.read()))) if pattern else []
            except OSError:
                continue
            rel = os.path.relpath(full, repo).replace("\\", "/")
            if found or rel in changed_paths:
                rel = os.path.relpath(full, repo).replace("\\", "/")
                out.append({"file": rel, "changed": rel in changed_paths, "names": found})
    out.sort(key=lambda r: r["file"])
    return out


def apply_fanout(results, max_fanout):
    """Drop identifiers referenced by more than max_fanout tests. Returns (results, broad {name: n}).
    Changed tests are always kept; other tests survive only through a non-broad identifier."""
    counts = {}
    for r in results:
        for n in r["names"]:
            counts[n] = counts.get(n, 0) + 1
    broad = {n: c for n, c in counts.items() if c > max_fanout}
    out = []
    for r in results:
        names = [n for n in r["names"] if n not in broad]
        if names or r["changed"]:
            out.append({"file": r["file"], "changed": r["changed"], "names": names})
    return out, broad


def analyse(repo, base=None, max_fanout=DEFAULT_MAX_FANOUT):
    base = base or default_base(repo)
    lines, paths = changed_lines(repo, base)
    ids = collect_identifiers(lines, paths)
    results, broad = apply_fanout(find_tests(repo, ids, paths), max_fanout)
    return base, ids, results, broad


def gut_line(results, path_arg):
    scripts = sorted({os.path.splitext(os.path.basename(r["file"]))[0]
                      for r in results if os.path.basename(r["file"]).startswith("test_")})
    if not scripts:
        return ""
    line = "powershell -NoProfile -File tools/run_gut.ps1 " + ",".join(scripts)
    if path_arg:
        line += " -Path " + path_arg
    return line


def format_text(base, ids, results, path_arg, broad=None):
    out = []
    for r in results:
        names = r["names"]
        shown = ", ".join(names[:MAX_NAMES_PER_LINE])
        if len(names) > MAX_NAMES_PER_LINE:
            shown += ", +%d" % (len(names) - MAX_NAMES_PER_LINE)
        out.append("%s%s: %s" % (r["file"], " [changed]" if r["changed"] else "", shown))
    for n, c in sorted((broad or {}).items()):
        out.append("BROAD %s (%d tests)" % (n, c))
    out.append("AFFECTED base=%s identifiers=%d tests=%d" % (base[:10], len(ids), len(results)))
    run = gut_line(results, path_arg)
    if run:
        out.append(run)
    return "\n".join(out)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=None, help="checkout (default: current directory)")
    ap.add_argument("--base", default=None, help="base revision (default: merge-base HEAD main)")
    ap.add_argument("--max-fanout", type=int, default=DEFAULT_MAX_FANOUT,
                    help="identifiers referenced by more tests than this are reported as BROAD, not expanded")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    repo = os.path.abspath(args.path or ".").replace("\\", "/")
    try:
        base, ids, results, broad = analyse(repo, args.base, args.max_fanout)
    except (RuntimeError, subprocess.SubprocessError) as e:
        print("affected_tests: %s" % e, file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps({"base": base, "identifiers": sorted(ids), "tests": results, "broad": broad,
                          "run": gut_line(results, args.path and repo)}, indent=1))
    else:
        print(format_text(base, ids, results, args.path and repo, broad))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
