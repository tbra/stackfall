"""Unit tests for tools/lint_layers.py (Bontago-1pi.11.77.4) on synthetic graphs.

Run: python tools/test_lint_layers.py   (or python -m unittest tools.test_lint_layers)
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lint_layers  # noqa: E402


def make_graph(edges, autoloads=None, extra_files=()):
    names = set(extra_files)
    for s, d, _k in edges:
        names.add(s)
        names.add(d)
    for p in (autoloads or {}).values():
        names.add(p)
    files = dict((p, {"path": p, "kind": "script", "loc": 10}) for p in names)
    return {"files": files, "autoloads": dict(autoloads or {}),
            "file_edges": [{"src": s, "dst": d, "kind": k, "line": 1} for s, d, k in edges]}


AUTO = {"Match": "autoload/Match.gd", "Net": "autoload/Net.gd"}


class LintLayersTest(unittest.TestCase):
    def check(self, graph, base):
        return lint_layers.evaluate(lint_layers.measure(graph), base)

    def test_l1_hits_class_and_autoload_use(self):
        g = make_graph([("game/specials/A.gd", "autoload/Match.gd", "autoload_use"),
                        ("core/B.gd", "autoload/Net.gd", "class"),
                        ("vfx/C.gd", "net/MatchNet.gd", "preload"),
                        ("game/Field.gd", "autoload/match/MatchStats.gd", "ext_resource"),
                        ("ui/D.gd", "autoload/Match.gd", "class")], AUTO)
        v = [x for x in self.check(g, {"largest_scc": 0}) if x.startswith("L1")]
        self.assertEqual(len(v), 4)
        self.assertFalse(any("ui/D.gd" in x for x in v))

    def test_l1_path_edge_ignored(self):
        g = make_graph([("config/weather/rain.tres", "autoload/match/RainEffect.gd", "path")], AUTO)
        self.assertEqual([x for x in self.check(g, {}) if x.startswith("L1")], [])

    def test_l1_baselined_exception_passes(self):
        g = make_graph([("game/specials/A.gd", "autoload/Match.gd", "class")], AUTO)
        base = {"largest_scc": 0, "l1_exceptions": ["game/specials/A.gd -> autoload/Match.gd"],
                "closure": ["autoload/Match.gd", "autoload/Net.gd"]}
        self.assertEqual(self.check(g, base), [])

    def test_scc_growth_fails(self):
        g = make_graph([("a.gd", "b.gd", "class"), ("b.gd", "c.gd", "class"), ("c.gd", "a.gd", "class")], {})
        self.assertTrue(any(x.startswith("L2 largest") for x in self.check(g, {"largest_scc": 2})))
        self.assertEqual([x for x in self.check(g, {"largest_scc": 3}) if x.startswith("L2")], [])

    def test_allow_listed_autoload_pair_passes_others_fail(self):
        g = make_graph([("autoload/Match.gd", "autoload/Net.gd", "autoload_use"),
                        ("autoload/Net.gd", "autoload/Match.gd", "autoload_use")], AUTO)
        base = {"largest_scc": 2, "autoload_scc_pairs": [["autoload/Match.gd", "autoload/Net.gd"]],
                "closure": ["autoload/Match.gd", "autoload/Net.gd"]}
        self.assertEqual(self.check(g, base), [])
        base["autoload_scc_pairs"] = []
        self.assertTrue(any("non-allow-listed" in x for x in self.check(g, base)))

    def test_late_scripts_edges_excluded_from_scc(self):
        # LateScripts names scripts by path string; those edges must not fuse autoloads into an SCC.
        g = make_graph([("autoload/Match.gd", "autoload/LateScripts.gd", "class"),
                        ("autoload/LateScripts.gd", "autoload/Match.gd", "path")], AUTO)
        m = lint_layers.measure(g)
        self.assertEqual(m["auto_sccs"], [])
        self.assertEqual(m["largest_scc"], 0)
        g2 = make_graph([("autoload/Match.gd", "x.gd", "class"), ("x.gd", "autoload/Match.gd", "class")], AUTO)
        self.assertEqual(lint_layers.measure(g2)["largest_scc"], 2)

    def test_new_closure_file_fails(self):
        g = make_graph([("autoload/Match.gd", "game/New.gd", "class")], AUTO)
        base = {"largest_scc": 0, "closure": ["autoload/Match.gd", "autoload/Net.gd"]}
        self.assertEqual([x for x in self.check(g, base) if x.startswith("L3")],
                         ["L3 game/New.gd entered the autoload closure"])

    def test_closure_ignores_path_edges(self):
        g = make_graph([("autoload/Match.gd", "config/x.tres", "path")], AUTO)
        self.assertNotIn("config/x.tres", lint_layers.measure(g)["closure"])

    def test_update_never_raises_and_allow_new_adds(self):
        g = make_graph([("autoload/Match.gd", "game/Old.gd", "class")], AUTO)
        cur = lint_layers.measure(g)
        base = lint_layers.initial_baseline(cur)
        smaller = make_graph([], AUTO)
        low = lint_layers.lowered(lint_layers.measure(smaller), base)
        self.assertNotIn("game/Old.gd", low["closure"])
        grown = make_graph([("autoload/Match.gd", "game/Old.gd", "class"),
                            ("autoload/Match.gd", "game/New.gd", "class"),
                            ("game/specials/Z.gd", "autoload/Match.gd", "class")], AUTO)
        gcur = lint_layers.measure(grown)
        same = lint_layers.lowered(gcur, base)
        self.assertNotIn("game/New.gd", same["closure"])
        self.assertEqual(same["l1_exceptions"], [])
        added = lint_layers.apply_allow_new(same, gcur, ["game/New.gd", "game/specials/Z.gd"])
        self.assertIn("game/New.gd", added["closure"])
        self.assertEqual(added["l1_exceptions"], ["game/specials/Z.gd -> autoload/Match.gd"])

    def test_run_report_exit_codes(self):
        g = make_graph([("game/specials/A.gd", "autoload/Match.gd", "class")], AUTO)
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "b.json")
            with open(path, "w") as fh:
                json.dump({"largest_scc": 0}, fh)
            code, lines = lint_layers.run(tmp, baseline_path=path, graph=g)
            self.assertEqual(code, 1)
            self.assertEqual(lines[-1], "LAYER LINT RED")
            code, lines = lint_layers.run(tmp, report=True, baseline_path=path, graph=g)
            self.assertEqual(code, 0)
            self.assertTrue(lines[-1].startswith("LAYER LINT GREEN"))


if __name__ == "__main__":
    unittest.main()
