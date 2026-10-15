"""PostToolUse hook (Bontago-fca.123): run the instruction drift guard right after an edit.

Registered for Edit|Write in .claude/settings.json. When the edited file is an agent
instruction file (CLAUDE.md, .claude/agents/*.md or .claude/skills/*/SKILL.md), it runs
lint_instructions on that checkout and feeds back any rule restated in the edited file,
so the copy is fixed while the edit is fresh. Every other edit exits at once.
"""
import json
import os
import re
import sys

_INSTRUCTION = re.compile(r"(?:^|/)(?:CLAUDE\.md|\.claude/agents/.+\.md|\.claude/skills/[^/]+/SKILL\.md)$")


def checkout_root(path):
    """Nearest ancestor of `path` holding both CLAUDE.md and .claude/, or None."""
    current = os.path.dirname(os.path.abspath(path))
    while True:
        if os.path.isfile(os.path.join(current, "CLAUDE.md")) and os.path.isdir(os.path.join(current, ".claude")):
            return current
        parent = os.path.dirname(current)
        if parent == current:
            return None
        current = parent


def findings_for(path):
    """Drift findings located in the edited instruction file at `path`."""
    normalized = os.path.abspath(path).replace("\\", "/")
    if not _INSTRUCTION.search(normalized):
        return []
    root = checkout_root(path)
    if root is None:
        return []
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import lint_instructions
    rel = os.path.relpath(path, root).replace("\\", "/")
    return [(rule, number, homes) for rule, found_rel, number, homes in lint_instructions.find_violations(root)
            if found_rel == rel]


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0  # Broken hook input must not trap the agent.
    path = (event.get("tool_input") or {}).get("file_path") or ""
    if not path:
        return 0
    found = findings_for(path)
    if found:
        lines = ["line %d: %s belongs in %s" % (number, rule, " or ".join(homes)) for rule, number, homes in found]
        print(json.dumps({"decision": "block", "reason": (
            "This edit restates rules whose home is another file (tools/lint_instructions.py). "
            "Replace each with a pointer to its home: " + "; ".join(lines))}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
