"""Session metrics: the numbers a session-close debrief starts from, instead of memory.

Usage: python tools/session_metrics.py --since <rev> [--path <checkout>] [--since-time ISO]
       [--scratch DIR] [--mutate] [--json]

<rev> is the main revision the session started from (the handoff names it). Everything is
read from Git, the scratch logs and Beads; nothing is written. Sections:

  delivery   non-merge commits and lines added/removed per area (game, tests, tools,
             instructions, docs, other) between <rev> and HEAD.
  guards     entries added to tools/*baseline*.json, tools/flag_dead_allow.json and
             tools/probe_allowlist.txt (new list entries, raised counts, new allow entries).
             With shrink-only baselines this should be 0; every entry is listed. Layer closure
             entries for files that did not exist at <rev> are planned --allow-new additions, and
             entries that only follow a file Git detects as renamed since <rev> are moves; both
             are counted on their own lines instead.
  tests      test count at <rev> and HEAD (`func test_` in tests/), the last gate's summed
             script seconds, and SHORTCUT markers added.
  gates      FULL GATE GREEN/RED lines in scratch logs written since the session started,
             with the failing scripts of each RED.
  handbacks  worker handback attempts logged by validate_worker_handback.py since the start:
             first-try denials, verdicts, reviewer APPROVE/CHANGES.
  beads      issues created/closed since the start (bugs separately) and open/closed
             `debrief` Beads.
  process    commits that changed agent instructions or tooling (CLAUDE.md, .claude/,
             non-test tools/), for the close report's list of process changes.
  mutation   core/ scripts changed; with --mutate, tools/mutate_core.py runs on each
             (10 mutations) and its MUTATION line is reported.
"""
import argparse
import datetime
import glob
import json
import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import repo_paths  # noqa: E402

GAME_DIRS = ("core/", "game/", "net/", "autoload/", "ui/", "config/", "shaders/", "assets/")
INSTRUCTION_PATHS = ("CLAUDE.md", ".claude/")
GUARD_FILES = ("tools/flag_dead_allow.json", "tools/probe_allowlist.txt")
LAYER_BASELINE = "tools/layer_baseline.json"
CLOSURE_KEYS = ("closure|", "main_closure|")
GATE_RE = re.compile(r"FULL GATE (GREEN|RED): (\d+)/(\d+) passing.*?failing=(\S+)")
LOG_EXTS = (".log", ".txt")
LIST_CAP = 25
MUTATE_CAP = 10
MUTATE_TIMEOUT_S = 1800


def git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                          encoding="utf-8", errors="replace").stdout


def area(path):
    if path.startswith("tests/"):
        return "tests"
    if path.startswith("tools/"):
        return "tools"
    if path.startswith(INSTRUCTION_PATHS):
        return "instructions"
    if path.startswith("docs/"):
        return "docs"
    if path.startswith(GAME_DIRS):
        return "game"
    return "other"


def delivery(repo, rev):
    commits = [ln for ln in git(repo, "log", "--no-merges", "--format=%h", rev + "..HEAD").splitlines() if ln]
    lines = {}
    for row in git(repo, "diff", "--numstat", rev, "HEAD").splitlines():
        parts = row.split("\t")
        if len(parts) != 3 or parts[0] == "-":
            continue
        add, rem = lines.get(area(parts[2]), (0, 0))
        lines[area(parts[2])] = (add + int(parts[0]), rem + int(parts[1]))
    return {"commits": len(commits), "lines": lines}


def _entries(text, path):
    """Comparable entries of one guard file: list items, numeric values and allow entries."""
    if path.endswith(".txt"):
        return {ln.strip(): 1 for ln in text.splitlines() if ln.strip() and not ln.startswith("#")}
    try:
        data = json.loads(text) if text.strip() else {}
    except ValueError:
        return {}
    out = {}

    def walk(node, prefix):
        if isinstance(node, dict):
            if "entry" in node and "id" in node:
                out["allow|%s|%s" % (node["id"], node["entry"])] = 1
                return
            for key, value in node.items():
                walk(value, prefix + key + "|")
        elif isinstance(node, list):
            for item in node:
                if isinstance(item, (dict, list)):
                    walk(item, prefix)
                else:
                    out[prefix + str(item)] = 1
        elif isinstance(node, (int, float)) and not isinstance(node, bool):
            out[prefix.rstrip("|")] = node
    walk(data, "")
    return out


