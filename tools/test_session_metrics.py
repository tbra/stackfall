"""Tests for tools/session_metrics.py on a temp Git repo.

Run: python tools/test_session_metrics.py
"""
import datetime
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import session_metrics as sm  # noqa: E402


def write(root, rel, text):
    path = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def git(root, *args):
    subprocess.run(["git", "-C", root, "-c", "user.name=t", "-c", "user.email=t@t"] + list(args),
                   check=True, capture_output=True)


class SessionMetricsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = self.tmp.name
        git(self.root, "init", "-q")
        write(self.root, "tools/dead_baseline.json", json.dumps({"checks": {"test-only-func": ["a.gd:f"]}, "allow": []}))
        write(self.root, "tools/magic_number_baseline.json", json.dumps({"files": {"core/A.gd": 3}}))
        write(self.root, "tests/unit/test_a.gd", "extends GutTest\nfunc test_one() -> void:\n\tpass\n")
        write(self.root, "core/A.gd", "extends RefCounted\nvar x := 1\n")
        write(self.root, "tools/layer_baseline.json", json.dumps({"closure": ["autoload/E.gd"]}))
        git(self.root, "add", "-A")
        git(self.root, "commit", "-qm", "base")
        self.rev = subprocess.run(["git", "-C", self.root, "rev-parse", "HEAD"], capture_output=True,
                                  text=True).stdout.strip()
        write(self.root, "tools/dead_baseline.json", json.dumps({
            "checks": {"test-only-func": ["a.gd:f", "b.gd:g"]},
            "allow": [{"id": "test-only-func", "entry": "c.gd:h", "reason": "AgentProbe call"}]}))
        write(self.root, "tools/magic_number_baseline.json", json.dumps({"files": {"core/A.gd": 5}}))
        write(self.root, "tests/unit/test_a.gd",
              "extends GutTest\nfunc test_one() -> void:\n\tpass\nfunc test_two() -> void:\n\tpass\n")
        write(self.root, "core/A.gd", "extends RefCounted\nvar x := 2\n")
        write(self.root, "tools/layer_baseline.json",
              json.dumps({"closure": ["autoload/E.gd", "core/A.gd", "core/B.gd"]}))
        write(self.root, "CLAUDE.md", "rules\n")
        git(self.root, "add", "-A")
        git(self.root, "commit", "-qm", "work")

    def tearDown(self):
        self.tmp.cleanup()

    def test_guard_additions_tests_areas_and_process_changes(self):
        added, new_closures = sm.guards(self.root, self.rev)
        self.assertIn("tools/dead_baseline.json: +checks|test-only-func|b.gd:g", added)
        self.assertIn("tools/dead_baseline.json: +allow|test-only-func|c.gd:h", added)
        self.assertIn("tools/magic_number_baseline.json: files|core/A.gd 3 -> 5", added)
        self.assertIn("tools/layer_baseline.json: +closure|core/A.gd", added)
        self.assertEqual(len(added), 4)
        self.assertEqual(new_closures, ["tools/layer_baseline.json: +closure|core/B.gd"])
        self.assertEqual((sm.test_count(self.root, self.rev), sm.test_count(self.root)), (1, 2))
        d = sm.delivery(self.root, self.rev)
        self.assertEqual(d["commits"], 1)
        self.assertIn("game", d["lines"])
        self.assertIn("instructions", d["lines"])
        changes = sm.process_changes(self.root, self.rev)
        self.assertEqual(len(changes), 1)
        self.assertIn("CLAUDE.md", changes[0]["files"])
        self.assertEqual(sm.changed_core(self.root, self.rev), ["core/A.gd"])

    def test_gate_lines_and_handback_log_since_the_start(self):
        start = datetime.datetime.now().astimezone() - datetime.timedelta(minutes=5)
        scratch = os.path.join(self.root, "scratch")
        write(scratch, "_orchestrator/integrate/x/05_gate.log",
              "FULL GATE RED: 10/12 passing, 2 shards, 9s, serial=0 scripts 0s; failing=['test_b'] "
              "parallel_flaky=none harness=none\n")
        write(scratch, "_orchestrator/integrate/y/05_gate.log",
              "FULL GATE GREEN: 12/12 passing, 2 shards, 9s, serial=0 scripts 0s; failing=none parallel_flaky=none\n")
        gates = sm.gates(scratch, start)
        self.assertEqual(sorted(g["verdict"] for g in gates), ["GREEN", "RED"])
        self.assertEqual([g["failing"] for g in gates if g["verdict"] == "RED"], ["['test_b']"])
        now = datetime.datetime.now().isoformat(timespec="seconds")
        old = (datetime.datetime.now() - datetime.timedelta(days=2)).isoformat(timespec="seconds")
        rows = [{"ts": old, "accepted": True, "verdict": "done", "finding": ""},
                {"ts": now, "accepted": False, "verdict": "", "finding": ""},
                {"ts": now, "accepted": True, "verdict": "done", "finding": ""},
                {"ts": now, "accepted": True, "verdict": "review", "finding": "CHANGES: HIGH x"},
                {"ts": now, "accepted": True, "verdict": "review", "finding": "APPROVE"}]
        write(scratch, "_orchestrator/handbacks.jsonl", "".join(json.dumps(r) + "\n" for r in rows))
        h = sm.handbacks(os.path.join(scratch, "_orchestrator", "handbacks.jsonl"), start)
        self.assertEqual((h["attempts"], h["denied"], h["review_approve"], h["review_changes"]), (4, 1, 1, 1))
        self.assertEqual(h["verdicts"], {"done": 1, "review": 2})


    def test_since_time_accepts_a_trailing_z(self):
        utc = datetime.timezone.utc
        self.assertEqual(sm.parse_since("2026-10-20T20:59:55Z"), datetime.datetime(2026, 10, 20, 20, 59, 55, tzinfo=utc))
        self.assertEqual(sm.parse_since("2026-10-20T22:59:55+02:00"),
                         datetime.datetime(2026, 10, 20, 20, 59, 55, tzinfo=utc))

if __name__ == "__main__":
    unittest.main()
