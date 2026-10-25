"""Unit tests for tools/session_brief.py (handover memories in the SessionStart hook)."""
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import session_brief  # noqa: E402


def _proc(payload):
    return subprocess.CompletedProcess([], 0, stdout=json.dumps(payload), stderr="")


class ReadMemoryTest(unittest.TestCase):
    def test_returns_text(self):
        with mock.patch.object(session_brief.shutil, "which", return_value="bd"), \
                mock.patch.object(session_brief.subprocess, "run",
                                  return_value=_proc({"k": "hello"})):
            self.assertEqual(session_brief.read_memory("k"), "hello")

    def test_missing_key_is_none(self):
        with mock.patch.object(session_brief.shutil, "which", return_value="bd"), \
                mock.patch.object(session_brief.subprocess, "run", return_value=_proc({})):
            self.assertEqual(session_brief.read_memory("k"), "none")

    def test_truncates_long_text(self):
        long_text = "x" * (session_brief.MAX_MEMORY_CHARS + 50)
        with mock.patch.object(session_brief.shutil, "which", return_value="bd"), \
                mock.patch.object(session_brief.subprocess, "run",
                                  return_value=_proc({"k": long_text})):
            out = session_brief.read_memory("k")
        self.assertTrue(out.startswith("x" * session_brief.MAX_MEMORY_CHARS))
        self.assertIn("truncated", out)

    def test_bd_missing_never_raises(self):
        with mock.patch.object(session_brief.shutil, "which", return_value=None):
            self.assertIn("UNAVAILABLE", session_brief.read_memory("k"))

    def test_bad_json_never_raises(self):
        bad = subprocess.CompletedProcess([], 1, stdout="not json", stderr="")
        with mock.patch.object(session_brief.shutil, "which", return_value="bd"), \
                mock.patch.object(session_brief.subprocess, "run", return_value=bad):
            self.assertIn("UNAVAILABLE", session_brief.read_memory("k"))


class DiskLineTest(unittest.TestCase):
    def _usage(self, free_gb):
        return mock.Mock(free=free_gb * 1e9)

    def test_reports_free_space(self):
        with mock.patch.object(session_brief.shutil, "disk_usage", return_value=self._usage(35)):
            line = session_brief.disk_line()
        self.assertIn("35 GB free", line)
        self.assertNotIn("LOW DISK", line)

    def test_warns_when_low(self):
        with mock.patch.object(session_brief.shutil, "disk_usage",
                               return_value=self._usage(session_brief.LOW_DISK_GB - 1)):
            self.assertIn("LOW DISK", session_brief.disk_line())

    def test_error_never_raises(self):
        with mock.patch.object(session_brief.shutil, "disk_usage", side_effect=OSError):
            self.assertIn("UNAVAILABLE", session_brief.disk_line())


if __name__ == "__main__":
    unittest.main()
