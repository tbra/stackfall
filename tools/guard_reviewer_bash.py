"""Claude hook: reviewer Bash is only for an assigned-issue Beads comment."""

import json
import re
import sys


COMMENT = re.compile(
    r'^bd -C M:/Bontago comments add Bontago-[A-Za-z0-9.]+ '
    r'--actor stackfall-reviewer "[^"\\\r\n`$;&|<>]{1,8000}"$'
)


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        event = {}
    command = (event.get("tool_input") or {}).get("command", "")
    if not isinstance(command, str) or not COMMENT.fullmatch(command):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": "Reviewer Bash is only for: bd -C M:/Bontago comments add Bontago-ID --actor stackfall-reviewer \"one-line finding\". Use Read/Glob/Grep for inspection. Do not edit, test, commit, or change issue status."
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
