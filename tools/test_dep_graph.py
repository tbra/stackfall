"""Unit tests for tools/dep_graph.py on a tiny synthetic project.

Run: python -m unittest tools.test_dep_graph   (from the repo root)
"""
import os
import shutil
import subprocess
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


class GraphViewerPayloadTest(DepGraphTest):
    """graph.html payload and template. Reuses the DepGraphTest fixture graph."""

    @classmethod
    def setUpClass(cls):
        super(GraphViewerPayloadTest, cls).setUpClass()
        cls.g["cycles"] = cls.cy
        cls.pl = dep_graph.build_viewer_payload(cls.g)

    def test_module_assignment_and_depth(self):
        self.assertEqual(dep_graph.module_of("main.gd"), "(root)")
        self.assertEqual(dep_graph.module_of("core/ai/sub/deep/X.gd"), "core/ai")
        self.assertEqual(dep_graph.module_of("source_art/x/y/z.png"), "source_art")
        self.assertEqual(dep_graph.module_of("autoload/Bus.gd"), "autoload")

    def test_module_edges_equal_sum_of_file_edges(self):
        pl = self.pl
        files = pl["files"]
        # Brute force from the raw graph: count file edges per (module a, module b).
        want = {}
        for e in self.g["file_edges"]:
            a, b = dep_graph.module_of(e["src"]), dep_graph.module_of(e["dst"])
            if a != b:
                want[(a, b)] = want.get((a, b), 0) + 1
        got = {}
        for a, b, c in pl["medges"]:
            got[(pl["mods"][a][0], pl["mods"][b][0])] = c
        self.assertEqual(got, want)
        self.assertTrue(want, "fixture should have cross-folder edges")
        # Folder file counts and LOC are sums of their files.
        for i, m in enumerate(pl["mods"]):
            members = [f for f in files if f[1] == i]
            self.assertEqual(m[2], len(members))
            self.assertEqual(m[3], sum(f[4] for f in members))

    def test_file_edges_merge_without_loss(self):
        total = sum(c for _, _, _, c in self.pl["edges"])
        self.assertEqual(total, len(self.g["file_edges"]))

    def test_filter_defaults(self):
        d = self.pl["defaults"]
        self.assertFalse(d["tests"])
        self.assertFalse(d["tools"])
        self.assertFalse(d["assets"])
        self.assertEqual(len(d["groups"]), len(dep_graph.EDGE_GROUPS))
        self.assertEqual(d["groups"][dep_graph.EDGE_GROUPS.index("dynamic")], 0)
        self.assertEqual(d["groups"][dep_graph.EDGE_GROUPS.index("extends")], 1)
        by_path = dict((f[0], f) for f in self.pl["files"])
        self.assertEqual(by_path["main.gd"][10], 1)
        self.assertEqual(by_path["art/icon.png"][10], 0)

    def test_scc_flags_copied_to_nodes(self):
        by_path = dict((f[0], f) for f in self.pl["files"])
        self.assertTrue(self.cy["file_sccs"], "fixture has a file cycle")
        for sid, c in enumerate(self.cy["file_sccs"]):
            self.assertEqual(self.pl["sccs"][sid], [c["size"], c["class"]])
            for m in c["members"]:
                self.assertEqual(by_path[m][9], sid)
                self.assertTrue(by_path[m][6] & dep_graph.FLAG_BITS["cycle"], m)
        for p, f in by_path.items():
            if f[9] < 0:
                self.assertFalse(f[6] & dep_graph.FLAG_BITS["cycle"], p)
        for name, path in self.g["autoloads"].items():
            self.assertTrue(by_path[path][6] & dep_graph.FLAG_AUTOLOAD)
            self.assertEqual(by_path[path][11], name)

    # ---- function call view payload ----
    def fv_rows(self, path):
        pl = self.pl
        idx = [f[0] for f in pl["files"]].index(path)
        fv = pl["fv"]
        return idx, [(r, fv["fn"][r]) for r in range(fv["fstart"][idx], fv["fstart"][idx + 1])]

    def test_function_payload_has_every_function_with_line_ranges(self):
        for path in ("main.gd", "core/Util.gd", "autoload/Bus.gd"):
            _idx, rows = self.fv_rows(path)
            want = sorted((f["name"], f["line"], f["end"]) for f in self.g["funcs"].values() if f["file"] == path)
            self.assertTrue(want, path)
            self.assertEqual(sorted((r[0], r[1], r[2]) for _, r in rows), want)
        total = sum(len(self.fv_rows(f[0])[1]) for f in self.pl["files"])
        self.assertEqual(total, len(self.g["funcs"]))
        self.assertEqual(len(self.pl["fv"]["fstart"]), len(self.pl["files"]) + 1)

    def test_function_flags_and_liveness_codes(self):
        _i, rows = self.fv_rows("core/Util.gd")
        by = dict((r[0], r) for _, r in rows)
        self.assertTrue(by["helper"][3] & dep_graph.FN_STATIC)
        self.assertEqual(by["helper"][4], dep_graph.LIVE_CODES["live"])
        self.assertEqual(by["never_called"][4], dep_graph.LIVE_CODES["dead"])
        self.assertEqual(by["test_only"][4], dep_graph.LIVE_CODES["test-tool-only"])
        for fid, f in self.g["funcs"].items():
            if f["file"] == "main.gd":
                row = self.fv_rows("main.gd")[1]
                got = [r for _, r in row if r[0] == f["name"]][0]
                self.assertEqual(got[4], dep_graph.LIVE_CODES[self.live[fid]], fid)

    def test_call_edges_map_to_ids_and_kinds(self):
        fv = self.pl["fv"]
        order = {}
        for fi, f in enumerate(self.pl["files"]):
            for r in range(fv["fstart"][fi], fv["fstart"][fi + 1]):
                order[r] = f[0] + ":" + fv["fn"][r][0]
        got = set()
        for s, d, k, amb in fv["ce"]:
            src = order[s] if s >= 0 else self.pl["files"][-(s + 1)][0]
            got.add((src, order[d], fv["ckinds"][k], amb))
        want = set((e["src"], e["dst"], e["kind"], 1 if e["amb"] else 0) for e in self.g["call_edges"])
        self.assertEqual(got, want)
        self.assertTrue(any(s == "main.gd:_ready" and d == "core/Util.gd:helper" for s, d, _k, _a in got))

    def test_file_level_callers_use_negative_file_index(self):
        fv = self.pl["fv"]
        tscn = [f[0] for f in self.pl["files"]].index("main.tscn")
        hits = [e for e in fv["ce"] if e[0] == -(tscn + 1)]
        self.assertTrue(hits, "scene connection is a file-level caller")
        self.assertEqual(fv["ckinds"][hits[0][2]], "scene")
        self.assertTrue(all(e[0] >= 0 or -(e[0] + 1) < len(self.pl["files"]) for e in fv["ce"]))

    def test_ambiguous_flag_kept_and_hidden_by_default(self):
        fv = self.pl["fv"]
        g2 = dict(self.g)
        g2["call_edges"] = list(self.g["call_edges"]) + [
            {"src": "main.gd:_ready", "dst": "core/Util.gd:test_only", "kind": "ambiguous", "line": 1, "amb": True}]
        fv = dep_graph.build_viewer_payload(g2)["fv"]
        want = sum(1 for e in g2["call_edges"] if e["amb"])
        self.assertGreaterEqual(want, 1)
        self.assertEqual(sum(1 for e in fv["ce"] if e[3]), want)
        self.assertEqual(fv["ckoff"][fv["ckinds"].index("ambiguous")], 1)
        self.assertEqual(fv["ckoff"][fv["ckinds"].index("typed")], 0)

    def test_signal_roles_attached_to_functions(self):
        fv = self.pl["fv"]
        names = fv["sigs"]
        self.assertIn("fired", names)
        _i, rows = self.fv_rows("main.gd")
        ready = [r for r, row in rows if row[0] == "_ready"][0]
        roles = set((names[s], role) for s, role in fv["fsig"][ready])
        self.assertIn(("fired", 0), roles)
        self.assertIn(("fired", 1), roles)

    def test_function_payload_is_compact(self):
        import json
        fv = self.pl["fv"]
        size = len(json.dumps(fv, separators=(",", ":")))
        self.assertLess(size / float(len(fv["ce"]) + len(fv["fn"])), 60.0)
        self.assertLess(size, 1024 * 1024)

    def test_template_filled_and_size_bounded(self):
        html = dep_graph.render_graph_html(self.g)
        self.assertNotIn(dep_graph.VIEWER_PLACEHOLDER, html)
        self.assertIn("main.gd", html)
        self.assertNotIn("http://", html)
        self.assertNotIn("https://", html)
        self.assertLess(len(html), 5 * 1024 * 1024)
        with open(dep_graph.VIEWER_TEMPLATE) as fh:
            self.assertIn(dep_graph.VIEWER_PLACEHOLDER, fh.read())

    def test_graph_html_written(self):
        out = os.path.join(self.tmp, "_out_viewer")
        dep_graph.write_outputs(self.g, out)
        self.assertTrue(os.path.getsize(os.path.join(out, "graph.html")) > 0)
        self.assertTrue(os.path.getsize(os.path.join(out, "mindmap.html")) > 0)


