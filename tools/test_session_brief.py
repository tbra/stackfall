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


if __name__ == "__main__":
    unittest.main()
