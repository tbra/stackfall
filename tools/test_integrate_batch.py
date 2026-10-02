"""Mocked-subprocess tests for tools/integrate_batch.py.
Run: python tools/test_integrate_batch.py
"""
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import integrate_batch as ib  # noqa: E402

GREEN = "FULL GATE GREEN: 10/10 passing\n"


class Fake:
    """Scripted run_cmd: records calls, returns canned (code, text) by log name."""

    def __init__(self, overrides=None):
        self.calls = []
        self.overrides = overrides or {}

    def __call__(self, ctx, name, args, cwd, timeout):
        self.calls.append((name, list(args)))
        if name in self.overrides:
            code, text = self.overrides[name]
        elif name in ("rev_main", "rev_main2"):
            code, text = 0, "base111\n"
        elif name in ("rev_result",):
            code, text = 0, "result22\n"
        elif name == "head":
            code, text = 0, "result22\n"
        elif name == "remote":
            code, text = 0, "result22\n"
        elif name == "cur_branch":
            code, text = 0, "main\n"
        elif name == "gate":
            code, text = 0, GREEN
        elif name in ("touched", "dirty"):
            code, text = 0, ""
        else:
            code, text = 0, ""
        return code, text, "/log/" + name

    def names(self):
        return [c[0] for c in self.calls]


def args_for(**kw):
    ns = dict(branches=["wt/a", "wt/b"], beads=["B-1", "B-2"], repo="R", worktree_root="W",
              log_dir="", game_code=True, dry_run=False, no_push=False)
    ns.update(kw)
    return type("A", (), ns)()


def run(fake, **kw):
    out, res = [], {}
    err = None
    with mock.patch.object(ib, "run_cmd", fake):
        try:
            ib.integrate(args_for(**kw), ib.Ctx(tempfile.gettempdir()), out.append, res)
        except ib.StepFailed as e:
            err = e
    return err, out, res


class Tests(unittest.TestCase):
    def test_verdict_parsing(self):
        self.assertEqual(ib.parse_verdict("x\nFULL GATE GREEN: 1/1\n"), "GREEN")
        self.assertEqual(ib.parse_verdict("FULL GATE RED: 1/2\n"), "RED")
        self.assertEqual(ib.parse_verdict("FULL GATE ERROR: no tests\n"), "RED")
        self.assertEqual(ib.parse_verdict("FULL GATE RED\nFULL GATE GREEN\n"), "RED")
        self.assertEqual(ib.parse_verdict("all tests passed, no verdict"), "RED")

    def test_missing_verdict_is_red_and_stops_before_ff(self):
        fake = Fake({"gate": (0, "Totals ... exit 0 but no verdict line")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "gate")
        self.assertNotIn("ff", fake.names())
        self.assertNotIn("push", fake.names())

    def test_conflict_stops_with_files(self):
        fake = Fake({"merge_wt_b": (1, "CONFLICT"), "conflicts": (0, "a.gd\nb.gd\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "merge")
        self.assertIn("a.gd", err.detail)
        self.assertIn("merge_abort", fake.names())
        self.assertNotIn("gate", fake.names())

    def test_close_only_after_verified_push(self):
        fake = Fake()
        err, out, _ = run(fake)
        self.assertIsNone(err)
        n = fake.names()
        self.assertLess(n.index("gate"), n.index("ff"))
        self.assertLess(n.index("ff"), n.index("push"))
        self.assertLess(n.index("remote"), n.index("close_B-1"))
        self.assertLess(n.index("close_B-1"), n.index("close_B-2"))
        self.assertLess(n.index("close_B-2"), n.index("postimport"))

    def test_remote_mismatch_never_closes(self):
        fake = Fake({"remote": (0, "other999\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "push")
        self.assertFalse([x for x in fake.names() if x.startswith("close_")])

    def test_push_failure_never_closes(self):
        fake = Fake({"push": (1, "rejected")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "push")
        self.assertFalse([x for x in fake.names() if x.startswith("close_")])

    def test_dirty_touched_file_refuses_ff(self):
        fake = Fake({"touched": (0, "core/x.gd\n"), "dirty": (0, " M core/x.gd\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")
        self.assertNotIn("push", fake.names())

    def test_main_moved_refuses_ff(self):
        class Moving(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                if name == "rev_main2":
                    s.calls.append((name, args))
                    return 0, "moved000\n", "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        fake = Moving()
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")

    def test_dry_run_and_no_game_code(self):
        fake = Fake()
        err, _, _ = run(fake, dry_run=True)
        self.assertIsNone(err)
        for bad in ("ff", "push", "close_B-1"):
            self.assertNotIn(bad, fake.names())
        fake = Fake()
        run(fake, game_code=False, dry_run=True)
        self.assertNotIn("gate", fake.names())

    def test_import_issue_fails(self):
        class Imp(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                if name == "import":
                    s.calls.append((name, args))
                    return 0, "ERROR: bad thing\n", "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        err, _, _ = run(Imp())
        self.assertEqual(err.step, "import")


if __name__ == "__main__":
    unittest.main(verbosity=1)
