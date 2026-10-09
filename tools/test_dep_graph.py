"""Unit tests for tools/dep_graph.py (Bontago-fca.52) on a tiny synthetic project.

Run: python -m unittest tools.test_dep_graph   (from the repo root)
"""
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dep_graph  # noqa: E402

FIXTURE = {
    "project.godot": (
        '[application]\nrun/main_scene="res://main.tscn"\nconfig/icon="res://art/icon.png"\n'
        '[autoload]\nBus="*res://autoload/Bus.gd"\nSvc="*res://autoload/Svc.gd"\n'
    ),
    "export_presets.cfg": '[preset.0]\nexclude_filter="tests/*"\n',
    "main.tscn": (
        '[gd_scene load_steps=3 format=3 uid="uid://scene_main"]\n\n'
        '[ext_resource type="Script" path="res://main.gd" id="1"]\n'
        '[ext_resource type="Texture2D" uid="uid://tex_stale" path="res://stale/old_name.png" id="2"]\n\n'
        '[node name="Main" type="Node"]\nscript = ExtResource("1")\n\n'
        '[connection signal="pressed" from="Btn" to="." method="handle_press"]\n'
    ),
    "main.gd": (
        "class_name Main\nextends Node\n\n"
        'const Pre := preload("res://live/Helper.gd")\n\n'
        "func _ready() -> void:\n"
        "\tUtil.helper()\n"
        "\tSvc.go()\n"
        "\tBus.fired.emit()\n"
        "\tBus.fired.connect(_on_fired)\n"
        "\tvar p: P = P.new()\n"
        "\tp.run()\n"
        "\tvar t: Thing = Thing.new()\n"
        '\tvar id := "a"\n'
        '\tload("res://data/%s.tres" % id)\n'
        '\t# load("res://commented/out.tres")\n'
        "\tPre.assist()\n"
        '\tcall_deferred("deferred_target")\n\n'
        "func handle_press() -> void:\n\tpass\n\n"
        "func _on_fired() -> void:\n\tpass\n\n"
        "func deferred_target() -> void:\n\tpass\n\n"
        "func truly_unused() -> void:\n\tpass\n"
    ),
    "main.gd.uid": "uid://script_main\n",
    "art/icon.png": "png",
    "art/icon.png.import": '[remap]\nuid="uid://tex_stale"\n',
    "art/unused.png": "png",
    "art/unused.png.import": '[remap]\nuid="uid://tex_unused"\n',
    "art/gone.png.import": '[remap]\nuid="uid://tex_gone"\n',
    "autoload/Bus.gd": "extends Node\nsignal fired\nsignal never_emitted\n\nfunc poke() -> void:\n\tSvc.go()\n",
    "autoload/Svc.gd": "extends Node\n\nfunc go() -> void:\n\tBus.poke()\n",
    "core/Util.gd": (
        "class_name Util\nextends RefCounted\n\n"
        "static func helper() -> void:\n\tpass\n\n"
        "static func test_only() -> void:\n\tpass\n\n"
        "static func never_called() -> void:\n\tpass\n"
    ),
    "core/Bad.gd": "extends RefCounted\n\nfunc f() -> Thing:\n\treturn Thing.new()\n",
    "game/Thing.gd": "class_name Thing\nextends Node\n",
    "live/P.gd": "class_name P\nextends RefCounted\n\nfunc run() -> void:\n\tQ.new().back()\n",
    "live/Q.gd": "class_name Q\nextends RefCounted\n\nfunc back() -> void:\n\tP.new().run()\n",
    "live/Helper.gd": "extends RefCounted\n\nstatic func assist() -> void:\n\tpass\n",
    "dead/A.gd": (
        'extends RefCounted\nconst B := preload("res://dead/B.gd")\n\n'
        "func ping() -> void:\n\tB.pong()\n"
    ),
    "dead/B.gd": (
        'extends RefCounted\nconst A := preload("res://dead/A.gd")\n\n'
        "func pong() -> void:\n\tA.ping()\n"
    ),
    "data/a.tres": "[gd_resource type=\"Resource\" format=3]\n",
    "data/b.tres": "[gd_resource type=\"Resource\" format=3]\n",
    "tests/unit/t.gd": (
        "extends GutTest\n\nfunc test_x() -> void:\n\tUtil.test_only()\n\tload(\"res://art/testonly.png\")\n"
    ),
    "art/testonly.png": "png",
    "art/testonly.png.import": '[remap]\nuid="uid://tex_to"\n',
}


class DepGraphTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="depgraph_fixture_")
        for rel, body in FIXTURE.items():
            path = os.path.join(cls.tmp, rel.replace("/", os.sep))
            if not os.path.isdir(os.path.dirname(path)):
                os.makedirs(os.path.dirname(path))
            with open(path, "w") as fh:
                fh.write(body)
        cls.g = dep_graph.build_graph(cls.tmp)
        cls.live = dep_graph.func_liveness(cls.g)
        cls.cy = dep_graph.analyze_cycles(cls.g, cls.live)
        cls.an = dep_graph.analyze(cls.g)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def edge(self, src, dst, kind=None):
        for e in self.g["file_edges"]:
            if e["src"] == src and e["dst"] == dst and (kind is None or e["kind"] == kind):
                return e
        return None

    def cedge(self, src, dst):
        for e in self.g["call_edges"]:
            if e["src"] == src and e["dst"] == dst:
                return e
        return None

    def test_uid_resolution_prefers_uid_over_stale_path(self):
        self.assertIn("uid://tex_stale", self.g["uids"])
        self.assertIsNotNone(self.edge("main.tscn", "art/icon.png", "ext_resource"))
        self.assertEqual(self.g["uids"]["uid://script_main"], "main.gd")

    def test_ext_resource_and_project_edges(self):
        self.assertIsNotNone(self.edge("main.tscn", "main.gd", "ext_resource"))
        self.assertIsNotNone(self.edge("project.godot", "main.tscn"))
        self.assertIsNotNone(self.edge("project.godot", "autoload/Bus.gd", "autoload"))

    def test_class_name_autoload_and_preload_edges(self):
        self.assertIsNotNone(self.edge("main.gd", "core/Util.gd", "class"))
        self.assertIsNotNone(self.edge("main.gd", "autoload/Svc.gd", "autoload_use"))
        self.assertIsNotNone(self.edge("main.gd", "live/Helper.gd", "preload"))

    def test_comments_are_ignored(self):
        self.assertFalse([b for b in self.g["broken"] if "commented" in b["ref"]])
        self.assertIsNone(self.edge("main.gd", "data/a.tres", "path"))

    def test_dynamic_path_flagged_with_pattern(self):
        e = self.edge("main.gd", "data/a.tres", "dynamic")
        self.assertIsNotNone(e)
        self.assertIn("%s", e["pattern"])
        self.assertIsNotNone(self.edge("main.gd", "data/b.tres", "dynamic"))
        self.assertEqual(self.g["files"]["data/a.tres"]["status"], "dynamic-only")

    def test_call_edges(self):
        ready = "main.gd:_ready"
        self.assertIsNotNone(self.cedge(ready, "core/Util.gd:helper"))
        self.assertIsNotNone(self.cedge(ready, "autoload/Svc.gd:go"))
        self.assertIsNotNone(self.cedge(ready, "live/P.gd:run"))
        self.assertIsNotNone(self.cedge(ready, "live/Helper.gd:assist"))
        self.assertIsNotNone(self.cedge(ready, "main.gd:_on_fired"))
        self.assertIsNotNone(self.cedge(ready, "main.gd:deferred_target"))

    def test_scene_connection_edge(self):
        e = self.cedge("main.tscn", "main.gd:handle_press")
        self.assertIsNotNone(e)
        self.assertEqual(e["kind"], "scene")

    def test_signals(self):
        s = self.g["signals"]
        self.assertTrue(s["fired"]["emit"])
        self.assertTrue(s["fired"]["listen"])
        self.assertIn("never_emitted", self.an["signals"]["never_emitted"])

    def test_callers_query(self):
        res = dep_graph.callers_of(self.g, "Util.helper")
        self.assertEqual(len(res), 1)
        self.assertEqual([e["src"] for e in res[0][1]], ["main.gd:_ready"])
        text = dep_graph.format_callers(self.g, "core/Util.gd:helper")
        self.assertIn("main.gd:_ready", text)

    def test_refs_query(self):
        inb, outb = dep_graph.refs_of(self.g, "core/Util.gd")
        self.assertIn("main.gd", [e["src"] for e in inb])
        self.assertIn("core/Util.gd", dep_graph.format_refs(self.g, "core/Util.gd"))

    def test_unused_files_and_roots(self):
        files = self.g["files"]
        self.assertEqual(files["project.godot"]["status"], "root")
        self.assertEqual(files["main.gd"]["status"], "live")
        self.assertEqual(files["art/unused.png"]["status"], "unreachable")
        self.assertEqual(files["art/testonly.png"]["status"], "test-tool-only")
        self.assertIn("art/unused.png", self.an["files"]["unreachable"])
        self.assertIn("art/testonly.png", self.an["files"]["test-tool-only"])
        self.assertNotIn("art/icon.png", self.an["files"]["unreachable"])

    def test_dead_island_is_unreachable_despite_inbound_refs(self):
        # dead/A and dead/B reference each other, so each HAS an inbound edge.
        self.assertIsNotNone(self.edge("dead/A.gd", "dead/B.gd"))
        self.assertEqual(self.g["files"]["dead/A.gd"]["status"], "unreachable")
        self.assertEqual(self.g["files"]["dead/B.gd"]["status"], "unreachable")
        self.assertNotIn("dead/A.gd", self.an["no_inbound"])
        self.assertIn("dead/A.gd", self.an["files"]["unreachable"])

    def test_sidecar_orphan(self):
        orphans = [s["path"] for s in self.an["orphan_sidecars"]]
        self.assertEqual(orphans, ["art/gone.png.import"])

    def test_function_unused_and_roots(self):
        fs = self.an["funcs"]
        self.assertIn("main.gd:truly_unused", fs["zero_callers"])
        self.assertIn("core/Util.gd:never_called", fs["zero_callers"])
        self.assertNotIn("main.gd:_ready", fs["zero_callers"])
        self.assertNotIn("main.gd:handle_press", fs["zero_callers"])
        self.assertEqual(self.live["core/Util.gd:helper"], "live")
        self.assertEqual(self.live["core/Util.gd:test_only"], "test-tool-only")
        self.assertEqual(self.live["tests/unit/t.gd:test_x"], "test-tool-only")

    def test_dead_cycle_functions_are_dead(self):
        self.assertEqual(self.live["dead/A.gd:ping"], "dead")
        self.assertEqual(self.live["dead/B.gd:pong"], "dead")
        # Callers exist (each other) so these are dead-chain, not zero-callers; dead files are skipped
        # in the per-function report, but the function SCC is classified as a dead island.
        classes = [c["class"] for c in self.cy["func_sccs"]
                   if "dead/A.gd:ping" in c["members"]]
        self.assertEqual(classes, ["dead-island"])

    def test_live_cycle(self):
        live = [c for c in self.cy["file_sccs"] if "live/P.gd" in c["members"]]
        self.assertEqual(len(live), 1)
        self.assertEqual(live[0]["class"], "live")
        self.assertEqual(sorted(live[0]["members"]), ["live/P.gd", "live/Q.gd"])
        self.assertEqual(live[0]["example"][0], live[0]["example"][-1])
        fl = [c for c in self.cy["func_sccs"] if "live/P.gd:run" in c["members"]]
        self.assertEqual(fl[0]["class"], "live")

    def test_dead_file_cycle_and_preload_cycle(self):
        dead = [c for c in self.cy["file_sccs"] if "dead/A.gd" in c["members"]]
        self.assertEqual(dead[0]["class"], "dead-island")
        pre = [c for c in self.cy["preload_sccs"] if "dead/A.gd" in c["members"]]
        self.assertEqual(len(pre), 1)
        self.assertEqual(sorted(pre[0]["members"]), ["dead/A.gd", "dead/B.gd"])
        # Helper.gd is preloaded once and not part of a preload cycle.
        self.assertFalse([c for c in self.cy["preload_sccs"] if "live/Helper.gd" in c["members"]])

    def test_autoload_cycle(self):
        c = [x for x in self.cy["file_sccs"] if "autoload/Bus.gd" in x["members"]]
        self.assertEqual(len(c), 1)
        self.assertEqual(sorted(c[0]["autoloads"]), ["Bus", "Svc"])
        self.assertIn("Bus", c[0]["autoload_cycles"])
        self.assertIn("autoload", dep_graph.render_cycles_md(self.g, self.cy))

    def test_layer_violation_core_to_game(self):
        v = [x for x in self.cy["layer_violations"] if x["src"] == "core/Bad.gd"]
        self.assertEqual(len(v), 1)
        self.assertEqual(v[0]["dst"], "game/Thing.gd")
        self.assertIn("layer", self.g["files"]["core/Bad.gd"]["flags"])
        self.assertFalse([x for x in self.cy["layer_violations"] if x["src"] == "core/Util.gd"])

    def test_tarjan_and_cycle_through(self):
        adj = {"a": {"b"}, "b": {"c"}, "c": {"a"}, "d": {"a"}}
        sccs = dep_graph.tarjan_scc(adj)
        self.assertIn(["a", "b", "c"], sccs)
        self.assertEqual(dep_graph.cycle_through(adj, ["a", "b", "c"], "a"), ["a", "b", "c", "a"])

    def test_outputs_written(self):
        out = os.path.join(self.tmp, "_out")
        dep_graph.write_outputs(self.g, out)
        for name in ("graph.json", "mindmap.html", "unused.md", "cycles.md"):
            self.assertTrue(os.path.getsize(os.path.join(out, name)) > 0, name)
        with open(os.path.join(out, "mindmap.html")) as fh:
            html = fh.read()
        self.assertIn("main.gd", html)
        self.assertNotIn("http://", html.replace("http://www.w3.org", ""))


if __name__ == "__main__":
    unittest.main()
