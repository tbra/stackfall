"""Tests for tools/lint_dead.py on small temp-dir fixture repos.

Run: python -m unittest discover -s tools -p test_lint_dead.py
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
import lint_dead  # noqa: E402

TODAY = "2026-10-15"  # lint-public: allow fixture clock for the expiry check
PROJECT = 'config_version=5\n[application]\nrun/main_scene="res://game/Main.tscn"\n'
MAIN_TSCN = ('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://game/Main.gd" id="1"]\n'
             '[node name="Main" type="Node"]\nscript = ExtResource("1")\n')
TSCN = '[gd_scene format=3]\n[node name="N" type="Node"]\n'
TRES = "[gd_resource format=3]\n[resource]\n"


def make_repo(files):
    """Temp repo with a project.godot + Main scene/script; `files` maps rel path -> text and may override."""
    tmp = tempfile.TemporaryDirectory()
    base = {"project.godot": PROJECT, "game/Main.tscn": MAIN_TSCN, "game/Main.gd": "extends Node\n"}
    base.update(files)
    for rel, text in base.items():
        path = os.path.join(tmp.name, *rel.split("/"))
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    return tmp


def findings(files, cid):
    with make_repo(files) as root:
        return [f for f in lint_dead.collect(root.replace("\\", "/"), TODAY) if f[2] == cid]


def keys(files, cid):
    return sorted(f[4] for f in findings(files, cid))


class DeadFileTest(unittest.TestCase):
    def test_unreferenced_file_is_dead_and_loaded_file_is_not(self):
        main = 'extends Node\nfunc _ready() -> void:\n\tload("res://game/Used.tscn")\n'
        self.assertEqual(keys({"game/Main.gd": main, "game/Used.tscn": TSCN, "game/Dead.tscn": TSCN}, "dead-file"),
                         ["game/Dead.tscn"])

    def test_comment_only_mention_does_not_keep_a_file_alive(self):
        main = 'extends Node\n# see res://game/Ghost.tscn\nfunc _ready() -> void:\n\tpass\n'
        self.assertEqual(keys({"game/Main.gd": main, "game/Ghost.tscn": TSCN}, "dead-file"), ["game/Ghost.tscn"])

    def test_test_only_reference_does_not_keep_a_file_alive(self):
        test = 'extends GutTest\nfunc test_x() -> void:\n\tload("res://game/Lonely.tscn")\n'
        self.assertEqual(keys({"tests/unit/test_x.gd": test, "game/Lonely.tscn": TSCN}, "dead-file"), ["game/Lonely.tscn"])

    def test_class_name_use_in_code_keeps_alive_but_not_in_comment(self):
        helper = 'class_name Helper\nextends RefCounted\nstatic func go() -> void:\n\tpass\n'
        live = 'extends Node\nfunc _ready() -> void:\n\tHelper.go()\n'
        self.assertEqual(keys({"game/Main.gd": live, "core/Helper.gd": helper}, "dead-file"), [])
        commented = 'extends Node\n# Helper.go() was removed\nfunc _ready() -> void:\n\tpass\n'
        self.assertEqual(keys({"game/Main.gd": commented, "core/Helper.gd": helper}, "dead-file"), ["core/Helper.gd"])

    def test_folder_scan_edge_reaches_listed_files(self):
        shape = "extends Resource\nclass_name BlockShape\nstatic func load_all() -> void:\n\tpass\n"
        main = 'extends Node\nfunc _ready() -> void:\n\tBlockShape.load_all()\n'
        files = {"game/Main.gd": main, "config/blocks/BlockShape.gd": shape, "config/blocks/cube.tres": TRES,
                 "config/blocks/tuning/deep.tres": TRES, "config/other/x.tres": TRES}
        self.assertEqual(keys(files, "dead-file"), ["config/blocks/tuning/deep.tres", "config/other/x.tres"])

    def test_uid_sidecar_follows_its_file_and_tests_are_never_candidates(self):
        files = {"game/Main.gd.uid": "uid://abc\n", "tests/unit/test_y.gd": "extends GutTest\n", "tools/t.gd": "extends Node\n"}
        self.assertEqual(keys(files, "dead-file"), [])


class FuncTest(unittest.TestCase):
    def test_only_test_callers_and_no_callers_are_flagged(self):
        main = ('extends Node\nfunc _ready() -> void:\n\tlive()\nfunc live() -> void:\n\tpass\n'
                'func tested_only() -> void:\n\tpass\nfunc orphan() -> void:\n\tpass\n')
        test = ('extends GutTest\nfunc test_a() -> void:\n\tvar n: Node = load("res://game/Main.gd").new()\n'
                '\tn.tested_only()\n')
        found = keys({"game/Main.gd": main, "tests/unit/test_a.gd": test}, "test-only-func")
        self.assertEqual(found, ["game/Main.gd:orphan", "game/Main.gd:tested_only"])

    def test_call_through_a_base_type_reaches_overrides_but_unrelated_homonyms_stay_ambiguous(self):
        main = ('extends Node\nfunc _ready() -> void:\n\tport().run()\n\tother().go()\n'
                'func port() -> BasePort:\n\treturn null\nfunc other() -> Node:\n\treturn null\n')
        base = 'class_name BasePort\nextends Node\nfunc run() -> void:\n\tpass\nfunc go() -> void:\n\tpass\n'
        mid = 'class_name MidFlow\nextends BasePort\nfunc run() -> void:\n\tpass\n'
        leaf = 'class_name LeafFlow\nextends "res://game/MidFlow.gd"\nfunc run() -> void:\n\tpass\n'
        stray = 'extends Node\nfunc go() -> void:\n\tpass\n'
        files = {"game/Main.gd": main, "game/BasePort.gd": base, "game/MidFlow.gd": mid,
                 "game/LeafFlow.gd": leaf, "game/Stray.gd": stray}
        found = keys(files, "test-only-func")
        self.assertNotIn("game/MidFlow.gd:run", found)
        self.assertNotIn("game/LeafFlow.gd:run", found)
        self.assertNotIn("game/BasePort.gd:run", found)
        self.assertIn("game/BasePort.gd:go", found)

    def test_signal_string_and_scene_connection_handlers_are_live(self):
        main = ('extends Node\nsignal done\nfunc _ready() -> void:\n\tdone.connect(Callable(self, "on_done"))\n'
                '\tcall_deferred("later")\nfunc on_done() -> void:\n\tpass\nfunc later() -> void:\n\tpass\n'
                'func from_scene() -> void:\n\tpass\n')
        scene = MAIN_TSCN + '[connection signal="pressed" from="." to="." method="from_scene"]\n'
        self.assertEqual(keys({"game/Main.gd": main, "game/Main.tscn": scene}, "test-only-func"), [])

    def test_engine_virtuals_and_signal_handler_names_are_live(self):
        main = 'extends Node\nfunc _process(_d: float) -> void:\n\tpass\nfunc _on_thing() -> void:\n\tpass\n'
        self.assertEqual(keys({"game/Main.gd": main}, "test-only-func"), [])

    def test_ambiguous_name_is_flagged_and_labelled_for_the_allow_list(self):
        other = 'extends Node\nfunc setup() -> void:\n\tpass\n'
        main = 'extends Node\nfunc _ready() -> void:\n\tvar x = get_child(0)\n\tx.setup()\nfunc setup() -> void:\n\tpass\n'
        found = findings({"game/Main.gd": main, "game/Other.gd": other}, "test-only-func")
        self.assertTrue(found)
        self.assertTrue(all("ambiguous" in f[3] for f in found))

    def test_functions_of_dead_files_are_not_double_reported(self):
        dead = 'extends Node\nfunc nobody() -> void:\n\tpass\n'
        self.assertEqual(keys({"game/Dead.gd": dead}, "test-only-func"), [])


class VarTest(unittest.TestCase):
    """test-only-var: a top-level var written in its own script and read only by tests (or nothing)."""
    WRITE = "var hits: int = 0\nfunc _ready() -> void:\n\thits += 1\n"
    TEST_READ = ('extends GutTest\nfunc test_a() -> void:\n\tvar n: Node = load("res://game/Main.gd").new()\n'
                 '\tassert_eq(n.hits, 1)\n')

    def main_with(self, body):
        return "extends Node\n" + body

    def var_keys(self, body, extra=None):
        files = {"game/Main.gd": self.main_with(body), "tests/unit/test_a.gd": self.TEST_READ}
        files.update(extra or {})
        return keys(files, "test-only-var")

    def test_written_in_own_script_and_read_only_by_tests_is_flagged(self):
        self.assertEqual(self.var_keys(self.WRITE), ["game/Main.gd:hits"])

    def test_var_nobody_reads_is_flagged_with_the_message(self):
        got = findings({"game/Main.gd": self.main_with(self.WRITE)}, "test-only-var")
        self.assertEqual([(f[0], f[1]) for f in got], [("game/Main.gd", 2)])
        self.assertIn("read only by tests", got[0][3])

    def test_plain_assignment_and_compound_assignment_are_writes(self):
        body = ("var a: int = 0\nvar b: int = 0\nvar c: int = 0\nfunc _ready() -> void:\n"
                "\ta = 1\n\tself.b = 2\n\tc <<= 1\n")
        self.assertEqual(self.var_keys(body), ["game/Main.gd:a", "game/Main.gd:b", "game/Main.gd:c"])

    def test_read_in_own_script_keeps_it_live(self):
        for read in ("\tprint(hits)\n", "\tif hits >= 3:\n\t\tpass\n", "\thits[0] = 1\n", "\thits.append(1)\n"):
            self.assertEqual(self.var_keys(self.WRITE + read), [], read)

    def test_equality_comparison_is_a_read_not_a_write(self):
        self.assertEqual(self.var_keys(self.WRITE + "\tif hits == 2:\n\t\tpass\n"), [])

    def test_read_by_another_game_file_keeps_it_live(self):
        main = self.WRITE + 'func go() -> void:\n\tload("res://game/Other.gd").new().peek(self)\n'
        other = "extends Node\nfunc peek(m: Node) -> int:\n\treturn m.hits\n"
        self.assertEqual(self.var_keys(main, {"game/Other.gd": other}), [])

    def test_read_by_unreached_file_or_in_comment_does_not_count(self):
        stray = "extends Node\nfunc peek(m: Node) -> int:\n\treturn m.hits\n"
        self.assertEqual(self.var_keys(self.WRITE + "\t# hits is read elsewhere\n", {"game/Stray.gd": stray}),
                         ["game/Main.gd:hits"])

    def test_read_by_a_tools_script_keeps_it_live(self):
        tool = "extends SceneTree\nfunc _init() -> void:\n\tprint(load('res://game/Main.gd').new().hits)\n"
        self.assertEqual(self.var_keys(self.WRITE, {"tools/probe.gd": tool}), [])

    def test_name_inside_a_string_keeps_it_live(self):
        for use in ('\tprint(get("hits"))\n', '\tprint(&"hits")\n', '\tprint(get_node("N:hits"))\n'):
            self.assertEqual(self.var_keys(self.WRITE + use), [], use)

    def test_word_boundary_longer_names_do_not_keep_it_live(self):
        self.assertEqual(self.var_keys(self.WRITE + '\tprint(hits_total, get("hitsx"))\n'), ["game/Main.gd:hits"])

    def test_export_onready_private_and_inline_variants_are_not_candidates(self):
        body = ("@export var a: int = 0\n@export_range(0, 1) var b: float = 0.0\n@onready var c: Node = null\n"
                "@export\nvar d: int = 0\nvar _e: int = 0\nvar f: int = 0 # lint-dead: ignore\n"
                "func _ready() -> void:\n\ta = 1\n\tb = 1.0\n\tc = null\n\td = 1\n\t_e = 1\n\tf = 1\n")
        self.assertEqual(self.var_keys(body), [])

    def test_var_with_setter_or_getter_block_is_not_a_candidate(self):
        body = ("var s: int = 0:\n\tset(v):\n\t\ts = v\n"
                "var g: int = 0:\n\tget:\n\t\treturn 1\n"
                "func _ready() -> void:\n\ts = 1\n\tg = 1\n")
        self.assertEqual(self.var_keys(body), [])

    def test_inner_class_and_local_vars_are_not_candidates(self):
        body = ("class Inner:\n\tvar inner_hits: int = 0\n\tfunc bump() -> void:\n\t\tinner_hits += 1\n"
                "func _ready() -> void:\n\tvar local_hits: int = 0\n\tlocal_hits += 1\n")
        self.assertEqual(self.var_keys(body), [])

    def test_static_var_is_flagged(self):
        body = "static var scans: int = 0\nfunc _ready() -> void:\n\tscans += 1\n"
        self.assertEqual(self.var_keys(body), ["game/Main.gd:scans"])

    def test_unreached_script_vars_are_not_reported(self):
        self.assertEqual(keys({"game/Dead.gd": "extends Node\n" + self.WRITE}, "test-only-var"), [])

    def run_main(self, root, *extra):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = lint_dead.main(["--path", root, "--today", TODAY, *extra])
        return code, buf.getvalue()

    def write_baseline(self, root, data):
        os.makedirs(os.path.join(root, "tools"), exist_ok=True)
        with open(os.path.join(root, "tools", "dead_baseline.json"), "w", encoding="utf-8") as fh:
            json.dump(data, fh)

    def test_baseline_suppresses_and_stale_entry_is_reported(self):
        with make_repo({"game/Main.gd": self.main_with(self.WRITE)}) as root:
            code, out = self.run_main(root)
            self.assertEqual(code, 1)
            self.assertIn("game/Main.gd:2: test-only-var: hits", out)
            self.write_baseline(root, {"checks": {"test-only-var": ["game/Main.gd:hits", "game/Main.gd:gone"]}})
            code, out = self.run_main(root)
            self.assertEqual(code, 0)
            self.assertIn("stale baseline entry", out)
            self.assertIn("game/Main.gd:gone", out)

    def test_update_baseline_refuses_a_new_var_and_drops_a_gone_one(self):
        with make_repo({"game/Main.gd": self.main_with(self.WRITE)}) as root:
            self.write_baseline(root, {"checks": {"test-only-var": ["game/Main.gd:gone"]}})
            code, out = self.run_main(root, "--update-baseline")
            self.assertEqual(code, 1)
            self.assertIn("test-only-var game/Main.gd:hits", out)
            with open(os.path.join(root, "tools", "dead_baseline.json"), encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["checks"]["test-only-var"], [])

    def test_allow_entry_with_a_live_reason_suppresses_and_a_test_reason_does_not(self):
        with make_repo({"game/Main.gd": self.main_with(self.WRITE)}) as root:
            entry = {"id": "test-only-var", "entry": "game/Main.gd:hits", "reason": "read by a scene script via get()"}
            self.write_baseline(root, {"checks": {}, "allow": [entry]})
            self.assertEqual(self.run_main(root)[0], 0)
            entry["reason"] = "used by tests/unit/test_a.gd"
            self.write_baseline(root, {"checks": {}, "allow": [entry]})
            code, out = self.run_main(root)
            self.assertEqual(code, 1)
            self.assertIn("allow entry exempts nothing", out)

    def test_report_lists_the_check(self):
        with make_repo({"game/Main.gd": self.main_with(self.WRITE)}) as root:
            self.assertIn("test-only-var", self.run_main(root, "--report")[1])


class StalePathTest(unittest.TestCase):
    def test_missing_res_path_in_comment_and_string_is_flagged(self):
        main = 'extends Node\n# see res://game/gone.gd\nvar p: String = "res://game/also_gone.tscn"\n'
        self.assertEqual(keys({"game/Main.gd": main}, "stale-path"),
                         ["game/Main.gd: res://game/also_gone.tscn", "game/Main.gd: res://game/gone.gd"])

    def test_existing_paths_templates_and_ignore_marker_pass(self):
        main = ('extends Node\n# res://game/Main.gd and game/Main.tscn and res://game/\n'
                'var a: String = "res://assets/%s.png"\nvar b: String = "res://game/missing.gd" # lint-dead: ignore\n'
                'var c: String = "res://game/*.tscn"\n')
        self.assertEqual(keys({"game/Main.gd": main}, "stale-path"), [])

    def test_repo_relative_path_with_known_extension_or_folder(self):
        py = '# runs tools/gone.py and writes docs/missing/\nprint("config/ok.tres")\n'
        self.assertEqual(keys({"tools/runner.py": py, "config/ok.tres": TRES}, "stale-path"),
                         ["tools/runner.py: docs/missing/", "tools/runner.py: tools/gone.py"])

    def test_only_named_markdown_files_are_scanned(self):
        files = {"README.md": "see tools/gone.py\n", "docs/OTHER.md": "see tools/gone2.py\n"}
        self.assertEqual(keys(files, "stale-path"), ["README.md: tools/gone.py"])

    def test_archive_and_generated_paths_are_skipped(self):
        files = {"docs/archive/OLD.md": "tools/gone.py\n", "README.md": "addons/godotsteam/ and build_info.cfg\n"}
        self.assertEqual(keys(files, "stale-path"), [])


class LegacyTest(unittest.TestCase):
    def test_marker_without_expiry_or_past_expiry_is_flagged(self):
        main = ('extends Node\n# legacy fallback\n# kept for one release\nvar compat_mode: bool = false\n'
                '# deprecated (Bontago-123.1, expires 2026-01-01)\n# legacy (expires 2026-01-02)\n')
        got = findings({"game/Main.gd": main}, "undated-legacy")
        self.assertEqual([f[1] for f in got], [2, 3, 4, 5, 6])
        self.assertIn("expired", got[-2][3])
        self.assertIn("expired", got[-1][3])

    def test_future_expiry_and_unrelated_words_pass(self):
        main = ('extends Node\n# legacy (Bontago-123.1, expires 2026-12-31)\n# legacy (expires 2026-12-31)\n'
                '# compatible with the lobby\n')
        self.assertEqual(findings({"game/Main.gd": main}, "undated-legacy"), [])

    def test_tests_are_not_scanned(self):
        self.assertEqual(findings({"tests/unit/test_z.gd": "# legacy thing\n"}, "undated-legacy"), [])


class BaselineTest(unittest.TestCase):
    def run_main(self, root, *extra):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = lint_dead.main(["--path", root, "--today", TODAY, *extra])
        return code, buf.getvalue()

    def write_baseline(self, root, data):
        os.makedirs(os.path.join(root, "tools"), exist_ok=True)
        with open(os.path.join(root, "tools", "dead_baseline.json"), "w", encoding="utf-8") as fh:
            json.dump(data, fh)

    def test_new_finding_fails_and_baselined_finding_passes(self):
        with make_repo({"game/Dead.tscn": TSCN}) as root:
            code, out = self.run_main(root)
            self.assertEqual(code, 1)
            self.assertIn("game/Dead.tscn:1: dead-file:", out)
            self.assertIn("LINT DEAD RED", out)
            self.write_baseline(root, {"checks": {"dead-file": ["game/Dead.tscn"]}})
            code, out = self.run_main(root)
            self.assertEqual(code, 0)
            self.assertIn("LINT DEAD GREEN: 1 baselined, 0 stale", out)

    def test_stale_baseline_entry_is_reported_but_does_not_fail(self):
        with make_repo({}) as root:
            self.write_baseline(root, {"checks": {"dead-file": ["game/Gone.tscn"]}})
            code, out = self.run_main(root)
            self.assertEqual(code, 0)
            self.assertIn("stale baseline entry", out)
            self.assertIn("game/Gone.tscn", out)

    def test_allow_list_entry_suppresses_and_goes_stale_when_unused(self):
        files = {"game/Main.gd": "extends Node\nfunc orphan() -> void:\n\tpass\n"}
        with make_repo(files) as root:
            allow = [{"id": "test-only-func", "entry": "game/Main.gd:orphan", "reason": "called via a dynamic string"}]
            self.write_baseline(root, {"checks": {}, "allow": allow})
            code, _ = self.run_main(root)
            self.assertEqual(code, 0)
            unused = {"id": "test-only-func", "entry": "game/Main.gd:gone", "reason": "x"}
            self.write_baseline(root, {"checks": {}, "allow": allow + [unused]})
            code, out = self.run_main(root)
            self.assertEqual(code, 0)
            self.assertIn("stale allow entry", out)

    def test_update_baseline_only_shrinks_and_refuses_new_findings(self):
        files = {"game/Dead.tscn": TSCN, "game/Main.gd": "extends Node\nfunc orphan() -> void:\n\tpass\n"}
        with make_repo(files) as root:
            allow = [{"id": "test-only-func", "entry": "game/Main.gd:orphan", "reason": "r"}]
            self.write_baseline(root, {"checks": {"dead-file": ["game/Old.tscn"]}, "allow": allow})
            code, out = self.run_main(root, "--update-baseline")
            self.assertEqual(code, 1)
            self.assertIn("not baselined (fix it, or add an allow entry with a reason): dead-file game/Dead.tscn", out)
            with open(os.path.join(root, "tools", "dead_baseline.json"), encoding="utf-8") as fh:
                data = json.load(fh)
            self.assertEqual(data["checks"]["dead-file"], [])
            self.assertEqual(data["allow"], allow)
            self.write_baseline(root, {"checks": {"dead-file": ["game/Dead.tscn", "game/Old.tscn"]}, "allow": allow})
            code, _ = self.run_main(root, "--update-baseline")
            self.assertEqual(code, 0)
            with open(os.path.join(root, "tools", "dead_baseline.json"), encoding="utf-8") as fh:
                self.assertEqual(json.load(fh)["checks"]["dead-file"], ["game/Dead.tscn"])

    def test_allow_reason_that_is_empty_or_a_test_exempts_nothing(self):
        files = {"game/Main.gd": "extends Node\nfunc orphan() -> void:\n\tpass\n"}
        with make_repo(files) as root:
            for reason in ("", "used by tests/unit/test_main.gd", "test_main.gd drives it", "tests only"):
                allow = [{"id": "test-only-func", "entry": "game/Main.gd:orphan", "reason": reason}]
                self.write_baseline(root, {"checks": {}, "allow": allow})
                code, out = self.run_main(root)
                self.assertEqual(code, 1, reason)
                self.assertIn("game/Main.gd:2: test-only-func: orphan", out)
                self.assertIn("allow entry exempts nothing (empty reason or a test): test-only-func game/Main.gd:orphan", out)

    def test_report_prints_counts_per_check_and_folder(self):
        with make_repo({"game/Dead.tscn": TSCN}) as root:
            _, out = self.run_main(root, "--report")
            self.assertIn("dead-file", out)
            self.assertIn("game=1", out)


class ConsumerTest(unittest.TestCase):
    ALLOW = [{"id": "test-only-func", "entry": "game/Main.gd:orphan", "reason": "removed by P7-Ibots", "consumer": "P7-Ibots"},
             {"id": "dead-file", "entry": "game/Gallery.tscn", "reason": "designer gallery"}]

    def test_landed_needs_a_closed_title_with_the_exact_package_prefix(self):
        landed = lint_dead.landed_consumers
        self.assertEqual(landed(self.ALLOW, ["P7-Ibots: headless bots flow"]),
                         [("test-only-func", "game/Main.gd:orphan", "P7-Ibots")])
        self.assertEqual(landed(self.ALLOW, ["P7-Ibots-b: later part", "P7-Iboot: other", "x P7-Ibots: no"]), [])
        self.assertEqual(landed(self.ALLOW, []), [])

    def run_main(self, root, titles):
        buf = io.StringIO()
        old = lint_dead.closed_titles
        lint_dead.closed_titles = lambda _root: titles
        try:
            with redirect_stdout(buf):
                code = lint_dead.main(["--path", root, "--today", TODAY])
        finally:
            lint_dead.closed_titles = old
        return code, buf.getvalue()

    def test_run_fails_once_consumer_landed_and_survives_missing_bd(self):
        files = {"game/Main.gd": "extends Node\nfunc orphan() -> void:\n\tpass\n"}
        with make_repo(files) as root:
            os.makedirs(os.path.join(root, "tools"))
            with open(os.path.join(root, "tools", "dead_baseline.json"), "w", encoding="utf-8") as fh:
                json.dump({"checks": {}, "allow": self.ALLOW[:1]}, fh)
            code, out = self.run_main(root, ["P7-Ibots: done"])
            self.assertEqual(code, 1)
            self.assertIn("consumer package P7-Ibots has landed", out)
            self.assertEqual(self.run_main(root, ["P7-Imatch-a: other"])[0], 0)
            code, out = self.run_main(root, None)
            self.assertEqual(code, 0)
            self.assertIn("consumer check skipped: bd unavailable", out)

    def test_checkout_behind_main_only_notes_the_landed_consumer(self):
        files = {"game/Main.gd": "extends Node\nfunc orphan() -> void:\n\tpass\n"}
        with make_repo(files) as root:
            os.makedirs(os.path.join(root, "tools"))
            with open(os.path.join(root, "tools", "dead_baseline.json"), "w", encoding="utf-8") as fh:
                json.dump({"checks": {}, "allow": self.ALLOW[:1]}, fh)

            def git(*args):
                subprocess.run(["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t"] + list(args),
                               check=True, capture_output=True)
            git("init", "-q", "-b", "main")
            git("add", "-A")
            git("commit", "-q", "-m", "base")
            self.assertEqual(self.run_main(root, ["P7-Ibots: done"])[0], 1)  # contains main
            git("checkout", "-q", "-b", "old")
            git("checkout", "-q", "main")
            git("commit", "-q", "--allow-empty", "-m", "main moves on")
            git("checkout", "-q", "old")  # behind main
            code, out = self.run_main(root, ["P7-Ibots: done"])
            self.assertEqual(code, 0)
            self.assertIn("clears after merging main", out)


if __name__ == "__main__":
    unittest.main()
