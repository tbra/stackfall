"""Tests for godot_exe.py (no Godot launched): python -I tools/test_godot_exe.py"""
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import godot_exe  # noqa: E402

SHIM_VAR = "STACKFALL_TEST_GODOT_DIR"


class ResolveTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        self.real_dir = os.path.join(self.root, "real install")
        os.makedirs(self.real_dir)
        self.real_exe = os.path.join(self.real_dir, "Godot_test_console.exe")
        with open(self.real_exe, "w") as f:
            f.write("")
        self.bin_dir = os.path.join(self.root, "bin")
        os.makedirs(self.bin_dir)

    def tearDown(self):
        self.tmp.cleanup()

    def _env(self, **extra):
        env = {k: v for k, v in os.environ.items() if k not in ("GODOT", SHIM_VAR)}
        env["PATH"] = self.bin_dir
        env.update(extra)
        return env

    def test_env_godot_wins(self):
        with mock.patch.dict(os.environ, self._env(GODOT=self.real_exe), clear=True):
            self.assertEqual(godot_exe.resolve(), self.real_exe)

    def test_env_godot_missing_file_falls_through(self):
        missing = os.path.join(self.root, "nope.exe")
        with mock.patch.dict(os.environ, self._env(GODOT=missing), clear=True):
            self.assertEqual(godot_exe.resolve(), "godot")

    def test_cmd_shim_resolves_quoted_expandvars_exe(self):
        shim = os.path.join(self.bin_dir, "godot.cmd")
        with open(shim, "w") as f:
            f.write('@echo off\r\n"%%%s%%\\Godot_test_console.exe" %%*\r\n' % SHIM_VAR)
        env = self._env(**{SHIM_VAR: self.real_dir})
        with mock.patch.dict(os.environ, env, clear=True):
            # name carries the suffix so which() finds the shim on any OS
            self.assertEqual(os.path.normcase(godot_exe.resolve("godot.cmd")),
                             os.path.normcase(self.real_exe))

    def test_cmd_shim_with_missing_target_returns_shim(self):
        shim = os.path.join(self.bin_dir, "godot.cmd")
        with open(shim, "w") as f:
            f.write('@echo off\r\n"%%%s%%\\absent.exe" %%*\r\n' % SHIM_VAR)
        env = self._env(**{SHIM_VAR: self.real_dir})
        with mock.patch.dict(os.environ, env, clear=True):
            self.assertEqual(godot_exe.resolve("godot.cmd"), shim)

    def test_plain_exe_on_path(self):
        exe = os.path.join(self.bin_dir, "godot.exe")
        with open(exe, "w") as f:
            f.write("")
        with mock.patch.dict(os.environ, self._env(), clear=True):
            self.assertEqual(os.path.normcase(godot_exe.resolve("godot")),
                             os.path.normcase(exe))

    def test_nothing_found_returns_name(self):
        with mock.patch.dict(os.environ, self._env(), clear=True):
            self.assertEqual(godot_exe.resolve("godot_not_installed_xyz"), "godot_not_installed_xyz")

    def test_default_name_when_nothing_found(self):
        with mock.patch.dict(os.environ, self._env(), clear=True):
            self.assertEqual(godot_exe.resolve(), "godot")


if __name__ == "__main__":
    unittest.main()
