"""Unit tests for the shard/serial split in full_gate.py (no Godot launched)."""
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
        # Bontago-tj6: the instruction drift guard gates like the other lints.
        src = open(full_gate.__file__, encoding="utf-8").read()
        self.assertIn('run_lint(path, "lint_instructions", lint_instructions)', src)
        self.assertIn("instr_code == 0", src)
        self.assertIn("instructions_lint=%s", src)

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
    """Bontago-fca.116: failing assertion text survives in result.json."""

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
    """Bontago-fca.120: a scheduled script GUT dropped must surface, not vanish from the totals."""

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


if __name__ == "__main__":
    unittest.main()
