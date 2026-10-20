"""Tests for tools/guard_reviewer_bash.py. Run: python -m unittest tools.test_guard_reviewer_bash"""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import guard_reviewer_bash as g  # noqa: E402
import repo_paths  # noqa: E402

R = repo_paths.repo_dir()
W = repo_paths.worktrees_root()

RUN = "powershell -NoProfile -File tools/run_gut.ps1 "


class GuardReviewerBashTest(unittest.TestCase):
    def test_gut_run_allowed_forms(self):
        for cmd in [RUN + "test_net_session",
                    RUN + "test_net_session,test_steam_client",
                    RUN + f"test_a -Path {W}/x",
                    RUN + "test_a -Unit test_one",
                    RUN + f"test_a,test_b -Path {W}/x -Unit test_one",
                    RUN + f"test_a -Unit test_one -Path {W}/x"]:
            self.assertTrue(g.allowed(cmd), cmd)
            self.assertTrue(g.is_gut_run(cmd), cmd)

    def test_gut_run_denied_forms(self):
        for cmd in [RUN + "test_*", RUN + "*", RUN + "", RUN + "net_session", RUN + "test_a,",
                    RUN + "test_a -Dir res://tests", RUN + "test_a -gdir=res://tests",
                    RUN + "test_a -gselect=x", RUN + "test_a -Godot evil.exe",
                    RUN + f"test_a -Path /other/x", RUN + f"test_a -Path {W}/x -Path {W}/y",
                    RUN + "test_a; rm -rf x", RUN + "test_a && echo hi", RUN + "test_a | cat",
                    RUN + "test_a > out.txt", RUN + "test_a $(x)", RUN + "test_a `x`",
                    RUN + "test_a -Unit 'x y'", RUN + f"test_a -Path {W}/x/../..;x",
                    "powershell -File tools/run_gut.ps1 test_a",
                    "powershell -NoProfile -File tools/other.ps1 test_a",
                    "powershell -NoProfile -File tools/run_gut.ps1 test_a\n",
                    "powershell -NoProfile -Command tools/run_gut.ps1 test_a",
                    "godot --headless --path . -s addons/gut/gut_cmdln.gd",
                    "python tools/full_gate.py"]:
            self.assertFalse(g.allowed(cmd), repr(cmd))

    def test_existing_forms_unchanged(self):
        self.assertTrue(g.allowed(f'bd -C {R} comments add Bontago-1.2 --actor stackfall-reviewer "ok; fine"'))
        self.assertTrue(g.allowed(f"bd -C {R} show Bontago-1 --json"))
        self.assertTrue(g.allowed(f"git -C {R} log -n5"))
        self.assertFalse(g.allowed(f"git -C {R} log --output=x"))
        self.assertFalse(g.allowed(f"bd -C {R} close Bontago-1"))
        self.assertFalse(g.allowed("ls | cat"))
        self.assertFalse(g.allowed(None))
        self.assertFalse(g.is_gut_run(f"git -C {R} log"))

    def test_read_only_python_tools(self):
        for cmd in (f"python tools/check_packages.py plans/net_packages.json --path {R}",
                    "python tools/lint_dead.py --report", "python tools/lint_all.py",
                    "python tools/dep_graph.py --callers SnapshotSync.host_tick",
                    "python tools/affected_tests.py net/SnapshotSync.gd --json"):
            self.assertTrue(g.allowed(cmd), cmd)
        for cmd in ("python tools/lint_dead.py --update-baseline", "python tools/dep_graph.py --update",
                    "python tools/dep_graph.py --out x.json", "python tools/dep_graph.py --allow-new a.gd",
                    "python tools/lint_all.py --path ../x", "python tools/mutate_core.py core/a.gd",
                    "python tools/lint_all.py; rm x", "python tools/lint_all.py > out.txt",
                    "python -c print(1)"):
            self.assertFalse(g.allowed(cmd), cmd)

    def test_counter_caps_at_two_per_agent(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual([g.count_run("agentA", d) for _ in range(3)], [1, 2, 3])
            self.assertEqual(g.count_run("agentB", d), 1)
            self.assertIsNone(g.count_run(None, d))
            self.assertIsNone(g.count_run("bad/../id", d))
            self.assertEqual(g.RUN_CAP, 2)


if __name__ == "__main__":
    unittest.main()
