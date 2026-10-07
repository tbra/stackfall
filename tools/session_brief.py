"""Small Claude SessionStart pointer; live state is loaded by the resume skill.

Also prints the two keyed memories the session skills hand over (owner 2026-10-07):
`stackfall-handoff` (next work target) and `stackfall-debrief` (previous session's
improvement items with reasoning), so they reach a new or compacted session even when
the resume skill is not invoked. The hook's `bd prime` runs with --no-memories; other
memories are fetched by key on demand.
"""

import json
import shutil
import subprocess

from skill_versions import list_versions

HANDOVER_KEYS = ("stackfall-handoff", "stackfall-debrief")
BD_TIMEOUT_S = 20
MAX_MEMORY_CHARS = 2500


def read_memory(key):
    """The memory's text, or a short UNAVAILABLE note (never raises)."""
    bd = shutil.which("bd")  # bd.CMD on Windows (npm shim); a bare "bd" is not found there
    if bd is None:
        return "UNAVAILABLE (bd not on PATH)"
    try:
        proc = subprocess.run([bd, "memories", key, "--json"], capture_output=True,
                              text=True, encoding="utf-8", errors="replace",
                              timeout=BD_TIMEOUT_S)
        data = json.loads(proc.stdout or "{}")
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        return "UNAVAILABLE (%s)" % exc.__class__.__name__
    text = data.get(key) if isinstance(data, dict) else None
    if not isinstance(text, str) or not text.strip():
        return "none"
    if len(text) > MAX_MEMORY_CHARS:
        text = text[:MAX_MEMORY_CHARS] + " ...(truncated; bd memories " + key + ")"
    return text


def main():
    try:
        versions = list_versions()
    except (OSError, ValueError) as exc:
        versions = "UNAVAILABLE (%s)" % exc
    print(
        "Stackfall: use .claude/skills/stackfall-session-resume/SKILL.md. "
        "Read the named Bead and live Git state; fetch other memories by key. "
        "docs/CLAUDE_HANDOFF.md is historical. "
        "Skill versions on disk: " + versions + ". Verify the active skill before use."
    )
    for key in HANDOVER_KEYS:
        print("[" + key + "] " + read_memory(key))


if __name__ == "__main__":
    main()
