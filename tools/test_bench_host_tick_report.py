"""Tests for bench_host_tick_report.py on canned lines (no Godot launched):
python -I tools/test_bench_host_tick_report.py"""
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bench_host_tick_report as report  # noqa: E402


def phase_line(phase, bodies=1500, smoke=0, **over):
    f = dict(
        ticks=600, mean_ms=10.0, p50_ms=10.0, p99_ms=14.0, p999_ms=18.0, max_ms=20.0, over_budget=0, awake=100.0,
        scan_phase=7, scan_tick_ms=10.5, other_tick_ms=10.0, snap_parity=0, snap_tick_ms=10.2, nonsnap_tick_ms=10.0,
        registry_ms=0.5, effects_ms=0.2, snapshot_ms=0.4)
    if phase == "ablate":
        for name in report.SUBSYSTEMS:
            f.update({"ablate_%s_delta_ms" % name: 0.1, "ablate_%s_min_ms" % name: 0.0, "ablate_%s_max_ms" % name: 0.2})
        f.update(batch_vy_on=0.1, batch_vy_off=0.1)
    if phase == "remainder":
        f.update(remainder_ms=3.0, all_on_ms=10.0)
    if phase == "frozen":
        f["p50_ms"] = 5.0  # 3.3 us per body at 1500, under the 5 us trigger
    f.update(over)
    head = "BENCH_HOST_TICK phase=%s bodies=%d layout=slab smoke=%d" % (phase, bodies, smoke)
    return head + "".join(" %s=%s" % (k, v) for k, v in f.items())


def canned(wanted=1500, smoke=0, overrides=None, pose="abc123", done=True):
    overrides = overrides or {}
    lines = ["noise", "BENCH_HOST_TICK start bodies=%d layout=slab seed=1 smoke=%d ticks=9000" % (wanted, smoke)]
    for phase in report.PHASES:
        lines.append(phase_line(phase, bodies=wanted, smoke=smoke, **overrides.get(phase, {})))
    lines.append("BENCH_HOST_TICK pose_hash=%s bodies=%d churn_added=9 smoke=%d" % (pose, wanted, smoke))
    if done:
        lines.append("BENCH_HOST_TICK result=DONE smoke=%d note=x" % smoke)
    return lines


def gate(run, name):
    return [g for g in report.evaluate_gates(run) if g.name.startswith(name)][0]


class ParseTest(unittest.TestCase):
    def test_parses_all_phases(self):
        run = report.parse_lines(canned())
        self.assertEqual(run.wanted, 1500)
        self.assertEqual(run.layout, "slab")
        self.assertEqual(sorted(run.phases), sorted(report.PHASES))
        self.assertEqual(run.phases["remainder"]["remainder_ms"], 3.0)

    def test_refuses_smoke_output(self):
        with self.assertRaises(report.BenchError):
            report.parse_lines(canned(smoke=1))

    def test_refuses_a_single_smoke_line_in_real_output(self):
        lines = canned()
        lines[3] = phase_line("churn", smoke=1)
        with self.assertRaises(report.BenchError):
            report.parse_lines(lines)

    def test_refuses_unfinished_run(self):
        with self.assertRaises(report.BenchError):
            report.parse_lines(canned(done=False))

    def test_refuses_fail_line_and_empty_input(self):
        with self.assertRaises(report.BenchError):
            report.parse_lines(canned() + ["BENCH_HOST_TICK result=FAIL reason=kill_plane_fall phase=churn falls=1"])
        with self.assertRaises(report.BenchError):
            report.parse_lines(["no bench output"])

    def test_refuses_missing_phase(self):
        lines = [l for l in canned() if "phase=ablate" not in l]
        with self.assertRaises(report.BenchError):
            report.parse_lines(lines)


