"""Tests for tools/lint_single_source.py (Bontago-1pi.86.1). Run: python tools/test_lint_single_source.py"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_single_source as ls  # noqa: E402

# rule id -> (bypass path, bypass text, allowed path carrying the same text, out-of-scope path or None)
CASES = {
    "NAME_FMT": ("ui/Row.gd", 'func f(n: int) -> String:\n\treturn "Team %d" % n\n',
                 "core/rules/PlayerNames.gd", None),
    "NAME_RAW": ("ui/Row.gd", 'var t := slot.display_name if slot != null else fallback\n',
                 "core/rules/PlayerNames.gd", None),
    "COLOR_LOOKUP": ("game/Fx.gd", 'var c: Color = palette.player_colors[slot_id]\n',
                     "core/rules/SlotColors.gd", None),
    "DIAMOND": ("ui/Beacon.gd", 'var diamond: PackedVector2Array = make_points()\n',
                "ui/SlotDiamond.gd", "game/Beacon.gd"),
    "GLYPH_EVENTS": ("ui/Prompt.gd", 'for e: InputEvent in InputMap.action_get_events(action):\n\tpass\n',
                     "ui/InputGlyph.gd", "core/Prompt.gd"),
    "GLYPH_ASSET": ("ui/Icon.gd", 'var t := load("res://assets/ui/input_glyphs/a.png")\n',
                    "ui/InputGlyph.gd", None),
    "GLYPH_TEXT": ("ui/Hint.gd", 'label.text = "Press Enter to start"\n',
                   "ui/InputGlyph.gd", "core/Hint.gd"),
    "ENUM_LABEL": ("ui/Pick.gd", 'var n: String = MapDef.MapSize.keys()[i]\n',
                   "config/MapDef.gd", "core/Pick.gd"),
    "CAPITALIZE_ID": ("ui/Name.gd", 'var n: String = String(id).capitalize()\n',
                      "core/rules/DisplayNames.gd", "core/Name.gd"),
    "GIFT_ICON": ("ui/Gift.gd", 'var t := load("res://assets/gifts/bomb.png")\n',
                  "game/GiftCrate.gd", None),
}


class LintTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        os.makedirs(os.path.join(self.root, "tools"))
        self.bfile = os.path.join(self.root, "tools", ls.BASELINE_NAME)

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, rel, text):
        full = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(text)

    def write_baseline(self, data):
        with open(self.bfile, "w", encoding="utf-8") as fh:
            json.dump(data, fh)

    def baseline(self):
        with open(self.bfile, encoding="utf-8") as fh:
            return json.load(fh)

    def run_lint(self, *extra):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = ls.main(["--path", self.root, *extra])
        self.last_out = out.getvalue()
        return code

    def test_every_rule_is_covered_by_a_case(self):
        self.assertEqual(sorted(CASES), sorted(ls.RULE_IDS))

    def test_each_rule_fires_on_bypass_and_passes_in_allowed_file(self):
        for rule_id, (bad, text, allowed, outside) in CASES.items():
            with self.subTest(rule=rule_id):
                self.tearDown()  # fresh checkout per rule
                self.setUp()
                self.write(bad, text)
                self.write_baseline({})
                self.assertEqual(self.run_lint(), 1, self.last_out)
                self.assertIn("SINGLE-SOURCE LINT FAIL %s %s" % (rule_id, bad), self.last_out)
                self.assertIn("SINGLE-SOURCE LINT RED", self.last_out)
                # the same text in the owner file passes
                os.remove(os.path.join(self.root, bad))
                self.write(allowed, text)
                self.assertEqual(self.run_lint(), 0, self.last_out)
                self.assertIn("SINGLE-SOURCE LINT GREEN", self.last_out)
                # and outside the rule's scope it is not this rule's business
                if outside:
                    os.remove(os.path.join(self.root, allowed))
                    self.write(outside, text)
                    self.assertEqual(self.run_lint(), 0, self.last_out)

    def test_name_format_variants(self):
        for text in ('var a := "Player %d" % i\n', 'var a := "Bot %s" % n\n', "var a := 'Team {n}'.format({})\n",
                     'var a := "Winner: Team %d" % n\n', 'var a := "Team " + str(n)\n',
                     'var a := "Spectator %d" % n\n'):
            self.assertEqual(len(ls.violations_in("ui/x.gd", text)), 1, text)
        for text in ('var a := "Team size"\n', 'var a := "Players"\n', 'var team: int = 3\n'):
            self.assertEqual(ls.violations_in("ui/x.gd", text), [], text)

    def test_comments_and_strings(self):
        # comments never count, even for the rules that match inside strings
        self.assertEqual(ls.violations_in("ui/x.gd", '# "Team %d" % n\nvar a := 1  # "Bot %d"\n'), [])
        self.assertEqual(ls.violations_in("ui/x.gd", "## InputMap.action_get_events(a)\n"), [])
        # string bodies do not count for code-only rules
        self.assertEqual(ls.violations_in("ui/x.gd", 'var s := "InputMap.action_get_events .capitalize()"\n'), [])
        # a # inside a string is not a comment start
        self.assertEqual(len(ls.violations_in("ui/x.gd", 'var s := "#" + "Team %d" % n\n')), 1)

    def test_diamond_allows_owner_consumers_but_not_hand_drawn_polygons(self):
        consumer = ('var d: SlotDiamond = SlotDiamond.create(color)\nd.name = "SlotDiamond"\n'
                    'var edge: float = d.diamond_size_px()\nadd_child(d)\n')
        self.assertEqual(ls.violations_in("ui/Row.gd", consumer), [])
        drawn = 'var pts := PackedVector2Array([a, b])\ncanvas.draw_colored_polygon(diamond, c)\n'
        self.assertEqual([r for r, _, _ in ls.violations_in("ui/Map.gd", drawn)], ["DIAMOND"])
        self.assertEqual(len(ls.violations_in("ui/Map.gd", "var diamond := PackedVector2Array(pts)\n")), 1)

    def test_enum_label_ignores_dictionary_keys(self):
        self.assertEqual(ls.violations_in("autoload/m.gd", "var t = alive_teams.keys()[0]\n"), [])
        self.assertEqual([r for r, _, _ in ls.violations_in("autoload/m.gd", "var n = Mode.keys()[i]\n")],
                         ["ENUM_LABEL"])

    def test_directory_allow_entries_and_scenes(self):
        gift = 'var t := load("res://assets/gifts/a.png")\n'
        self.assertEqual(ls.violations_in("config/specials/X.gd", gift), [])
        self.assertEqual(len(ls.violations_in("autoload/X.gd", gift)), 1)
        scene = '[ext_resource type="Texture2D" path="res://assets/ui/input_glyphs/a.png" id="1"]\n'
        self.assertEqual([r for r, _, _ in ls.violations_in("ui/A.tscn", scene)], ["GLYPH_ASSET"])
        self.assertEqual(ls.violations_in("ui/InputGlyph.gd", scene), [])
        # a .tscn is scanned for GLYPH_ASSET only
        other = 'text = "Team %d"\n[ext_resource path="res://assets/gifts/a.png"]\n'
        self.assertEqual(ls.violations_in("ui/A.tscn", other), [])

    def test_skip_dirs_and_other_extensions(self):
        self.write_baseline({})
        for rel in ("tests/t.gd", "tools/t.gd", "addons/x/t.gd", ".godot/t.gd", "source_art/t.gd"):
            self.write(rel, 'var a := "Team %d" % n\n')
        self.write("ui/readme.md", 'var a := "Team %d" % n\n')
        self.assertEqual(self.run_lint(), 0, self.last_out)

    def test_baseline_growth_new_file_and_lowering(self):
        line = 'var a := "Team %d" % n\n'
        self.write("ui/A.gd", line + line)
        self.assertEqual(self.run_lint("--update"), 0)  # no baseline yet: seeded from the scan
        self.assertEqual(self.baseline(), {"NAME_FMT": {"ui/A.gd": 2}})
        self.assertEqual(self.run_lint(), 0)
        # growth in a baselined file fails
        self.write("ui/A.gd", line * 3)
        self.assertEqual(self.run_lint(), 1)
        self.assertIn("3 line(s) > baseline 2", self.last_out)
        # --update never raises a baseline
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {"NAME_FMT": {"ui/A.gd": 2}})
        # a new file fails for that rule and is not admitted without --allow-new
        self.write("ui/A.gd", line)
        self.write("ui/B.gd", line)
        self.assertEqual(self.run_lint(), 1)
        self.assertIn("ui/B.gd: 1 line(s), new", self.last_out)
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {"NAME_FMT": {"ui/A.gd": 1}})
        self.assertEqual(self.run_lint(), 1)
        # --allow-new admits it, by rule or for every rule
        self.run_lint("--update", "--allow-new", "GLYPH_TEXT:ui/B.gd")
        self.assertEqual(self.baseline(), {"NAME_FMT": {"ui/A.gd": 1}})
        self.run_lint("--update", "--allow-new", "NAME_FMT:ui/B.gd")
        self.assertEqual(self.baseline(), {"NAME_FMT": {"ui/A.gd": 1, "ui/B.gd": 1}})
        self.assertEqual(self.run_lint(), 0)
        self.write("ui/C.gd", line)
        self.run_lint("--update", "--allow-new", "ui/C.gd")
        self.assertEqual(self.baseline()["NAME_FMT"]["ui/C.gd"], 1)

    def test_fixed_file_drops_out_and_stays_banned(self):
        line = 'var a := "Team %d" % n\n'
        self.write("ui/A.gd", line)
        self.write_baseline({"NAME_FMT": {"ui/A.gd": 1}})
        self.write("ui/A.gd", "var a := 1\n")
        self.assertEqual(self.run_lint(), 0)
        self.assertIn("can be lowered", self.last_out)
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {})
        # the migrated file is now concept-complete: reappearance fails
        self.write("ui/A.gd", line)
        self.assertEqual(self.run_lint(), 1)
        # an emptied baseline is not re-seeded by --update
        self.run_lint("--update")
        self.assertEqual(self.baseline(), {})

    def test_baseline_entry_does_not_cover_another_rule(self):
        self.write("ui/A.gd", 'var a := "Team %d" % n\nvar b := String(i).capitalize()\n')
        self.write_baseline({"NAME_FMT": {"ui/A.gd": 1}})
        self.assertEqual(self.run_lint(), 1)
        self.assertIn("CAPITALIZE_ID ui/A.gd", self.last_out)
        self.assertNotIn("NAME_FMT ui/A.gd", self.last_out)

    def test_list_prints_line_numbers_and_filters(self):
        self.write("ui/A.gd", 'var ok := 1\nvar a := "Team %d" % n\nvar b := String(i).capitalize()\n')
        self.assertEqual(self.run_lint("--list"), 0)
        self.assertIn('NAME_FMT ui/A.gd:2: var a := "Team %d" % n', self.last_out)
        self.assertIn("CAPITALIZE_ID ui/A.gd:3:", self.last_out)
        self.assertIn("2 violation(s)", self.last_out)
        self.assertEqual(self.run_lint("--list", "--rule", "NAME_FMT"), 0)
        self.assertNotIn("CAPITALIZE_ID", self.last_out)

    def test_checked_in_baseline_is_well_formed(self):
        path = os.path.join(ls.ROOT, "tools", ls.BASELINE_NAME)
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        for rule_id, files in data.items():
            self.assertIn(rule_id, ls.RULE_IDS)
            for rel, n in files.items():
                self.assertTrue(rel.endswith((".gd", ".tscn")), rel)
                self.assertIsInstance(n, int)
                self.assertGreater(n, 0, "%s %s: delete zero entries" % (rule_id, rel))


class FullGateWiringTest(unittest.TestCase):
    """full_gate.py runs the lint and reports it, without launching Godot."""

    def run_gate(self, root, out_dir):
        import full_gate
        fake = {"shard0": {"exit": 0, "totals": {"Tests": 1, "Passing Tests": 1}, "failing": [],
                           "log": "x.log", "seconds": 0.1}}
        buf = io.StringIO()
        with mock.patch.object(full_gate, "collect", return_value=["res://tests/unit/test_x.gd"]), \
                mock.patch.object(full_gate, "run_batch", return_value=fake) as batch, \
                mock.patch.object(full_gate, "TIMINGS", os.path.join(out_dir, "timings.json")), \
                contextlib.redirect_stdout(buf):
            code = full_gate.main(["--path", root, "--out", out_dir, "--shards", "2"])
        self.assertEqual(batch.call_count, 1)  # shards only run once; nothing failed
        with open(os.path.join(out_dir, "result.json"), encoding="utf-8") as fh:
            return code, buf.getvalue(), json.load(fh)

    def test_gate_imports_lint_and_reports_green_and_red(self):
        import full_gate
        self.assertIs(full_gate.lint_single_source, ls)
        with tempfile.TemporaryDirectory() as root, tempfile.TemporaryDirectory() as out:
            os.makedirs(os.path.join(root, "tools"))
            with open(os.path.join(root, "tools", ls.BASELINE_NAME), "w", encoding="utf-8") as fh:
                fh.write("{}")
            code, text, result = self.run_gate(root, out)
            self.assertEqual(code, 0, text)
            self.assertEqual(result["verdict"], "GREEN")
            self.assertEqual(result["single_source_lint"], "green")
            self.assertIn("SINGLE-SOURCE LINT GREEN", text)
            self.assertIn("single_source_lint=green", text)
            # a bypass flips the verdict and the key
            os.makedirs(os.path.join(root, "ui"))
            with open(os.path.join(root, "ui", "A.gd"), "w", encoding="utf-8") as fh:
                fh.write('var a := "Team %d" % n\n')
            code, text, result = self.run_gate(root, out)
            self.assertEqual(code, 1, text)
            self.assertEqual(result["verdict"], "RED")
            self.assertEqual(result["single_source_lint"], "red")
            self.assertEqual(result["magic_lint"], "green")
            self.assertIn("single_source_lint=RED", text)


if __name__ == "__main__":
    unittest.main()
