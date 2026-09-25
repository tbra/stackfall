"""Small Claude SessionStart pointer; live state is loaded by the resume skill."""

from skill_versions import list_versions

try:
    versions = list_versions()
except (OSError, ValueError) as exc:
    versions = "UNAVAILABLE (%s)" % exc

print(
    "Stackfall: use .claude/skills/stackfall-session-resume/SKILL.md. "
    "Read the named Bead and live Git state; fetch memories by key. "
    "docs/CLAUDE_HANDOFF.md is historical. Run bd prime --no-memories only if workflow context is missing. "
    "Skill versions on disk: " + versions + ". Verify the active skill before use."
)
