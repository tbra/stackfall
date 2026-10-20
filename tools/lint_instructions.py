"""Instruction drift guard: every agent rule has one home file.

Usage: python tools/lint_instructions.py [--path <checkout>] [--list]

Scans the agent instruction files (CLAUDE.md, .claude/agents/*.md and
.claude/skills/*/SKILL.md) for marker text that identifies a rule, and fails when
a marker appears outside the file(s) allowed to hold that rule. Other files point
to the home instead of restating the rule, so a later edit cannot leave a stale
copy behind. To move a rule, change its home in RULES in the same commit.
Prints one `LINT INSTRUCTIONS GREEN|RED` line (exit 1 on RED); --list prints the
rule table.
"""
import argparse
import glob
import os
import re
import sys

ORCHESTRATOR = ".claude/agents/stackfall-orchestrator.md"
WORKER = ".claude/skills/stackfall-worker/SKILL.md"
GODOT = ".claude/skills/stackfall-godot/SKILL.md"
USER_QUESTIONS = ".claude/skills/stackfall-user-questions/SKILL.md"
SESSION_SKILLS = tuple(".claude/skills/%s/SKILL.md" % name for name in
                       ("stackfall-session-resume", "stackfall-auto-run", "stackfall-session-close"))

# (rule, marker regex, home files allowed to contain the marker)
RULES = (
    ("off-screen window flags", r"--position 10000,10000", ("CLAUDE.md",)),
    ("orchestrator Beads actor", r"--actor stackfall-orchestrator", ("CLAUDE.md",)),
    ("full-suite cadence", r"once per integrated", ("CLAUDE.md",)),
    ("Beads remote sync", r"bd dolt (?:push|pull)", ("CLAUDE.md",)),
    ("smallest-change ladder", r"first option that fully works", ("CLAUDE.md",)),
    ("shortcut comment format", r"<when to upgrade>", ("CLAUDE.md",)),
    ("handback limits", r"\b1800\b", (WORKER,)),
    ("failed-comment handback", r"comment-failed", (WORKER,)),
    ("checkpoint template", r"Next exact action / blocked", (WORKER,)),
    ("time limits on long runs", r"wall-clock limit", (WORKER,)),
    ("model routing", r"route_model\.py", (ORCHESTRATOR,)),
    ("claim command", r"--if-status", (ORCHESTRATOR,)),
    ("decision format", r"accept all defaults", (USER_QUESTIONS,)),
    ("owner reply handling", r"bd gate resolve", (USER_QUESTIONS,)),
    ("machine guard", r"cpumon\.ps1", (ORCHESTRATOR,)),
    ("integration command", r"integrate_batch\.py", (ORCHESTRATOR,)),
    ("skill version check", r"skill_versions\.py", SESSION_SKILLS),
    ("Godot process listing", r"tasklist", (GODOT,)),
    ("targeted test totals", r"`Totals`", (GODOT,)),
    ("ENet result line", r"ENET RESULT", (GODOT,)),
    ("tuning panel hints", r"tuning_panel_hints", (GODOT,)),
    ("probe file ban", r"probe_lint", (GODOT,)),
    ("GPU measurement", r"measure_gpu_steady", (GODOT,)),
    ("startup measurement", r"measure_startup", (GODOT,)),
)


def instruction_files(root):
    """Repo-relative paths of the scanned instruction files that exist under `root`."""
    paths = ["CLAUDE.md"]
    paths += glob.glob(os.path.join(root, ".claude", "agents", "**", "*.md"), recursive=True)
    paths += glob.glob(os.path.join(root, ".claude", "skills", "*", "SKILL.md"))
    out = []
    for p in paths:
        rel = os.path.relpath(os.path.join(root, p), root).replace("\\", "/")
        if os.path.isfile(os.path.join(root, rel)) and rel not in out:
            out.append(rel)
    return sorted(out)


def find_violations(root):
    """[(rule, rel_path, line_no, homes)] for each marker found outside its homes."""
    found = []
    compiled = [(rule, re.compile(marker), homes) for rule, marker, homes in RULES]
    for rel in instruction_files(root):
        with open(os.path.join(root, rel), encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
        for rule, pattern, homes in compiled:
            if rel in homes:
                continue
            for number, line in enumerate(lines, 1):
                if pattern.search(line):
                    found.append((rule, rel, number, homes))
    return found


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=None, help="checkout (default: the checkout holding this script)")
    ap.add_argument("--list", action="store_true", help="print each rule's marker and home files")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path or os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    if args.list:
        for rule, marker, homes in RULES:
            print("%s: /%s/ -> %s" % (rule, marker, ", ".join(homes)))
    violations = find_violations(root)
    for rule, rel, number, homes in violations:
        print("%s:%d: %s belongs in %s; point there instead of restating it" % (rel, number, rule, " or ".join(homes)))
    if violations:
        print("LINT INSTRUCTIONS RED: %d finding(s)" % len(violations))
        return 1
    print("LINT INSTRUCTIONS GREEN: %d rules, %d files" % (len(RULES), len(instruction_files(root))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
