"""Small Claude SessionStart pointer; live state is loaded by the resume skill.

Also prints the two keyed memories the session skills hand over:
`stackfall-handoff` (next work target) and the previous session's
improvement items with reasoning, so they reach a new or compacted session even when
the resume skill is not invoked. The hook's `bd prime` runs with --no-memories; other
memories are fetched by key on demand.
"""

import json
import shutil
import subprocess
from pathlib import Path

from bd_cli import native_or
from skill_versions import list_versions

HANDOVER_KEYS = ("stackfall-handoff", "stackfall-debrief")
BD_TIMEOUT_S = 20
MAX_MEMORY_CHARS = 2500
LOW_DISK_GB = 20
REPO = Path(__file__).resolve().parents[1]


def read_memory(key):
    """The memory's text, or a short UNAVAILABLE note (never raises)."""
    bd = native_or(shutil.which("bd"))  # npm shim -> its native bd.exe; a bare "bd" is not found there
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


def disk_line(path=REPO):
    """Free space on the checkout's drive; a full drive broke integration and Dolt writes."""
    try:
        free_gb = shutil.disk_usage(str(path)).free / 1e9
    except OSError as exc:
        return "[disk] UNAVAILABLE (%s)" % exc.__class__.__name__
    warn = " LOW DISK: free space before integrating or soaking" if free_gb < LOW_DISK_GB else ""
    return "[disk] %s %.0f GB free%s" % (Path(path).anchor or path, free_gb, warn)


def main():
    try:
        versions = list_versions()
    except (OSError, ValueError) as exc:
        versions = "UNAVAILABLE (%s)" % exc
    print(
        "Stackfall: use .claude/skills/stackfall-session-resume/SKILL.md. "
        "Read the named Bead and live Git state; fetch other memories by key. "
        "Skill versions on disk: " + versions + ". Verify the active skill before use."
    )
    print(disk_line())
    for key in HANDOVER_KEYS:
        print("[" + key + "] " + read_memory(key))


if __name__ == "__main__":
    main()
