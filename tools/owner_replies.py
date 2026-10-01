"""Surface new owner replies on Beads to the orchestrator (Claude hook).

Owner 2026-10-01: "the whole bd human system is kinda pointless if you dont
check for responses". Run from the UserPromptSubmit and SessionStart hooks and
from tools/board_brief.py: prints one line per owner comment (any author that
is not an agent profile) newer than the last check, then records the check
time so each reply is shown once.

Usage:
  python tools/owner_replies.py          # print new replies, mark them seen
  python tools/owner_replies.py --peek   # print without marking seen
  python tools/owner_replies.py --since 2026-10-01T00:00:00Z --peek
"""

import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, ".claude", "owner_replies_state.json")
# Comment authors that are agents, not the owner.
AGENT_PREFIXES = ("stackfall-", "codex", "claude", "orchestrator", "jev", "typesafe")
MAX_TEXT = 400
# First run with no state: look back this far so a fresh install still shows
# recent replies.
FIRST_RUN_LOOKBACK = "1970-01-01T00:00:00Z"


def _export():
    """All issues with comments in one call (bd export; ~1-2 s)."""
    out = subprocess.run(
        [shutil.which("bd.cmd") or shutil.which("bd") or "bd", "export"], cwd=ROOT,
        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=40,
    )
    if out.returncode != 0:
        raise RuntimeError(out.stderr.strip() or "bd export failed")
    rows = []
    for line in out.stdout.splitlines():
        line = line.strip()
        if line:
            row = json.loads(line)
            if row.get("_type", "issue") == "issue":
                rows.append(row)
    return rows


def _is_owner(author):
    name = (author or "").strip().lower()
    return bool(name) and not name.startswith(AGENT_PREFIXES)


def _load_since():
    try:
        with open(STATE, encoding="utf-8") as fh:
            return json.load(fh).get("last_check", FIRST_RUN_LOOKBACK)
    except (OSError, ValueError):
        return FIRST_RUN_LOOKBACK


def _save(now):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w", encoding="utf-8") as fh:
        json.dump({"last_check": now}, fh)


def find_replies(since):
    replies = []
    for issue in _export():
        if (issue.get("updated_at") or "") < since:
            continue
        for comment in issue.get("comments") or []:
            if (comment.get("created_at") or "") <= since or not _is_owner(comment.get("author")):
                continue
            text = " ".join((comment.get("text") or "").split())
            if len(text) > MAX_TEXT:
                text = text[:MAX_TEXT] + "..."
            replies.append((comment["created_at"], issue["id"], issue.get("status", ""),
                            issue.get("title", "")[:70], comment.get("author"), text))
    return sorted(replies)


def main(argv):
    peek = "--peek" in argv
    since = argv[argv.index("--since") + 1] if "--since" in argv else _load_since()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        replies = find_replies(since)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        print("owner_replies: could not query Beads (%s); check bd comments manually." % exc)
        return 0
    if replies:
        print("NEW OWNER REPLIES ON BEADS (%d) - act on these before other work:" % len(replies))
        for created, issue_id, status, title, author, text in replies:
            print("  %s [%s] %s (%s) %s: %s" % (issue_id, status, title, created[:16], author, text))
    if not peek:
        _save(now)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
