#!/usr/bin/env python
"""Tests for bot_h2h.py (Bontago-1t5.12 gate tool; P1b options Bontago-1t5.20).

Fake runner only: no Godot is launched. Run with:
    python -I tools/test_bot_h2h.py
"""

from __future__ import annotations

import contextlib
import io
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bot_h2h as h2h  # noqa: E402

LINE_TMPL = "HEADLESS_MATCH index=0 mode=0 seed=1 duration=%s winner_team=%d placements=9 homes_alive=2"


def _write_candidate(tmp: str) -> str:
    cand = os.path.join(tmp, "c.txt")
    with open(cand, "w", encoding="utf-8") as fh:
        fh.write("weight_height = 1.2\n")
    return cand


def _run(argv: list, runner=None) -> tuple:
    out = io.StringIO()
    kwargs = {} if runner is None else {"runner": runner}
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
        rc = h2h.main(argv, **kwargs)
    return rc, out.getvalue()


class H2HTests(unittest.TestCase):
    def test_wilson_and_verdict(self) -> None:
        lo, hi = h2h.wilson(80, 100)
        self.assertLess(lo, 0.8)
        self.assertGreater(hi, 0.8)
        self.assertEqual(h2h.verdict(90, 10, 100), "PASS")
        self.assertEqual(h2h.verdict(50, 50, 100), "FAIL")
        self.assertEqual(h2h.verdict(76, 24, 100), "INCONCLUSIVE")
        self.assertEqual(h2h.verdict(9, 1, 10), "INSUFFICIENT")

    def test_parse_winner_takes_last_line(self) -> None:
        text = "HEADLESS_MATCH index=0 mode=0 seed=1 duration=5.0 winner_team=3 placements=9 homes_alive=2\n" \
               "HEADLESS_MATCH index=1 mode=0 seed=2 duration=5.0 winner_team=-1 placements=9 homes_alive=2\n"
        self.assertEqual(h2h.parse_winner(text), -1)
        self.assertIsNone(h2h.parse_winner("nothing"))

    def test_parse_duration_takes_last_line(self) -> None:
        text = LINE_TMPL % ("12.5", 0) + "\n" + LINE_TMPL % ("300.0", -1) + "\n"
        self.assertEqual(h2h.parse_duration(text), 300.0)
        self.assertIsNone(h2h.parse_duration("HEADLESS_BOTS done t=1.0"))

    def test_timeout_match_is_draw_not_failed(self) -> None:
        line = "HEADLESS_MATCH index=1 mode=0 seed=1 duration=300.0 winner_team=-1 placements=9 homes_alive=8 teams=0 timeout=1"
        self.assertTrue(h2h.timed_out(line))
        self.assertFalse(h2h.timed_out(line.replace(" timeout=1", "")))
        jobs = [h2h.MatchJob(1, False, []), h2h.MatchJob(1, True, []), h2h.MatchJob(2, False, [])]
        t = h2h.tally(jobs, [line, "HEADLESS_BOTS done t=1.0", line.replace(" timeout=1", "").replace("-1", "0")],
                      [0], [1])
        self.assertEqual((t["draws"], t["timeouts"], t["failed"], t["wins"]), (1, 1, 1, 1))

    def test_refuses_without_seam_and_dry_run(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cand = _write_candidate(tmp)
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(h2h.main(["--candidate", cand, "--out-dir", tmp]), 2)
            with contextlib.redirect_stdout(io.StringIO()) as out:
                self.assertEqual(h2h.main(["--candidate", cand, "--out-dir", tmp, "--pairs", "2",
                                           "--dry-run"]), 0)
            self.assertIn("H2H DRY-RUN matches=4", out.getvalue())

    def test_paired_run_with_fake_runner(self) -> None:
        # Candidate (teams 0,2,4,6 in match A, 1,3,5,7 in B) wins every match.
        def runner(cmd, timeout):
            swapped = any("slots=1,3,5,7" in c for c in cmd)
            winner = 1 if swapped else 0
            return "HEADLESS_MATCH index=0 mode=0 seed=1 duration=1.0 winner_team=%d placements=1 homes_alive=1" % winner

        with tempfile.TemporaryDirectory() as tmp:
            cand = _write_candidate(tmp)
            rc, text = _run(["--candidate", cand, "--out-dir", tmp, "--pairs", "50", "--parallel", "4",
                             "--godot-args=--match-seed={seed} --bot-weights-slots={cand_slots}"],
                            runner=runner)
            self.assertEqual(rc, 0)
            self.assertIn("H2H RESULT PASS", text)
            self.assertIn("matches=100 wins=100", text)


class P1bOptionTests(unittest.TestCase):
    def test_default_parallel_is_one(self) -> None:
        self.assertEqual(h2h.build_parser().parse_args([]).parallel, 1)

    def test_candidate_optional_without_weight_placeholder(self) -> None:
        rc, text = _run(["--dry-run", "--pairs", "2", "--godot-args=--match-seed={seed}"])
        self.assertEqual(rc, 0)
        self.assertIn("H2H DRY-RUN matches=4", text)
        self.assertNotIn("weights", text)

    def test_candidate_missing_with_weight_placeholder_refuses(self) -> None:
        rc, _ = _run(["--dry-run", "--pairs", "2", "--godot-args=--w={weights_json}"])
        self.assertEqual(rc, 2)

    def test_players_mode_and_no_swap_in_command(self) -> None:
        rc, text = _run(["--dry-run", "--pairs", "3", "--no-swap", "--bots", "1", "--players", "4",
                         "--mode", "elimination", "--cand-slots-a", "0", "--godot-args=--match-seed={seed}"])
        self.assertEqual(rc, 0)
        self.assertIn("H2H DRY-RUN matches=3", text)  # one job per seed, no swapped half
        line = text.splitlines()[0]
        self.assertIn("--players=4", line)
        self.assertIn("--mode=elimination", line)
        self.assertIn("--bots=1", line)

    def test_no_swap_run_reports_per_seed_and_time_summary(self) -> None:
        durations = {1000: "40.0", 1001: "100.0", 1002: "200.0"}

        def runner(cmd, timeout):
            seed = int([c for c in cmd if c.startswith("--match-seed=")][0].split("=")[1])
            return LINE_TMPL % (durations[seed], 0)

        with tempfile.TemporaryDirectory() as tmp:
            rc, text = _run(["--no-swap", "--pairs", "3", "--cand-slots-a", "0", "--out-dir", tmp,
                             "--godot-args=--match-seed={seed}"], runner=runner)
            self.assertEqual(rc, 1)  # 3 matches is under the 100-match gate: INSUFFICIENT by design
            self.assertIn("H2H matches=3 wins=3", text)
            self.assertIn("candidate_win_time_s median=100.0 max=200.0 n=3", text)
            self.assertIn("H2H seed=1001 side=a result=win winner_team=0 duration=100.0", text)
            self.assertIn("H2H RESULT INSUFFICIENT", text)

    def test_time_summary_skips_draws_and_losses(self) -> None:
        jobs = [h2h.MatchJob(1, False, []), h2h.MatchJob(2, False, []), h2h.MatchJob(3, False, [])]
        outs = [LINE_TMPL % ("50.0", 0), LINE_TMPL % ("999.0", 1), LINE_TMPL % ("300.0", -1)]
        self.assertEqual(h2h.win_times(jobs, outs, [0], [1]), [50.0])
        t = h2h.tally(jobs, outs, [0], [1])
        self.assertEqual((t["wins"], t["losses"], t["draws"], t["timeouts"]), (1, 1, 1, 0))

    def test_battery_dry_run_prints_e1_to_e5(self) -> None:
        rc, text = _run(["--dry-run", "--battery", "all"])
        self.assertEqual(rc, 0)
        for label in ("E1", "E2", "E3", "E4", "E4-passive", "E5a", "E5b", "E5c", "E5d"):
            self.assertIn("# %s " % label, text)
        self.assertIn("H2H DRY-RUN label=E1 matches=100", text)  # 50 pairs, swapped
        self.assertIn("H2H DRY-RUN label=E3 matches=20", text)   # 20 seeds, no swap
        self.assertIn("H2H DRY-RUN label=E4-passive matches=10", text)
        self.assertIn("--bot-brain=<v2>", text)
        self.assertIn("--players=4", text)
        self.assertIn("--mode=elimination", text)
        self.assertIn("H2H DRY-RUN battery=all matches=", text)

    def test_battery_selects_one_group(self) -> None:
        rc, text = _run(["--dry-run", "--battery", "E4"])
        self.assertEqual(rc, 0)
        self.assertIn("# E4 ", text)
        self.assertIn("# E4-passive ", text)
        self.assertNotIn("# E1 ", text)

    def test_battery_refuses_real_launch(self) -> None:
        rc, _ = _run(["--battery", "E1"])
        self.assertEqual(rc, 2)

    def test_real_launch_refuses_unfilled_placeholder(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cand = _write_candidate(tmp)
            rc, _ = _run(["--candidate", cand, "--out-dir", tmp,
                          "--godot-args=--bot-brain=<v2> --match-seed={seed} {cand_slots}"])
            self.assertEqual(rc, 2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
