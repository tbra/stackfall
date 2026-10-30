"""Unit tests for the shard/serial split in full_gate.py (no Godot launched)."""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import full_gate  # noqa: E402


class SerialSplitTest(unittest.TestCase):
    def write(self, text):
        fd, p = tempfile.mkstemp(suffix=".txt")
        os.close(fd)
        self.addCleanup(os.remove, p)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        return p

    def test_list_filters_unknown_comments_and_dupes(self):
        p = self.write("# c\nres://a.gd  # trailing\n\nres://gone.gd\nres://a.gd\nres://b.gd\n")
        self.assertEqual(full_gate.load_serial_list(p, ["res://a.gd", "res://b.gd", "res://c.gd"]),
                         ["res://a.gd", "res://b.gd"])

    def test_missing_file_is_empty(self):
        self.assertEqual(full_gate.load_serial_list("/nonexistent/x.txt", ["res://a.gd"]), [])

    def test_shards_exclude_serial_scripts(self):
        tests = ["res://t%d.gd" % i for i in range(6)]
        serial = ["res://t0.gd", "res://t3.gd"]
        shards = full_gate.make_shards(".", [t for t in tests if t not in serial], 2, {})
        flat = [t for s in shards for t in s]
        self.assertEqual(sorted(flat), sorted(set(tests) - set(serial)))

    def test_seed_list_entries_exist(self):
        tests = full_gate.collect(full_gate.ROOT)
        with open(full_gate.SERIAL_LIST, encoding="utf-8") as fh:
            wanted = [l.split("#")[0].strip() for l in fh if l.split("#")[0].strip()]
        self.assertEqual([w for w in wanted if w not in tests], [])

    def test_layer_lint_wired_into_gate(self):
        # The gate runs lint_layers on the candidate tree and any non-green exit makes it RED.
        with open(full_gate.__file__.replace(".pyc", ".py"), encoding="utf-8") as fh:
            src = fh.read()
        self.assertIn('run_lint(path, "lint_layers", lint_layers)', src)
        self.assertIn("layer_code == 0", src)
        self.assertIn("layer_lint=%s", src)

    def test_instructions_lint_wired_into_gate(self):
        # the instruction drift guard gates like the other lints.
        src = open(full_gate.__file__, encoding="utf-8").read()
        self.assertIn('run_lint(path, "lint_instructions", lint_instructions)', src)
        self.assertIn("instr_code == 0", src)
        self.assertIn("instructions_lint=%s", src)

    def test_public_lint_wired_into_gate(self):
        # the public-repository guard gates like the other lints.
        src = open(full_gate.__file__, encoding="utf-8").read()
        self.assertIn('run_lint(path, "lint_public", lint_public)', src)
        self.assertIn("public_code == 0", src)
        self.assertIn("public_lint=%s", src)
        self.assertIn('"public_lint"', src)

    def test_run_lint_uses_candidate_script_and_falls_back(self):
        with tempfile.TemporaryDirectory() as root:
            class Stub(object):
                calls = []

                @staticmethod
                def main(argv):
                    Stub.calls.append(argv)
                    return 7
            self.assertEqual(full_gate.run_lint(root, "lint_layers", Stub), 7)
            os.makedirs(os.path.join(root, "tools"))
            with open(os.path.join(root, "tools", "lint_layers.py"), "w") as fh:
                fh.write("import sys; sys.exit(3)")
            self.assertEqual(full_gate.run_lint(root, "lint_layers", Stub), 3)


class FailureDetailTest(unittest.TestCase):
    """failing assertion text survives in result.json."""

    ESC = chr(27)
    LOG = "\n".join([
        "res://tests/unit/test_a.gd",
        ESC + "[0m* test_ok",
        "* test_bad",
        "    " + ESC + "[31m[Failed]" + ESC + "[0m:  Expected [1] to equal [2]: tilt angle",
        "          at line 30",
        "",
        "res://tests/unit/test_b.gd",
        "* test_fine",
        "Tests             3",
        "Failing Tests     1",
        "",
    ])

    def _log(self):
        fd, path = tempfile.mkstemp(suffix=".log")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(self.LOG)
        self.addCleanup(os.remove, path)
        return path

    def test_detail_names_test_and_assertion_only(self):
        totals, failing, detail = full_gate.parse_detail(self._log())
        self.assertEqual(totals.get("Failing Tests"), 1)
        self.assertEqual(sorted(failing), ["res://tests/unit/test_a.gd"])
        entry = detail["res://tests/unit/test_a.gd"][0]
        self.assertIn("* test_bad", entry)
        self.assertIn("Expected [1] to equal [2]: tilt angle", entry)
        self.assertIn("at line 30", entry)
        self.assertNotIn("test_b.gd", entry)
        self.assertNotIn(self.ESC, entry)

    def test_parse_keeps_its_old_shape(self):
        totals, failing = full_gate.parse(self._log())
        self.assertEqual(sorted(failing), ["res://tests/unit/test_a.gd"])

    def test_details_for_merges_runs_and_caps(self):
        many = {"res://t.gd": ["x"] * (full_gate.DETAIL_MAX_LINES + 3)}
        out = full_gate._details_for(["res://t.gd", "res://none.gd"], {"shard0": {"failing_detail": many}}, {})
        self.assertEqual(len(out["res://t.gd"]), full_gate.DETAIL_MAX_LINES)
        self.assertEqual(out["res://none.gd"], [])

