"""Classifier checks for board_brief's stale-blocked section."""

import datetime
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import board_brief as bb  # noqa: E402


def issue(iid, status, deps=()):
    return {"id": iid, "status": status, "title": iid,
            "dependencies": [{"type": t, "depends_on_id": d} for t, d in deps]}


class StaleBlockedTests(unittest.TestCase):
    def test_classifier(self):
        rows = [
            issue("done", "closed"),
            issue("live", "open"),
            issue("stale", "blocked", [("blocks", "done")]),
            issue("mixed", "blocked", [("blocks", "done"), ("blocks", "live")]),
            issue("parent_only", "blocked", [("parent-child", "done")]),
            issue("parent_ignored", "blocked", [("blocks", "done"), ("parent-child", "live")]),
            issue("manual", "blocked"),
            issue("not_blocked", "open", [("blocks", "done")]),
        ]
        self.assertEqual([r["id"] for r in bb.find_stale_blocked(rows)], ["stale", "parent_ignored"])


class OwnerQuestionTests(unittest.TestCase):
    def test_classifier(self):
        def row(iid, title, status="open", assignee="owner", kind="task", labels=()):
            return {"id": iid, "title": title, "status": status, "assignee": assignee,
                    "issue_type": kind, "labels": list(labels)}
        rows = [
            row("plain", "Keep the rule?"),
            row("trailing_space", "Keep the rule? "),
            row("decision_human", "Q?", kind="decision", labels=["human"]),
            row("decision_no_label", "Q?", kind="decision"),
            row("label_on_task", "Q?", labels=["human"]),
            row("no_question", "Do it"),
            row("closed", "Q?", status="closed"),
            row("agent", "Q?", assignee="stackfall-implementer (sonnet)"),
            row("unassigned", "Q?", assignee=None),
        ]
        found = bb.find_owner_questions(rows, lambda a: a == "owner")
        self.assertEqual([r["id"] for r in found],
                         ["plain", "trailing_space", "decision_no_label", "label_on_task"])


class StaleInProgressTests(unittest.TestCase):
    def test_classifier(self):
        now = datetime.datetime(2026, 10, 20, 12, tzinfo=datetime.timezone.utc)
        def row(iid, status, updated, kind="task"):
            return {"id": iid, "status": status, "issue_type": kind, "updated_at": updated}
        rows = [
            row("old", "in_progress", "2026-10-14T09:00:00Z"),
            row("fresh", "in_progress", "2026-10-19T09:00:00Z"),
            row("old_epic", "in_progress", "2026-10-01T09:00:00Z", "epic"),
            row("old_open", "open", "2026-10-01T09:00:00Z"),
        ]
        self.assertEqual([r["id"] for r in bb.find_stale_in_progress(rows, now)], ["old"])


if __name__ == "__main__":
    unittest.main()
