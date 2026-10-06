"""Tests for tools/prune_worktrees.py on a temporary git repo.
Run: python tools/test_prune_worktrees.py
"""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prune_worktrees as pw  # noqa: E402


def g(cwd, *a):
    subprocess.run(["git", "-C", cwd, *a], check=True, capture_output=True, text=True)


class PruneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "main").replace("\\", "/")
        os.makedirs(self.repo)
        g(self.repo, "init", "-b", "main")
        g(self.repo, "config", "user.email", "t@t")
        g(self.repo, "config", "user.name", "t")
        self.write(self.repo, "a.txt", "1")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "init")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, d, name, text):
        with open(os.path.join(d, name), "w") as fh:
            fh.write(text)

    def add_wt(self, branch, commit=False):
        path = os.path.join(self.tmp.name, branch.replace("/", "_")).replace("\\", "/")
        g(self.repo, "worktree", "add", "-b", branch, path)
        if commit:
            self.write(path, "b.txt", "x")
            g(path, "add", "-A")
            g(path, "commit", "-m", "work")
        return path

    def branches(self):
        return subprocess.run(["git", "-C", self.repo, "branch", "--format=%(refname:short)"],
                              capture_output=True, text=True).stdout.split()

    def run_prune(self, apply=True, **kw):
        return pw.prune(self.repo, apply=apply, say=lambda s: None, **kw)

    def test_merged_clean_removed_and_branch_deleted(self):
        p = self.add_wt("wt/a")
        c = self.run_prune()
        self.assertEqual(c["removed"], 1)
        self.assertFalse(os.path.exists(p))
        self.assertNotIn("wt/a", self.branches())

    def test_modified_tracked_kept(self):
        p = self.add_wt("wt/a")
        self.write(p, "a.txt", "changed")
        c = self.run_prune()
        self.assertEqual((c["removed"], c["kept_dirty"]), (0, 1))
        self.assertTrue(os.path.exists(p))
        self.assertIn("wt/a", self.branches())

    def test_untracked_non_sidecar_kept(self):
        p = self.add_wt("wt/a")
        self.write(p, "notes.txt", "x")
        self.assertEqual(self.run_prune()["kept_dirty"], 1)
        self.assertTrue(os.path.exists(p))

    def test_untracked_sidecars_removed(self):
        p = self.add_wt("wt/a")
        self.write(p, "x.png.import", "x")
        self.write(p, "x.gd.uid", "x")
        self.assertEqual(self.run_prune()["removed"], 1)
        self.assertFalse(os.path.exists(p))

    def test_unmerged_kept(self):
        p = self.add_wt("wt/a", commit=True)
        c = self.run_prune()
        self.assertEqual((c["removed"], c["kept_unmerged"]), (0, 1))
        self.assertTrue(os.path.exists(p))
        self.assertIn("wt/a", self.branches())

    def test_protected_kept(self):
        p = self.add_wt("codex/job")
        c = self.run_prune()
        self.assertEqual((c["removed"], c["protected"]), (0, 1))
        self.assertTrue(os.path.exists(p))

    def test_dry_run_changes_nothing(self):
        p = self.add_wt("wt/a")
        c = self.run_prune(apply=False)
        self.assertEqual(c["removed"], 1)
        self.assertTrue(os.path.exists(p))
        self.assertIn("wt/a", self.branches())

    def test_branches_filter(self):
        a, b = self.add_wt("wt/a"), self.add_wt("wt/b")
        c = self.run_prune(branches=["wt/a"])
        self.assertEqual(c["removed"], 1)
        self.assertFalse(os.path.exists(a))
        self.assertTrue(os.path.exists(b))


if __name__ == "__main__":
    unittest.main()
