"""UI component ratchet (Bontago-1pi.159.6; plan: docs/UI_COMPONENTS_PLAN.md section 5).

Screens must build their controls from ui/components/ (Ui* nodes) instead of raw Godot
controls restyled per screen. This lint counts matching lines per (rule, file) in ui/** and
compares with tools/ui_components_baseline.json ({rule: {file: count}}). A file may never
exceed its baseline for a rule and a file absent from a rule's baseline must have zero.
Each migration lowers (then deletes) its baseline entries; zero is the end state.

Rules: R1 raw CheckButton/CheckBox/SpinBox/TabBar/TabContainer/HSlider/OptionButton (.gd
code and .tscn node types); R2 add_theme_*_override; R3 MenuStyleFactory.apply_toggle_chip /
apply_pill / apply_flat_stepper_button / make_well_pill / make_badge; R4 Button.new().
Exempt: ui/components/, ui/theme/, and the dev tools NetDebugOverlay*, TuningPanel*, Perf*,
Physics*, Sandbox*.

  python tools/lint_ui_components.py [--path <checkout>]   # check; exit 1 on growth
  python tools/lint_ui_components.py --list [--rule ID]    # every violation with line numbers
  python tools/lint_ui_components.py --update              # lower baselines only
  python tools/lint_ui_components.py --update --allow-new <RULE:path | path>

Prints UI COMPONENT LINT GREEN|RED as its last line.
"""

import argparse
import json
import os
import re
import sys
from collections import namedtuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lint_magic_numbers import strip_line  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE_NAME = "ui_components_baseline.json"
SCOPE = "ui/"
EXEMPT_PREFIXES = ("ui/components/", "ui/theme/", "ui/NetDebugOverlay", "ui/TuningPanel",
                   "ui/Perf", "ui/Physics", "ui/Sandbox")
SKIP_DIRS = {".godot", "addons", ".git", "build", "feedback", ".claude", "tests", "tools", "source_art"}

RAW = r"(?:CheckButton|CheckBox|SpinBox|TabBar|TabContainer|HSlider|OptionButton)"
# gd: code pattern (strings/comments blanked). tscn: pattern on the raw scene line.
Rule = namedtuple("Rule", "id gd tscn message")
RULES = [
    Rule("R1", r"\b" + RAW + r"\b", r"^\[node\b.*\btype=\"" + RAW + r"\"",
         "use a ui/components Ui* control (UiToggle, UiChipToggle, UiStepper, UiTabs, UiDropdown, UiSegmentMeter), not a raw control"),
    Rule("R2", r"\badd_theme_(?:color|font_size|constant|stylebox|font)_override\b", None,
         "style through a component / theme, not per-node theme overrides"),
    Rule("R3", r"\bMenuStyleFactory\s*\.\s*(?:apply_toggle_chip|apply_pill|apply_flat_stepper_button|make_well_pill|make_badge)\b",
         None, "use the Ui* component instead of the MenuStyleFactory helper"),
    Rule("R4", r"\bButton\.new\s*\(", None, "use UiBlockButton / UiIconButton, not Button.new()"),
]
RULE_IDS = [r.id for r in RULES]
_GD = {r.id: re.compile(r.gd) for r in RULES}
_TSCN = {r.id: re.compile(r.tscn) for r in RULES if r.tscn}


def in_scope(rel):
    return rel.startswith(SCOPE) and rel.endswith((".gd", ".tscn")) and not rel.startswith(EXEMPT_PREFIXES)


def violations_in(rel, text):
    """[(rule_id, line_number, source_line)] for one file's text."""
    out = []
    if not in_scope(rel):
        return out
    is_scene = rel.endswith(".tscn")
    for n, line in enumerate(text.splitlines(), 1):
        if is_scene:
            for rid, rx in _TSCN.items():
                if rx.search(line):
                    out.append((rid, n, line.strip()))
        else:
            code = strip_line(line)
            for rid, rx in _GD.items():
                if rx.search(code):
                    out.append((rid, n, line.strip()))
    return out


def walk(path):
    for d, dirs, files in os.walk(path):
        dirs[:] = sorted(x for x in dirs if x not in SKIP_DIRS)
        for f in sorted(files):
            if f.endswith((".gd", ".tscn")):
                full = os.path.join(d, f)
                yield os.path.relpath(full, path).replace(os.sep, "/"), full