def _new_file_closure(repo, rev, path, key):
    """A layer closure entry for a file that did not exist at `rev`: a planned --allow-new, not a guard."""
    if path != LAYER_BASELINE or not key.startswith(CLOSURE_KEYS):
        return False
    target = key.split("|", 1)[1]
    return subprocess.run(["git", "-C", repo, "cat-file", "-e", "%s:%s" % (rev, target)],
                          capture_output=True).returncode != 0


def _renames(repo, rev):
    """(old path, new path) pairs Git detects as renamed between `rev` and the working tree."""
    out = git(repo, "diff", "-M", "--name-status", "--diff-filter=R", rev, "--")
    return [tuple(parts[1:3]) for parts in (ln.split("	") for ln in out.splitlines()) if len(parts) == 3]


def _moved_from(key, before, renames):
    """The `before` key this entry had under a renamed file's old path, or None."""
    for old, new in renames:
        if new in key and key.replace(new, old) in before:
            return key.replace(new, old)
    return None


def guards(repo, rev):
    """(added guard entries, layer closure entries for files new since `rev`, entries moved with a renamed file)."""
    files = sorted(set(glob.glob(os.path.join(repo, "tools", "*baseline*.json"))))
    paths = [os.path.relpath(f, repo).replace("\\", "/") for f in files] + list(GUARD_FILES)
    renames = _renames(repo, rev)
    added = []
    new_closures = []
    moved = []
    for path in paths:
        before = _entries(git(repo, "show", "%s:%s" % (rev, path)), path)
        full = os.path.join(repo, path)
        if not os.path.isfile(full):
            continue
        with open(full, encoding="utf-8", errors="replace") as fh:
            after = _entries(fh.read(), path)
        for key, value in sorted(after.items()):
            old_key = key if key in before else _moved_from(key, before, renames)
            if old_key is None:
                bucket = new_closures if _new_file_closure(repo, rev, path, key) else added
                bucket.append("%s: +%s" % (path, key))
            elif value > before[old_key]:
                added.append("%s: %s %s -> %s" % (path, key, before[old_key], value))
            elif old_key != key:
                moved.append("%s: %s (was %s)" % (path, key, old_key))
    return added, new_closures, moved


def test_count(repo, rev=None):
    args = ["grep", "-c", "^func test_"] + ([rev] if rev else []) + ["--", "tests/"]
    total = 0
    for row in git(repo, *args).splitlines():
        try:
            total += int(row.rsplit(":", 1)[1])
        except (IndexError, ValueError):
            pass
    return total


