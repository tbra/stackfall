"""Claude hook: reviewer Bash is read-only plus one assigned-issue Beads comment.

Allowed (session debrief 2026-10-01: reviewers kept asking the orchestrator to
export Beads/git data and to persist their findings for them):
  - bd -C M:/Bontago comments add Bontago-ID --actor stackfall-reviewer "finding"
  - bd -C M:/Bontago show|comments|children Bontago-ID [--json] [--brief-deps]
  - git -C <M:/ path> log|show|diff|status [plain args]
  - (Bontago-fca.55, owner choice A) powershell -NoProfile -File tools/run_gut.ps1
    test_a[,test_b...] [-Path M:/<checkout>] [-Unit name]: explicit test_* script names only.
    Max 2 runs per review (RUN_CAP) is a profile rule; the hook also counts per subagent when
    the hook event carries an agent_id (no agent_id = not enforced, to avoid a shared session cap).
Everything else (edits, other tests, commits, status changes, pipes, redirects,
command chaining, substitutions, -gdir/-gselect/-Dir overrides) is denied.
"""

import json
import os
import re
import sys
import tempfile

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
# Exact run_gut.ps1 form: explicit script names (no wildcards), optional -Path/-Unit once each.
GUT_RUN = re.compile(
    r'^powershell -NoProfile -File tools/run_gut\.ps1 '
    r'test_[A-Za-z0-9_]+(,test_[A-Za-z0-9_]+)*'
    r'( -Path M:/[A-Za-z0-9_./-]+)?( -Unit [A-Za-z0-9_]+)?$'
)
GUT_RUN_ALT = re.compile(
    r'^powershell -NoProfile -File tools/run_gut\.ps1 '
    r'test_[A-Za-z0-9_]+(,test_[A-Za-z0-9_]+)*'
    r'( -Unit [A-Za-z0-9_]+)( -Path M:/[A-Za-z0-9_./-]+)?$'
)
RUN_CAP = 2
ALLOWED = (COMMENT, BD_READ, GIT_READ, GUT_RUN, GUT_RUN_ALT)
# git options that write files or run external programs.
GIT_DENY = re.compile(r' (--output|-o|--ext-diff|--textconv|--exec|--upload-pack)(=| |$)')


def allowed(command):
    if not isinstance(command, str):
        return False
    if GIT_READ.fullmatch(command) and GIT_DENY.search(command):
        return False
    return any(p.fullmatch(command) for p in ALLOWED)


def is_gut_run(command):
    return isinstance(command, str) and bool(GUT_RUN.fullmatch(command) or GUT_RUN_ALT.fullmatch(command))


def count_run(agent_id, counter_dir=None):
    """Increment and return the per-agent run count; None when there is no agent id."""
    if not agent_id or not re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", str(agent_id)):
        return None
    path = os.path.join(counter_dir or tempfile.gettempdir(), "stackfall_reviewer_gut_%s.count" % agent_id)
    try:
        with open(path) as f:
            n = int(f.read().strip() or 0)
    except (OSError, ValueError):
        n = 0
    n += 1
    try:
        with open(path, "w") as f:
            f.write(str(n))
    except OSError:
        return None
    return n


def deny(reason):
    print(json.dumps({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason,
    }}))


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        event = {}
    command = (event.get("tool_input") or {}).get("command", "")
    if allowed(command) and is_gut_run(command):
        n = count_run(event.get("agent_id"))
        if n is not None and n > RUN_CAP:
            deny("Reviewer test runs are capped at %d per review." % RUN_CAP)
        return 0
    if not allowed(command):
        deny((
                "Reviewer Bash allows only: bd -C M:/Bontago comments add Bontago-ID "
                "--actor stackfall-reviewer \"one-line finding\"; bd -C M:/Bontago "
                "show|comments|children Bontago-ID [--json] [--brief-deps]; git -C M:/<path> "
                "log|show|diff|status <plain args>. No pipes, redirects, chaining or quotes "
                "in git args; powershell -NoProfile -File tools/run_gut.ps1 test_a,test_b "
                "[-Path M:/<checkout>] [-Unit name] (max 2 runs). Use Read/Glob/Grep for files."
            ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
