"""Tests for tools/mutate_core.py: mutation generator and apply/restore on fixture text (no Godot).
Run: python -m unittest tools.test_mutate_core   (or python tools/test_mutate_core.py)
"""
import json
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mutate_core as mc  # noqa: E402

FIXTURE = '''class_name Fixture
extends RefCounted
## Doc comment with a < b and 3 apples.

@export_range(0, 10) var level: int = 2
enum Kind { A = 1, B = 2 }
const NAME := "x < 4 and y"


func pick(a: int, b: int) -> int:
	if a <= b and b != 0:
		return a
	elif a > 7 or b == 1:  # comment: a >= 9
		return b
	for i: int in range(items.size()):
		total += i
	for j: int in range(0, 3):
		pass
	var s: String = """multi
line < 5 string"""
	var t: StringName = &"id_9"
	var f: float = 0.25 + 1e3
	return a >> 1
'''


def gen(text, ops=mc.ALL_OPS):
    return mc.generate("core/x/Fixture.gd", text, ops)


def kinds(muts):
    return [(m.line, m.op, m.old, m.new) for m in muts]


class MaskTest(unittest.TestCase):
    def test_strings_and_comments_blanked_same_length(self):
        lines = ['a = "x < 1" # b > 2', "c = 'q' + d"]
        masked = mc.mask_code(lines)
        self.assertEqual([len(x) for x in masked], [len(x) for x in lines])
        self.assertNotIn("<", masked[0])
        self.assertNotIn(">", masked[0])
        self.assertIn("+ d", masked[1])

    def test_triple_quoted_string_spans_lines(self):
        masked = mc.mask_code(['s = """one', "two < 3", 'end""" + x < y'])
        self.assertEqual(masked[1].strip(), "")
        self.assertIn("x < y", masked[2])

    def test_escaped_quote_stays_inside_string(self):
        masked = mc.mask_code(['s = "a\\"b < c" < d'])
        self.assertEqual(masked[0].count("<"), 1)


class GenerateTest(unittest.TestCase):
    def setUp(self):
        self.muts = gen(FIXTURE)
        self.by_line = {}
        for m in self.muts:
            self.by_line.setdefault(m.line, []).append((m.op, m.old, m.new))

    def test_skipped_lines_have_no_mutations(self):
        # class_name, extends, doc comment, annotation, enum lines
        for line in (1, 2, 3, 5, 6):
            self.assertNotIn(line, self.by_line, line)

    def test_const_string_contents_are_not_mutated(self):
        self.assertEqual(self.by_line.get(7, []), [])

    def test_if_line(self):
        self.assertEqual(self.by_line[11], [
            ("if_true", "a <= b and b != 0", "true"),
            ("cmp", "<=", "<"),
            ("bool", "and", "or"),
            ("eq", "!=", "=="),
            ("int", "0", "1"),
        ])

    def test_elif_line_ignores_comment(self):
        self.assertEqual(self.by_line[13], [
            ("if_true", "a > 7 or b == 1", "true"),
            ("cmp", ">", ">="),
            ("int", "7", "8"),
            ("bool", "or", "and"),
            ("eq", "==", "!="),
            ("int", "1", "2"),
        ])

    def test_return_arrow_shift_and_floats_untouched(self):
        self.assertNotIn(10, self.by_line)  # `-> int`
        self.assertEqual(self.by_line[23], [("int", "1", "2")])  # `>>` is not a comparison
        self.assertNotIn(22, self.by_line)  # 0.25 and 1e3
        self.assertNotIn(21, self.by_line)  # &"id_9"
        self.assertNotIn(20, self.by_line)  # inside the multi-line string

    def test_range_stop(self):
        self.assertEqual(self.by_line[15], [("range", "items.size()", "items.size() - 1")])
        # literal bounds are left to the int operator
        self.assertEqual(self.by_line[17], [("int", "0", "1"), ("int", "3", "4")])

    def test_range_complex_stop_is_parenthesised(self):
        muts = gen("\tfor i in range(1, n + k, 2):\n", ("range",))
        self.assertEqual(kinds(muts), [(1, "range", "n + k", "(n + k) - 1")])

    def test_range_three_arg_literal_stop_skipped(self):
        self.assertEqual(gen("\tfor i in range(a.size() - 1, 0, -1):\n", ("range",)), [])

    def test_multiline_if_without_colon_is_skipped(self):
        self.assertEqual(gen("\tif (a and\n\t\tb):\n", ("if_true",)), [])

    def test_if_with_dict_literal_finds_header_colon(self):
        muts = gen("\tif d == {\"k\": 1}: pass\n", ("if_true",))
        self.assertEqual(kinds(muts), [(1, "if_true", 'd == {"k": 1}', "true")])

    def test_already_true_condition_skipped(self):
        self.assertEqual(gen("\tif true:\n\t\tpass\n", ("if_true",)), [])

    def test_skip_pragma(self):
        self.assertEqual(gen("\tif a < b:  # mutate: skip\n"), [])

    def test_ops_filter(self):
        self.assertTrue(all(m.op == "eq" for m in gen(FIXTURE, ("eq",))))
        self.assertEqual(len(gen(FIXTURE, ("eq",))), 2)

    def test_symbolic_bool_ops(self):
        self.assertEqual(kinds(gen("\tx = a && b || c\n", ("bool",))),
                         [(1, "bool", "&&", "||"), (1, "bool", "||", "&&")])

    def test_every_mutation_applies_and_changes_only_its_line(self):
        src = FIXTURE.splitlines(True)
        for m in self.muts:
            out = mc.apply_mutation(FIXTURE, m).splitlines(True)
            self.assertEqual(len(out), len(src), m)
            diff = [i for i, (a, b) in enumerate(zip(src, out)) if a != b]
            self.assertEqual(diff, [m.line - 1], m)


