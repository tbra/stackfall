"""Mocked-subprocess tests for tools/integrate_batch.py.
Run: python tools/test_integrate_batch.py
"""
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import integrate_batch as ib  # noqa: E402

GREEN = "FULL GATE GREEN: 10/10 passing, 1 shards, 5s; failing=none parallel_flaky=none harness=none; out=/tmp/gate_output\n"


class Fake:
    """Scripted run_cmd: records calls, returns canned (code, text) by log name."""

    def __init__(self, overrides=None):
        self.calls = []
        self.overrides = overrides or {}

    def __call__(self, ctx, name, args, cwd, timeout):
        self.calls.append((name, list(args)))
        if name in self.overrides:
            code, text = self.overrides[name]
        elif name in ("rev_main", "rev_main2"):
            code, text = 0, "base111\n"
        elif name in ("rev_result",):
            code, text = 0, "result22\n"
        elif name == "head":
            code, text = 0, "result22\n"
        elif name == "remote":
            code, text = 0, "result22\n"
        elif name == "cur_branch":
            code, text = 0, "main\n"
        elif name in ("gate", "gate2"):
            code, text = 0, GREEN
        elif name in ("touched", "dirty"):
            code, text = 0, ""
        else:
            code, text = 0, ""
        return code, text, "/log/" + name

    def names(self):
        return [c[0] for c in self.calls]


def args_for(**kw):
    ns = dict(branches=["wt/a", "wt/b"], beads=["B-1", "B-2"], repo="R", worktree_root="W",
              log_dir="", game_code=True, dry_run=False, merge_only=False, no_push=False, force_close=False, allow_probes=False)
    ns.update(kw)
    return type("A", (), ns)()


def run(fake, **kw):
    out, res = [], {}
    err = None
    log_dir = kw.pop("log_dir", tempfile.gettempdir())
    with mock.patch.object(ib, "run_cmd", fake):
        try:
            ib.integrate(args_for(**kw), ib.Ctx(log_dir), out.append, res)
        except ib.StepFailed as e:
            err = e
    return err, out, res


