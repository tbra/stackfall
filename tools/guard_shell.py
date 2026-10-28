"""Project PreToolUse hook for Bash and PowerShell calls.

Registered once in .claude/settings.json, so a call starts one Python process. It denies:
- `python3`/`pip3` Microsoft Store aliases (tools/guard_store_python.py);
- a Godot launch that is neither `--headless` nor off-screen (windows
  interrupted the user on another monitor; the flags are in CLAUDE.md §Environment);
- killing Godot by image name (other agents run Godot in other worktrees);
- the full GUT suite from writer roles (`agent_type` in the hook input names the subagent;
  the orchestrator and the integrator may run it);
- `git stash` (any subcommand, global options allowed) from every worker profile; the
  orchestrator may stash.
Only command positions are checked, so the words may still appear in quoted text, commit
messages or grep patterns. Everything else passes untouched.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guard_store_python  # noqa: E402

_SEP = r"(?:^|[;&|(`\n]|\$\()"
_PREFIX = r"\s*(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*(?:&\s*)?"
# Wrappers that run another command: `timeout N` and the Godot slot queue.
_WRAP = r"(?:timeout\s+\S+\s+|python\S*\s+\S*godot_slots\.py\s+run\b[^;&|\n]*?\s--\s+)?"
_GODOT = r"[\"']?(?:\S*[\\/])?godot(?:_v[\w.-]*|[\w-]*)(?:\.exe)?[\"']?(?=\s|$)"
GODOT_LAUNCH = re.compile(_SEP + _PREFIX + _WRAP + "(" + _GODOT + r"[^;&|\n]*)", re.IGNORECASE)
OFF_SCREEN = re.compile(r"--position\s+10000,10000")
NO_WINDOW = re.compile(r"--headless(?![\w-])|--version(?![\w-])|--help(?![\w-])|(?:^|\s)-h(?=\s|$)")
IMAGE_KILL = re.compile(
    _SEP + _PREFIX + r"(?:taskkill\b[^;&|\n]*?/+IM\s+[\"']?godot"
    r"|Stop-Process\b[^;|\n]*-Name\s+[\"']?godot"
    r"|Get-Process\s+[^;|\n]*godot[^;|\n]*\|\s*Stop-Process"
    r"|(?:pkill|killall)\b[^;&|\n]*godot)",
    re.IGNORECASE)
# Heredoc and PowerShell here-string bodies are data (scripts, notes, file contents), not
# commands; the line that opens them is kept.
_HEREDOC = re.compile(r"(<<-?\s*(['\"]?)([A-Za-z_]\w*)\2[^\n]*)\n.*?\n[ \t]*\3[ \t]*(?=\n|$)", re.S)
_HERESTRING = re.compile(r"@(['\"])\r?\n.*?\r?\n\1@", re.S)
FULL_SUITE = re.compile(
    r"-gdir=res://tests/?(?=[\s\"']|$)"
    r"|" + _SEP + _PREFIX + r"python\S*\s+(?:\S*[\\/])?full_gate\.py\b",
    re.IGNORECASE)
_SEGMENT_SPLIT = re.compile(r"[;&|(`\n]|\$\(")
_TOKEN = re.compile(r"\"[^\"]*\"|'[^']*'|\S+")
# Commands that run their first non-option argument; their own option values are skipped loosely.
_WRAPPERS = frozenset(("timeout", "env", "xargs", "command", "nice", "nohup", "sudo", "exec", "time", "builtin"))
# git global options whose value is the next token (the attached forms are one token).
_GIT_VALUE_OPTIONS = frozenset(("-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix",
                                "--config-env", "--attr-source", "--exec-path", "--list-cmds"))


def _word(token):
    return token.strip("\"'")


def _basename(token):
    return re.split(r"[\\/]", _word(token))[-1].lower()


def _is_git_stash(tokens):
    i = 0
    while i < len(tokens) and re.fullmatch(r"[A-Za-z_]\w*=\S*", _word(tokens[i])):
        i += 1
    while i < len(tokens) and _basename(tokens[i]) in _WRAPPERS:
        i += 1
        while i < len(tokens) and re.fullmatch(r"-\S*|\S*=\S*|\d+[smhd]?", _word(tokens[i])):
            i += 1
    if i >= len(tokens) or _basename(tokens[i]) not in ("git", "git.exe"):
        return False
    i += 1
    while i < len(tokens) and _word(tokens[i]).startswith("-"):
        i += 2 if _word(tokens[i]) in _GIT_VALUE_OPTIONS else 1
    return i < len(tokens) and _word(tokens[i]) == "stash"


def git_stash(command):
    """True when a command segment runs `git stash` (any global options or wrapper in front)."""
    return any(_is_git_stash(_TOKEN.findall(segment)) for segment in _SEGMENT_SPLIT.split(command))


ORCHESTRATOR_ROLE = "stackfall-orchestrator"
WRITER_ROLES = frozenset((
    "stackfall-implementer", "stackfall-netcode", "stackfall-designer", "stackfall-triage",
    "stackfall-planner", "stackfall-editor", "stackfall-tester",
))

REASON_WINDOW = (
    "Blocked: windowed Godot launches must run off-screen. Add the off-screen "
    "flags from CLAUDE.md §Environment (`--position 10000,10000` and the rest, plus `-- --agent-probe`), "
    "or use `--headless` when no screenshot is needed.")
REASON_KILL = (
    "Blocked: never kill Godot by image name; other agents run Godot in other worktrees. "
    "Kill only PIDs you started: `taskkill //F //PID <n>` after reading their CommandLine.")
REASON_SUITE = (
    "Blocked: the full GUT suite is the orchestrator's once-per-batch gate. Run the targeted "
    "`tools/run_gut.ps1 <scripts>` named in your brief instead.")
REASON_STASH = (
    "Blocked: workers never use `git stash`; it moves files other checkouts and agents rely on. "
    "Copy the files you need to set aside into your scratchpad instead.")


# A quoted argument holds data, so a separator inside it starts no command: the `\|` of a grep
# alternation like 'a\|godot-ai' once read as a pipe into a windowed launch. The body of
# `bash -c '...'` or `powershell -Command "..."` still runs, so it keeps its separators.
_COMMAND_ARG = re.compile(r"(?:^|\s)-(?:c|Command)\s+$", re.IGNORECASE)
_SINGLE_QUOTED_SEPARATORS = re.compile(r"[;&|`\n(]")
# Inside double quotes `$(...)` and backticks still run, so only plain separators are blanked.
_DOUBLE_QUOTED_SEPARATORS = re.compile(r"[;&|\n]")


def _quoted_end(command, start):
    """Index of the quote closing the one at `start`, or -1; `\\"` does not close a double quote."""
    quote = command[start]
    i = start + 1
    while i < len(command):
        if command[i] == "\\" and quote == '"':
            i += 2
            continue
        if command[i] == quote:
            return i
        i += 1
    return -1


def _blank_quoted_separators(command):
    out = []
    i = 0
    while i < len(command):
        ch = command[i]
        end = _quoted_end(command, i) if ch in "'\"" else -1
        if end < 0:
            out.append(ch)
            i += 1
            continue
        span = command[i:end + 1]
        if not _COMMAND_ARG.search(command[:i]):
            pattern = _SINGLE_QUOTED_SEPARATORS if ch == "'" else _DOUBLE_QUOTED_SEPARATORS
            span = pattern.sub(" ", span)
        out.append(span)
        i = end + 1
    return "".join(out)


def executable_text(command):
    """`command` without heredoc and here-string bodies or separators inside quoted arguments."""
    return _blank_quoted_separators(_HERESTRING.sub("@''@", _HEREDOC.sub(r"\1", command or "")))


def problem(command, agent_type=None):
    """The deny reason for `command`, or None when it may run."""
    command = executable_text(command)
    if guard_store_python.blocked(command):
        return guard_store_python.REASON
    if IMAGE_KILL.search(command):
        return REASON_KILL
    for match in GODOT_LAUNCH.finditer(command):
        segment = match.group(1)
        if not NO_WINDOW.search(segment) and not OFF_SCREEN.search(segment):
            return REASON_WINDOW
    if agent_type in WRITER_ROLES and FULL_SUITE.search(command):
        return REASON_SUITE
    if agent_type and agent_type != ORCHESTRATOR_ROLE and git_stash(command):
        return REASON_STASH
    return None


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0  # Broken hook input must not trap the agent.
    reason = problem((event.get("tool_input") or {}).get("command", ""), event.get("agent_type"))
    if reason:
        print(json.dumps({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
