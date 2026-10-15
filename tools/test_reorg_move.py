"""Unit tests for tools/reorg_move.py on a temporary git repo.

Run: python -m unittest tools.test_reorg_move   (or python tools/test_reorg_move.py)
"""
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reorg_move  # noqa: E402

CRLF = chr(13) + chr(10)
HEADER = "old_path\tnew_path\taction\treason\n"


def git(root, *args):
    subprocess.run(["git", "-C", root] + list(args), check=True, capture_output=True)


class Fixture(object):
    def __init__(self, files, rows, rules=""):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = os.path.join(self.tmp.name, "repo")
        os.makedirs(self.root)
        git(self.root, "init", "-q")
        git(self.root, "config", "user.email", "t@t")
        git(self.root, "config", "user.name", "t")
        for path, text in files.items():
            self.write(path, text)
        git(self.root, "add", "-A")
        git(self.root, "commit", "-qm", "base")
        self.map = os.path.join(self.tmp.name, "map.tsv")
        with open(self.map, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(HEADER + "".join("\t".join(r) + "\n" for r in rows))
        self.rules = os.path.join(self.tmp.name, "rules.tsv")
        with open(self.rules, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(rules)

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, "wb") as fh:
            fh.write(text.encode("utf-8"))

    def read(self, path):
        with open(os.path.join(self.root, path), "rb") as fh:
            return fh.read().decode("utf-8").replace(CRLF, chr(10))

    def exists(self, path):
        return os.path.exists(os.path.join(self.root, path))

    def run(self, mode, *extra):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = reorg_move.main(["--map", self.map, "--path", self.root, "--rules", self.rules, mode] + list(extra))
        return code, buf.getvalue()

    def close(self):
        self.tmp.cleanup()


def base_files():
    return {
        "game/Main.gd": 'const A = preload("res://game/Field.gd")\nvar s := "game/Field.gd"\n',
        "game/Main.gd.uid": "uid://aaa\n",
        "game/Field.gd": "class_name Field\n",
        "game/Field.gd.uid": "uid://bbb\n",
        "game/world/Ctx.gd": "class_name Ctx\n",
        "config/specials/rocket.tres": '[ext_resource path="res://assets/effects/boom.wav"]\n',
        "config/specials/bomb.tres": "x\n",
        "assets/effects/boom.wav": "RIFF",
        "assets/effects/boom.wav.import": 'source_file="res://assets/effects/boom.wav"\npath="res://.godot/imported/boom.wav-1.sample"\nuid="uid://zzz"\n',
        "assets/effects/old.wav": "RIFF",
        "scene.tscn": '[ext_resource path="res://game/Main.gd"]\n[x p="game\\Field.gd" q="xgame/Field.gd" r="game/Field.gd.uid" s="other/game/Main.gd"]\n',
        "docs/notes.md": "See `game/Field.gd` and config/specials/ and game/world/Ctx.gd.\n",
        "docs/archive/old.md": "game/Field.gd\n",
        "tools/probe.py": "x = 1\n",
    }


def base_rows():
    return [
        ("game/Main.gd", "game/main/Main.gd", "move", ""),
        ("game/Main.gd.uid", "game/main/Main.gd.uid", "move", ""),
        ("game/Field.gd", "game/field/Field.gd", "move", ""),
        ("game/Field.gd.uid", "game/field/Field.gd.uid", "move", ""),
        ("game/world/Ctx.gd", "game/world/Ctx.gd", "keep", ""),
        ("config/specials/rocket.tres", "config/gifts/specials/rocket.tres", "move", ""),
        ("config/specials/bomb.tres", "config/gifts/specials/bomb.tres", "move", ""),
        ("assets/effects/boom.wav", "assets/audio/sfx/boom.wav", "move", ""),
        ("assets/effects/boom.wav.import", "assets/audio/sfx/boom.wav.import", "move", ""),
        ("assets/effects/old.wav", "", "delete", "dead"),
        ("scene.tscn", "scene.tscn", "keep", ""),
        ("docs/notes.md", "docs/notes.md", "keep", ""),
        ("docs/archive/old.md", "docs/archive/old.md", "keep", ""),
        ("tools/probe.py", "tools/probe.py", "keep", ""),
    ]


class ReorgMoveTest(unittest.TestCase):
    def setUp(self):
        self.fx = Fixture(base_files(), base_rows())

    def tearDown(self):
        self.fx.close()

    def test_dry_run_changes_nothing(self):
        code, out = self.fx.run("--dry-run")
        self.assertEqual(code, 0, out)
        self.assertIn("moves: 8", out)
        self.assertTrue(self.fx.exists("game/Main.gd"))
        self.assertIn("game/Field.gd", self.fx.read("game/Main.gd"))

    def test_apply_moves_deletes_and_rewrites(self):
        code, out = self.fx.run("--apply")
        self.assertEqual(code, 0, out)
        for p in ("game/main/Main.gd", "game/main/Main.gd.uid", "game/field/Field.gd", "config/gifts/specials/rocket.tres",
                  "assets/audio/sfx/boom.wav", "assets/audio/sfx/boom.wav.import"):
            self.assertTrue(self.fx.exists(p), p)
        self.assertFalse(self.fx.exists("game/Main.gd"))
        self.assertFalse(self.fx.exists("assets/effects"), "emptied folder is removed")
        self.assertFalse(self.fx.exists("config/specials"))
        main = self.fx.read("game/main/Main.gd")
        self.assertIn('preload("res://game/field/Field.gd")', main)
        self.assertIn('"game/field/Field.gd"', main)
        self.assertEqual(self.fx.read("game/main/Main.gd.uid"), "uid://aaa\n")

    def test_boundary_windows_and_directory_forms(self):
        self.fx.run("--apply")
        scene = self.fx.read("scene.tscn")
        self.assertIn('res://game/main/Main.gd', scene)
        self.assertIn('p="game\\field\\Field.gd"', scene)
        self.assertIn('q="xgame/Field.gd"', scene)  # not at a path boundary
        self.assertIn('r="game/field/Field.gd.uid"', scene)
        self.assertIn('s="other/game/Main.gd"', scene)  # nested under another directory
        self.assertIn("res://assets/audio/sfx/boom.wav", self.fx.read("config/gifts/specials/rocket.tres"))
        notes = self.fx.read("docs/notes.md")
        self.assertIn("config/gifts/specials/", notes)  # directory map
        self.assertIn("game/world/Ctx.gd", notes)
        self.assertEqual(self.fx.read("docs/archive/old.md"), "game/Field.gd\n")

    def test_directory_map_derivation(self):
        rows = reorg_move.load_rows(self.fx.map)
        plan = reorg_move.Plan(rows, reorg_move.tracked_files(self.fx.root))
        self.assertEqual(plan.dir_map["config/specials"], "config/gifts/specials")
        self.assertIn("game", plan.split_dirs)
        self.assertNotIn("game/world", plan.split_dirs)

    def test_import_file_only_source_and_path_keys(self):
        self.fx.write("assets/effects/boom.wav.import", 'source_file="res://assets/effects/boom.wav"\n'
                      'path="res://.godot/imported/boom.wav-1.sample"\nnote="assets/effects/boom.wav"\n')
        git(self.fx.root, "add", "-A")
        self.fx.run("--apply")
        text = self.fx.read("assets/audio/sfx/boom.wav.import")
        self.assertIn('source_file="res://assets/audio/sfx/boom.wav"', text)
        self.assertIn('note="assets/effects/boom.wav"', text)

    def test_idempotent_second_apply(self):
        self.assertEqual(self.fx.run("--apply")[0], 0)
        git(self.fx.root, "add", "-A")
        code, out = self.fx.run("--apply")
        self.assertEqual(code, 0, out)
        self.assertIn("moves: 0", out)
        self.assertIn("files rewritten: 0", out)

    def test_unmapped_file_is_an_error_and_blocks_apply(self):
        self.fx.write("game/New.gd", "x\n")
        git(self.fx.root, "add", "-A")
        code, out = self.fx.run("--apply")
        self.assertEqual(code, 1)
        self.assertIn("unmapped tracked file game/New.gd", out)
        self.assertTrue(self.fx.exists("game/Main.gd"), "nothing applied")

    def test_missing_source_is_an_error(self):
        rows = base_rows() + [("game/Ghost.gd", "game/main/Ghost.gd", "move", "")]
        fx = Fixture(base_files(), rows)
        try:
            code, out = fx.run("--dry-run")
            self.assertEqual(code, 1)
            self.assertIn("missing: game/Ghost.gd", out)
        finally:
            fx.close()

    def test_restore_move(self):
        files = base_files()
        files["config/maps/medium.tres"] = "map\n"
        rows = base_rows() + [("config/maps/medium.tres", "config/match/maps/round.tres", "restore-move", "")]
        fx = Fixture(files, rows)
        try:
            os.remove(os.path.join(fx.root, "config/maps/medium.tres"))  # the user deleted it, still in HEAD
            code, out = fx.run("--apply")
            self.assertEqual(code, 0, out)
            self.assertEqual(fx.read("config/match/maps/round.tres"), "map\n")
        finally:
            fx.close()

    def test_split_prefix_reference_is_flagged_and_allow_rule_clears_it(self):
        self.fx.write("tools/probe.py", 'ROOT = "game/"\nOK = "game/world/"\n# game/ comment\n')
        git(self.fx.root, "add", "-A")
        code, out = self.fx.run("--dry-run")
        self.assertEqual(code, 1)
        self.assertIn("SPLIT tools/probe.py: game/", out)
        self.assertNotIn("game/world/", out.split("SPLIT tools/probe.py:")[1].split("\n")[0])
        with open(self.fx.rules, "w", encoding="utf-8") as fh:
            fh.write("allow\ttools/probe.py\tgame/\n")
        self.assertEqual(self.fx.run("--dry-run")[0], 0)

    def test_replace_rule(self):
        with open(self.fx.rules, "w", encoding="utf-8") as fh:
            fh.write('replace\ttools/probe.py\tx = 1\tx = 2\n')
        self.fx.run("--apply")
        self.assertEqual(self.fx.read("tools/probe.py"), "x = 2\n")

    def test_extra_file_is_rewritten(self):
        extra = os.path.join(self.fx.tmp.name, "brief.md")
        with open(extra, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("edit game/Field.gd and res://assets/effects/boom.wav\n")
        code, out = self.fx.run("--apply", "--extra", extra)
        self.assertEqual(code, 0, out)
        with open(extra, encoding="utf-8") as fh:
            self.assertEqual(fh.read(), "edit game/field/Field.gd and res://assets/audio/sfx/boom.wav\n")

    def test_validation_rejects_non_idempotent_and_duplicate_rows(self):
        rows = base_rows() + [("game/world/Ctx.gd.uid", "game/world/Ctx.gd.uid", "keep", "")]
        rows[0] = ("game/Main.gd", "game/Main.gd/x", "move", "")
        plan = reorg_move.Plan([reorg_move.Row(*r) for r in rows], ["game/Main.gd"])
        self.assertTrue(any("not idempotent" in e for e in plan.validate()))
        rows2 = base_rows() + [("game/Main.gd", "game/x.gd", "move", "")]
        with self.assertRaises(reorg_move.MapError):
            reorg_move.Plan([reorg_move.Row(*r) for r in rows2], [])

    def test_verify_green_after_apply_and_red_before(self):
        code, out = self.fx.run("--verify", "--skip-godot")
        self.assertEqual(code, 1, out)
        self.assertIn("OLD scene.tscn", out)
        self.fx.run("--apply")
        git(self.fx.root, "add", "-A")
        code, out = self.fx.run("--verify", "--skip-godot")
        self.assertEqual(code, 0, out)
        self.assertIn("REORG VERIFY GREEN", out)


class LayerRulesTest(unittest.TestCase):
    def test_membership_is_the_image_of_the_old_membership(self):
        files = {
            "core/A.gd": "x", "config/C.gd": "x", "game/specials/S.gd": "x", "vfx/Cloud.gd": "x", "vfx/Cloud.gd.uid": "x", "vfx/Bird.gd": "x",
            "game/Field.gd": "x", "game/Other.gd": "x", "game/Sky.gd": "x",
            "tools/layer_rules.json": json.dumps({
                "source_prefixes": ["core/", "config/", "game/specials/", "vfx/"],
                "source_files": ["game/Field.gd"], "forbidden_prefixes": ["net/"], "forbidden_files": [],
                "late_scripts_file": "autoload/L.gd", "main_scene": "game/Main.tscn", "main_forbidden": ["game/Other.gd"]}),
        }
        rows = [
            ("core/A.gd", "core/A.gd", "keep", ""), ("config/C.gd", "config/x/C.gd", "move", ""),
            ("game/specials/S.gd", "game/gifts/specials/S.gd", "move", ""),
            ("vfx/Cloud.gd", "game/sky/Cloud.gd", "move", ""), ("vfx/Cloud.gd.uid", "game/sky/Cloud.gd.uid", "move", ""), ("vfx/Bird.gd", "game/ambient/Bird.gd", "move", ""),
            ("game/Field.gd", "game/field/Field.gd", "move", ""), ("game/Other.gd", "game/main/Other.gd", "move", ""),
            ("game/Sky.gd", "game/sky/Sky.gd", "move", ""),
            ("tools/layer_rules.json", "tools/layer_rules.json", "keep", ""),
        ]
        fx = Fixture(files, rows)
        try:
            code, out = fx.run("--apply")
            self.assertEqual(code, 0, out)
            new = json.loads(fx.read("tools/layer_rules.json"))
            self.assertIn("core/", new["source_prefixes"])
            self.assertIn("config/", new["source_prefixes"])
            self.assertIn("game/gifts/specials/", new["source_prefixes"])
            self.assertIn("game/ambient/", new["source_prefixes"])
            self.assertNotIn("game/sky/", new["source_prefixes"], "game/sky/ also holds a non-member")
            self.assertIn("game/sky/Cloud.gd", new["source_files"])
            self.assertIn("game/sky/Cloud.gd.uid", new["source_files"])
            self.assertIn("game/field/Field.gd", new["source_files"])
            self.assertNotIn("game/sky/Sky.gd", new["source_files"])
            self.assertEqual(new["main_forbidden"], ["game/main/Other.gd"])
            git(fx.root, "add", "-A")
            git(fx.root, "commit", "-qm", "moved")
            code, out = fx.run("--verify", "--skip-godot", "--base-ref", "HEAD~1")
            self.assertEqual(code, 0, out)
            self.assertIn("membership identical", out)
        finally:
            fx.close()


if __name__ == "__main__":
    unittest.main()
