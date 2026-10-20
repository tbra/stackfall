"""Tests for tools/lint_shader_uniforms.py on small temp-dir fixture repos.

Run: python tools/test_lint_shader_uniforms.py
"""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_shader_uniforms as lint  # noqa: E402


def make_repo(files):
    tmp = tempfile.TemporaryDirectory()
    for rel, text in files.items():
        path = os.path.join(tmp.name, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    return tmp


def material(params):
    lines = ['[gd_resource type="ShaderMaterial" format=3]',
             '[ext_resource type="Shader" path="res://shaders/a.gdshader" id="1"]',
             "[resource]", 'shader = ExtResource("1")']
    lines += ["shader_parameter/%s = %s" % kv for kv in params.items()]
    return "\n".join(lines) + "\n"


def findings(files):
    with make_repo(files) as root:
        return lint.collect(root.replace("\\", "/"))


def keys(files, cid):
    return sorted(f[4] for f in findings(files) if f[2] == cid)


SHADER = """shader_type spatial;
uniform float live = 1.0;
uniform float dead_one : hint_range(0.0, 1.0) = 0.5;
uniform bool gate = false;
uniform float inside_gate = 2.0; // a comment mentioning dead_one does not read it
void fragment() {
	ALBEDO = vec3(live);
	if (gate) {
		ALBEDO *= inside_gate;
	}
}
"""


class UnreadTest(unittest.TestCase):
    def test_declared_never_read_is_found_and_comment_mention_is_not_a_read(self):
        self.assertEqual(keys({"shaders/a.gdshader": SHADER}, "uniform-unread"), ["shaders/a.gdshader:dead_one"])

    def test_include_reads_count_for_the_includer_and_inc_declarations_are_reported_at_the_inc(self):
        inc = "uniform float from_inc = 1.0;\nuniform float unused_inc = 1.0;\n"
        sh = ('shader_type spatial;\n#include "res://shaders/common.gdshaderinc"\n'
              "void fragment() { ALBEDO = vec3(from_inc); }\n")
        self.assertEqual(keys({"shaders/a.gdshader": sh, "shaders/common.gdshaderinc": inc}, "uniform-unread"),
                         ["shaders/common.gdshaderinc:unused_inc"])

    def test_uniform_read_by_any_sharing_shader_is_live(self):
        inc = "uniform float shared = 1.0;\n"
        a = 'shader_type spatial;\n#include "res://shaders/c.gdshaderinc"\nvoid fragment() { ALBEDO = vec3(shared); }\n'
        b = 'shader_type spatial;\n#include "res://shaders/c.gdshaderinc"\nvoid fragment() { ALBEDO = vec3(0.0); }\n'
        self.assertEqual(keys({"shaders/a.gdshader": a, "shaders/b.gdshader": b, "shaders/c.gdshaderinc": inc},
                              "uniform-unread"), [])


class GatedTest(unittest.TestCase):
    def test_read_only_behind_a_constant_false_gate_is_found(self):
        self.assertEqual(keys({"shaders/a.gdshader": SHADER}, "uniform-gated"), ["shaders/a.gdshader:inside_gate"])

    def test_gate_set_true_by_a_material_is_live(self):
        files = {"shaders/a.gdshader": SHADER, "m.tres": material({"gate": "true"})}
        self.assertEqual(keys(files, "uniform-gated"), [])

    def test_gate_zero_in_every_material_stays_constant(self):
        files = {"shaders/a.gdshader": SHADER, "m.tres": material({"gate": "false"}),
                 "n.tres": material({})}
        self.assertEqual(keys(files, "uniform-gated"), ["shaders/a.gdshader:inside_gate"])

    def test_gate_written_by_gdscript_is_not_constant(self):
        files = {"shaders/a.gdshader": SHADER,
                 "game/W.gd": 'extends Node\nfunc f(m: ShaderMaterial) -> void:\n\tm.set_shader_parameter(&"gate", true)\n'}
        self.assertEqual(keys(files, "uniform-gated"), [])

    def test_a_read_outside_the_gate_keeps_it_live(self):
        sh = SHADER.replace("ALBEDO = vec3(live);", "ALBEDO = vec3(live + inside_gate);")
        self.assertEqual(keys({"shaders/a.gdshader": sh}, "uniform-gated"), [])

    def test_comparison_gate_and_else_of_a_true_condition(self):
        sh = ("shader_type spatial;\nuniform float amount = 0.0;\nuniform float a = 1.0;\nuniform float b = 1.0;\n"
              "void fragment() {\n\tif (amount > 0.5) { ALBEDO = vec3(a); }\n"
              "\tif (amount < 0.5) { ALBEDO = vec3(0.0); } else { ALBEDO += vec3(b); }\n}\n")
        self.assertEqual(keys({"shaders/a.gdshader": sh}, "uniform-gated"),
                         ["shaders/a.gdshader:a", "shaders/a.gdshader:b"])

    def test_short_circuit_and_unknown_conditions(self):
        sh = ("shader_type spatial;\nuniform bool off = false;\nuniform float x = 1.0;\nuniform float y = 1.0;\n"
              "void fragment() {\n\tif (length(vec2(1.0)) > 0.5 && off) { ALBEDO = vec3(x); }\n"
              "\tif (length(vec2(1.0)) > 0.5 || off) { ALBEDO = vec3(y); }\n}\n")
        self.assertEqual(keys({"shaders/a.gdshader": sh}, "uniform-gated"), ["shaders/a.gdshader:x"])

    def test_single_statement_body_without_braces(self):
        sh = ("shader_type spatial;\nuniform bool off = false;\nuniform float x = 1.0;\n"
              "void fragment() {\n\tif (off) ALBEDO = vec3(x);\n}\n")
        self.assertEqual(keys({"shaders/a.gdshader": sh}, "uniform-gated"), ["shaders/a.gdshader:x"])


class BaselineTest(unittest.TestCase):
    def run_main(self, files, *args):
        with make_repo(files) as root:
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = lint.main(["--path", root] + list(args))
            return code, buf.getvalue(), root

    def test_new_finding_fails_and_update_baseline_then_passes(self):
        with make_repo({"shaders/a.gdshader": SHADER, "tools/keep": ""}) as root:
            buf = io.StringIO()
            with redirect_stdout(buf):
                self.assertEqual(lint.main(["--path", root]), 1)
                self.assertEqual(lint.main(["--path", root, "--update-baseline"]), 0)
                self.assertEqual(lint.main(["--path", root]), 0)
            self.assertIn("LINT SHADER UNIFORMS RED: 2 new", buf.getvalue())
            self.assertIn("LINT SHADER UNIFORMS GREEN: 2 baselined, 0 stale", buf.getvalue())

    def test_stale_baseline_entry_is_reported_but_does_not_fail(self):
        base = {"checks": {"uniform-unread": ["shaders/a.gdshader:dead_one", "shaders/a.gdshader:gone"],
                           "uniform-gated": ["shaders/a.gdshader:inside_gate"]}, "allow": []}
        code, out, _ = self.run_main({"shaders/a.gdshader": SHADER, "tools/shader_uniform_baseline.json": json.dumps(base)})
        self.assertEqual(code, 0)
        self.assertIn("stale baseline entry (no longer found, run --update-baseline): uniform-unread shaders/a.gdshader:gone", out)
        self.assertIn("GREEN: 2 baselined, 1 stale", out)

    def test_allow_entry_is_kept_and_update_refuses_a_new_finding(self):
        base = {"checks": {}, "allow": [{"id": "uniform-unread", "entry": "shaders/a.gdshader:dead_one", "reason": "set by code"}]}
        with make_repo({"shaders/a.gdshader": SHADER, "tools/shader_uniform_baseline.json": json.dumps(base)}) as root:
            buf = io.StringIO()
            with redirect_stdout(buf):
                self.assertEqual(lint.main(["--path", root, "--update-baseline"]), 1)
                self.assertEqual(lint.main(["--path", root]), 1)
            self.assertIn("not baselined (fix it, or add an allow entry with a reason): uniform-gated "
                          "shaders/a.gdshader:inside_gate", buf.getvalue())
            with open(os.path.join(root, "tools", "shader_uniform_baseline.json"), encoding="utf-8") as fh:
                data = json.load(fh)
            self.assertEqual([a["entry"] for a in data["allow"]], ["shaders/a.gdshader:dead_one"])
            self.assertEqual(data["checks"]["uniform-unread"], [])
            self.assertEqual(data["checks"]["uniform-gated"], [])


if __name__ == "__main__":
    unittest.main()
