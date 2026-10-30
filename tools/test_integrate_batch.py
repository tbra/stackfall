"""Mocked-subprocess tests for tools/integrate_batch.py.
Run: python tools/test_integrate_batch.py
"""
import json
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
              log_dir="", game_code=True, dry_run=False, merge_only=False, no_push=False, force_close=False, allow_probes=False, gate_shards=2)
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
        with mock.patch.object(ib.shutil, "which", lambda n: "/npm/bd.CMD" if n == "bd" else None):
            fake = Fake()
            run(fake)
            closes = [a for name, a in fake.calls if name.startswith("close_")]
            self.assertEqual(closes[0][0], "/npm/bd.CMD")
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
        self.assertIn("lint", fake.names())

    def test_merge_only_lint_red_fails_step_lint(self):
        fake = Fake({"lint": (1, "LINT ALL RED: lint_dead")})
        err, out, _ = run(fake, merge_only=True)
        self.assertEqual(err.step, "lint")
        self.assertTrue([l for l in out if l.startswith("lint      FAIL LINT ALL RED")])

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

    def _moved(self, delta, batch=""):
        class Moving(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                canned = {"rev_main2": "moved000\n", "moved_delta": delta,
                          "moved_batch": batch, "moved_log": "abc1234\n",
                          "moved_result": "result33\n", "head": "result33\n", "remote": "result33\n"}
                if name in canned:
                    s.calls.append((name, args))
                    return 0, canned[name], "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        return Moving()

    def test_docs_only_main_delta_is_absorbed(self):
        fake = self._moved("docs/PLAN.md\nREADME.md\n")
        err, out, _ = run(fake)
        self.assertIsNone(err)
        self.assertIn("moved_merge", fake.names())
        self.assertIn("ff", fake.names())
        self.assertTrue([l for l in out if "absorbed" in l and "abc1234" in l])

    def test_code_main_delta_still_refuses_ff(self):
        fake = self._moved("docs/PLAN.md\ncore/x.gd\n")
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")
        self.assertNotIn("moved_merge", fake.names())

    def test_docs_delta_overlapping_batch_refuses_ff(self):
        fake = self._moved("docs/PLAN.md\n", batch="docs/PLAN.md\ncore/a.gd\n")
        err, _, _ = run(fake)
        self.assertEqual(err.step, "ff")

    HARNESSES = [("qol", "x"), ("rocket", "x"), ("gift_fx", "x")]

    def _enet(self, changed, results, **kw):
        fake = Fake({"gate_touched": (0, changed)})
        out, res, err = [], {}, None
        with mock.patch.object(ib, "run_cmd", fake), \
                mock.patch.object(ib.run_enet_set, "discover", return_value=self.HARNESSES), \
                mock.patch.object(ib.run_enet_set, "run_set", return_value=results) as rs:
            try:
                ib.integrate(args_for(dry_run=True, **kw), ib.Ctx(tempfile.gettempdir()), out.append, res)
            except ib.StepFailed as e:
                err = e
        return err, out, rs

    PASS2 = [("qol", "PASS", "", 1.0, "/l"), ("rocket", "PASS", "", 1.0, "/l")]

    def test_enet_runs_when_net_touched(self):
        for changed in ("net/session.gd\n", "tests/enet/qol_enet.gd\n"):
            err, out, rs = self._enet(changed, self.PASS2)
            self.assertIsNone(err)
            rs.assert_called_once()
            self.assertTrue([l for l in out if "ENET SET GREEN" in l])

    def test_enet_selection_net_change_runs_whole_set(self):
        for paths in (["net/a.gd"], ["net/a.gd", "tests/enet/qol_enet.gd"], ["tests/enet/qol_enet.gd", "net\\b.gd"]):
            self.assertEqual(ib.enet_selection(paths), (True, None))

    def test_enet_selection_harness_files_run_only_those(self):
        sel = ib.enet_selection(["tests/enet/qol_enet.gd", "tests/enet/qol_enet.tscn", "tools/run_rocket_enet.ps1", "core/a.gd"])
        self.assertEqual(sel, (True, {"qol", "rocket"}))
        self.assertEqual(ib.enet_selection(["tests/enet/gift_fx_enet.gd.uid"]), (True, {"gift_fx"}))

    def test_enet_selection_shared_or_unnamed_enet_file_runs_whole_set(self):
        for p in ("tests/enet/m3a_acceptance.gd", "tools/enet_result.ps1"):
            self.assertEqual(ib.enet_selection([p, "tests/enet/qol_enet.gd"]), (True, None))

    def test_enet_selection_unrelated_paths_skip(self):
        self.assertEqual(ib.enet_selection(["core/a.gd", "tools/run_enet_set.py", "tests/unit/test_enet_x.gd"]), (False, None))

    def test_enet_step_passes_only_for_changed_harnesses(self):
        err, out, rs = self._enet("tests/enet/qol_enet.gd\ntools/run_rocket_enet.ps1\n", self.PASS2)
        self.assertIsNone(err)
        self.assertEqual(rs.call_args.kwargs["only"], {"qol", "rocket"})
        self.assertTrue([l for l in out if "only changed harnesses: qol,rocket" in l])

    def test_enet_step_net_change_runs_all(self):
        _, _, rs = self._enet("net/a.gd\ntests/enet/qol_enet.gd\n", self.PASS2)
        self.assertIsNone(rs.call_args.kwargs["only"])

    def test_enet_step_removed_harness_is_skipped(self):
        err, out, rs = self._enet("tests/enet/gone_enet.gd\n", self.PASS2)
        self.assertIsNone(err)
        rs.assert_not_called()
        self.assertTrue([l for l in out if "no runner" in l])

    def _soak(self, changed, soak_text=None, **kw):
        ov = {"gate_touched": (0, changed)}
        if soak_text is not None:
            ov["soak"] = (1, soak_text)
        fake = Fake(ov)
        out, res, err = [], {}, None
        with mock.patch.object(ib, "run_cmd", fake), mock.patch.object(ib, "enet_step"):
            try:
                ib.integrate(args_for(dry_run=True, **kw), ib.Ctx(tempfile.gettempdir()), out.append, res)
            except ib.StepFailed as e:
                err = e
        return err, out, fake

    def test_soak_selection(self):
        self.assertTrue(ib.soak_selection(["net/a.gd"]))
        self.assertTrue(ib.soak_selection(["core\\territory\\t.gd"]))
        self.assertTrue(ib.soak_selection(["tools/run_soak.py"]))
        self.assertFalse(ib.soak_selection(["core/a.gd", "autoload/Match.gd", "tools/soak_known.json", ""]))

    def test_soak_not_run_without_idle_flag(self):
        err, out, fake = self._soak("net/a.gd\n")
        self.assertIsNone(err)
        self.assertNotIn("soak", fake.names())
        self.assertTrue([l for l in out if l.startswith("soak      NOT RUN: batch touches soak paths")])

    def test_soak_silent_when_untouched(self):
        err, out, fake = self._soak("core/a.gd\n", soak_idle=True)
        self.assertIsNone(err)
        self.assertNotIn("soak", fake.names())
        self.assertFalse([l for l in out if l.startswith("soak")])

    def test_soak_idle_reports_and_never_fails_the_batch(self):
        for verdict, shown in (("PASS", "ok"), ("REPORT", "REPORT"), ("FAIL", "FAIL"), ("INVALID", "INVALID")):
            err, out, fake = self._soak("net/a.gd\n", "noise\nSOAK RESULT %s: x\n" % verdict, soak_idle=True)
            self.assertIsNone(err, verdict)
            args = dict(fake.calls)["soak"]
            self.assertIn("--idle", args)
            self.assertTrue([l for l in out if l.startswith("soak      %s SOAK RESULT %s" % (shown, verdict))], verdict)

    def test_soak_missing_result_line_is_reported_not_raised(self):
        err, out, _ = self._soak("net/a.gd\n", "crashed", soak_idle=True)
        self.assertIsNone(err)
        self.assertTrue([l for l in out if l.startswith("soak      FAIL no SOAK RESULT")])

    def test_enet_skipped_when_not_touched(self):
        err, out, rs = self._enet("core/a.gd\nui/net_panel.gd\n", self.PASS2)
        self.assertIsNone(err)
        rs.assert_not_called()
        self.assertTrue([l for l in out if l.startswith("enet") and "skip" in l])

    def test_enet_fail_line_fails_step(self):
        err, _, _ = self._enet("net/a.gd\n", [("qol", "PASS", "", 1.0, "/l"), ("rocket", "FAIL", "host: fail marker", 2.0, "/l")])
        self.assertEqual(err.step, "enet")
        self.assertIn("rocket", err.detail)

    def test_enet_missing_result_line_fails_step(self):
        v, d = ib.run_enet_set.parse_result("RKTENET host result=PASS\n")
        self.assertEqual((v, d), ("FAIL", "no ENET RESULT line"))
        err, _, _ = self._enet("net/a.gd\n", [("qol", v, d, 1.0, "/l")])
        self.assertEqual(err.step, "enet")

    def test_enet_empty_set_fails(self):
        err, _, _ = self._enet("net/a.gd\n", [])
        self.assertEqual(err.step, "enet")

    def test_enet_skip_flag_logs_reason(self):
        err, out, rs = self._enet("net/a.gd\n", self.PASS2, skip_enet="harness host busy")
        self.assertIsNone(err)
        rs.assert_not_called()
        self.assertTrue([l for l in out if "harness host busy" in l])

    def test_enet_not_run_after_red_gate(self):
        fake = Fake({"gate_touched": (0, "net/a.gd\n"), "gate": (1, "FULL GATE RED: 1/2\n")})
        with mock.patch.object(ib, "run_cmd", fake), mock.patch.object(ib.run_enet_set, "run_set") as rs:
            with self.assertRaises(ib.StepFailed) as cm:
                ib.integrate(args_for(dry_run=True), ib.Ctx(tempfile.gettempdir()), lambda l: None, {})
        self.assertEqual(cm.exception.step, "gate")
        rs.assert_not_called()

    def test_enet_flaky_harness_passes_step(self):
        err, out, _ = self._enet("net/a.gd\n", [("qol", "PASS", "", 1.0, "/l"), ("beacon", "FLAKY", "first run: x", 2.0, "/l")])
        self.assertIsNone(err)
        self.assertTrue([l for l in out if "enet_flaky=beacon" in l])

    def test_enet_run_set_reruns_failure_once(self):
        calls = []
        def runner(name, script, path, out_dir, timeout_s):
            calls.append(name)
            if name == "flaky":
                return ("FAIL", "boom", 1.0, "/l") if calls.count(name) == 1 else ("PASS", "", 1.0, "/l")
            if name == "bad":
                return "FAIL", "boom", 1.0, "/l"
            return "PASS", "", 1.0, "/l"
        with mock.patch.object(ib.run_enet_set, "discover", return_value=[("ok", "a"), ("flaky", "b"), ("bad", "c")]):
            res = ib.run_enet_set.run_set("/p", "/o", say=lambda l: None, runner=runner)
        self.assertEqual(calls, ["ok", "flaky", "flaky", "bad", "bad"])
        self.assertEqual([r[1] for r in res], ["PASS", "FLAKY", "FAIL"])
        green, line = ib.run_enet_set.summary(res)
        self.assertFalse(green)
        self.assertIn("2/3", line)
        self.assertIn("enet_flaky=flaky", line)

    def test_enet_result_parsing(self):
        p = ib.run_enet_set.parse_result
        self.assertEqual(p("x\nENET RESULT PASS\n"), ("PASS", ""))
        self.assertEqual(p("ENET RESULT FAIL: host: no pass marker\n"), ("FAIL", "host: no pass marker"))

    def test_dry_run_and_no_game_code(self):
        fake = Fake()
        err, _, _ = run(fake, dry_run=True)
        self.assertIsNone(err)
        for bad in ("ff", "push", "close_B-1"):
            self.assertNotIn(bad, fake.names())
        fake = Fake()
        run(fake, game_code=False, dry_run=True)
        self.assertNotIn("gate", fake.names())
        self.assertIn("lint", fake.names())

    def test_no_game_code_lint_red_fails(self):
        class Red(Fake):
            def __call__(s, ctx, name, args, cwd, timeout):
                if name == "lint":
                    s.calls.append((name, args))
                    return 1, "LINT ALL RED: lint_dead" + chr(10), "/l"
                return Fake.__call__(s, ctx, name, args, cwd, timeout)
        err, _, _ = run(Red(), game_code=False)
        self.assertEqual(err.step, "lint")

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
        self.assertEqual(ib.merge_subject("wt/123.7-x"), "Merge wt/123.7-x")

    def test_link_args_record_the_commit_on_the_bead(self):
        argv = ib.link_args("R", "B-1", "abc123", ["wt/a", "wt/b"])
        self.assertEqual(argv[1:6], ["-C", "R", "comments", "add", "B-1"])
        self.assertIn("main abc123 (merge of wt/a, wt/b)", argv[-1])
        fake = Fake()
        run(fake, branches=["wt/b-1"])
        a = [c[1] for c in fake.calls if c[0] == "merge_wt_b-1"][0]
        self.assertIn("--no-ff", a)
        self.assertNotIn("--no-edit", a)
        i = a.index("-m")
        self.assertEqual(a[i + 1], "Merge wt/b-1")
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


class StatusFileTests(unittest.TestCase):
    """the status.json a watcher polls while a batch runs."""

    def _main(self, extra, behave):
        fake = Fake()
        log_dir = tempfile.mkdtemp()

        def fake_integrate(args, ctx, say, res):
            ctx.log_path("fetch")
            say("worktree  ok   W/integrate-tmp-1 @ base111")
            res["worktree"], res["branch"], res["result"] = "W/integrate-tmp-1", "integrate/tmp-1", "result22"
            ctx.log_path("gate")
            behave(res)
        with mock.patch.object(ib, "run_cmd", fake), mock.patch.object(ib, "integrate", fake_integrate):
            try:
                code = ib.main(["--branches", "wt/a", "wt/b", "--beads", "B-1", "--log-dir", log_dir] + extra)
            except RuntimeError:
                code = "raised"
        with open(os.path.join(log_dir, ib.STATUS_FILE), encoding="utf-8") as fh:
            return code, json.load(fh)

    def test_success_records_branches_lines_and_ok(self):
        def green(res):
            res["verdict"] = "GREEN"
        code, st = self._main(["--no-push"], green)
        self.assertEqual(code, 0)
        self.assertEqual((st["state"], st["mode"], st["branches"], st["beads"]), ("ok", "no-push", ["wt/a", "wt/b"], ["B-1"]))
        self.assertEqual((st["worktree"], st["result"], st["verdict"]), ("W/integrate-tmp-1", "result22", "GREEN"))
        self.assertEqual(st["lines"][0], "worktree  ok   W/integrate-tmp-1 @ base111")
        self.assertTrue(st["lines"][-1].startswith("INTEGRATE OK"))
        self.assertEqual(st["pid"], os.getpid())

    def test_failed_step_and_detail_are_recorded(self):
        def red(res):
            raise ib.StepFailed("gate", "verdict RED; log /log/gate")
        code, st = self._main([], red)
        self.assertEqual(code, 1)
        self.assertEqual((st["state"], st["failed_step"], st["step"]), ("failed", "gate", "gate"))
        self.assertIn("verdict RED", st["detail"])
        self.assertEqual(st["worktree"], "W/integrate-tmp-1")

    def test_a_crash_is_recorded_and_still_raised(self):
        def boom(res):
            raise RuntimeError("disk gone")
        code, st = self._main([], boom)
        self.assertEqual(code, "raised")
        self.assertEqual(st["state"], "crashed")
        self.assertIn("RuntimeError: disk gone", st["detail"])

    def test_step_follows_the_log_being_written(self):
        log_dir = tempfile.mkdtemp()
        ctx = ib.Ctx(log_dir, ib.Status(log_dir, args_for(merge_only=True)))
        ctx.log_path("merge_wt_a")
        with open(os.path.join(log_dir, ib.STATUS_FILE), encoding="utf-8") as fh:
            st = json.load(fh)
        self.assertEqual((st["step"], st["mode"], st["state"]), ("merge_wt_a", "merge-only", "running"))

    def test_unwritable_log_dir_never_fails_the_batch(self):
        status = ib.Status(os.path.join(tempfile.gettempdir(), "no", "such", "dir"), args_for())
        status.line("x")
        status.end("ok", {})


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

    def test_script_without_uid_aborts(self):
        fake = Fake({"probes_wt_a": (0, "core/a.gd\nshaders/s.gdshader\nshaders/s.gdshader.uid\n")})
        err, out, res = run(fake)
        self.assertEqual(err.step, "probes")
        self.assertIn("wt/a: missing uid: core/a.gd", err.detail)
        self.assertNotIn("s.gdshader added", err.detail)
        self.assertFalse([n for n in fake.names() if n.startswith("merge_")])

    def test_clean_branches_pass(self):
        fake = Fake({"probes_wt_a": (0, "core/a.gd\ncore/a.gd.uid\n")})
        err, out, res = run(fake)
        self.assertTrue(err is None or err.step != "probes")


class HintsMergeTests(unittest.TestCase):
    """Real git repo: two branches editing config/ui/tuning_panel_hints.tres."""

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
        os.makedirs(os.path.dirname(os.path.join(self.repo, ib.HINTS_PATH)), exist_ok=True)
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
            ib.merge_branches(ib.Ctx(self.tmp.name), self.repo, branches, out.append)
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


class UiBaselineTests(unittest.TestCase):
    BASE = '{\n "R2": {\n  "ui/a.gd": 5,\n  "ui/b.gd": 4,\n  "ui/c.gd": 3\n }\n}\n'

    @staticmethod
    def bl(r2):
        import json
        return json.dumps({"R2": r2}, indent=1, sort_keys=True) + "\n"

    def test_min_per_key(self):
        o = self.bl({"ui/a.gd": 2, "ui/b.gd": 4, "ui/c.gd": 3})
        t = self.bl({"ui/a.gd": 5, "ui/b.gd": 1, "ui/c.gd": 3})
        out, why = ib.merge_ui_baselines(o, t, self.BASE)
        self.assertIsNone(why)
        self.assertEqual(out, self.bl({"ui/a.gd": 2, "ui/b.gd": 1, "ui/c.gd": 3}))

    def test_removed_key_and_missing_file(self):
        o = self.bl({"ui/a.gd": 5, "ui/c.gd": 3})  # removed b
        t = self.bl({"ui/a.gd": 5, "ui/b.gd": 4, "ui/c.gd": 3, "ui/n.gd": 2})
        out, why = ib.merge_ui_baselines(o, t, self.BASE, lambda f: f != "ui/c.gd")
        self.assertIsNone(why)
        self.assertEqual(out, self.bl({"ui/a.gd": 5, "ui/n.gd": 2}))

    def test_malformed(self):
        for bad in ("{nope", "[]", '{"R2": {"ui/a.gd": "x"}}', '{"R2": 3}'):
            out, why = ib.merge_ui_baselines(bad, self.BASE, self.BASE)
            self.assertIsNone(out)
            self.assertTrue(why)

    @staticmethod
    def _w(repo, text):
        with open(os.path.join(repo, ib.UI_BASELINE_PATH), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)

    def _repo(self, tmp):
        repo = os.path.join(tmp, "r").replace("\\", "/")
        os.makedirs(os.path.join(repo, "tools"))
        os.makedirs(os.path.join(repo, "ui"))
        git_run(repo, "init", "-q", "-b", "main")
        git_run(repo, "config", "user.email", "t@t")
        git_run(repo, "config", "user.name", "t")
        for f in ("a", "b", "c"):
            with open(os.path.join(repo, "ui", f + ".gd"), "w") as fh:
                fh.write("x")
        self._w(repo, self.BASE)
        git_run(repo, "add", "-A")
        git_run(repo, "commit", "-qm", "base")
        for name, r2 in (("a", {"ui/a.gd": 2, "ui/b.gd": 4, "ui/c.gd": 3}),
                         ("b", {"ui/a.gd": 5, "ui/b.gd": 1, "ui/c.gd": 3})):
            git_run(repo, "checkout", "-q", "-b", name, "main")
            self._w(repo, self.bl(r2))
            git_run(repo, "add", "-A")
            git_run(repo, "commit", "-qm", name)
        git_run(repo, "checkout", "-q", "main")
        return repo

    def _merge(self, lint_code):
        with tempfile.TemporaryDirectory() as tmp:
            repo = self._repo(tmp)
            real = ib.run_cmd

            def fake(ctx, name, args, cwd, timeout):
                if name == "uib_lint":
                    return lint_code, "lint", "log"
                return real(ctx, name, args, cwd, timeout)
            out = []
            with mock.patch.object(ib, "run_cmd", fake):
                try:
                    ib.merge_branches(ib.Ctx(tmp), repo, ["a", "b"], out.append)
                    err = None
                except ib.StepFailed as e:
                    err = e
            with open(os.path.join(repo, ib.UI_BASELINE_PATH), encoding="utf-8") as fh:
                text = fh.read()
            merging = os.path.exists(os.path.join(repo, ".git", "MERGE_HEAD"))
            return err, out, text, merging

    def test_real_conflict_resolved(self):
        err, out, text, _ = self._merge(0)
        self.assertIsNone(err, err and err.detail)
        self.assertTrue(any("auto-resolved" in l for l in out))
        self.assertEqual(text, self.bl({"ui/a.gd": 2, "ui/b.gd": 1, "ui/c.gd": 3}))

    def test_lint_failure_aborts(self):
        err, _, _, merging = self._merge(1)
        self.assertEqual(err.step, "merge")
        self.assertIn("refused", err.detail)
        self.assertFalse(merging)


class AbsorbRealGitTests(unittest.TestCase):
    """Real temp repo: main gains commits after the gated base."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = os.path.join(self.tmp.name, "r")
        self.wt = os.path.join(self.tmp.name, "wt")
        os.makedirs(self.repo)
        git_run(self.repo, "init", "-b", "main")
        git_run(self.repo, "config", "user.email", "t@t")
        git_run(self.repo, "config", "user.name", "t")
        self.commit("a.txt", "1")
        self.base = self.head()
        git_run(self.repo, "worktree", "add", "-b", "tmp", self.wt, "main")
        git_run(self.wt, "config", "user.email", "t@t")
        git_run(self.wt, "config", "user.name", "t")
        with open(os.path.join(self.wt, "b.txt"), "w") as fh:
            fh.write("batch")
        git_run(self.wt, "add", "-A")
        git_run(self.wt, "commit", "-m", "batch")
        self.result = subprocess.run(["git", "-C", self.wt, "rev-parse", "HEAD"], capture_output=True,
                                     text=True).stdout.strip()

    def tearDown(self):
        subprocess.run(["git", "-C", self.repo, "worktree", "remove", "--force", self.wt], capture_output=True)
        self.tmp.cleanup()

    def head(self):
        return subprocess.run(["git", "-C", self.repo, "rev-parse", "HEAD"], capture_output=True,
                              text=True).stdout.strip()

    def commit(self, rel, text):
        p = os.path.join(self.repo, *rel.split("/"))
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as fh:
            fh.write(text)
        git_run(self.repo, "add", "-A")
        git_run(self.repo, "commit", "-m", "c " + rel)

    def absorb(self):
        out = []
        new = ib.absorb_docs_delta(ib.Ctx(self.tmp.name), self.repo, self.wt, self.base, self.head(),
                                   self.result, out.append)
        return new, out

    def test_docs_commit_absorbed_and_ff_possible(self):
        self.commit("docs/x.md", "d")
        self.commit("NOTES.md", "n")
        new, out = self.absorb()
        self.assertEqual(len(out), 1)
        git_run(self.repo, "merge", "--ff-only", "tmp")
        for rel in ("b.txt", "docs/x.md", "NOTES.md"):
            self.assertTrue(os.path.isfile(os.path.join(self.repo, *rel.split("/"))), rel)
        self.assertEqual(self.head(), new)

    def test_code_commit_not_absorbed(self):
        self.commit("docs/x.md", "d")
        self.commit("core/y.gd", "c")
        with self.assertRaises(ib.StepFailed):
            self.absorb()


if __name__ == "__main__":
    unittest.main(verbosity=1)