class UnloadableScriptTest(unittest.TestCase):
    """a scheduled script GUT dropped must surface, not vanish from the totals."""

    GOOD = "res://tests/unit/test_good.gd"
    BAD = "res://tests/unit/test_bad.gd"
    ESC = chr(27)

    def _log(self, text):
        fd, path = tempfile.mkstemp(suffix=".log")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        self.addCleanup(os.remove, path)
        return path

    def test_parse_error_script_reported_with_error_text(self):
        log = "\n".join([
            'SCRIPT ERROR: Parse Error: Preload file "res://config/x.tres" does not exist.',
            "   at: GDScript::reload (%s:13)" % self.BAD,
            'ERROR: Failed to load script "%s" with error "Parse error".' % self.BAD,
            self.ESC + "[33m[WARNING]:  " + self.ESC + "[0mIgnoring script %s because it does not extend GutTest" % self.BAD,
            self.GOOD, "* test_ok", "Tests  1", "Passing Tests  1", ""])
        out = full_gate.find_unloadable([self.BAD, self.GOOD], self._log(log))
        self.assertEqual([u["script"] for u in out], [self.BAD])
        self.assertIn("Preload file", out[0]["error"])
        self.assertIn("Parse error", out[0]["error"])

    def test_script_absent_from_results_is_reported(self):
        log = "\n".join([self.GOOD, "* test_ok", "Tests  1", ""])
        out = full_gate.find_unloadable([self.GOOD, self.BAD], self._log(log))
        self.assertEqual(out, [{"script": self.BAD, "error": full_gate.MISSING_ERROR}])

    def test_all_present_is_clean(self):
        log = "\n".join([self.ESC + "[0m" + self.GOOD, self.BAD, "Tests  2", ""])
        self.assertEqual(full_gate.find_unloadable([self.GOOD, self.BAD], self._log(log)), [])

    def test_missing_log_reports_every_script(self):
        out = full_gate.find_unloadable([self.GOOD], "/nonexistent/shard.log")
        self.assertEqual(len(out), 1)


class NotRunTest(unittest.TestCase):
    """pending and risky tests are named, not just counted, so a near-total cannot hide them."""

    XML = "\n".join([
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<testsuites name="GutTests" failures="1" tests="4" >',
        '  <testsuite name="tests/unit/test_a.gd" tests="4" failures="1" skipped="1" time="1" >',
        '      <testcase name="test_ok" assertions="1" status="pass" classname="tests/unit/test_a.gd" time="0.1" >',
        '      </testcase>',
        '      <testcase name="test_later" assertions="0" status="pending" classname="tests/unit/test_a.gd" time="0.1" >',
        '      <skipped message="pending"><![CDATA[needs a Match field]]></skipped></testcase>',
        '      <testcase name="test_silent" assertions="0" status="no asserts" classname="tests/unit/test_a.gd" time="0.1" >',
        '      </testcase>',
        '      <testcase name="test_bad" assertions="1" status="fail" classname="tests/unit/test_a.gd" time="0.1" >',
        '      <failure message="failed"><![CDATA[x]]></failure></testcase>',
        '  </testsuite>',
        '</testsuites>', ""])

    def test_junit_names_pending_and_risky_only(self):
        with tempfile.TemporaryDirectory() as out:
            with open(os.path.join(out, "shard0.xml"), "w", encoding="utf-8") as fh:
                fh.write(self.XML)
            got = full_gate.junit_not_run(out, "shard0")
            self.assertEqual(full_gate.junit_not_run(out, "missing"), [])
        self.assertEqual(got, [
            {"script": "res://tests/unit/test_a.gd", "test": "test_later", "status": "pending", "reason": "needs a Match field"},
            {"script": "res://tests/unit/test_a.gd", "test": "test_silent", "status": "no asserts", "reason": ""}])

    def test_totals_read_guts_risky_pending_line(self):
        fd, path = tempfile.mkstemp(suffix=".log")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write("Tests              1080\nPassing Tests      1079\nRisky/Pending         1\n")
        self.addCleanup(os.remove, path)
        totals, _failing = full_gate.parse(path)
        self.assertEqual(totals.get("Risky/Pending"), 1)


