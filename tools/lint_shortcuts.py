"""Shortcut ledger: every deliberate shortcut names its limit and when to upgrade it.

Usage: python tools/lint_shortcuts.py [--path <checkout>] [--list] [--added <rev>]

Finds SHORTCUT comments (`#` or `//` followed by `SHORTCUT:`) in .gd, .gdshader, .gdshaderinc and tools .py
files outside addons/, tests/ and scratch folders. The format is CLAUDE.md's: the limit, a comma, then the
upgrade trigger. A marker with no text after a comma is a `no-trigger` finding and fails the run (exit 1),
because a deferral without a trigger silently becomes permanent.
`--list` prints the ledger, one `path:line: text` row per marker.
`--added <rev>` prints only the markers added since <rev> (`git diff <rev>`), for filing follow-up Beads.
Prints one `LINT SHORTCUTS GREEN|RED` line.
"""
import argparse
import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
EXTS = (".gd", ".gdshader", ".gdshaderinc", ".py")
SKIP_DIRS = (".godot", ".git", ".claude", "addons", "tests", "scratch", "node_modules", "__pycache__",
             "worktrees", "source_art")
MARKER_RE = re.compile(r"(?:#|//)\s*SHORTCUT:\s*(.*)$")
TRIGGER_RE = re.compile(r",\s*\S")


def skipped(rel):
    parts = rel.split("/")
    name = parts[-1]
    return any(p in SKIP_DIRS for p in parts[:-1]) or (name.startswith("test_") and name.endswith(".py"))


def walk(root):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            rel = os.path.relpath(os.path.join(dirpath, name), root).replace("\\", "/")
            if name.endswith(EXTS) and not skipped(rel):
                yield rel


def markers(root):
    """[(rel, line_no, text)] for every SHORTCUT marker under `root`."""
    out = []
    for rel in sorted(walk(root)):
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as handle:
            for number, line in enumerate(handle, 1):
                m = MARKER_RE.search(line)
                if m:
                    out.append((rel, number, m.group(1).strip()))
    return out


def added_markers(root, rev):
    """[(rel, line_no, text)] for SHORTCUT markers on lines added since `rev`."""
    diff = subprocess.run(["git", "-C", root, "diff", "-U0", rev, "--"], capture_output=True, text=True,
                          encoding="utf-8", errors="replace", check=True).stdout
    out, rel, number = [], None, 0
    for line in diff.splitlines():
        if line.startswith("+++ "):
            rel = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            number = int(re.search(r"\+(\d+)", line).group(1))
        elif line.startswith("+") and rel:
            m = MARKER_RE.search(line)
            if m and rel.endswith(EXTS) and not skipped(rel):
                out.append((rel, number, m.group(1).strip()))
            number += 1
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=None, help="checkout (default: the checkout holding this script)")
    ap.add_argument("--list", action="store_true", help="print every marker")
    ap.add_argument("--added", metavar="REV", help="print only markers added since REV")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path or os.path.dirname(TOOLS))
    found = added_markers(root, args.added) if args.added else markers(root)
    bad = [m for m in found if not TRIGGER_RE.search(m[2])]
    for rel, number, text in found:
        if args.list or args.added or (rel, number, text) in bad:
            tag = "" if TRIGGER_RE.search(text) else " [no-trigger]"
            print("%s:%d: %s%s" % (rel, number, text, tag))
    state = "RED" if bad else "GREEN"
    print("LINT SHORTCUTS %s: %d markers, %d with no trigger" % (state, len(found), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