def scan(path):
    """{rule_id: {file: [(line_number, source_line), ...]}}."""
    found = {}
    for rel, full in walk(path):
        if not in_scope(rel):
            continue
        with open(full, encoding="utf-8", errors="ignore") as fh:
            text = fh.read()
        for rid, n, src in violations_in(rel, text):
            found.setdefault(rid, {}).setdefault(rel, []).append((n, src))
    return found


def counts_of(found):
    return {rid: {f: len(v) for f, v in sorted(files.items())} for rid, files in sorted(found.items())}


def load_baseline(file):
    """None when the file is missing or unreadable (distinct from an empty baseline)."""
    try:
        with open(file, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def check(counts, baseline):
    """One message per (rule, file) that exceeds its baseline."""
    problems = []
    messages = {r.id: r.message for r in RULES}
    for rid, files in sorted(counts.items()):
        base_files = baseline.get(rid) or {}
        for rel, n in sorted(files.items()):
            base = base_files.get(rel)
            if base is None:
                problems.append("%s %s: %d line(s), new (baseline 0); %s" % (rid, rel, n, messages.get(rid, "")))
            elif n > base:
                problems.append("%s %s: %d line(s) > baseline %d; %s" % (rid, rel, n, base, messages.get(rid, "")))
    return problems


def parse_allow_new(items):
    """['RULE:path' | 'path'] -> set of (rule_id or None, path)."""
    out = set()
    for item in items:
        head, sep, tail = item.partition(":")
        if sep and head in RULE_IDS:
            out.add((head, tail))
        else:
            out.add((None, item))
    return out


def updated(counts, baseline, allow_new):
    """Baseline lowered to current counts; new (rule, file) pairs only when allowed."""
    new = {}
    for rid, files in counts.items():
        base_files = baseline.get(rid) or {}
        for rel, n in files.items():
            if rel in base_files:
                new.setdefault(rid, {})[rel] = min(n, base_files[rel])
            elif (rid, rel) in allow_new or (None, rel) in allow_new:
                new.setdefault(rid, {})[rel] = n
    return {rid: dict(sorted(files.items())) for rid, files in sorted(new.items())}


def total(counts):
    return sum(sum(files.values()) for files in counts.values())


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=ROOT)
    ap.add_argument("--baseline", default="")
    ap.add_argument("--update", action="store_true")
    ap.add_argument("--allow-new", action="append", default=[],
                    help="admit a new (rule, file): RULE:path or path (every rule)")
    ap.add_argument("--list", action="store_true", help="print every violation with line numbers")
    ap.add_argument("--rule", action="append", default=[], help="with --list: only these rule ids")
    args = ap.parse_args(argv)
    path = os.path.abspath(args.path)
    bfile = args.baseline or os.path.join(path, "tools", BASELINE_NAME)
    found = scan(path)
    if args.list:
        wanted = set(args.rule) or set(RULE_IDS)
        shown = 0
        for rid in RULE_IDS:
            if rid not in wanted:
                continue
            for rel, hits in sorted(found.get(rid, {}).items()):
                for n, src in hits:
                    print("%s %s:%d: %s" % (rid, rel, n, src))
                    shown += 1
        print("UI COMPONENT LIST: %d violation(s)" % shown)
        return 0
    counts = counts_of(found)
    baseline = load_baseline(bfile)
    if args.update:
        # No baseline yet: seed from the scan. An existing baseline only ever lowers.
        new = counts if baseline is None else updated(counts, baseline, parse_allow_new(args.allow_new))
        os.makedirs(os.path.dirname(bfile), exist_ok=True)
        with open(bfile, "w", encoding="utf-8", newline="\n") as fh:
            json.dump(new, fh, indent=1, sort_keys=True)
            fh.write("\n")
        print("UI COMPONENT LINT baseline written: %d rules, %d violations" % (len(new), total(new)))
        return 0
    baseline = baseline or {}
    problems = check(counts, baseline)
    for p in problems:
        print("UI COMPONENT LINT FAIL " + p)
    if problems:
        print("UI COMPONENT LINT RED: %d (rule, file) pair(s); build from ui/components (docs/UI_COMPONENTS_PLAN.md)"
              % len(problems))
        return 1
    stale = sum(1 for rid, files in baseline.items() for rel, b in files.items()
                if counts.get(rid, {}).get(rel, 0) < b)
    print("UI COMPONENT LINT GREEN: %d rules, %d violations (baseline %d)%s" % (
        len(RULES), total(counts), total(baseline),
        "; %d baseline entr%s can be lowered (--update)" % (stale, "y" if stale == 1 else "ies") if stale else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
