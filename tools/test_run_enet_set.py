"""Tests for tools/run_enet_set.py: harness process counts and slot/exclusive capacity. Nothing
here launches Godot or a harness.
Run: python tools/test_run_enet_set.py
"""
import contextlib
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import run_enet_set as res  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class FakeSlots:
    """godot_slots stand-in recording how capacity was taken."""

    def __init__(self, cap):
        self._cap = cap
        self.events = []
        self.held = 0
        self.fail_on_slot = None

    def cap(self):
        return self._cap

    @contextlib.contextmanager
    def godot_slot(self, label="godot", wait_s=None):
        if self.fail_on_slot is not None and self.held == self.fail_on_slot:
            raise TimeoutError("no slot")
        self.held += 1
        self.events.append(("slot", label))
        try:
            yield self.held
        finally:
            self.held -= 1

    @contextlib.contextmanager
    def godot_exclusive(self, label="exclusive", wait_s=None):
        self.events.append(("exclusive", label, wait_s))
        yield


def write_runner(text):
    d = tempfile.mkdtemp()
    p = os.path.join(d, "run_x_enet.ps1")
    with open(p, "w", encoding="utf-8") as fh:
        fh.write(text)
    return p


class ProcessCountTest(unittest.TestCase):
    def test_header_line_is_parsed(self):
        self.assertEqual(res.process_count(write_runner("# ENET-PROCESSES: 4  (host + three clients)\nparam()\n")), 4)
        self.assertEqual(res.process_count(write_runner("# note\n#ENET-PROCESSES:3\n")), 3)

    def test_missing_zero_or_unreadable_is_none(self):
        self.assertIsNone(res.process_count(write_runner("param()\n")))
        self.assertIsNone(res.process_count(write_runner("# ENET-PROCESSES: 0\n")))
        self.assertIsNone(res.process_count(write_runner("# ENET-PROCESSES: many\n")))
        self.assertIsNone(res.process_count(os.path.join(tempfile.gettempdir(), "no_such_runner_enet.ps1")))

    def test_every_runner_declares_its_process_count(self):
        runners = res.discover(REPO)
        self.assertTrue(runners, "no tools/run_*_enet.ps1 found")
        missing = [n for n, p in runners if res.process_count(p) is None]
        self.assertEqual(missing, [], "runners without `# ENET-PROCESSES: <n>`: %s" % missing)

    def test_declared_count_is_at_least_host_plus_client(self):
        for name, path in res.discover(REPO):
            self.assertGreaterEqual(res.process_count(path) or 0, 2, name)

    def test_known_multi_peer_harnesses(self):
        counts = {n: res.process_count(p) for n, p in res.discover(REPO)}
        self.assertEqual(counts["gift_fx"], 4)
        self.assertEqual(counts["glue_fuse"], 3)
        self.assertEqual(counts["qol"], 2)


class HoldCapacityTest(unittest.TestCase):
    def test_within_cap_takes_one_slot_per_process(self):
        slots = FakeSlots(cap=3)
        with res.hold_capacity("glue_fuse", 3, slots=slots):
            self.assertEqual(slots.held, 3)
        self.assertEqual(slots.held, 0)
        self.assertEqual([e[0] for e in slots.events], ["slot"] * 3)

    def test_over_cap_runs_exclusive_not_partial_slots(self):
        slots = FakeSlots(cap=3)
        with res.hold_capacity("gift_fx", 4, slots=slots):
            self.assertEqual(slots.held, 0)
        self.assertEqual([e[0] for e in slots.events], ["exclusive"])
        self.assertEqual(slots.events[0][2], res.EXCLUSIVE_WAIT_S)

    def test_cap_of_one_makes_a_pair_exclusive(self):
        slots = FakeSlots(cap=1)
        with res.hold_capacity("qol", 2, slots=slots):
            pass
        self.assertEqual([e[0] for e in slots.events], ["exclusive"])

    def test_timeout_on_later_slot_releases_earlier_ones(self):
        slots = FakeSlots(cap=3)
        slots.fail_on_slot = 2
        with self.assertRaises(TimeoutError):
            res.hold_capacity("glue_fuse", 3, slots=slots)
        self.assertEqual(slots.held, 0)


class RunOneTest(unittest.TestCase):
    def test_runner_without_declaration_fails_without_launching(self):
        runner = write_runner("param()\n")
        out = os.path.join(os.path.dirname(runner), "out")
        verdict, detail, secs, _ = res.run_one("x", runner, os.path.dirname(runner), out, 5)
        self.assertEqual(verdict, "FAIL")
        self.assertIn("ENET-PROCESSES", detail)
        self.assertEqual(secs, 0.0)


if __name__ == "__main__":
    unittest.main()
