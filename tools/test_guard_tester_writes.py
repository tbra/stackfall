"""Tests for tools/guard_tester_writes.py.

Run: python tools/test_guard_tester_writes.py
"""
import io
import json
import os
import sys
import unittest
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guard_tester_writes as guard  # noqa: E402

REPO = "/work/repo"
WT = "/work/repo-worktrees"
SCRATCH = "/work/repo-tools/scratch"


def ok(path):
    return guard.allowed(path, REPO, WT, SCRATCH)


class GuardTesterWritesTest(unittest.TestCase):
    def test_tests_folder_of_every_checkout_kind_is_allowed(self):
        self.assertTrue(ok("/work/repo/tests/unit/blocks/test_block_bag.gd"))
        self.assertTrue(ok("\\work\\repo\\tests\\support\\Helper.gd"))
        self.assertTrue(ok("/work/repo-worktrees/net-n4/tests/unit/net/test_x.gd"))
        self.assertTrue(ok("/work/repo/.claude/worktrees/abc/tests/unit/test_y.gd"))
        self.assertTrue(ok("/WORK/REPO/tests/unit/test_case.gd"))

    def test_scratch_is_allowed(self):
        self.assertTrue(ok("/work/repo-tools/scratch/Bontago-1/log.txt"))

    def test_game_code_and_everything_else_is_denied(self):
        for path in ("/work/repo/core/blocks/BlockBag.gd", "/work/repo-worktrees/net-n4/net/Net.gd",
                     "/work/repo/.claude/worktrees/abc/game/sky/Skybox.gd", "/work/repo/tools/x.py",
                     "/work/repo/testsuite/a.gd", "/work/repo/tests", "/work/elsewhere/tests/a.gd",
                     "/work/repo/tests/../core/BlockBag.gd", "/work/repo/CLAUDE.md"):
            self.assertFalse(ok(path), path)

    def test_hook_denies_with_a_reason_and_passes_silently(self):
        def run(path):
            buf = io.StringIO()
            event = {"tool_input": {"file_path": path}}
            with mock.patch.object(sys, "stdin", io.StringIO(json.dumps(event))), redirect_stdout(buf), \
                    mock.patch.object(guard, "allowed", lambda p: p.endswith("_test_ok")):
                self.assertEqual(guard.main(), 0)
            return buf.getvalue()
        self.assertEqual(run("x_test_ok"), "")
        out = json.loads(run("/work/repo/core/A.gd"))["hookSpecificOutput"]
        self.assertEqual(out["permissionDecision"], "deny")
        self.assertIn("report the boundary", out["permissionDecisionReason"])


if __name__ == "__main__":
    unittest.main()
