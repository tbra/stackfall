"""Classifier checks for board_brief's stale-blocked section."""

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


if __name__ == "__main__":
    unittest.main()
