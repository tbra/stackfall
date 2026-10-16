import os
import unittest
from unittest import mock

import repo_paths as rp


class RepoPathsTest(unittest.TestCase):
    def test_defaults_are_siblings_of_main_repo(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop(rp.WORKTREES_ENV, None)
            os.environ.pop(rp.TOOLS_ROOT_ENV, None)
            main = rp.main_repo()
            parent = str(main.parent).replace("\\", "/").rstrip("/")
            self.assertEqual(rp.worktrees_root(), parent + "/" + main.name + "-worktrees")
            self.assertEqual(rp.tools_root(), parent + "/" + main.name + "-tools")
            self.assertEqual(rp.scratch_root(), rp.tools_root() + "/scratch")

    def test_env_overrides(self):
        with mock.patch.dict(os.environ, {rp.WORKTREES_ENV: "/w", rp.TOOLS_ROOT_ENV: "/t"}):
            self.assertEqual(rp.worktrees_root(), "/w")
            self.assertEqual(rp.tools_root(), "/t")
            self.assertEqual(rp.locks_dir(), "/t/locks/godot_slots")

    def test_agent_checkout(self):
        with mock.patch.dict(os.environ, {rp.WORKTREES_ENV: "/nowhere/wts"}):
            self.assertTrue(rp.is_agent_checkout(rp.repo_dir() + "/sub"))
            self.assertTrue(rp.is_agent_checkout("/nowhere/wts/x"))
            self.assertFalse(rp.is_agent_checkout("/elsewhere/x"))


if __name__ == "__main__":
    unittest.main()
