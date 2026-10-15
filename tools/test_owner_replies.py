"""Focused tests for the owner-reply check's hook modes (Bontago-fca.125)."""

import contextlib
import io
import unittest
from unittest import mock

import owner_replies

REPLY = ("2026-10-15T20:00:00Z", "Bontago-1", "open", "Pick a map?", "Tony", "b please")


def run(argv, replies=None, error=None):
    out = io.StringIO()
    with mock.patch.object(owner_replies, "find_replies", side_effect=error, return_value=replies or []), \
            mock.patch.object(owner_replies, "_save"), contextlib.redirect_stdout(out):
        code = owner_replies.main(argv)
    return code, out.getvalue()


class RewakeTest(unittest.TestCase):
    def test_replies_wake_claude_with_exit_2(self):
        code, text = run(["--rewake"], [REPLY])
        self.assertEqual(code, 2)
        self.assertIn("NEW OWNER REPLIES", text)
        self.assertIn("Bontago-1", text)

    def test_no_replies_or_query_failure_stay_silent(self):
        self.assertEqual(run(["--rewake"]), (0, ""))
        self.assertEqual(run(["--rewake"], error=RuntimeError("database locked")), (0, ""))

    def test_plain_mode_keeps_exit_0_and_reports_failures(self):
        self.assertEqual(run([], [REPLY])[0], 0)
        code, text = run([], error=RuntimeError("database locked"))
        self.assertEqual(code, 0)
        self.assertIn("could not query Beads", text)


if __name__ == "__main__":
    unittest.main()