class SampleTest(unittest.TestCase):
    def test_cap_and_reproducible(self):
        muts = gen(FIXTURE)
        a = mc.sample(muts, 5, 1)
        self.assertEqual(len(a), 5)
        self.assertEqual(a, mc.sample(muts, 5, 1))
        self.assertEqual(a, sorted(a, key=lambda m: (m.path, m.line, m.col, m.op)))

    def test_cap_above_count_keeps_all(self):
        muts = gen(FIXTURE)
        self.assertEqual(len(mc.sample(muts, len(muts) + 10, 0)), len(muts))


class ApplyRestoreTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.work = self.tmp.name
        os.makedirs(os.path.join(self.work, "core", "x"))
        self.rel = "core/x/Fixture.gd"
        self.full = os.path.join(self.work, self.rel)
        self.original = FIXTURE.replace("\n", "\r\n", 3).encode("utf-8")  # mixed endings survive
        with open(self.full, "wb") as fh:
            fh.write(self.original)
        self.m = [m for m in gen(FIXTURE) if m.op == "cmp"][0]

    def tearDown(self):
        self.tmp.cleanup()

    def read(self):
        with open(self.full, "rb") as fh:
            return fh.read()

    def test_mutated_inside_restored_after(self):
        with mc.Mutated(self.work, self.m):
            self.assertNotEqual(self.read(), self.original)
            self.assertIn(b"if a < b and", self.read())
            self.assertTrue(os.path.exists(os.path.join(self.work, mc.JOURNAL)))
        self.assertEqual(self.read(), self.original)
        self.assertFalse(os.path.exists(os.path.join(self.work, mc.JOURNAL)))
        self.assertFalse(os.path.exists(os.path.join(self.work, mc.BACKUP)))

    def test_restored_on_exception(self):
        with self.assertRaises(KeyError):
            with mc.Mutated(self.work, self.m):
                raise KeyError("boom")
        self.assertEqual(self.read(), self.original)

    def test_stale_mutation_refused_without_writing(self):
        stale = self.m._replace(old=">=")
        with self.assertRaises(ValueError):
            with mc.Mutated(self.work, stale):
                pass
        self.assertEqual(self.read(), self.original)
        self.assertFalse(os.path.exists(os.path.join(self.work, mc.JOURNAL)))

    def test_recover_after_killed_run(self):
        ctx = mc.Mutated(self.work, self.m)
        ctx.__enter__()  # simulate a run killed before __exit__
        self.assertNotEqual(self.read(), self.original)
        with self.assertRaises(RuntimeError):
            mc.Mutated(self.work, self.m).__enter__()  # refuses to stack mutations
        self.assertEqual(mc.recover(self.work), self.rel)
        self.assertEqual(self.read(), self.original)
        self.assertIsNone(mc.recover(self.work))

    def test_recover_refuses_corrupt_backup(self):
        mc.Mutated(self.work, self.m).__enter__()
        with open(os.path.join(self.work, mc.BACKUP), "wb") as fh:
            fh.write(b"garbage")
        with self.assertRaises(RuntimeError):
            mc.recover(self.work)

    def test_journal_names_the_mutation(self):
        with mc.Mutated(self.work, self.m):
            with open(os.path.join(self.work, mc.JOURNAL), encoding="utf-8") as fh:
                entry = json.load(fh)
        self.assertEqual(entry["path"], self.rel)
        self.assertEqual(entry["mutation"], self.m.describe())


class TargetsAndReportTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = self.tmp.name
        for rel, text in (("core/a/Foo.gd", "class_name FooThing\n"), ("core/a/Bar.gd", ""),
                          ("game/Baz.gd", ""), ("tests/unit/test_foo.gd", "var f = FooThing.new()\n"),
                          ("tests/unit/test_match_flow.gd", "var f = FooThing.new()\n")):
            full = os.path.join(self.repo, rel)
            os.makedirs(os.path.dirname(full), exist_ok=True)
            with open(full, "w", encoding="utf-8") as fh:
                fh.write(text)

    def tearDown(self):
        self.tmp.cleanup()

    def test_resolve_targets(self):
        self.assertEqual(mc.resolve_targets(self.repo, []), ["core/a/Bar.gd", "core/a/Foo.gd"])
        self.assertEqual(mc.resolve_targets(self.repo, ["res://core/a/Foo.gd"]), ["core/a/Foo.gd"])
        with self.assertRaises(ValueError):
            mc.resolve_targets(self.repo, ["game/Baz.gd"])
        with self.assertRaises(ValueError):
            mc.resolve_targets(self.repo, ["core/a/Missing.gd"])

    def test_tests_for_class_name_and_slow_filter(self):
        self.assertEqual(mc.tests_for(self.repo, "core/a/Foo.gd", False), ["test_foo"])
        self.assertEqual(mc.tests_for(self.repo, "core/a/Foo.gd", True), ["test_foo", "test_match_flow"])
        self.assertEqual(mc.tests_for(self.repo, "core/a/Bar.gd", False), [])

    def test_copy_skips_git_and_journal(self):
        os.makedirs(os.path.join(self.repo, ".git"))
        open(os.path.join(self.repo, mc.JOURNAL), "w").close()
        dst = os.path.join(self.repo + "_copy")
        try:
            mc.make_copy(self.repo, dst)
            self.assertTrue(os.path.isfile(os.path.join(dst, "core", "a", "Foo.gd")))
            self.assertFalse(os.path.exists(os.path.join(dst, ".git")))
            self.assertFalse(os.path.exists(os.path.join(dst, mc.JOURNAL)))
        finally:
            import shutil
            shutil.rmtree(dst, ignore_errors=True)

    def test_classify(self):
        self.assertEqual(mc.classify(0, "", "core/a/Foo.gd"), "pass")
        self.assertEqual(mc.classify(1, "Failing Tests 2", "core/a/Foo.gd"), "fail")
        err = "SCRIPT ERROR: Parse Error: x\n   at: GDScript::reload (res://core/a/Foo.gd:3)"
        self.assertEqual(mc.classify(1, err, "core/a/Foo.gd"), "invalid")
        self.assertEqual(mc.classify(1, err, "core/a/Other.gd"), "fail")

    def test_error_lines_keep_script_errors_and_locations(self):
        out = "noise\nSCRIPT ERROR: Parse Error: X\n   at: GDScript::reload (res://a.gd:1)\nTotals\n"
        self.assertEqual(mc.error_lines(out), "SCRIPT ERROR: Parse Error: X\n   at: GDScript::reload (res://a.gd:1)")

    def test_report_lines(self):
        recs = [{"mutation": "core/a/Foo.gd:3: cmp '<' -> '<='", "result": "survived", "status": "pass"},
                {"mutation": "m2", "result": "killed", "status": "fail"},
                {"mutation": "m3", "result": "killed", "status": "timeout"},
                {"mutation": "m4", "result": "invalid", "status": "invalid"}]
        lines = mc.report_lines(recs, ["core/a/Bar.gd"], [], 2)
        self.assertEqual(lines[0], "SURVIVED core/a/Foo.gd:3: cmp '<' -> '<='")
        self.assertIn("UNTESTED core/a/Bar.gd (no test names it)", lines)
        self.assertEqual(lines[-1], "MUTATION 2/3 killed (1 invalid, 1 by timeout, 2 not run: time limit)")
        self.assertEqual(mc.report_lines([], [], [], 0), ["MUTATION 0/0 killed"])


if __name__ == "__main__":
    unittest.main()
