"""Claude hook (PreToolUse Edit|Write|NotebookEdit): the tester writes tests only.

stackfall-tester authors behaviour tests against a module's public interface, so it may
write only under a checkout's tests/ folder, or a tools/test_*.py tool test (the main repo, a worktree under the worktrees
root, or an app worktree under <repo>/.claude/worktrees/<name>/) or under the scratch root
for logs. Any other path is denied: a hook, accessor or counter added to game code to make
something testable is exactly what this role must not produce. Report the boundary instead.
"""

import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repo_paths  # noqa: E402

TOOL_TEST = re.compile(r"tools/test_[A-Za-z0-9_]+\.py")
APP_WORKTREES = "/.claude/worktrees/"


def _norm(path):
    p = os.path.abspath(path).replace("\\", "/")
    return p[0].upper() + p[1:] if len(p) > 1 and p[1] == ":" else p


def checkout_relative(path, repo, worktrees):
    """`path` relative to the checkout that holds it, or None when it is in no checkout."""
    p = _norm(path)
    repo = _norm(repo)
    worktrees = _norm(worktrees)
    low = p.lower()
    if low.startswith(worktrees.lower() + "/"):
        rest = p[len(worktrees) + 1:]
        return rest.split("/", 1)[1] if "/" in rest else ""
    if low.startswith(repo.lower() + "/"):
        rest = p[len(repo) + 1:]
        if ("/" + rest).startswith(APP_WORKTREES):
            parts = rest[len(APP_WORKTREES) - 1:].split("/", 1)
            return parts[1] if len(parts) > 1 else ""
        return rest
    return None


def allowed(path, repo=None, worktrees=None, scratch=None):
    repo = repo or repo_paths.repo_dir()
    worktrees = worktrees or repo_paths.worktrees_root()
    scratch = _norm(scratch or repo_paths.scratch_root())
    if ".." in path.replace("\\", "/").split("/"):
        return False
    if _norm(path).lower().startswith(scratch.lower() + "/"):
        return True
    rel = checkout_relative(path, repo, worktrees)
    return rel is not None and (rel.startswith("tests/") or bool(TOOL_TEST.fullmatch(rel)))


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        event = {}
    tool_input = event.get("tool_input") or {}
    path = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    if path and allowed(path):
        return 0
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "stackfall-tester writes only under a checkout's tests/ folder, tools/test_*.py or the scratch root. "
            "If the behaviour cannot be tested through the public interface, do not add a hook, "
            "accessor or counter to game code: report the boundary to the orchestrator."),
    }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
