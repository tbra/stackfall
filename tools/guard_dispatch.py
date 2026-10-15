"""Project PreToolUse hook for the Agent tool (Bontago-fca.122): check worker dispatches.

A `stackfall-*` dispatch must pass the model `tools/route_model.py` chose (agent-file
`model:` values are only fallbacks), and its brief must name the Bead (`Bontago-<id>`) and
an absolute checkout path. `tools/dispatch_prep.py` prints the model and posts the dispatch
comment. Built-in agents and other subagent types pass untouched.
"""
import json
import re
import sys

BEAD = re.compile(r"\bBontago-[A-Za-z0-9.]+")
CHECKOUT = re.compile(r"\b[A-Za-z]:[\\/]")


def problem(tool_input):
    """The deny reason for an Agent call, or None when it may run."""
    if not str(tool_input.get("subagent_type") or "").startswith("stackfall-"):
        return None
    missing = []
    if not str(tool_input.get("model") or "").strip():
        missing.append("an explicit `model` (the route_model.py verdict from tools/dispatch_prep.py)")
    prompt = str(tool_input.get("prompt") or "")
    if not BEAD.search(prompt):
        missing.append("the assigned Bead id (Bontago-<id>)")
    if not CHECKOUT.search(prompt):
        missing.append("the absolute checkout path")
    if not missing:
        return None
    return ("Blocked worker dispatch: add %s. Write the brief from \"Your brief\" in "
            ".claude/skills/stackfall-worker/SKILL.md." % "; ".join(missing))


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0  # Broken hook input must not trap the orchestrator.
    reason = problem(event.get("tool_input") or {})
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
