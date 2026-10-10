"""Tests for tools/lint_ui_components.py (Bontago-1pi.159.6). Run: python -I tools/test_lint_ui_components.py"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_ui_components as lu  # noqa: E402

# rule id -> (path, bypass text)
CASES = {
    "R1": ("ui/Menu.gd", "var c: CheckButton = CheckButton.new()\n"),
    "R2": ("ui/Menu.gd", 'label.add_theme_color_override("font_color", c)\n'),
    "R3": ("ui/Menu.gd", "MenuStyleFactory.apply_pill(b)\n"),
    "R4": ("ui/Menu.gd", "var b := Button.new()\n"),
}


def run(argv):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = lu.main(argv)
    return code, out.getvalue()


class RuleTests(unittest.TestCase):
    def test_each_rule_fires(self):
        for rid, (rel, text) in CASES.items():
            ids = [v[0] for v in lu.violations_in(rel, text)]
            self.assertIn(rid, ids, rid)

    def test_exempt_paths_ignored(self):
        for rid, (_rel, text) in CASES.items():
            for rel in ("ui/components/UiToggle.gd", "ui/theme/MenuStyleFactory.gd", "ui/TuningPanel.gd",
                        "ui/NetDebugOverlay.gd", "ui/PerfOverlay.gd", "ui/PhysicsComparisonPanel.gd",
                        "ui/SandboxPanel.gd", "game/Field.gd"):
                self.assertEqual(lu.violations_in(rel, text), [], "%s %s" % (rid, rel))

    def test_comments_strings_and_lookalikes_ignored(self):
        self.assertEqual(lu.violations_in("ui/A.gd", "# CheckButton.new() Button.new()\n"), [])
        self.assertEqual(lu.violations_in("ui/A.gd", 'var s := "OptionButton"\n'), [])
        ids = [v[0] for v in lu.violations_in("ui/A.gd", "var b := UiBlockButton.new()\nvar t := MyButton.new()\n")]
        self.assertEqual(ids, [])
        # CheckButton.new() is R1, not R4.
        ids = [v[0] for v in lu.violations_in("ui/A.gd", "x = CheckButton.new()\n")]
        self.assertEqual(ids, ["R1"])

    def test_tscn_node_types(self):
        scene = '[node name="T" type="CheckButton" parent="."]\n[node name="B" type="Button" parent="."]\n'
        self.assertEqual([v[0] for v in lu.violations_in("ui/Menu.tscn", scene)], ["R1"])
        self.assertEqual(lu.violations_in("ui/components/X.tscn", scene), [])


class RatchetTests(unittest.TestCase):
    def make_tree(self, files):
        d = tempfile.mkdtemp()
        for rel, text in files.items():
            full = os.path.join(d, rel)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(text)
        return d

    def test_green_then_red_on_new_raw_control(self):
        d = self.make_tree({"ui/Menu.gd": "var b := Button.new()\n"})
        self.assertEqual(run(["--path", d, "--update"])[0], 0)
        code, out = run(["--path", d])
        self.assertEqual(code, 0)
        self.assertIn("UI COMPONENT LINT GREEN", out)
        with open(os.path.join(d, "ui", "Menu.gd"), "a", encoding="utf-8") as fh:
            fh.write("var c := CheckButton.new()\n")
        code, out = run(["--path", d])
        self.assertEqual(code, 1)
        self.assertIn("UI COMPONENT LINT RED", out)
        self.assertIn("R1 ui/Menu.gd", out)

    def test_growth_and_new_file_fail_shrink_passes(self):
        d = self.make_tree({"ui/A.gd": "var a := Button.new()\nvar b := Button.new()\n"})
        run(["--path", d, "--update"])
        with open(os.path.join(d, "ui", "A.gd"), "a", encoding="utf-8") as fh:
            fh.write("var c := Button.new()\n")
        self.assertEqual(run(["--path", d])[0], 1)
        with open(os.path.join(d, "ui", "A.gd"), "w", encoding="utf-8") as fh:
            fh.write("var a := Button.new()\n")
        code, out = run(["--path", d])
        self.assertEqual(code, 0)
        self.assertIn("can be lowered", out)
        with open(os.path.join(d, "ui", "B.gd"), "w", encoding="utf-8") as fh:
            fh.write("var a := Button.new()\n")
        self.assertEqual(run(["--path", d])[0], 1)

    def test_update_lowers_only_and_allow_new(self):
        d = self.make_tree({"ui/A.gd": "var a := Button.new()\nvar b := Button.new()\n"})
        run(["--path", d, "--update"])
        with open(os.path.join(d, "ui", "A.gd"), "w", encoding="utf-8") as fh:
            fh.write("var a := Button.new()\n")
        with open(os.path.join(d, "ui", "B.gd"), "w", encoding="utf-8") as fh:
            fh.write("var a := Button.new()\n")
        run(["--path", d, "--update"])
        base = json.load(open(os.path.join(d, "tools", lu.BASELINE_NAME), encoding="utf-8"))
        self.assertEqual(base, {"R4": {"ui/A.gd": 1}})
        run(["--path", d, "--update", "--allow-new", "R4:ui/B.gd"])
        base = json.load(open(os.path.join(d, "tools", lu.BASELINE_NAME), encoding="utf-8"))
        self.assertEqual(base, {"R4": {"ui/A.gd": 1, "ui/B.gd": 1}})

    def test_list(self):
        d = self.make_tree({"ui/A.gd": "var a := Button.new()\n"})
        code, out = run(["--path", d, "--list"])
        self.assertEqual(code, 0)
        self.assertIn("R4 ui/A.gd:1", out)


if __name__ == "__main__":
    unittest.main()
