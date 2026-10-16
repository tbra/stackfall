"""Focused tests for tools/archive_beads.py (no bd process)."""
import datetime
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import archive_beads as ab  # noqa: E402

NOW = datetime.datetime(2026, 10, 16, 12, 0, tzinfo=datetime.timezone.utc)


def rec(rid, status="closed", closed_at=None, **extra):
    out = {"id": rid, "status": status}
    if closed_at is not None:
        out["closed_at"] = closed_at
    out.update(extra)
    return out


class DueTest(unittest.TestCase):
    def test_only_closed_unpinned_beads_past_the_cutoff(self):
        records = [
            rec("old", closed_at="2026-10-01T10:00:00Z"),
            rec("edge", closed_at="2026-10-09T12:00:00Z"),
            rec("fresh", closed_at="2026-10-15T09:00:00Z"),
            rec("open", status="open", closed_at="2026-09-01T00:00:00Z"),
            rec("pinned", closed_at="2026-09-01T00:00:00Z", pinned=True),
            rec("undated"),
        ]
        self.assertEqual([r["id"] for r in ab.due(records, 7, NOW)], ["old", "edge"])

    def test_nanosecond_and_offset_timestamps_parse(self):
        self.assertIsNotNone(ab.parse_time("2026-10-01T10:00:00.123456789Z"))
        self.assertEqual(ab.parse_time("2026-10-01T12:00:00+02:00"), ab.parse_time("2026-10-01T10:00:00Z"))
        self.assertIsNone(ab.parse_time("not a date"))


class ArchiveFileTest(unittest.TestCase):
    def test_append_keeps_one_line_per_id(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "archive", "closed.jsonl")
            self.assertEqual(ab.append_archive(path, [rec("a"), rec("b")]), 2)
            self.assertEqual(ab.append_archive(path, [rec("b"), rec("c")]), 1)
            with open(path, encoding="utf-8") as fh:
                ids = [json.loads(line)["id"] for line in fh]
            self.assertEqual(ids, ["a", "b", "c"])


if __name__ == "__main__":
    unittest.main()
