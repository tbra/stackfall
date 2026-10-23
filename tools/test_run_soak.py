"""Tests for tools/run_soak.py with an injected fake process runner, slots and clock. No Godot starts.
Run: python tools/test_run_soak.py
"""
import contextlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_soak as rs  # noqa: E402
import soak_report as sr  # noqa: E402
import test_soak_report as t  # noqa: E402

CFG_TEXT = """[resource]
duration_s = 900.0
match_seed = 20261020
client_sim_lag_ms = 100.0
client_sim_loss = 0.02
host_ready_timeout_s = 60.0
shutdown_grace_s = 120.0
idle_cpu_max_pct = 25.0
curve_bands = PackedInt32Array(250, 500, 1000, 1500)
"""
READY = "HEADLESS_BOTS t=1.0 placed=0\n"


class Clock:
    def __init__(self):
        self.now = 0.0

    def time(self):
        return self.now

    def sleep(self, s):
        self.now += s


class FakeProc:
    def __init__(self, clock, ends_at, log_path):
        self.clock, self.ends_at, self.log_path = clock, ends_at, log_path
        self.killed = False

    def poll(self):
        if self.killed or (self.ends_at is not None and self.clock.now >= self.ends_at):
            return 0
        return None

    def kill(self):
        if self.poll() is None:
            self.killed = True


class FakeRunner:
    """Writes canned logs at start. host_ready=False leaves the host log without HEADLESS_BOTS;
    hang=True keeps both processes alive past any deadline."""

    def __init__(self, clock, host_extra=(), client_extra=(), host_ready=True, hang=False):
        self.clock, self.hang, self.host_ready = clock, hang, host_ready
        self.host_text, self.client_text = t.logs(host_extra, client_extra)
        self.cmds, self.procs = [], []

    def start(self, cmd, log_path):
        self.cmds.append(cmd)
        is_host = "--headless-host" in cmd
        text = (READY if self.host_ready else "") + self.host_text if is_host else self.client_text
        with open(log_path, "w") as fh:
            fh.write(text)
        p = FakeProc(self.clock, None if self.hang else self.clock.now + 30, log_path)
        self.procs.append(p)
        return p


class FakeSlots:
    def __init__(self, loads=(5,)):
        self.loads = list(loads)
        self.exclusive = []

    def cpu_load_pct(self):
        return self.loads.pop(0) if len(self.loads) > 1 else self.loads[0]

    @contextlib.contextmanager
    def godot_exclusive(self, label="exclusive", wait_s=None):
        self.exclusive.append(label)
        yield


class RunSoakTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.checkout = os.path.join(self.tmp.name, "wt")
        os.makedirs(os.path.join(self.checkout, "config", "soak"))
        with open(os.path.join(self.checkout, rs.CONFIG_REL), "w") as fh:
            fh.write(CFG_TEXT)
        self.out = os.path.join(self.tmp.name, "out")
        self.lines = []

    def go(self, runner, slots=None, triage=None, scenario="load", clock=None):
        clock = clock or runner.clock
        argv = ["--idle", "--path", self.checkout, "--out", self.out, "--scenario", scenario]
        return rs.main(argv, runner=runner, slots=slots or FakeSlots(), triage=triage or (lambda p: (0, "")),
                       clock=clock.time, sleep=clock.sleep, say=self.lines.append, godot="godot")

    def result(self):
        return [x for x in self.lines if x.startswith("SOAK RESULT")]

    def test_without_idle_refuses_and_starts_nothing(self):
        clock = Clock()
        runner = FakeRunner(clock)
        code = rs.main(["--path", self.checkout], runner=runner, slots=FakeSlots(), say=self.lines.append)
        self.assertEqual((code, self.lines), (3, [rs.REFUSAL]))
        self.assertIn("idle", rs.REFUSAL)
        self.assertEqual(runner.cmds, [])

    def test_clean_pair_passes_and_prints_one_result_line(self):
        clock = Clock()
        runner = FakeRunner(clock)
        slots = FakeSlots()
        self.assertEqual(self.go(runner, slots), 0)
        self.assertEqual(len(self.result()), 1)
        self.assertTrue(self.result()[0].startswith("SOAK RESULT PASS: load 0 violations"))
        self.assertEqual(slots.exclusive, ["soak"])
        self.assertEqual(len(runner.cmds), 2)
        self.assertTrue(all(os.path.exists(os.path.join(self.out, n)) for n in ("load.log", "load_host.log", "load_client.log")))
        with open(os.path.join(self.out, "load.log"), encoding="utf-8") as fh:
            merged = fh.read()
        self.assertIn("[host] SOAK_END", merged)
        self.assertIn("[client] SOAK_END", merged)

    def test_injected_violation_fails(self):
        clock = Clock()
        code = self.go(FakeRunner(clock, host_extra=[t.violation("authority.fuzz_accepted")]))
        self.assertEqual(code, 1)
        self.assertEqual(self.result(), ["SOAK RESULT FAIL: authority.fuzz_accepted x1"])

    def test_known_id_reports(self):
        clock = Clock()
        code = self.go(FakeRunner(clock, client_extra=[t.violation("budget.client_tick_p99", "client")]))
        self.assertEqual(code, 0)
        self.assertEqual(self.result(), ["SOAK RESULT REPORT: 1 known (budget.client_tick_p99), 0 new violations"])

    def test_commands_per_scenario(self):
        port = 4242
        cfg = sr.read_tres(CFG_TEXT)
        host = rs.build_host_cmd("godot", "wt", port, "authority", cfg, 180.0)
        for flag in ("--headless-host", "--port=4242", "--bots=6", "--players=8", "--seconds=180", "--soak",
                     "--match-config=res://config/soak/soak_match_authority.tres", "--match-seed=20261020"):
            self.assertIn(flag, host)
        self.assertIn("--bots=8", rs.build_host_cmd("godot", "wt", port, "load", cfg, 900.0))
        client = rs.build_client_cmd("godot", "wt", port, "authority", cfg)
        for flag in ("--join=127.0.0.1:4242", "--sim-lag=100", "--sim-loss=0.02", "--soak", "--soak-fuzz", "--debug"):
            self.assertIn(flag, client)
        self.assertNotIn("--soak-fuzz", rs.build_client_cmd("godot", "wt", port, "load", cfg))

    def test_both_peers_name_the_scenario_they_run(self):
        cfg = sr.read_tres(CFG_TEXT)
        for name in ("load", "authority"):
            for cmd in (rs.build_host_cmd("godot", "wt", 1, name, cfg, 10.0), rs.build_client_cmd("godot", "wt", 1, name, cfg)):
                self.assertIn("--soak-scenario=%s" % name, cmd)

    def test_scenario_all_runs_both_with_their_durations(self):
        clock = Clock()
        runner = FakeRunner(clock)
        self.assertEqual(self.go(runner, scenario="all"), 0)
        hosts = [c for c in runner.cmds if "--headless-host" in c]
        self.assertEqual([[x for x in c if x.startswith("--seconds=")][0] for c in hosts],
                         ["--seconds=960", "--seconds=240"])
        self.assertTrue(self.result()[0].startswith("SOAK RESULT PASS: load+authority"))

    def test_busy_machine_before_is_invalid_and_runs_nothing(self):
        clock = Clock()
        runner = FakeRunner(clock)
        self.assertEqual(self.go(runner, FakeSlots([61])), 2)
        self.assertEqual(runner.cmds, [])
        self.assertEqual(self.result(), ["SOAK RESULT INVALID: all: machine busy (cpu 61% > 25%)"])

    def test_busy_machine_after_invalidates_a_red_run(self):
        clock = Clock()
        runner = FakeRunner(clock, host_extra=[t.violation("authority.fuzz_accepted")])
        self.assertEqual(self.go(runner, FakeSlots([5, 70])), 2)
        self.assertIn("machine busy (cpu 70%", self.result()[0])

    def test_cpu_unknown_is_not_busy(self):
        clock = Clock()
        self.assertEqual(self.go(FakeRunner(clock), FakeSlots([-1])), 0)

    def test_host_never_ready_is_invalid_and_killed(self):
        clock = Clock()
        runner = FakeRunner(clock, host_ready=False, hang=True)
        self.assertEqual(self.go(runner), 2)
        self.assertEqual(len(runner.cmds), 1)  # the client never started
        self.assertTrue(runner.procs[0].killed)
        self.assertIn("host not ready within 60s", self.result()[0])
        self.assertLess(clock.now, 70)

    def test_hang_past_deadline_kills_the_tree(self):
        clock = Clock()
        runner = FakeRunner(clock, hang=True)
        self.assertEqual(self.go(runner), 2)
        self.assertTrue(all(p.killed for p in runner.procs))
        self.assertIn("timeout after 1020s", self.result()[0])
        self.assertLess(clock.now, 1100)

    def test_triage_gate_fails_and_missing_flag_does_not(self):
        clock = Clock()
        self.assertEqual(self.go(FakeRunner(clock), triage=lambda p: (1, "gating")), 1)
        self.assertIn("log.triage_gate", self.result()[0])

    def test_triage_rc_other_than_0_or_1_is_invalid(self):
        for rc in (2, -1):
            self.lines.clear()
            self.assertEqual(self.go(FakeRunner(Clock()), triage=lambda p, rc=rc: (rc, "unrecognized arguments: --soak")), 2)
            self.assertIn("triage_log --soak failed (rc %d)" % rc, self.result()[0])

    def test_exclusive_wait_timeout_is_invalid_not_a_traceback(self):
        class Busy(FakeSlots):
            @contextlib.contextmanager
            def godot_exclusive(self, label="exclusive", wait_s=None):
                raise TimeoutError("machine held")
                yield
        runner = FakeRunner(Clock())
        self.assertEqual(self.go(runner, slots=Busy()), 2)
        self.assertEqual(runner.cmds, [])
        self.assertTrue(self.result()[0].startswith("SOAK RESULT INVALID:"))

    def test_duration_override_sets_seconds_and_deadline(self):
        clock = Clock()
        runner = FakeRunner(clock, hang=True)
        rs.main(["--idle", "--path", self.checkout, "--out", self.out, "--duration-s", "10"], runner=runner,
                slots=FakeSlots(), triage=lambda p: (0, ""), clock=clock.time, sleep=clock.sleep, say=self.lines.append, godot="godot")
        self.assertIn("--seconds=70", runner.cmds[0])
        self.assertIn("timeout after 130s", self.result()[0])

    def test_missing_config_is_invalid(self):
        os.remove(os.path.join(self.checkout, rs.CONFIG_REL))
        self.assertEqual(rs.main(["--idle", "--path", self.checkout], say=self.lines.append), 2)


if __name__ == "__main__":
    unittest.main()
