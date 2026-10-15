"""Project PreToolUse hook for Bash and PowerShell calls.

Registered once in .claude/settings.json, so a call starts one Python process. It denies:
- `python3`/`pip3` Microsoft Store aliases (tools/guard_store_python.py);
- a Godot launch that is neither `--headless` nor off-screen (windows
  interrupted the user on another monitor; the flags are in CLAUDE.md §Environment);
- killing Godot by image name (other agents run Godot in other worktrees);
- the full GUT suite from writer roles (`agent_type` in the hook input names the subagent;
  the orchestrator and the integrator may run it).
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
WRITER_ROLES = frozenset((
    "stackfall-implementer", "stackfall-netcode", "stackfall-designer", "stackfall-triage",
    "stackfall-planner", "stackfall-editor",
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


def executable_text(command):
    """`command` without heredoc and here-string bodies."""
    return _HERESTRING.sub("@''@", _HEREDOC.sub(r"\1", command or ""))


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