FIXTURE_FP = {
    "project.godot": '[application]\nrun/main_scene="res://main.gd"\n',
    ".gutconfig.json": "{}",
    "main.gd": (
        "extends Node\n\n"
        'const D := preload("res://dyn/")\n\n'
        "func _ready() -> void:\n"
        '\tvar tuning: SnowT = preload("res://snow.tres") as SnowT\n'
        "\ttuning.density()\n"
        "\tvar s: Sub = Sub.new()\n"
        "\ts.hook()\n"
        "\tvar d: Dictionary = {}\n"
        "\td.count_items()\n"
        "\tvar thing = null\n"
        "\tthing.fetch()\n"
        '\tif FileAccess.file_exists("res://guarded/none.png"):\n\t\tpass\n'
        '\tload("res://__missing_scene__.tscn")\n'
        '\tload("res://truly/gone.png")\n'
    ),
    "snow.tres": (
        '[gd_resource type="Resource" script_class="SnowT" load_steps=2 format=3]\n'
        '[ext_resource type="Script" path="res://SnowT.gd" id="1"]\n[resource]\nscript = ExtResource("1")\n'
    ),
    "SnowT.gd": (
        'class_name SnowT\nextends Resource\n\nconst SELF_RES := preload("res://snow.tres")\n\n'
        "func density() -> float:\n\treturn 1.0\n"
    ),
    "Base.gd": "class_name Base\nextends RefCounted\n\nfunc hook() -> void:\n\tpass\n",
    "Sub.gd": "class_name Sub\nextends Base\n\nfunc hook() -> void:\n\tpass\n",
    "A.gd": "class_name A\nextends RefCounted\n\nfunc count_items() -> int:\n\treturn 0\n",
    "B.gd": "class_name B\nextends RefCounted\n\nfunc count_items() -> int:\n\treturn 1\n",
    "Fetcher.gd": "class_name Fetcher\nextends RefCounted\n\nfunc fetch() -> int:\n\treturn 1\n",
    "tests/FakeFetcher.gd": "extends RefCounted\n\nfunc fetch() -> int:\n\treturn 2\n",
    "dyn/one.tres": '[gd_resource type="Resource" format=3]\n[ext_resource type="Texture2D" path="res://dyn_tex.png" id="1"]\n',
    "dyn_tex.png": "png",
    "source_art/x/project.godot.review": "config_version=5\n",
    "source_art/x/tool.gd": 'extends Node\n\nfunc _ready() -> void:\n\tload("res://sheets/own_root.png")\n',
    "ignored/skip.png": "png",
    ".gitignore": "ignored/\n",
}


