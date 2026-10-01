"""Claude hook: reviewer Bash is read-only plus one assigned-issue Beads comment.

Allowed (session debrief 2026-10-01: reviewers kept asking the orchestrator to
export Beads/git data and to persist their findings for them):
  - bd -C M:/Bontago comments add Bontago-ID --actor stackfall-reviewer "finding"
  - bd -C M:/Bontago show|comments|children Bontago-ID [--json] [--brief-deps]
  - git -C <M:/ path> log|show|diff|status [plain args]
Everything else (edits, tests, commits, status changes, pipes, redirects,
command chaining, substitutions) is denied.
"""

import json
import re
import sys

# Inside double quotes bash only treats $ ` \ " as special, so ; | & < > are
# literal there and allowed in finding text. One line, no quote/escape chars.
COMMENT = re.compile(
    r'^bd -C M:/Bontago comments add Bontago-[A-Za-z0-9.]+ '
    r'--actor stackfall-reviewer "[^"\\\r\n`$]{1,8000}"$'
)
BD_READ = re.compile(
    r'^bd -C M:/Bontago (show|comments|children) Bontago-[A-Za-z0-9.]+'
    r'( --json| --brief-deps)*$'
)
# Plain tokens only: no shell metacharacters, quotes, spaces inside tokens.
GIT_READ = re.compile(
    r'^git -C M:/[A-Za-z0-9_./-]+ (log|show|diff|status)'
    r'( [A-Za-z0-9_.:/=@^~%+,-]+)*$'
)
ALLOWED = (COMMENT, BD_READ, GIT_READ)
# git options that write files or run external programs.
GIT_DENY = re.compile(r' (--output|-o|--ext-diff|--textconv|--exec|--upload-pack)(=| |$)')


def allowed(command):
    if not isinstance(command, str):
        return False
    if GIT_READ.fullmatch(command) and GIT_DENY.search(command):
        return False
    return any(p.fullmatch(command) for p in ALLOWED)


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        event = {}
    command = (event.get("tool_input") or {}).get("command", "")
    if not allowed(command):
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": (
                "Reviewer Bash allows only: bd -C M:/Bontago comments add Bontago-ID "
                "--actor stackfall-reviewer \"one-line finding\"; bd -C M:/Bontago "
                "show|comments|children Bontago-ID [--json] [--brief-deps]; git -C M:/<path> "
                "log|show|diff|status <plain args>. No pipes, redirects, chaining or quotes "
                "in git args. Use Read/Glob/Grep for files."
            ),
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