class LiveProgressTest(unittest.TestCase):
    """the progress file a watcher polls while shards run."""

    ESC = chr(27)

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.log = os.path.join(self.tmp.name, "shard0.log")
        open(self.log, "w").close()

    def append(self, text):
        with open(self.log, "a", encoding="utf-8") as fh:
            fh.write(text)

    def test_counts_follow_a_growing_log_without_double_counting(self):
        c = full_gate.LiveCounts(self.log)
        self.append(self.ESC + "[4m\nres://tests/unit/test_a.gd\n" + self.ESC + "[0m* test_one\n* test_t")
        c.read()
        self.assertEqual((c.started, len(c.failed)), (1, 0))
        self.append("wo\n    " + self.ESC + "[31m[Failed]" + self.ESC + "[0m: no\n    [Failed]: again\n")
        c.read()
        self.assertEqual((c.started, len(c.failed)), (2, 1))
        # The run summary repeats failures under "- test_" lines; they are not new.
        self.append("= Run Summary\nres://tests/unit/test_a.gd\n- test_two\n    [Failed]: no\n* test_x\n")
        c.read()
        self.assertEqual((c.started, len(c.failed)), (2, 1))

    def test_progress_file_tracks_phases_shards_and_counts(self):
        clock = [100.0]
        d = os.path.join(self.tmp.name, "progress")
        p = full_gate.Progress("/repo", "/out", directory=d, now=lambda: clock[0])
        files = os.listdir(d)
        self.assertEqual(len(files), 1)
        def read():
            with open(os.path.join(d, files[0]), encoding="utf-8") as fh:
                return json.load(fh)
        self.assertEqual(read()["phase"], "lint")
        p.update(phase="shards", shards=1, expected=3)
        p.data["shard_state"]["shard0"] = "waiting"
        p.shard("shard0", "running", self.log)
        self.append("res://tests/unit/test_a.gd\n* test_one\n* test_two\n    [Failed]: x\n* test_three\n")
        p.tick()
        self.assertEqual(read()["run"], 0)  # throttled
        clock[0] += full_gate.PROGRESS_EVERY_S
        p.tick()
        got = read()
        self.assertEqual((got["run"], got["passed"], got["failed"]), (2, 1, 1))
        self.assertEqual(got["shard_state"], {"shard0": "running"})
        p.shard("shard0", "done")
        got = read()
        self.assertEqual((got["run"], got["passed"], got["failed"], got["shard_state"]["shard0"]), (3, 2, 1, "done"))
        self.assertEqual(got["updated"], clock[0])
        self.assertFalse([n for n in os.listdir(d) if n.endswith(".tmp")])

    def test_old_progress_files_are_pruned(self):
        d = os.path.join(self.tmp.name, "progress")
        os.makedirs(d)
        for i in range(full_gate.PROGRESS_KEEP + 5):
            open(os.path.join(d, "20200101_%06d_1.json" % i), "w").close()
        full_gate.Progress("/repo", "/out", directory=d)
        names = sorted(os.listdir(d))
        self.assertEqual(len(names), full_gate.PROGRESS_KEEP)
        self.assertNotIn("20200101_000000_1.json", names)

    def test_unwritable_folder_never_fails_the_gate(self):
        blocker = os.path.join(self.tmp.name, "file")
        open(blocker, "w").close()
        p = full_gate.Progress("/repo", "/out", directory=os.path.join(blocker, "sub"))
        p.update(phase="done")

    def test_expected_counts_test_functions(self):
        with open(os.path.join(self.tmp.name, "test_a.gd"), "w", encoding="utf-8") as fh:
            fh.write("extends GutTest\nfunc test_one():\n\tpass\nfunc helper():\n\tpass\nfunc test_two():\n\tpass\n")
        self.assertEqual(full_gate.expected_tests(self.tmp.name, ["res://test_a.gd", "res://gone.gd"]), 2)

    def test_main_feeds_progress_through_every_phase(self):
        src = open(full_gate.__file__, encoding="utf-8").read()
        for phase in ('phase="shards"', 'phase="serial"', 'phase="retry"', 'phase="done"'):
            self.assertIn(phase, src)
        self.assertIn("not_run=result[\"not_run\"]", src)


if __name__ == "__main__":
    unittest.main()
