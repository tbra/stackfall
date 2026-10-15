"""Tests for tools/lint_public.py."""
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_public as lp  # noqa: E402


def git(root, *args):
    subprocess.run(["git", "-C", root, *args], check=True, capture_output=True)


class LintPublicTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        git(self.root, "init", "-q")
        os.makedirs(os.path.join(self.root, "tools"))

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        full = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)

    def run_lint(self, *extra):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = lp.main(["--path", self.root, *extra])
        return code, buf.getvalue()

    def baseline(self):
        with open(os.path.join(self.root, "tools", lp.BASELINE_NAME), encoding="utf-8") as fh:
            return json.load(fh)["findings"]

    def test_clean_tree_is_green(self):
        self.write("a.gd", "# fine\nvar x := 1\n")
        code, out = self.run_lint()
        self.assertEqual(code, 0)
        self.assertIn("LINT PUBLIC GREEN", out)

    def test_findings_fail_and_allow_marker_exempts(self):
        self.write("docs/a.md", "see Bontago-abc.1\n")  # lint-public: allow fixture
        code, out = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn("LINT PUBLIC RED", out)
        self.assertIn("NEW docs/a.md: bead-id x1", out)
        self.write("docs/a.md", "see Bontago-abc.1 lint-public: allow fixture\n")
        self.assertEqual(self.run_lint()[0], 0)

    def test_skips_addons_binaries_beads_and_local_notes(self):
        for rel in ("addons/x/a.gd", ".beads/a.md", "CLAUDE.local.md"):
            self.write(rel, "# Tony Bontago-abc.1\n")  # lint-public: allow fixture
        self.write("img.png", "Tony\0")  # lint-public: allow fixture
        self.write("tools/x_baseline.json", '{"k": "Bontago-abc.1"}\n')  # lint-public: allow fixture
        self.assertEqual(self.run_lint()[0], 0)

    def test_baseline_allows_existing_and_blocks_growth(self):
        self.write("docs/a.md", "Bontago-abc.1\nBontago-abc.2\n")  # lint-public: allow fixture
        self.assertEqual(self.run_lint()[0], 1)
        self.assertEqual(self.run_lint("--init-baseline")[0], 0)
        self.assertEqual(self.baseline(), {"docs/a.md": {"bead-id": 2}})
        self.write("docs/a.md", "Bontago-abc.1\nBontago-abc.2\nBontago-abc.3\n")  # lint-public: allow fixture
        code, out = self.run_lint()
        self.assertEqual(code, 1)
        self.assertIn("(baseline 2)", out)
        # --update-baseline never raises or adds entries
        self.write("docs/b.md", "Tony\n")  # lint-public: allow fixture
        self.run_lint("--update-baseline")
        self.assertEqual(self.baseline(), {"docs/a.md": {"bead-id": 2}})

    def test_update_baseline_shrinks(self):
        self.write("docs/a.md", "Bontago-abc.1\nBontago-abc.2\n")  # lint-public: allow fixture
        self.run_lint("--init-baseline")
        self.write("docs/a.md", "Bontago-abc.1\n")  # lint-public: allow fixture
        code, out = self.run_lint()
        self.assertEqual(code, 0)
        self.assertIn("1 stale", out)
        self.run_lint("--update-baseline")
        self.assertEqual(self.baseline(), {"docs/a.md": {"bead-id": 1}})
        self.write("docs/a.md", "clean\n")
        self.run_lint("--update-baseline")
        self.assertEqual(self.baseline(), {})

    def test_tools_have_no_baseline(self):
        self.write("tools/a.py", "# Bontago-abc.1\n")  # lint-public: allow fixture
        self.run_lint("--init-baseline")
        self.assertEqual(self.baseline(), {})
        self.assertEqual(self.run_lint()[0], 1)

    def test_this_checkout_is_green(self):
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            code = lp.main(["--path", root])
        self.assertEqual(code, 0, buf.getvalue()[-2000:])


if __name__ == "__main__":
    unittest.main()
