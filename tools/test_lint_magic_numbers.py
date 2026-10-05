"""Tests for tools/lint_magic_numbers.py. Run: python tools/test_lint_magic_numbers.py"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_magic_numbers as lm  # noqa: E402


class LintTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        os.makedirs(os.path.join(self.root, "tools"))
        self.bfile = os.path.join(self.root, "tools", lm.BASELINE_NAME)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        full = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(text)

    def run_lint(self, *extra):
        return lm.main(["--path", self.root, *extra])

    def baseline(self):
        with open(self.bfile, encoding="utf-8") as fh:
            return json.load(fh)

    def test_counting_rules(self):
        text = ('const A := 7\nenum E { X = 9 }\n@export var v: float = 3.5\n'
                'var a := 0.5 + 2 + 1.0  # 99\nvar s := "12 # 34"\nvar t := \'56\'\n'
                'var x := 3 + 4.25 - 1\n')
        self.assertEqual(lm.count_text(text), 2)

    def test_pass_growth_new_file_and_update(self):
        self.write("a.gd", "var x := 3\nvar y := 4\n")
        self.assertEqual(self.run_lint("--update"), 0)
        self.assertEqual(self.baseline(), {"a.gd": 2})
        self.assertEqual(self.run_lint(), 0)
        # excluded dirs are ignored
        self.write("tests/t.gd", "var z := 77\n")
        self.assertEqual(self.run_lint(), 0)
        # growth fails
        self.write("a.gd", "var x := 3\nvar y := 4\nvar w := 5\n")
        self.assertEqual(self.run_lint(), 1)
        # --update never raises a baseline
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {"a.gd": 2})
        # downward update; a new file fails and is not admitted without --allow-new
        self.write("a.gd", "var x := 3\n")
        self.write("b.gd", "var q := 8\n")
        self.assertEqual(self.run_lint(), 1)
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {"a.gd": 1})
        self.assertEqual(self.run_lint(), 1)
        self.run_lint("--update", "--allow-new", "b.gd")
        self.assertEqual(self.baseline(), {"a.gd": 1, "b.gd": 1})
        self.assertEqual(self.run_lint(), 0)


if __name__ == "__main__":
    unittest.main()
