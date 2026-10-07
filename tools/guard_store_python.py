"""Claude PreToolUse hook (owner 2026-10-07): block shell commands that open the Microsoft Store.

On this machine `python3` and `pip3` resolve to the WindowsApps App Execution Alias stubs
(C:/Users/tonyf/AppData/Local/Microsoft/WindowsApps), which open the Store's "Python install
manager" page instead of running Python. `python` (Python 3.8 first on PATH) and `py` work.
Denies: python3 / python3.N / pip3 in command position, any path into WindowsApps/python*,
and ms-windows-store: URLs. Everything else passes untouched.
"""
import json
import re
import sys

# python3/pip3 in command position: line start or after ; & | ( ` $( or a newline, optionally
# behind VAR=value assignments, a PowerShell `&` call operator or a directory prefix.
_SEP = r"(?:^|[;&|(`\n]|\$\()"
_PREFIX = r"\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:&\s*)?(?:\S*[\\/])?"
_ALIAS = r"(?:python3|pip3)(?:\.\d+)?(?:\.exe)?(?=$|[\s;&|)`])"
# Only command positions are checked, so the words may still appear in quoted text (commit
# messages, bead descriptions, grep patterns).
_STORE_PATH = r"\s*(?:&\s*)?\S*WindowsApps[\\/]+(?:python|pip)"
_STORE_URL = r"\s*(?:start|start-process|explorer(?:\.exe)?)\s+[^;&|\n]*ms-windows-store:"
BLOCKED = re.compile(
    _SEP + "(?:" + _PREFIX + _ALIAS + "|" + _STORE_PATH + "|" + _STORE_URL + ")",
    re.IGNORECASE | re.MULTILINE,
)

REASON = (
    "Blocked: `python3`/`pip3` on this machine are Microsoft Store aliases that open the Store "
    "(owner 2026-10-07). Use `python` (or `py -3.13` / `python -m pip`) instead."
)


def blocked(command):
    return bool(BLOCKED.search(command or ""))


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0
    command = (event.get("tool_input") or {}).get("command", "")
    if blocked(command):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": REASON,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
