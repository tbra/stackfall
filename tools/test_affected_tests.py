"""Tests for tools/affected_tests.py on a temporary git repo.
Run: python -m unittest tools.test_affected_tests   (or python tools/test_affected_tests.py)
"""
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import affected_tests as at  # noqa: E402


def g(cwd, *a):
    subprocess.run(["git", "-C", cwd, *a], check=True, capture_output=True, text=True)


class AffectedTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "r").replace("\\", "/")
        os.makedirs(self.repo)
        g(self.repo, "init", "-b", "main")
        g(self.repo, "config", "user.email", "t@t")
        g(self.repo, "config", "user.name", "t")
        self.write("core/rules.gd", "const MAX_RISE := 3\nfunc other_thing() -> void:\n\tpass\n")
        self.write("config/tune.tres", "[resource]\nfall_speed = 2.0\ngrip = 1.0\n")
        self.write("tests/unit/test_rules.gd", "func test_a():\n\tassert_eq(MAX_RISE, 3)\n")
        self.write("tests/unit/test_tune.gd", "func test_b():\n\tvar x = t.fall_speed\n")
        self.write("tests/unit/test_gift.gd", 'func test_c():\n\tvar id = &"rocket"\n')
        self.write("tests/unit/test_none.gd", "func test_d():\n\tvar a = true\n\tvar b = self\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "init")
        self.base = "HEAD"

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        full = os.path.join(self.repo, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", newline="\n") as fh:
            fh.write(text)

    def test_const_tres_key_and_quoted_id(self):
        self.write("core/rules.gd", "const MAX_RISE := 5\nfunc other_thing() -> void:\n\tpass\n"
                   'const GIFT := &"rocket"\nfunc self() -> void:\n\tpass\n')
        self.write("config/tune.tres", "[resource]\nfall_speed = 3.0\ngrip = 1.0\n")
        base, ids, results, _ = at.analyse(self.repo, self.base)
        files = {r["file"]: r for r in results}
        self.assertEqual(set(files), {"tests/unit/test_rules.gd", "tests/unit/test_tune.gd",
                                      "tests/unit/test_gift.gd"})
        self.assertIn("MAX_RISE", files["tests/unit/test_rules.gd"]["names"])
        self.assertIn("fall_speed", files["tests/unit/test_tune.gd"]["names"])
        self.assertIn("rocket", files["tests/unit/test_gift.gd"]["names"])
        self.assertNotIn("grip", ids)
        self.assertNotIn("self", ids)
        self.assertNotIn("true", ids)

    def test_unchanged_class_name_found_in_string_literal(self):
        self.write("core/black_hole_vis.gd", "class_name BlackHoleVisual\nextends Node3D\nvar a := 1\n")
        self.write("tests/unit/test_entr.gd", 'func test_e():\n\tn.find_children("*", "BlackHoleVisual")\n')
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "vis")
        self.write("core/black_hole_vis.gd", "class_name BlackHoleVisual\nextends Node3D\nvar a := 2\n")
        _, ids, results, _ = at.analyse(self.repo, self.base)
        self.assertIn("BlackHoleVisual", ids)
        self.assertIn("tests/unit/test_entr.gd", {r["file"] for r in results})

    def test_untracked_file_and_basename(self):
        self.write("scenes/aurora_sky.gd", "extends Node\nfunc paint_aurora() -> void:\n\tpass\n")
        self.write("tests/unit/test_sky.gd", "var s = preload('res://scenes/aurora_sky.gd')\n")
        _, ids, results, _ = at.analyse(self.repo, self.base)
        self.assertIn("aurora_sky", ids)
        self.assertIn("paint_aurora", ids)
        self.assertEqual([r["file"] for r in results], ["tests/unit/test_sky.gd"])
        self.assertTrue(results[0]["changed"])

    def test_short_and_stop_words_dropped(self):
        self.assertFalse(at.keep("abc"))
        self.assertFalse(at.keep("Vector3"))
        self.assertFalse(at.keep("true"))
        self.assertTrue(at.keep("rocket"))

    def test_gut_line_and_cli(self):
        self.write("core/rules.gd", "const MAX_RISE := 5\n")
        out = subprocess.run([sys.executable, os.path.join(os.path.dirname(at.__file__), "affected_tests.py"),
                              "--path", self.repo, "--base", "HEAD"],
                             capture_output=True, text=True).stdout
        self.assertIn("tests/unit/test_rules.gd: MAX_RISE", out)
        self.assertIn("run_gut.ps1 test_rules -Path " + self.repo, out)
        self.assertIn("AFFECTED", out)

    def test_fanout_broad_and_stoplist(self):
        for i in range(3):
            self.write("tests/unit/test_many%d.gd" % i, "func f():\n\tvar a = MAX_RISE\n\t_process(0)\n")
        g(self.repo, "add", "-A")
        g(self.repo, "commit", "-m", "more")
        self.write("core/rules.gd", "const MAX_RISE := 9\nfunc _process(d) -> void:\n\tpass\n")
        _, ids, results, broad = at.analyse(self.repo, self.base, max_fanout=2)
        self.assertNotIn("_process", ids)
        self.assertEqual(broad, {"MAX_RISE": 4})
        self.assertEqual(results, [])
        _, _, results, broad = at.analyse(self.repo, self.base, max_fanout=4)
        self.assertEqual(broad, {})
        self.assertEqual(len(results), 4)

    def test_changed_test_always_listed(self):
        self.write("tests/unit/test_none.gd", "func test_d():\n\tpass\n")
        _, _, results, _ = at.analyse(self.repo, self.base)
        self.assertEqual([(r["file"], r["changed"]) for r in results], [("tests/unit/test_none.gd", True)])

    def test_nothing_changed(self):
        _, ids, results, _ = at.analyse(self.repo, self.base)
        self.assertEqual((ids, results), ({}, []))


if __name__ == "__main__":
    unittest.main()
