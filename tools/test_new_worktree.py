"""Tests for tools/new_worktree.py on a temporary git repo.
Run: python -m unittest tools.test_new_worktree   (or python tools/test_new_worktree.py)
"""
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import new_worktree as nw  # noqa: E402


def g(cwd, *a):
    return subprocess.run(["git", "-C", cwd, *a], check=True, capture_output=True, text=True).stdout.strip()


class NewWorktreeTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "main")
        os.makedirs(self.repo)
        g(self.repo, "init", "-b", "main")
        g(self.repo, "config", "user.email", "t@t")
        g(self.repo, "config", "user.name", "t")
        with open(os.path.join(self.repo, "project.godot"), "w") as fh:
            fh.write("config_version=5\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "init")
        self.root = os.path.join(self.tmp.name, "wts")

    def tearDown(self):
        self.tmp.cleanup()

    def test_creates_worktree_branch_and_override(self):
        path, branch, sha = nw.create("feat", self.repo, root=self.root)
        self.assertEqual(branch, "wt/feat")
        self.assertTrue(os.path.isfile(os.path.join(path, "override.cfg")))
        self.assertEqual(g(self.repo, "rev-parse", "--short", "wt/feat"), sha)
        self.assertEqual(g(self.repo, "rev-parse", "--short", "main"), sha)

    def test_default_root_is_sibling_of_repo(self):
        path, _, _ = nw.create("feat2", self.repo)
        self.assertEqual(os.path.normcase(os.path.realpath(os.path.dirname(path))),
                         os.path.normcase(os.path.realpath(os.path.join(self.tmp.name, "Bontago-worktrees"))))

    def test_refusals(self):
        nw.create("feat", self.repo, root=self.root)
        with self.assertRaises(ValueError):
            nw.create("feat", self.repo, branch="wt/other", root=self.root)  # path exists
        with self.assertRaises(ValueError):
            nw.create("fresh", self.repo, branch="wt/feat", root=self.root)  # branch exists
        with self.assertRaises(ValueError):
            nw.create("main", self.repo, root=self.tmp.name)  # main checkout path
        with self.assertRaises(ValueError):
            nw.create("x", self.repo, base="nope", root=self.root)  # bad base

    def test_cli_line(self):
        out = subprocess.run([sys.executable, nw.__file__, "cli", "--repo", self.repo, "--root", self.root, "--no-import"],
                             capture_output=True, text=True).stdout
        self.assertTrue(out.startswith("worktree "))
        self.assertIn("branch wt/cli base ", out)

    def _run(self, **kw):
        with mock.patch.object(nw.subprocess, "run", **kw) as m:
            return nw.import_project("P"), m

    def test_import_ok_uses_godot_env_and_flags(self):
        with mock.patch.dict(os.environ, {"GODOT": "G"}):
            res, m = self._run(return_value=mock.Mock(returncode=0))
        self.assertEqual(res, "ok")
        self.assertEqual(m.call_args[0][0], ["G", "--headless", "--editor", "--path", "P", "--quit"])
        self.assertEqual(m.call_args[1]["timeout"], 600)

    def test_import_failed_and_timeout(self):
        self.assertEqual(self._run(return_value=mock.Mock(returncode=3))[0], "failed(3)")
        self.assertEqual(self._run(side_effect=subprocess.TimeoutExpired("g", 600))[0], "timeout")

    def test_main_prints_import_and_no_import_skips(self):
        argv = ["m1", "--repo", self.repo, "--root", self.root]
        with mock.patch.object(nw, "import_project", return_value="failed(1)") as imp, \
                mock.patch("builtins.print") as pr:
            self.assertEqual(nw.main(argv), 0)
        imp.assert_called_once()
        pr.assert_any_call("import failed(1)")
        self.assertTrue(os.path.isdir(os.path.join(self.root, "m1")))  # kept on failure
        with mock.patch.object(nw, "import_project") as imp:
            nw.main(["m2", "--repo", self.repo, "--root", self.root, "--no-import"])
        imp.assert_not_called()


if __name__ == "__main__":
    unittest.main()
