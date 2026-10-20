"""Tests for tools/lint_shortcuts.py on small temp-dir fixture repos.

Run: python tools/test_lint_shortcuts.py
"""
import io
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_shortcuts as lint  # noqa: E402

MARK = "# " + "SHORTCUT: "


def make_repo(files):
    tmp = tempfile.TemporaryDirectory()
    for rel, text in files.items():
        path = os.path.join(tmp.name, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    return tmp


def run(argv):
    buf = io.StringIO()
    with redirect_stdout(buf):
        code = lint.main(argv)
    return code, buf.getvalue()


class LintShortcutsTest(unittest.TestCase):
    def test_trigger_required(self):
        with make_repo({
            "game/a.gd": "var x := 1\n" + MARK + "linear scan, use a grid past 500 blocks\n",
            "game/b.gd": "\t" + MARK + "no pooling\n",
            "shaders/s.gdshader": "// " + "SHORTCUT: one light, add more when the sky needs it\n",
        }) as root:
            code, out = run(["--path", root])
        self.assertEqual(code, 1)
        self.assertIn("game/b.gd:1: no pooling [no-trigger]", out)
        self.assertNotIn("game/a.gd", out)
        self.assertIn("LINT SHORTCUTS RED: 3 markers, 1 with no trigger", out)

    def test_list_and_skips(self):
        with make_repo({
            "core/a.gd": MARK + "fixed seed, randomise when bots ship\n",
            "addons/x.gd": MARK + "vendored\n",
            "tests/unit/t.gd": MARK + "fixture\n",
            "tools/test_x.py": MARK + "fixture\n",
            "docs/n.md": MARK + "prose\n",
        }) as root:
            code, out = run(["--path", root, "--list"])
        self.assertEqual(code, 0)
        self.assertIn("core/a.gd:1: fixed seed, randomise when bots ship", out)
        self.assertIn("LINT SHORTCUTS GREEN: 1 markers, 0 with no trigger", out)

    def test_added_since_rev(self):
        with make_repo({"game/a.gd": "var a := 1\n" + MARK + "old one, later\n"}) as root:
            git = ["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t"]
            subprocess.run(git[:3] + ["init", "-q"], check=True)
            subprocess.run(git + ["add", "-A"], check=True)
            subprocess.run(git + ["commit", "-qm", "base"], check=True)
            with open(os.path.join(root, "game", "a.gd"), "a", encoding="utf-8", newline="\n") as fh:
                fh.write("var b := 2\n" + MARK + "new one, when it hurts\n")
            code, out = run(["--path", root, "--added", "HEAD"])
        self.assertEqual(code, 0)
        self.assertIn("game/a.gd:4: new one, when it hurts", out)
        self.assertNotIn("old one", out)


if __name__ == "__main__":
    unittest.main()
