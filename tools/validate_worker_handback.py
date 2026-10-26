"""Claude hook: keep project worker reports compact before they reach the main chat.

Registered in project subagent frontmatter, not globally: built-in agents and the
main orchestrator must not be forced into this worker-only report contract.

A handback is refused while one of the worker's own background tasks (a Monitor or a
run_in_background shell) is still live: the task's next notification would wake the worker
after its report and the harness would demand the report again (duplicate handbacks).
The worker's transcript is read to find launched tasks without a final notification or a
TaskStop; an unreadable transcript fails open.
"""

import datetime
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repo_paths  # noqa: E402


REQUIRED = ("bead", "verdict", "candidate", "files", "checks", "finding", "next", "record")
FAILURE_VERDICTS = {"blocked", "fail", "failed", "partial"}
VERDICTS = FAILURE_VERDICTS | {"done", "review"}
# DECISION (/doctor): replaying 1,322 recorded first handbacks,
# 98% were denied, mostly for list-valued files/checks, synonym keys or a ```json fence,
# costing nearly every worker a retry turn. These shapes carry the same compact content,
# so accept them; the size and line limits still apply to the raw message. bead,
# verdict, candidate, next and record stay plain strings because they are matched.
STRUCTURED = ("files", "checks", "finding")
ALIASES = {"finding": ("findings", "decisive_finding"), "next": ("next_action",)}
# DECISION (handback caps): replaying 84 first handbacks, 59 were denied as oversize
# (done median 1800 chars, review 1250, partial 1950; p75 done 1950, partial 2200) and
# 9 for multi-bead briefs. The eight required keys with paths and named checks already
# take ~700-1000 chars, so 1100 was below legitimate content, not below log dumps.
# Caps are now 1800 done/review and 2400 partial/blocked/failed (about the 60th and
# 85th percentile of recorded reports): still ~2-3x smaller than a log dump, and
# anything longer must move to the bead comment. comment-failed keeps 3200.
# Multi-bead briefs may name several ids in `bead` (separated by , ; + & / and) or a
# range like Bontago-epic.60-64; `record` must begin with bd:<one of those ids>, optionally
# followed by more bd: ids and one short parenthetical.
LIMIT_OK = 1800
LIMIT_FAIL = 2400
LIMIT_COMMENT_FAILED = 3200
MAX_LINES = 8
_ID = r"Bontago-[A-Za-z0-9.]+?(?:-\d+)?"
_SEP = r"\s*(?:,|;|\+|&|/|and)?\s*"
_BEADS = re.compile(r"(%s)(?:%s%s)*" % (_ID, _SEP, _ID))
_RECORD_TAIL = re.compile(r"(?:%s(?:bd:)?%s)*(?:\s*\(.{0,120}\))?" % (_SEP, _ID))
_FENCE = re.compile(r"^```[A-Za-z]*[ \t]*\r?\n(.*?)\r?\n```$", re.S)
# DECISION (handback checks): workers handed back verdict=done with brief-required
# checks reading NOT RUN, and each needed a resume. The hook cannot see the brief, so a
# done handback may list a NOT RUN check only when that entry says the brief marks it
# optional; otherwise the honest verdict is partial.
_NOT_RUN = re.compile(r"not[ _-]run", re.I)
_OPTIONAL = re.compile(r"optional", re.I)


def _filled(value, structured, nested=False):
    if isinstance(value, str):
        return bool(value.strip())
    if nested and isinstance(value, (int, float, bool)):
        return True
    if structured and isinstance(value, (list, dict)):
        items = value.values() if isinstance(value, dict) else value
        return bool(value) and all(_filled(item, True, True) for item in items)
    return False


def _check_entries(checks):
    if isinstance(checks, dict):
        return ["%s: %s" % (key, value) for key, value in checks.items()]
    if isinstance(checks, list):
        return [str(item) for item in checks]
    return re.split(r"[;\n]", str(checks))


def _skipped_required(checks):
    return [entry.strip() for entry in _check_entries(checks)
            if _NOT_RUN.search(entry) and not _OPTIONAL.search(entry)]


def _field(report, key):
    if key in report:
        return report[key]
    for alias in ALIASES.get(key, ()):
        if alias in report:
            return report[alias]
    return None