class FalsePositiveFixesTest(unittest.TestCase):
    """one fixture assertion per fixed false-positive pattern."""

    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="depgraph_fp_")
        for rel, body in FIXTURE_FP.items():
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

    def cedge(self, src, dst):
        for e in self.g["call_edges"]:
            if e["src"] == src and e["dst"] == dst:
                return e
        return None

    def test_typed_resource_alias_resolves_to_class(self):
        e = self.cedge("main.gd:_ready", "SnowT.gd:density")
        self.assertIsNotNone(e)
        self.assertEqual(e["kind"], "typed")
        self.assertNotIn("SnowT.gd:density", self.an["funcs"]["zero_callers"])

    def test_called_override_keeps_base_stub_live(self):
        self.assertIsNotNone(self.cedge("main.gd:_ready", "Sub.gd:hook"))
        self.assertEqual(self.live["Base.gd:hook"], "live")
        self.assertNotIn("Base.gd:hook", self.an["funcs"]["zero_callers"])

    def test_value_typed_receiver_does_not_match_project_function(self):
        self.assertIsNone(self.cedge("main.gd:_ready", "A.gd:count_items"))
        self.assertIsNone(self.cedge("main.gd:_ready", "B.gd:count_items"))

    def test_game_caller_ignores_test_double_candidates(self):
        e = self.cedge("main.gd:_ready", "Fetcher.gd:fetch")
        self.assertIsNotNone(e)
        self.assertFalse(e["amb"])
        self.assertIsNone(self.cedge("main.gd:_ready", "tests/FakeFetcher.gd:fetch"))

    def test_intentional_missing_paths_are_not_broken(self):
        refs = [b["ref"] for b in self.g["broken"]]
        self.assertEqual(refs, ["res://truly/gone.png"])
        why = dict((i["ref"], i["why"]) for i in self.g["intentional"])
        self.assertIn("res://__missing_scene__.tscn", why)
        self.assertIn("res://guarded/none.png", why)

    def test_nested_project_refs_are_not_broken(self):
        self.assertFalse([b for b in self.g["broken"] if b["src"].startswith("source_art/")])

    def test_tool_config_is_root(self):
        self.assertEqual(self.g["files"][".gutconfig.json"]["status"], "root")
        self.assertNotIn(".gutconfig.json", self.an["files"]["unreachable"])

    def test_script_and_own_resource_pair_is_not_a_cycle(self):
        self.assertFalse([c for c in self.cy["file_sccs"] if "SnowT.gd" in c["members"]])

    def test_dynamic_only_split_direct_vs_static(self):
        self.assertIn("dyn/one.tres", self.an["files"]["dynamic-direct"])
        self.assertIn("dyn_tex.png", self.an["files"]["dynamic-via-static"])
        self.assertNotIn("dyn_tex.png", self.an["files"]["dynamic-direct"])

    def test_git_checkout_skips_gitignored_files(self):
        if subprocess.call(["git", "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE) != 0:
            self.skipTest("git unavailable")
        self.assertIn("ignored/skip.png", self.g["files"])  # plain walk (no git repo) keeps it
        subprocess.check_call(["git", "init", "-q", self.tmp])
        try:
            g = dep_graph.build_graph(self.tmp)
        finally:
            shutil.rmtree(os.path.join(self.tmp, ".git"), ignore_errors=True)
        self.assertNotIn("ignored/skip.png", g["files"])
        self.assertIn("main.gd", g["files"])


if __name__ == "__main__":
    unittest.main()
