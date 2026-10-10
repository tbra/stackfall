"""Tests for tools/probe_lint.py on a temporary git repo. Run: python tools/test_probe_lint.py"""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import probe_lint as pl  # noqa: E402


def g(cwd, *a):
    return subprocess.run(["git", "-C", cwd, *a], check=True, capture_output=True, text=True).stdout.strip()


class ProbeLintTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        g(self.repo, "init", "-b", "main")
        g(self.repo, "config", "user.email", "t@t")
        g(self.repo, "config", "user.name", "t")
        self.write("tools/screenshot_old.gd")  # grandfathered
        self.write("tools/probe_allowlist.txt", "# header\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "init")
        g(self.repo, "checkout", "-b", "wt/x")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text="x\n"):
        p = os.path.join(self.repo, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(text)

    def commit(self):
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "work")

    def test_patterns(self):
        for ok in ("tools/screenshot_a.gd", "tools/capture_b.tscn", "tools/my_probe.gd.uid",
                   "tools/foo_probe.sh", "tools/_scratch_bob/a.gd", "tools/_scratch/x/y.tscn"):
            self.assertTrue(pl.is_probe(ok), ok)
        for no in ("tools/probe_lint.py", "tools/integrate_batch.py", "core/probe_x.gd", "tests/x.gd"):
            self.assertFalse(pl.is_probe(no), no)

    def test_added_files_flagged_existing_grandfathered(self):
        self.write("tools/screenshot_old.gd", "changed\n")  # modified, not added
        for f in ("tools/capture_new.gd", "tools/_scratch_w/a.gd"):
            self.write(f)
            self.write(f + ".uid")
        self.write("tools/ok_tool.py")
        self.commit()
        self.assertEqual(sorted(pl.new_probe_files(self.repo, "main", "HEAD")),
                         ["tools/_scratch_w/a.gd", "tools/_scratch_w/a.gd.uid",
                          "tools/capture_new.gd", "tools/capture_new.gd.uid"])

    def test_allowlist(self):
        self.write("tools/probe_allowlist.txt", "# header\ntools/capture_keep*\n")
        for f in ("tools/capture_keep.gd", "tools/capture_drop.gd"):
            self.write(f)
            self.write(f + ".uid")
        self.commit()
        self.assertEqual(pl.new_probe_files(self.repo, "main", "HEAD"),
                         ["tools/capture_drop.gd", "tools/capture_drop.gd.uid"])

    def test_untracked_mode_and_cli(self):
        self.write("tools/new_probe.gd")
        self.write("tools/new_probe.gd.uid")
        self.assertEqual(pl.untracked_probe_files(self.repo), ["tools/new_probe.gd", "tools/new_probe.gd.uid"])
        self.assertEqual(pl.main(["--path", self.repo, "--untracked"]), 1)
        self.assertEqual(pl.main(["--path", self.repo, "--base", "main", "--head", "HEAD"]), 0)
        os.remove(os.path.join(self.repo, "tools", "new_probe.gd"))
        os.remove(os.path.join(self.repo, "tools", "new_probe.gd.uid"))
        self.assertEqual(pl.main(["--path", self.repo, "--untracked"]), 0)

    def test_branch_script_without_uid_flagged(self):
        self.write("core/foo.gd")
        self.write("shaders/s.gdshader")
        self.write("shaders/s.gdshader.uid")
        self.write("shaders/i.gdshaderinc")
        self.commit()
        found = pl.new_probe_files(self.repo, "main", "HEAD")
        self.assertEqual(len(found), 2)
        self.assertIn("core/foo.gd", found[0] + found[1])
        self.assertIn("core/foo.gd.uid", found[0] + found[1])
        self.assertIn("shaders/i.gdshaderinc", found[0] + found[1])
        self.assertEqual(pl.main(["--path", self.repo, "--base", "main", "--head", "HEAD"]), 1)

    def test_branch_script_with_uid_clean(self):
        self.write("core/foo.gd")
        self.write("core/foo.gd.uid")
        self.commit()
        self.assertEqual(pl.new_probe_files(self.repo, "main", "HEAD"), [])

    def test_untracked_mode_uid_rules(self):
        self.write("core/foo.gd")  # untracked script, no uid
        self.assertEqual(len(pl.untracked_probe_files(self.repo)), 1)
        self.write("core/foo.gd.uid")  # both untracked: fine
        self.assertEqual(pl.untracked_probe_files(self.repo), [])
        g(self.repo, "add", "core/foo.gd")  # script staged, uid still untracked
        found = pl.untracked_probe_files(self.repo)
        self.assertEqual(len(found), 1)
        self.assertIn("untracked", found[0])


if __name__ == "__main__":
    unittest.main()