def problem(message):
    text = message.strip() if isinstance(message, str) else message
    fenced = _FENCE.match(text) if isinstance(text, str) else None
    try:
        report = json.loads(fenced.group(1) if fenced else text)
    except (TypeError, ValueError):
        return "Return one JSON object, not prose."
    if not isinstance(report, dict):
        return "The handback must be one JSON object."
    missing = [key for key in REQUIRED if not _filled(_field(report, key), key in STRUCTURED)]
    if missing:
        return "Missing nonempty fields: %s (use these exact key names; files, checks and finding may be strings or short lists)." % ", ".join(missing)
    bead = _BEADS.fullmatch(report["bead"].strip())
    if not bead:
        return "The bead field must name the assigned Bontago issue (several ids may be joined with , ; + & / or 'and')."
    ids = re.findall(r"Bontago-[A-Za-z0-9.]+?(?=-\d+(?:\s|,|;|\+|&|/|$)|[\s,;+&/]|$)", report["bead"].strip())
    verdict = report["verdict"].lower()
    if verdict not in VERDICTS:
        return "Verdict must be done, review, partial, blocked, or failed."
    skipped = _skipped_required(_field(report, "checks")) if verdict == "done" else []
    if skipped:
        return "verdict=done but checks are NOT RUN: %s. Run them, use verdict=partial, or say 'optional' in the entry when the brief marks the check optional. Omit a check the brief forbids or assigns to another package instead of listing it." % "; ".join(skipped)[:300]
    comment_failed = report["record"].startswith("comment-failed:") and len(report["record"]) > len("comment-failed:")
    record = report["record"].strip()
    record_ok = any(record.startswith("bd:" + one) and _RECORD_TAIL.fullmatch(record[len("bd:" + one):]) is not None for one in ids)
    if not record_ok and not (comment_failed and verdict in FAILURE_VERDICTS):
        return "Record must be bd:<assigned-issue-id> (extra bd: ids allowed for a multi-bead brief) after commenting, or comment-failed:<error> for a failed handback."
    limit = LIMIT_COMMENT_FAILED if comment_failed else LIMIT_FAIL if verdict in FAILURE_VERDICTS else LIMIT_OK
    if len(message) > limit:
        return "Handback is %d characters; limit is %d for verdict=%s. Keep decisive candidate, files, checks, finding and next action here; put full detail in the Bead comment. If the comment failed, use verdict=blocked and record=comment-failed:<error>." % (len(message), limit, verdict)
    if message.count("\n") > MAX_LINES:
        return "Use compact JSON (at most 8 lines)."
    return None


def used_handback(path):
    """True when the transcript holds a SubagentHandback call anywhere. The whole file is read:
    background notifications after a handback push it out of any tail window, and a stop after
    such a wake-up must not demand the report again."""
    if not path:
        return False
    try:
        with open(path, "rb") as transcript:
            return b'"SubagentHandback"' in transcript.read()
    except OSError:
        return False


def transcript_path(event):
    """The worker's own transcript: the hook field when given, else derived from the session
    transcript and the agent id (<session dir>/<session id>/subagents/agent-<id>.jsonl)."""
    path = event.get("agent_transcript_path")
    if path:
        return path
    agent_id, session_path = event.get("agent_id"), event.get("transcript_path")
    if not agent_id or not session_path:
        return None
    base = session_path[:-len(".jsonl")] if session_path.endswith(".jsonl") else session_path
    return os.path.join(base, "subagents", "agent-%s.jsonl" % agent_id)


LAUNCH_RE = re.compile(r"(?:Command running in background with ID: |Monitor started \(task )([A-Za-z0-9]+)")
DONE_RE = re.compile(r"<task-id>([A-Za-z0-9]+)</task-id>(?:(?!<task-id>).)*?(?:<status>[a-z_]+</status>|Monitor expired)", re.S)


def _texts(node):
    """Every string inside a transcript record (tool results, notifications, tool inputs)."""
    if isinstance(node, str):
        yield node
    elif isinstance(node, dict):
        for value in node.values():
            yield from _texts(value)
    elif isinstance(node, list):
        for value in node:
            yield from _texts(value)


