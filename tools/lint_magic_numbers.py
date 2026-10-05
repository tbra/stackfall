"""Magic-number ratchet (Bontago-fca.35).

CLAUDE.md requires tunables to live in config/ Resources. This counts numeric
literals other than 0, 1, -1, 2, 0.5 (and float spellings) per game .gd file,
ignoring comments, string literals, and const/enum/@export lines, and compares
against tools/magic_number_baseline.json. A file may never exceed its baseline
and a file absent from the baseline must have zero.

  python tools/lint_magic_numbers.py [--path <checkout>]   # check; exit 1 on growth
  python tools/lint_magic_numbers.py --update              # lower baselines only
  python tools/lint_magic_numbers.py --update --allow-new <path relative to repo>
"""

import argparse
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE_NAME = "magic_number_baseline.json"
SKIP_DIRS = {".godot", "addons", ".git", "build", "feedback", ".claude", "tests", "tools", "source_art", "config"}
ALLOWED = {"0", "1", "-1", "2", "0.0", "1.0", "-1.0", "0.5", "2.0"}
NUM_RE = re.compile(r"(?<![\w.#])-?(\d+\.\d+|\d+)(?![\w.])")
SKIP_LINE_RE = re.compile(r"\s*(const|enum|@export)")


def strip_line(line):
    """Drop string literals and the trailing comment from one line."""
    out = []
    quote = ""
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\":
                i += 1
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
        elif c == "#":
            break
        else:
            out.append(c)
        i += 1
    return "".join(out)


def count_text(text):
    total = 0
    for line in text.splitlines():
        s = strip_line(line)
        if SKIP_LINE_RE.match(s):
            continue
        total += sum(1 for m in NUM_RE.finditer(s) if m.group(0) not in ALLOWED)
    return total


def scan(path):
    counts = {}
    for d, dirs, files in os.walk(path):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            if not f.endswith(".gd"):
                continue
            full = os.path.join(d, f)
            rel = os.path.relpath(full, path).replace(os.sep, "/")
            with open(full, encoding="utf-8", errors="ignore") as fh:
                n = count_text(fh.read())
            if n:
                counts[rel] = n
    return counts


def load_baseline(file):
    try:
        with open(file, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def check(counts, baseline):
    """Return one message per offending file."""
    problems = []
    for rel, n in sorted(counts.items()):
        base = baseline.get(rel)
        if base is None:
            problems.append("%s: %d literals, new file (baseline 0)" % (rel, n))
        elif n > base:
            problems.append("%s: %d literals > baseline %d" % (rel, n, base))
    return problems


def updated(counts, baseline, allow_new):
    """Baseline lowered to current counts; new files only when allowed."""
    new = {}
    for rel, n in counts.items():
        if rel in baseline:
            new[rel] = min(n, baseline[rel])
        elif rel in allow_new:
            new[rel] = n
    return dict(sorted(new.items()))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=ROOT)
    ap.add_argument("--baseline", default="")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--allow-new", action="append", default=[])
    args = ap.parse_args(argv)
    path = os.path.abspath(args.path)
    bfile = args.baseline or os.path.join(path, "tools", BASELINE_NAME)
    counts = scan(path)
    baseline = load_baseline(bfile)
    if args.update:
        # No baseline file yet: seed it from the current scan.
        new = updated(counts, baseline, set(args.allow_new)) if baseline else counts
        with open(bfile, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(new, fh, indent=1, sort_keys=True)
            fh.write("\n")
        print("MAGIC LINT baseline written: %d files, %d literals" % (len(new), sum(new.values())))
        return 0
    problems = check(counts, baseline)
    for p in problems:
        print("MAGIC LINT FAIL " + p)
    if problems:
        print("MAGIC LINT RED: %d file(s); move values to config/ Resources" % len(problems))
        return 1
    print("MAGIC LINT GREEN: %d files, %d literals (baseline %d)" % (
        len(counts), sum(counts.values()), sum(baseline.values())))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
