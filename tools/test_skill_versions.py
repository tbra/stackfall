"""Focused tests for the project skill version inventory."""

import subprocess
import sys
import unittest
from pathlib import Path

from tools.skill_versions import ROOT, SKILLS, list_versions, read_version


SCRIPT = Path(__file__).resolve().parent / "skill_versions.py"


class SkillVersionTests(unittest.TestCase):
    def test_every_project_skill_has_a_version(self):
        for name in SKILLS:
            self.assertRegex(read_version(name, ROOT), r"^\d+\.\d+\.\d+$")
        self.assertEqual(len(list_versions(ROOT).split()), len(SKILLS))

    def test_check_detects_stale_loaded_definition(self):
        result = subprocess.run([sys.executable, str(SCRIPT), "--check", SKILLS[0], "0.0.0"],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertIn("STALE", result.stdout)

    def test_current_version_passes(self):
        name = SKILLS[0]
        result = subprocess.run([sys.executable, str(SCRIPT), "--check", name, read_version(name)],
                                capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0)
        self.assertIn("disk verified", result.stdout)


if __name__ == "__main__":
    unittest.main()