def live_background_tasks(path):
    """Ids of background tasks the worker launched that have no final notification or TaskStop yet.
    Returns [] when the transcript cannot be read (fail open)."""
    if not path or not os.path.isfile(path):
        return []
    launched, finished = [], set()
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    record = json.loads(line)
                except ValueError:
                    continue
                if record.get("type") not in ("user", "assistant", "attachment"):
                    continue
                for text in _texts(record.get("message", record.get("attachment", {}))):
                    for task_id in LAUNCH_RE.findall(text):
                        if task_id not in launched:
                            launched.append(task_id)
                    finished.update(DONE_RE.findall(text))
                message = record.get("message", {})
                for block in message.get("content", []) if isinstance(message.get("content"), list) else []:
                    if isinstance(block, dict) and block.get("type") == "tool_use" and block.get("name") == "TaskStop":
                        task_id = (block.get("input") or {}).get("task_id") or (block.get("input") or {}).get("id")
                        if task_id:
                            finished.add(str(task_id))
    except OSError:
        return []
    return [task_id for task_id in launched if task_id not in finished]


def live_tasks_issue(event):
    live = live_background_tasks(transcript_path(event))
    if not live:
        return None
    return ("Background task(s) still running: %s. A live task wakes you after your handback and you would have "
            "to report again. Stop each one first (TaskStop <id> if you have it, else kill the process it runs and "
            "wait for its final notification), then hand back once." % ", ".join(live))


HANDBACK_LOG = ("_orchestrator", "handbacks.jsonl")
HANDBACK_LOG_ENV = "STACKFALL_HANDBACK_LOG"  # tests point the log at a temp file
FINDING_HEAD = 80


def log_handback(event, message, issue, log_path=None):
    """Append one line per validated handback attempt (accepted or denied) for tools/session_metrics.py.
    Never raises: logging must not trap a worker."""
    try:
        report = {}
        try:
            report = json.loads(message) if isinstance(message, str) else {}
        except ValueError:
            pass
        report = report if isinstance(report, dict) else {}
        row = {"ts": datetime.datetime.now().isoformat(timespec="seconds"),
               "agent": event.get("agent_type") or "", "accepted": issue is None,
               "bead": str(report.get("bead", ""))[:120], "verdict": str(report.get("verdict", "")).lower(),
               "finding": str(_field(report, "finding") or "")[:FINDING_HEAD], "issue": (issue or "")[:FINDING_HEAD]}
        path = (log_path or os.environ.get(HANDBACK_LOG_ENV)
                or os.path.join(repo_paths.scratch_root(), *HANDBACK_LOG))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(row) + "\n")
    except Exception:  # noqa: BLE001 - see docstring
        pass


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0  # Broken hook input must not trap a worker.
    kind = event.get("hook_event_name")
    if kind == "PreToolUse" and event.get("tool_name") == "SubagentHandback":
        message = event.get("tool_input", {}).get("message", "")
        issue = problem(message)
        live = None if issue else live_tasks_issue(event)
        log_handback(event, message, issue or live)
        if live:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": live}}))
        elif issue:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": issue + " Format: {\"bead\":\"Bontago-id\",\"verdict\":\"done|review|partial|blocked|failed\",\"candidate\":\"checkout@revision or uncommitted\",\"files\":\"owned paths\",\"checks\":\"named check: result\",\"finding\":\"decisive result or blocker\",\"next\":\"exact action\",\"record\":\"bd:Bontago-id\"}. First post full recovery detail to your assigned bead; do not make the orchestrator open it for routine acceptance."
            }}))
    elif kind == "SubagentStop":
        # Fallback for workers that return final text instead of SubagentHandback.
        # Claude sets stop_hook_active after one block; fail open on that retry.
        if event.get("stop_hook_active") or used_handback(transcript_path(event)):
            return 0
        message = event.get("last_assistant_message", "")
        issue = problem(message) if message and message.strip() else "Missing worker handback."
        log_handback(event, message, issue)
        if issue:
            print(json.dumps({"decision": "block", "reason": issue + " Return the compact JSON handback specified in the stackfall-worker skill."}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
