"""Tests for tools/lint_flag_dead.py on small temp-dir fixture repos.

Run: python tools/test_lint_flag_dead.py
"""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_flag_dead as lint  # noqa: E402

BASE_GD = ("class_name Tuning\nextends Resource\n\n@export var fx_enabled: bool = true\n"
           "@export var other_enabled: bool = false\n@export var width: float = 1.0\n")
CHILD_GD = 'class_name ChildTuning\nextends "res://config/Tuning.gd"\n'
NODE_GD = "class_name NotAResource\nextends Node\n\n@export var node_enabled: bool = true\n"


def tres(script, props, script_id="1"):
    lines = ['[gd_resource type="Resource" script_class="X" format=3]',
             '[ext_resource type="Script" path="res://%s" id="%s"]' % (script, script_id), "[resource]",
             'script = ExtResource("%s")' % script_id]
    lines += ["%s = %s" % kv for kv in props.items()]
    return "\n".join(lines) + "\n"


def make_repo(files):
    tmp = tempfile.TemporaryDirectory()
    for rel, text in files.items():
        path = os.path.join(tmp.name, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    return tmp


def keys(files):
    with make_repo(files) as root:
        found, _ = lint.collect(root.replace("\\", "/"))
        return sorted(f[4] for f in found)


class FlagFindingTest(unittest.TestCase):
    def test_flag_constant_across_default_and_every_resource_is_found(self):
        files = {"config/Tuning.gd": BASE_GD, "config/a.tres": tres("config/Tuning.gd", {"fx_enabled": "true"})}
        self.assertEqual(keys(files), ["config/Tuning.gd:fx_enabled", "config/Tuning.gd:other_enabled"])

    def test_one_resource_flipping_the_default_makes_the_flag_live(self):
        files = {"config/Tuning.gd": BASE_GD, "config/a.tres": tres("config/Tuning.gd", {"fx_enabled": "false"})}
        self.assertEqual(keys(files), ["config/Tuning.gd:other_enabled"])

    def test_resource_of_a_subclass_counts_for_the_inherited_flag(self):
        files = {"config/Tuning.gd": BASE_GD, "config/Child.gd": CHILD_GD,
                 "config/c.tres": tres("config/Child.gd", {"other_enabled": "true"})}
        self.assertEqual(keys(files), ["config/Tuning.gd:fx_enabled"])

    def test_non_resource_script_and_flags_outside_config_are_ignored(self):
        files = {"config/Node.gd": NODE_GD, "game/Outside.gd": BASE_GD}
        self.assertEqual(keys(files), [])

    def test_flags_in_tests_folder_resources_do_not_count(self):
        files = {"config/Tuning.gd": BASE_GD, "tests/fixture.tres": tres("config/Tuning.gd", {"fx_enabled": "false"})}
        self.assertEqual(keys(files), ["config/Tuning.gd:fx_enabled", "config/Tuning.gd:other_enabled"])

    def test_inferred_type_declaration_is_read(self):
        gd = "extends Resource\n@export var lit_enabled := true\n"
        self.assertEqual(keys({"config/T.gd": gd}), ["config/T.gd:lit_enabled"])


class AllowListTest(unittest.TestCase):
    def run_main(self, files):
        with make_repo(files) as root:
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = lint.main(["--path", root])
            return code, buf.getvalue()

    def test_unlisted_finding_fails(self):
        code, out = self.run_main({"config/Tuning.gd": BASE_GD})
        self.assertEqual(code, 1)
        self.assertIn("config/Tuning.gd:4: flag-constant: fx_enabled is always true", out)
        self.assertIn("LINT FLAG DEAD RED: 2 new", out)

    def test_allow_entry_with_reason_exempts_and_one_without_does_not(self):
        allow = {"allow": [{"entry": "config/Tuning.gd:fx_enabled", "reason": "flipped by the panel"},
                           {"entry": "config/Tuning.gd:other_enabled", "reason": " "}]}
        code, out = self.run_main({"config/Tuning.gd": BASE_GD, "tools/flag_dead_allow.json": json.dumps(allow)})
        self.assertEqual(code, 1)
        self.assertIn("other_enabled", out)
        self.assertNotIn("fx_enabled is always", out)
        self.assertIn("LINT FLAG DEAD RED: 1 new finding(s) (1 allowed, 0 stale)", out)

    def test_stale_allow_entry_is_reported_without_failing(self):
        allow = {"allow": [{"entry": "config/Tuning.gd:fx_enabled", "reason": "r"},
                           {"entry": "config/Tuning.gd:other_enabled", "reason": "r"},
                           {"entry": "config/Tuning.gd:gone_enabled", "reason": "r"}]}
        code, out = self.run_main({"config/Tuning.gd": BASE_GD, "tools/flag_dead_allow.json": json.dumps(allow)})
        self.assertEqual(code, 0)
        self.assertIn("stale allow entry (no longer found, delete it): config/Tuning.gd:gone_enabled", out)
        self.assertIn("LINT FLAG DEAD GREEN: 2 allowed, 1 stale", out)


if __name__ == "__main__":
    unittest.main()