def suite_seconds(repo):
    try:
        with open(os.path.join(repo, "tests", ".gut_targeted", "gate_timings.json"), encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    values = data.values() if isinstance(data, dict) else []
    return round(sum(v for v in values if isinstance(v, (int, float))), 1)


def shortcuts_added(repo, rev):
    try:
        import lint_shortcuts
        return ["%s:%d: %s" % m for m in lint_shortcuts.added_markers(repo, rev)]
    except (ImportError, subprocess.CalledProcessError):
        return []


def gates(scratch, since):
    found = []
    stamp = since.timestamp()
    for dirpath, _dirs, names in os.walk(scratch):
        for name in names:
            if not name.endswith(LOG_EXTS):
                continue
            path = os.path.join(dirpath, name)
            try:
                if os.path.getmtime(path) < stamp:
                    continue
                with open(path, encoding="utf-8", errors="replace") as fh:
                    text = fh.read()
            except OSError:
                continue
            for m in GATE_RE.finditer(text):
                found.append((m.group(1), "%s/%s" % (m.group(2), m.group(3)), m.group(4), path))
    seen, out = set(), []
    for verdict, totals, failing, path in found:
        key = (verdict, totals, failing, os.path.basename(os.path.dirname(path)))
        if key not in seen:
            seen.add(key)
            out.append({"verdict": verdict, "totals": totals, "failing": failing, "log": path.replace("\\", "/")})
    return out


def handbacks(log_path, since, bead=None, skip_verdict=None):
    rows = []
    try:
        with open(log_path, encoding="utf-8") as fh:
            for line in fh:
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                if row.get("ts", "") >= since.isoformat(timespec="seconds") and (
                        bead is None or bead in row.get("bead", "")) and row.get("verdict") != skip_verdict:
                    rows.append(row)
    except OSError:
        return {"attempts": 0}
    accepted = [r for r in rows if r.get("accepted")]
    verdicts = {}
    for r in accepted:
        verdicts[r.get("verdict", "")] = verdicts.get(r.get("verdict", ""), 0) + 1
    reviews = [r for r in accepted if r.get("verdict") == "review"]
    return {"attempts": len(rows), "denied": len(rows) - len(accepted), "verdicts": verdicts,
            "review_approve": sum(1 for r in reviews if r.get("finding", "").upper().startswith("APPROVE")),
            "review_changes": sum(1 for r in reviews if r.get("finding", "").upper().startswith("CHANGES"))}


def beads(repo, since):
    try:
        from bd_cli import bd_executable
        bd = bd_executable()
    except ImportError:
        bd = "bd"
    day = since.date().isoformat()

    def listing(*args):
        try:
            out = subprocess.run([bd, "list", "--all", "--json", "--brief", "--limit", "0"] + list(args),
                                 capture_output=True, text=True, encoding="utf-8", errors="replace", cwd=repo).stdout
            return json.loads(out) if out.strip() else []
        except (OSError, ValueError):
            return None
    created, closed, debrief = listing("--created-after", day), listing("--closed-after", day), listing("--label", "debrief")
    if created is None or closed is None or debrief is None:
        return {"error": "bd unavailable"}
    return {"created": len(created), "created_bugs": sum(1 for i in created if i.get("issue_type") == "bug"),
            "closed": len(closed),
            "debrief_open": sum(1 for i in debrief if i.get("status") != "closed"),
            "debrief_closed": sum(1 for i in debrief if i.get("status") == "closed")}


def process_changes(repo, rev):
    text = git(repo, "log", "--no-merges", "--format=@@%h %s", "--name-only", rev + "..HEAD", "--",
               "CLAUDE.md", ".claude", "tools", ":(exclude)tools/test_*")
    out, current = [], None
    for line in text.splitlines():
        if line.startswith("@@"):
            current = {"commit": line[2:], "files": []}
            out.append(current)
        elif line.strip() and current is not None:
            current["files"].append(line.strip())
    return out


def changed_core(repo, rev):
    return [p for p in git(repo, "diff", "--name-only", rev, "HEAD", "--", "core").splitlines()
            if p.endswith(".gd") and os.path.isfile(os.path.join(repo, p))]


def mutate(repo, scripts):
    results = {}
    for script in scripts:
        try:
            out = subprocess.run([sys.executable, os.path.join(TOOLS, "mutate_core.py"), script, "--path", repo,
                                  "--max-mutations", str(MUTATE_CAP)], capture_output=True, text=True,
                                 encoding="utf-8", errors="replace", timeout=MUTATE_TIMEOUT_S).stdout
        except subprocess.TimeoutExpired:
            results[script] = "timeout"
            continue
        lines = [ln for ln in out.splitlines() if ln.startswith(("MUTATION", "UNTESTED", "BASELINE RED"))]
        results[script] = "; ".join(lines) or "no result"
    return results


def collect(repo, rev, since, scratch, run_mutation):
    core = changed_core(repo, rev)
    added_guards, new_closures, moved = guards(repo, rev)
    return {
        "since": rev, "since_time": since.isoformat(timespec="seconds"), "head": git(repo, "rev-parse", "--short", "HEAD").strip(),
        "delivery": delivery(repo, rev),
        "guards_added": added_guards,
        "new_file_closures": new_closures,
        "moved_entries": moved,
        "tests": {"before": test_count(repo, rev), "after": test_count(repo), "suite_seconds": suite_seconds(repo),
                  "shortcuts_added": shortcuts_added(repo, rev)},
        "gates": gates(scratch, since),
        "handbacks": handbacks(os.environ.get("STACKFALL_HANDBACK_LOG")
                               or os.path.join(scratch, "_orchestrator", "handbacks.jsonl"), since),
        "beads": beads(repo, since),
        "process_changes": process_changes(repo, rev),
        "core_changed": core,
        "mutation": mutate(repo, core) if run_mutation else {},
    }


def render(m):
    d = m["delivery"]
    lines = ["SESSION METRICS %s..%s (since %s)" % (m["since"], m["head"], m["since_time"]),
             "delivery: %d commits; lines %s" % (d["commits"], ", ".join(
                 "%s +%d/-%d" % (k, a, r) for k, (a, r) in sorted(d["lines"].items())) or "none")]
    g = m["guards_added"]
    lines.append("guards: %d entries added%s" % (len(g), "" if g else " (expected 0)"))
    lines += ["  " + e for e in g[:LIST_CAP]]
    lines.append("layer closures for new files (planned --allow-new, not guards): %d" % len(m.get("new_file_closures", [])))
    lines.append("entries moved with renamed files (not guards): %d" % len(m.get("moved_entries", [])))
    t = m["tests"]
    lines.append("tests: %d -> %d (%+d); last gate summed script seconds %s; SHORTCUT added %d" % (
        t["before"], t["after"], t["after"] - t["before"], t["suite_seconds"], len(t["shortcuts_added"])))
    lines += ["  " + s for s in t["shortcuts_added"][:LIST_CAP]]
    reds = [x for x in m["gates"] if x["verdict"] == "RED"]
    lines.append("gates: %d GREEN, %d RED" % (len(m["gates"]) - len(reds), len(reds)))
    lines += ["  RED %s failing=%s (%s)" % (x["totals"], x["failing"], x["log"]) for x in reds[:LIST_CAP]]
    h = m["handbacks"]
    lines.append("handbacks: %s" % ("none logged" if not h.get("attempts") else
                 "%d attempts, %d denied; verdicts %s; reviews APPROVE %d / CHANGES %d" % (
                     h["attempts"], h["denied"], h["verdicts"], h["review_approve"], h["review_changes"])))
    b = m["beads"]
    lines.append("beads: %s" % (b.get("error") or "%d created (%d bugs), %d closed; debrief beads %d open / %d closed" % (
        b["created"], b["created_bugs"], b["closed"], b["debrief_open"], b["debrief_closed"])))
    lines.append("process changes: %d commits" % len(m["process_changes"]))
    lines += ["  %s [%s]" % (c["commit"], ", ".join(c["files"][:6])) for c in m["process_changes"][:LIST_CAP]]
    lines.append("core changed: %s" % (", ".join(m["core_changed"]) or "none"))
    lines += ["  %s: %s" % (k, v) for k, v in m["mutation"].items()]
    return "\n".join(lines)


def parse_since(stamp):
    """ISO time to an aware local datetime; accepts the trailing Z that Python 3.8 fromisoformat rejects."""
    if stamp.endswith("Z"):
        stamp = stamp[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(stamp).astimezone()


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", required=True, help="main revision the session started from")
    ap.add_argument("--path", default=os.path.dirname(TOOLS))
    ap.add_argument("--since-time", default="", help="ISO start time (default: the --since commit time)")
    ap.add_argument("--scratch", default="", help="scratch root (default: repo_paths.scratch_root())")
    ap.add_argument("--mutate", action="store_true", help="run mutate_core.py on changed core/ scripts")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    repo = os.path.abspath(args.path)
    stamp = args.since_time or git(repo, "show", "-s", "--format=%cI", args.since).strip()
    try:
        since = parse_since(stamp)
    except ValueError:
        print("session_metrics: cannot resolve the start time of %s" % args.since, file=sys.stderr)
        return 2
    metrics = collect(repo, args.since, since, args.scratch or repo_paths.scratch_root(), args.mutate)
    print(json.dumps(metrics, indent=1) if args.json else render(metrics))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
