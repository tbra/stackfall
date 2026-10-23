"""Tests for the lint_all lint slot: python -m unittest tools.test_lint_all"""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import godot_slots  # noqa: E402
import lint_all  # noqa: E402

DEAD_PID = 2 ** 22 + 12345


class LintSlotTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.gtmp = tempfile.TemporaryDirectory()
        self.over = {"STACKFALL_LINT_SLOTS_DIR": self.tmp.name, "STACKFALL_LINT_SLOTS": "2",
                     "STACKFALL_GODOT_SLOTS_DIR": self.gtmp.name, "STACKFALL_GODOT_SLOTS": "1",
                     "STACKFALL_GODOT_SLOTS_CPU": "0"}
        self.old = {k: os.environ.get(k) for k in self.over}
        os.environ.update(self.over)

    def tearDown(self):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()
        self.gtmp.cleanup()

    def test_cap_respected(self):
        a = lint_all.acquire_lint_slot(0)
        b = lint_all.acquire_lint_slot(0)
        self.assertNotEqual(a, b)
        with self.assertRaises(TimeoutError):
            lint_all.acquire_lint_slot(0.1)
        lint_all.release_lint_slot(a)
        self.assertEqual(lint_all.acquire_lint_slot(0), a)

    def test_dead_pid_reclaimed(self):
        self.assertTrue(godot_slots._try_take(self.tmp.name, 0, DEAD_PID, "x"))
        self.assertTrue(godot_slots._try_take(self.tmp.name, 1, DEAD_PID, "x"))
        self.assertIn(lint_all.acquire_lint_slot(0), (0, 1))

    def test_godot_gate_and_slots_do_not_block(self):
        with godot_slots.godot_exclusive("t", wait_s=1):
            self.assertIsNotNone(lint_all.acquire_lint_slot(0))
        self.assertTrue(godot_slots._try_take(self.gtmp.name, 0, os.getpid(), "g"))
        self.assertIsNotNone(lint_all.acquire_lint_slot(0))
        self.assertEqual(godot_slots.busy_count(self.gtmp.name), 1)

    def test_timeout_is_red(self):
        os.environ["STACKFALL_LINT_SLOTS"] = "1"
        os.environ["STACKFALL_GODOT_SLOTS_WAIT"] = "0.1"
        lint_all.acquire_lint_slot(0)
        self.assertEqual(lint_all.main(["--path", HERE]), 1)


if __name__ == "__main__":
    unittest.main()