class Tests(unittest.TestCase):
    def test_verdict_parsing(self):
        self.assertEqual(ib.parse_verdict("x\nFULL GATE GREEN: 1/1\n"), "GREEN")
        self.assertEqual(ib.parse_verdict("FULL GATE RED: 1/2\n"), "RED")
        self.assertEqual(ib.parse_verdict("FULL GATE ERROR: no tests\n"), "RED")
        self.assertEqual(ib.parse_verdict("FULL GATE RED\nFULL GATE GREEN\n"), "RED")
        self.assertEqual(ib.parse_verdict("all tests passed, no verdict"), "RED")

    def test_extract_out_path(self):
        self.assertEqual(ib.extract_out_path("FULL GATE GREEN: 10/10 passing, 1 shards, 5s; failing=none parallel_flaky=none harness=none; out=/tmp/test"), "/tmp/test")
        self.assertEqual(ib.extract_out_path("FULL GATE GREEN: 10/10 passing, 1 shards, 5s; failing=none parallel_flaky=none harness=none; out=/tmp/test\n"), "/tmp/test")
        self.assertEqual(ib.extract_out_path("FULL GATE GREEN: no out field"), None)
        self.assertEqual(ib.extract_out_path(""), None)

    def test_missing_verdict_is_red_and_stops_before_ff(self):
        fake = Fake({"gate": (0, "Totals ... exit 0 but no verdict line")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "gate")
        self.assertNotIn("ff", fake.names())
        self.assertNotIn("push", fake.names())

    def test_gate_runner_detection(self):
        self.assertTrue(ib.touches_gate_runner(["tools/full_gate.py"]))
        self.assertTrue(ib.touches_gate_runner(["a.gd", "addons/gut/gut.gd"]))
        self.assertTrue(ib.touches_gate_runner([".gutconfig.json", "x"]))
        self.assertFalse(ib.touches_gate_runner(["tools/full_gate_extra.py", "core/a.gd", "addons/gutx/a.gd"]))
        self.assertFalse(ib.touches_gate_runner([]))

    def test_untouched_runner_runs_single_gate(self):
        fake = Fake({"gate_touched": (0, "core/a.gd\n")})
        err, out, _ = run(fake)
        self.assertIsNone(err)
        self.assertNotIn("gate2", fake.names())
        self.assertTrue(any("gate2" in l and "skip" in l for l in out))

    def test_touched_runner_runs_candidate_gate_and_reports_both(self):
        fake = Fake({"gate_touched": (0, "tools/run_gut.ps1\n")})
        err, out, _ = run(fake)
        self.assertIsNone(err)
        self.assertEqual(fake.names().count("gate"), 1)
        self.assertEqual(fake.names().count("gate2"), 1)
        args2 = [c for c in fake.calls if c[0] == "gate2"][0][1]
        self.assertTrue(args2[1].replace("\\", "/").startswith("W/integrate-tmp-"))
        self.assertEqual(sum(1 for l in out if "FULL GATE GREEN" in l), 2)

    def test_candidate_gate_red_blocks_ff(self):
        fake = Fake({"gate_touched": (0, "tools/full_gate.py\n"),
                     "gate2": (0, "FULL GATE RED: 1 failing; out=/tmp/x\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "gate")
        self.assertNotIn("ff", fake.names())

    def test_candidate_gate_skipped_without_game_code(self):
        fake = Fake({"gate_touched": (0, "tools/full_gate.py\n")})
        run(fake, game_code=False, dry_run=True)
        self.assertNotIn("gate2", fake.names())

    def test_conflict_stops_with_files(self):
        fake = Fake({"merge_wt_b": (1, "CONFLICT"), "conflicts": (0, "a.gd\nb.gd\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "merge")
        self.assertIn("a.gd", err.detail)
        self.assertIn("merge_abort", fake.names())
        self.assertNotIn("gate", fake.names())

    def test_close_only_after_verified_push(self):
        fake = Fake()
        err, out, _ = run(fake)
        self.assertIsNone(err)
        n = fake.names()
        self.assertLess(n.index("gate"), n.index("ff"))
        self.assertLess(n.index("ff"), n.index("push"))
        self.assertLess(n.index("remote"), n.index("close_B-1"))
        self.assertLess(n.index("close_B-1"), n.index("close_B-2"))
        self.assertLess(n.index("close_B-2"), n.index("postimport"))

    def test_close_uses_resolved_bd_and_force_only_on_request(self):
        with mock.patch.object(ib.shutil, "which", lambda n: "C:/npm/bd.CMD" if n == "bd" else None):
            fake = Fake()
            run(fake)
            closes = [a for name, a in fake.calls if name.startswith("close_")]
            self.assertEqual(closes[0][0], "C:/npm/bd.CMD")
            self.assertNotIn("--force", closes[0])
            fake = Fake()
            run(fake, force_close=True)
            closes = [a for name, a in fake.calls if name.startswith("close_")]
            self.assertTrue(all("--force" in a for a in closes))

    def test_reassign_precedes_close_and_retries_with_force(self):
        fake = Fake()
        err, _, _ = run(fake)
        self.assertIsNone(err)
        n = fake.names()
        self.assertLess(n.index("assign_B-1"), n.index("close_B-1"))
        self.assertLess(n.index("close_B-1"), n.index("assign_B-2"))
        a = dict(fake.calls)["assign_B-1"]
        self.assertIn("update", a)
        self.assertIn("stackfall-orchestrator", a)
        self.assertNotIn("--force", a)
        for forbidden in (c for _, c in fake.calls):
            self.assertNotIn("dolt", forbidden)
        fake = Fake({"assign_B-1": (1, "claimed by worker")})
        err, _, _ = run(fake)
        self.assertIsNone(err)
        self.assertIn("--force", dict(fake.calls)["assign_force_B-1"])
        fake = Fake({"assign_B-1": (1, "x"), "assign_force_B-1": (1, "x")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "close")
        self.assertNotIn("close_B-1", fake.names())
        fake = Fake({"assign_B-1": (1, "x"), "assign_force_B-1": (1, "x")})
        err, _, _ = run(fake, force_close=True)
        self.assertIsNone(err)
        self.assertIn("close_B-1", fake.names())

    def test_dry_run_shows_reassign_then_close(self):
        err, out, _ = run(Fake(), dry_run=True)
        self.assertIsNone(err)
        line = [l for l in out if "dry-run would run" in l][0]
        self.assertLess(line.index("bd update B-1 --assignee"), line.index("then bd close B-1"))

    def test_merge_only_starts_no_godot(self):
        fake = Fake()
        err, out, _ = run(fake, merge_only=True)
        self.assertIsNone(err)
        for bad in ("import", "gate", "ff", "push", "close_B-1"):
            self.assertNotIn(bad, fake.names())
        self.assertTrue([l for l in out if l.startswith("merge-only")])

    def test_remote_mismatch_never_closes(self):
        fake = Fake({"remote": (0, "other999\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "push")
        self.assertFalse([x for x in fake.names() if x.startswith("close_")])

    def test_push_failure_never_closes(self):
        fake = Fake({"push": (1, "rejected")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "push")
        self.assertFalse([x for x in fake.names() if x.startswith("close_")])

    def test_dirty_touched_file_refuses_ff(self):
        fake = Fake({"touched": (0, "core/x.gd\n"), "dirty": (0, " M core/x.gd\n")})
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")
        self.assertNotIn("push", fake.names())

    def test_main_moved_refuses_ff(self):
        class Moving(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                if name == "rev_main2":
                    s.calls.append((name, args))
                    return 0, "moved000\n", "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        fake = Moving()
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")

    def test_dry_run_and_no_game_code(self):
        fake = Fake()
        err, _, _ = run(fake, dry_run=True)
        self.assertIsNone(err)
        for bad in ("ff", "push", "close_B-1"):
            self.assertNotIn(bad, fake.names())
        fake = Fake()
        run(fake, game_code=False, dry_run=True)
        self.assertNotIn("gate", fake.names())

    def test_import_issue_fails(self):
        class Imp(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                if name == "import":
                    s.calls.append((name, args))
                    return 0, "ERROR: bad thing\n", "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        err, _, _ = run(Imp())
        self.assertEqual(err.step, "import")

    def test_gate_output_copied_before_cleanup(self):
        """Test that gate output directory is copied to log_dir before worktree removal."""
        with tempfile.TemporaryDirectory() as tmpdir:
            # Create a fake gate output directory
            gate_src = os.path.join(tmpdir, "src_gate_output")
            os.makedirs(gate_src)
            with open(os.path.join(gate_src, "test.log"), "w") as f:
                f.write("test output")

            gate_output_txt = (
                "FULL GATE GREEN: 10/10 passing, 1 shards, 5s; "
                "failing=none parallel_flaky=none harness=none; out=%s\n" % gate_src
            )

            log_dir = os.path.join(tmpdir, "logs")
            os.makedirs(log_dir)

            fake = Fake({"gate": (0, gate_output_txt)})
            err, out, _ = run(fake, log_dir=log_dir)

            self.assertIsNone(err)
            # Verify the gate output was copied to log_dir/gate_output/
            copied_path = os.path.join(log_dir, "gate_output")
            self.assertTrue(os.path.isdir(copied_path))
            self.assertTrue(os.path.isfile(os.path.join(copied_path, "test.log")))
            # Verify the status line mentions the new location
            status_lines = [l for l in out if "gate" in l.lower()]
            self.assertTrue(any("preserved in" in l for l in status_lines))

    def test_gate_output_copy_failure_warns_but_succeeds(self):
        """Test that gate output copy failure doesn't fail the integration."""
        gate_output_txt = (
            "FULL GATE GREEN: 10/10 passing, 1 shards, 5s; "
            "failing=none parallel_flaky=none harness=none; out=/nonexistent/path\n"
        )

        fake = Fake({"gate": (0, gate_output_txt)})
        err, out, _ = run(fake)

        # Should succeed despite copy failure
        self.assertIsNone(err)
        # Should print a warning
        warning_lines = [l for l in out if "warning" in l.lower()]
        self.assertTrue(warning_lines)

    def test_merge_message_and_trailer(self):
        self.assertEqual(ib.merge_subject("wt/fca.7-x", ["Bontago-fca.11", "Bontago-fca.7"]), "Merge wt/fca.7-x (Bontago-fca.7)")
        self.assertEqual(ib.merge_subject("wt/x", ["B-1", "B-2"]), "Merge wt/x (B-1, B-2)")
        self.assertEqual(ib.merge_subject("wt/x", []), "Merge wt/x")
        fake = Fake()
        run(fake, branches=["wt/b-1"])
        a = [c[1] for c in fake.calls if c[0] == "merge_wt_b-1"][0]
        self.assertIn("--no-ff", a)
        self.assertNotIn("--no-edit", a)
        i = a.index("-m")
        self.assertEqual(a[i + 1], "Merge wt/b-1 (B-1)")
        self.assertEqual(a[i + 2:i + 4], ["-m", ib.MERGE_TRAILER])
        self.assertIn("Claude Opus 5.5", ib.MERGE_TRAILER)

    def _main(self, extra, fail=False):
        fake = Fake()

        def fake_integrate(args, ctx, say, res):
            res["worktree"], res["branch"] = "W/integrate-tmp-1", "integrate/tmp-1"
            if fail:
                raise ib.StepFailed("gate", "RED")
        with mock.patch.object(ib, "run_cmd", fake), mock.patch.object(ib, "integrate", fake_integrate):
            code = ib.main(["--branches", "wt/a", "--log-dir", tempfile.gettempdir()] + extra)
        return code, fake.names()

    def test_cleanup_after_success_even_no_push(self):
        for extra in (["--no-push"], [], ["--dry-run"]):
            code, names = self._main(extra)
            self.assertEqual(code, 0)
            self.assertIn("wt_remove", names)
            self.assertIn("br_delete", names)

    def test_prune_merged_targets_only_merged_branches_and_never_raises(self):
        lines = []
        args = mock.Mock(repo="R", branches=["wt/a", "wt/b"])
        counts = {"removed": 1, "kept_dirty": 1, "kept_unmerged": 0, "protected": 0, "failed": 0}
        with mock.patch.object(ib.prune_worktrees, "prune", return_value=counts) as pr:
            ib.prune_merged(args, lines.append)
        self.assertEqual(pr.call_args.kwargs["branches"], ["wt/a", "wt/b"])
        self.assertTrue(pr.call_args.kwargs["apply"])
        self.assertIn("prune     ok   removed=1 kept=1", lines)
        with mock.patch.object(ib.prune_worktrees, "prune", side_effect=RuntimeError("boom")):
            ib.prune_merged(args, lines.append)
        self.assertTrue(lines[-1].startswith("prune     warn"))

    def test_failure_keeps_worktree(self):
        code, names = self._main(["--no-push"], fail=True)
        self.assertEqual(code, 1)
        self.assertNotIn("wt_remove", names)
        self.assertNotIn("br_delete", names)



def git_run(cwd, *a):
    subprocess.run(["git", "-C", cwd, *a], check=True, capture_output=True, text=True)


HINTS_BASE = ('[resource]\nranges = {\n"A.x": Vector2(0.0, 1.0),\n}\n'
              + ''.join('"F%d.f": Vector2(0.0, 1.0),\n' % n for n in range(8))
              + 'descriptions = {\n"A.x": "ax",\n}\n')


class ProbeLintTests(unittest.TestCase):
    def test_probe_added_aborts_before_merge(self):
        fake = Fake({"probes_wt_b": (0, "tools/capture_x.gd\ncore/a.gd\n")})
        err, out, res = run(fake)
        self.assertIsNotNone(err)
        self.assertEqual(err.step, "probes")
        self.assertIn("wt/b: tools/capture_x.gd", err.detail)
        self.assertFalse([n for n in fake.names() if n.startswith("merge_")])

    def test_allow_probes_skips_check(self):
        fake = Fake({"probes_wt_b": (0, "tools/capture_x.gd\n")})
        err, out, res = run(fake, allow_probes=True)
        self.assertFalse([n for n in fake.names() if n.startswith("probes_")])
        self.assertTrue(err is None or err.step != "probes")

    def test_clean_branches_pass(self):
        fake = Fake({"probes_wt_a": (0, "core/a.gd\n")})
        err, out, res = run(fake)
        self.assertTrue(err is None or err.step != "probes")


class HintsMergeTests(unittest.TestCase):
    """Real git repo: two branches editing config/tuning_panel_hints.tres."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "r").replace("\\", "/")
        os.makedirs(os.path.join(self.repo, "config"))
        git_run(self.repo, "init", "-q", "-b", "main")
        git_run(self.repo, "config", "user.email", "t@t")
        git_run(self.repo, "config", "user.name", "t")
        self.write(HINTS_BASE)
        git_run(self.repo, "add", "-A")
        git_run(self.repo, "commit", "-qm", "base")

    def tearDown(self):
        self.tmp.cleanup()

    def write(self, text):
        with open(os.path.join(self.repo, ib.HINTS_PATH), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def branch(self, name, text, extra=None):
        git_run(self.repo, "checkout", "-q", "-b", name, "main")
        self.write(text)
        if extra:
            with open(os.path.join(self.repo, extra), "w") as fh:
                fh.write(name)
        git_run(self.repo, "add", "-A")
        git_run(self.repo, "commit", "-qm", name)

    def merge(self, branches):
        git_run(self.repo, "checkout", "-q", "main")
        out = []
        try:
            ib.merge_branches(ib.Ctx(self.tmp.name), self.repo, branches, [], out.append)
        except ib.StepFailed as e:
            return e, out
        return None, out

    def test_additive_conflict_is_resolved(self):
        self.branch("a", HINTS_BASE.replace('"A.x": Vector2(0.0, 1.0),\n', '"A.x": Vector2(0.0, 1.0),\n"B.y": Vector2(0.0, 2.0),\n')
                    .replace('"A.x": "ax",\n', '"A.x": "ax",\n"B.y": "by",\n'))
        self.branch("b", HINTS_BASE.replace('"A.x": Vector2(0.0, 1.0),\n', '"A.x": Vector2(0.0, 1.0),\n"C.z": Vector2(0.0, 3.0),\n')
                    .replace('"A.x": "ax",\n', '"A.x": "ax",\n"C.z": "cz",\n'))
        err, out = self.merge(["a", "b"])
        self.assertIsNone(err, err and err.detail)
        self.assertTrue(any("auto-resolved" in l for l in out))
        with open(os.path.join(self.repo, ib.HINTS_PATH), encoding="utf-8") as fh:
            text = fh.read()
        self.assertNotIn("<<<<", text)
        for k in ('"A.x"', '"B.y"', '"C.z"'):
            self.assertEqual(text.count(k), 2, k)
        self.assertEqual(subprocess.run(["git", "-C", self.repo, "status", "--porcelain"], capture_output=True, text=True).stdout, "")

    def test_same_key_different_value_aborts(self):
        self.branch("a", HINTS_BASE.replace('"A.x": Vector2(0.0, 1.0),\n', '"A.x": Vector2(0.0, 1.0),\n"B.y": Vector2(0.0, 2.0),\n'))
        self.branch("b", HINTS_BASE.replace('"A.x": Vector2(0.0, 1.0),\n', '"A.x": Vector2(0.0, 1.0),\n"B.y": Vector2(0.0, 9.0),\n'))
        err, _ = self.merge(["a", "b"])
        self.assertEqual(err.step, "merge")
        self.assertIn("refused", err.detail)
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "MERGE_HEAD")))

    def test_modified_base_line_aborts(self):
        self.branch("a", HINTS_BASE.replace('Vector2(0.0, 1.0)', 'Vector2(0.0, 5.0)'))
        self.branch("b", HINTS_BASE.replace('Vector2(0.0, 1.0)', 'Vector2(0.0, 7.0)'))
        err, _ = self.merge(["a", "b"])
        self.assertEqual(err.step, "merge")
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "MERGE_HEAD")))

    def test_other_file_conflict_aborts(self):
        self.branch("a", HINTS_BASE.replace('"A.x": "ax",\n', '"A.x": "ax",\n"B.y": "by",\n'), extra="f.txt")
        self.branch("b", HINTS_BASE.replace('"A.x": "ax",\n', '"A.x": "ax",\n"C.z": "cz",\n'), extra="f.txt")
        git_run(self.repo, "checkout", "-q", "main")
        # make f.txt exist on main so both branches conflict on it
        err, _ = self.merge(["a", "b"])
        self.assertEqual(err.step, "merge")
        self.assertFalse(os.path.exists(os.path.join(self.repo, ".git", "MERGE_HEAD")))


if __name__ == "__main__":
    unittest.main(verbosity=1)
