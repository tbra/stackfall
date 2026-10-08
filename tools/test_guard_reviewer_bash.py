"""Tests for tools/guard_reviewer_bash.py (Bontago-fca.55). Run: python -m unittest tools.test_guard_reviewer_bash"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guard_reviewer_bash as g  # noqa: E402

RUN = "powershell -NoProfile -File tools/run_gut.ps1 "


class GuardReviewerBashTest(unittest.TestCase):
    def test_gut_run_allowed_forms(self):
        for cmd in [RUN + "test_net_session",
                    RUN + "test_net_session,test_steam_client",
                    RUN + "test_a -Path M:/Bontago-worktrees/x",
                    RUN + "test_a -Unit test_one",
                    RUN + "test_a,test_b -Path M:/Bontago-worktrees/x -Unit test_one",
                    RUN + "test_a -Unit test_one -Path M:/Bontago-worktrees/x"]:
            self.assertTrue(g.allowed(cmd), cmd)
            self.assertTrue(g.is_gut_run(cmd), cmd)

    def test_gut_run_denied_forms(self):
        for cmd in [RUN + "test_*", RUN + "*", RUN + "", RUN + "net_session", RUN + "test_a,",
                    RUN + "test_a -Dir res://tests", RUN + "test_a -gdir=res://tests",
                    RUN + "test_a -gselect=x", RUN + "test_a -Godot evil.exe",
                    RUN + "test_a -Path C:/x", RUN + "test_a -Path M:/x -Path M:/y",
                    RUN + "test_a; rm -rf x", RUN + "test_a && echo hi", RUN + "test_a | cat",
                    RUN + "test_a > out.txt", RUN + "test_a $(x)", RUN + "test_a `x`",
                    RUN + "test_a -Unit 'x y'", RUN + "test_a -Path M:/x/../..;x",
                    "powershell -File tools/run_gut.ps1 test_a",
                    "powershell -NoProfile -File tools/other.ps1 test_a",
                    "powershell -NoProfile -File tools/run_gut.ps1 test_a\n",
                    "powershell -NoProfile -Command tools/run_gut.ps1 test_a",
                    "godot --headless --path . -s addons/gut/gut_cmdln.gd",
                    "python tools/full_gate.py"]:
            self.assertFalse(g.allowed(cmd), repr(cmd))

    def test_existing_forms_unchanged(self):
        self.assertTrue(g.allowed('bd -C M:/Bontago comments add Bontago-1.2 --actor stackfall-reviewer "ok; fine"'))
        self.assertTrue(g.allowed("bd -C M:/Bontago show Bontago-1 --json"))
        self.assertTrue(g.allowed("git -C M:/Bontago log -n5"))
        self.assertFalse(g.allowed("git -C M:/Bontago log --output=x"))
        self.assertFalse(g.allowed("bd -C M:/Bontago close Bontago-1"))
        self.assertFalse(g.allowed("ls | cat"))
        self.assertFalse(g.allowed(None))
        self.assertFalse(g.is_gut_run("git -C M:/Bontago log"))

    def test_counter_caps_at_two_per_agent(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual([g.count_run("agentA", d) for _ in range(3)], [1, 2, 3])
            self.assertEqual(g.count_run("agentB", d), 1)
            self.assertIsNone(g.count_run(None, d))
            self.assertIsNone(g.count_run("bad/../id", d))
            self.assertEqual(g.RUN_CAP, 2)


if __name__ == "__main__":
    unittest.main()
