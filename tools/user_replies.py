"""Surface new user replies on Beads to the orchestrator (Claude hook).

A reply on a Beads issue is only useful if it is noticed: check for responses on every prompt and
board scan. Run from the UserPromptSubmit and SessionStart hooks and
from tools/board_brief.py: prints one line per user comment (any author that
is not an agent profile) newer than the last check, then records the check
time so each reply is shown once.

Usage:
  python tools/user_replies.py          # print new replies, mark them seen
  python tools/user_replies.py --peek   # print without marking seen
  python tools/user_replies.py --since 2026-10-01T00:00:00Z --peek
  python tools/user_replies.py --rewake # UserPromptSubmit hook (asyncRewake): exit 2 with the
                                         # replies wakes Claude; silent exit 0 otherwise

Calls bd through tools/bd_cli.py (native binary when present).
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from bd_cli import bd_executable  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE = os.path.join(ROOT, ".claude", "user_replies_state.json")
# Comment authors that are agents, not the user.
AGENT_PREFIXES = ("stackfall-", "codex", "claude", "orchestrator", "jev", "typesafe")
MAX_TEXT = 400
# First run with no state: look back this far so a fresh install still shows
# recent replies.
FIRST_RUN_LOOKBACK = "1970-01-01T00:00:00Z"


def _export():
    """All issues with comments in one call (bd export; ~1-2 s)."""
    out = subprocess.run(
        [bd_executable(), "export"], cwd=ROOT,
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


def _is_user(author):
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
        # No updated_at prefilter: adding a comment does not bump the issue's
        # updated_at in Beads, so that filter hid user replies.
        for comment in issue.get("comments") or []:
            if (comment.get("created_at") or "") <= since or not _is_user(comment.get("author")):
                continue
            text = " ".join((comment.get("text") or "").split())
            if len(text) > MAX_TEXT:
                text = text[:MAX_TEXT] + "..."
            replies.append((comment["created_at"], issue["id"], issue.get("status", ""),
                            issue.get("title", "")[:70], comment.get("author"), text))
    return sorted(replies)


def main(argv):
    peek = "--peek" in argv
    rewake = "--rewake" in argv
    since = argv[argv.index("--since") + 1] if "--since" in argv else _load_since()
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    try:
        replies = find_replies(since)
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as exc:
        if not rewake:  # A background check stays silent; the next prompt retries.
            print("user_replies: could not query Beads (%s); check bd comments manually." % exc)
        return 0
    if replies:
        print("NEW USER REPLIES ON BEADS (%d) - act on these before other work:" % len(replies))
        for created, issue_id, status, title, author, text in replies:
            print("  %s [%s] %s (%s) %s: %s" % (issue_id, status, title, created[:16], author, text))
    if not peek:
        _save(now)
    return 2 if rewake and replies else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