class GateTest(unittest.TestCase):
    def test_baseline_triggers_nothing(self):
        run = report.parse_lines(canned())
        self.assertEqual([g.hit for g in report.evaluate_gates(run)], [False, False, False, False, False, False, None])
        text = report.format_gates(run, report.evaluate_gates(run))
        self.assertIn("fix packages released by the bench: none", text)
        self.assertIn("Q1 (physics-feel levers, gates 2/3): not triggered", text)

    def test_scan_delta_boundary(self):
        just_under = report.parse_lines(canned(overrides={"frozen": {"scan_tick_ms": 14.99, "other_tick_ms": 10.0}}))
        at = report.parse_lines(canned(overrides={"frozen": {"scan_tick_ms": 15.0, "other_tick_ms": 10.0}}))
        self.assertFalse(gate(just_under, "1a").hit)
        self.assertTrue(gate(at, "1a").hit)
        self.assertIn("HP-SCAN", report.format_gates(at, report.evaluate_gates(at)))

    def test_snapshot_gate_from_parity_delta(self):
        run = report.parse_lines(canned(overrides={"churn": {"snap_tick_ms": 12.5, "nonsnap_tick_ms": 10.0}}))
        self.assertTrue(gate(run, "1b").hit)
        self.assertIn("HP-SNAP", report.format_gates(run, report.evaluate_gates(run)))

    def test_frozen_floor_per_body(self):
        run = report.parse_lines(canned(overrides={"frozen": {"p50_ms": 7.5}}))  # 5 us x 1500
        self.assertTrue(gate(run, "1c").hit)
        under = report.parse_lines(canned(overrides={"frozen": {"p50_ms": 7.45}}))
        self.assertFalse(gate(under, "1c").hit)
        self.assertNotIn("HP-", report.format_gates(run, report.evaluate_gates(run)).split("fix packages released by the bench:")[1].split("\n")[0])

    def test_awake_fraction_triggers_q1_only(self):
        run = report.parse_lines(canned(overrides={"churn": {"awake": 451.0}}))  # over 30% of 1500
        text = report.format_gates(run, report.evaluate_gates(run))
        self.assertTrue(gate(run, "2").hit)
        self.assertIn("Q1 (physics-feel levers, gates 2/3): TRIGGERED", text)
        self.assertIn("fix packages released by the bench: none", text)
        self.assertFalse(gate(report.parse_lines(canned(overrides={"churn": {"awake": 450.0}})), "2").hit)

    def test_remainder_share_triggers_q1(self):
        run = report.parse_lines(canned(overrides={"remainder": {"remainder_ms": 6.5}}))  # 65% of the 10 ms p50
        self.assertTrue(gate(run, "3").hit)
        self.assertIn("TRIGGERED", report.format_gates(run, report.evaluate_gates(run)))

    def test_loops_gate_releases_loops_and_scan_without_summing_stable(self):
        over = {name: 1.0 for name in ("registry", "effects", "batch")}
        ablate = {"ablate_%s_delta_ms" % k: v for k, v in over.items()}
        ablate["ablate_stable_delta_ms"] = 50.0  # reported, not part of gate 4
        run = report.parse_lines(canned(overrides={"ablate": ablate}))  # 3.0 ms = 30% of 10 ms
        self.assertTrue(gate(run, "4").hit)
        text = report.format_gates(run, report.evaluate_gates(run))
        self.assertIn("fix packages released by the bench: HP-LOOPS, HP-SCAN", text)
        quiet = report.parse_lines(canned(overrides={"ablate": {"ablate_stable_delta_ms": 50.0}}))
        self.assertFalse(gate(quiet, "4").hit)

    def test_ablation_gates_use_the_same_window_denominator(self):
        # Early CHURN p50 is tiny (the pile has not grown yet); the remainder and the deltas
        # are measured later on a bigger pile and must not be divided by it.
        over = {"churn": {"p50_ms": 1.0}, "remainder": {"remainder_ms": 3.0, "all_on_ms": 10.0},
                "ablate": {"mean_ms": 10.0, "ablate_registry_delta_ms": 0.5}}
        run = report.parse_lines(canned(overrides=over))
        self.assertFalse(gate(run, "3").hit)
        self.assertFalse(gate(run, "4").hit)
        self.assertIn("different body state", gate(run, "3").text)

    def test_gate_run_is_the_largest_slab(self):
        runs = [report.parse_lines(canned(wanted=n)) for n in (400, 1500, 1000)]
        self.assertEqual(report.pick_gate_run(runs).wanted, 1500)
        self.assertIsNone(report.pick_gate_run([]))


class FloorTest(unittest.TestCase):
    def test_identical_deterministic_fields_with_wall_clock_spread(self):
        a = report.parse_lines(canned(wanted=1000))
        b = report.parse_lines(canned(wanted=1000, overrides={"churn": {"p50_ms": 10.4, "scan_tick_ms": 11.0}}))
        same, text = report.floor_report(a, b)
        self.assertTrue(same)
        self.assertIn("IDENTICAL", text)
        self.assertIn("p50 0.400", text)

    def test_deterministic_difference_is_flagged(self):
        a = report.parse_lines(canned(wanted=1000))
        for override, pose in (({"churn": {"awake": 101.0}}, "abc123"), ({}, "zzz")):
            same, text = report.floor_report(a, report.parse_lines(canned(wanted=1000, overrides=override, pose=pose)))
            self.assertFalse(same)
            self.assertIn("DIFF", text)

    def test_full_report_pairs_equal_counts(self):
        runs = [report.parse_lines(canned(wanted=n)) for n in (1000, 1500, 1000)]
        text = report.full_report(runs)
        self.assertEqual(text.count("== floor:"), 1)
        self.assertIn("== gates of plan 3.4 on 1500/slab", text)


if __name__ == "__main__":
    unittest.main()
