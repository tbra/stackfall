"""Claude hook: keep project worker reports compact before they reach the main chat.

Registered in project subagent frontmatter, not globally: built-in agents and the
main orchestrator must not be forced into this worker-only report contract.
"""

import json
import re
import sys


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
_FENCE = re.compile(r"^```[A-Za-z]*[ \t]*\r?\n(.*?)\r?\n```$", re.S)


def _filled(value, structured, nested=False):
    if isinstance(value, str):
        return bool(value.strip())
    if nested and isinstance(value, (int, float, bool)):
        return True
    if structured and isinstance(value, (list, dict)):
        items = value.values() if isinstance(value, dict) else value
        return bool(value) and all(_filled(item, True, True) for item in items)
    return False


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
    if not re.fullmatch(r"Bontago-[A-Za-z0-9.]+", report["bead"]):
        return "The bead field must name the assigned Bontago issue."
    verdict = report["verdict"].lower()
    if verdict not in VERDICTS:
        return "Verdict must be done, review, partial, blocked, or failed."
    comment_failed = report["record"].startswith("comment-failed:") and len(report["record"]) > len("comment-failed:")
    if report["record"] != "bd:" + report["bead"] and not (comment_failed and verdict in FAILURE_VERDICTS):
        return "Record must be bd:<assigned-issue-id> after commenting, or comment-failed:<error> for a failed handback."
    limit = 3200 if comment_failed else 1500 if verdict in FAILURE_VERDICTS else 1100
    if len(message) > limit:
        return "Handback is %d characters; limit is %d for verdict=%s. Keep decisive candidate, files, checks, finding and next action here; put full detail in the Bead comment. If the comment failed, use verdict=blocked and record=comment-failed:<error>." % (len(message), limit, verdict)
    if message.count("\n") > 8:
        return "Use compact JSON (at most 8 lines)."
    return None


def used_handback(path):
    if not path:
        return False
    try:
        with open(path, "rb") as transcript:
            transcript.seek(0, 2)
            transcript.seek(max(0, transcript.tell() - 24000))
            return b'"SubagentHandback"' in transcript.read()
    except OSError:
        return False


def main():
    try:
        event = json.load(sys.stdin)
    except (TypeError, ValueError):
        return 0  # Broken hook input must not trap a worker.
    kind = event.get("hook_event_name")
    if kind == "PreToolUse" and event.get("tool_name") == "SubagentHandback":
        message = event.get("tool_input", {}).get("message", "")
        issue = problem(message)
        if issue:
            print(json.dumps({"hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": issue + " Format: {\"bead\":\"Bontago-id\",\"verdict\":\"done|review|partial|blocked|failed\",\"candidate\":\"checkout@revision or uncommitted\",\"files\":\"owned paths\",\"checks\":\"named check: result\",\"finding\":\"decisive result or blocker\",\"next\":\"exact action\",\"record\":\"bd:Bontago-id\"}. First post full recovery detail to your assigned bead; do not make the orchestrator open it for routine acceptance."
            }}))
    elif kind == "SubagentStop":
        # Fallback for workers that return final text instead of SubagentHandback.
        # Claude sets stop_hook_active after one block; fail open on that retry.
        if event.get("stop_hook_active") or used_handback(event.get("agent_transcript_path")):
            return 0
        message = event.get("last_assistant_message", "")
        issue = problem(message) if message and message.strip() else "Missing worker handback."
        if issue:
            print(json.dumps({"decision": "block", "reason": issue + " Return the compact JSON handback specified in the stackfall-worker skill."}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
