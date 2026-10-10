"""Tests for godot_slots.py (no Godot launched): python -I tools/test_godot_slots.py"""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "godot_slots.py")
sys.path.insert(0, HERE)
import godot_slots  # noqa: E402

CAP = 2
CHILDREN = 5


class SlotsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.over = {"STACKFALL_GODOT_SLOTS_DIR": self.tmp.name, "STACKFALL_GODOT_SLOTS": str(CAP)}
        self.old = {k: os.environ.get(k) for k in self.over}
        os.environ.update(self.over)
        self.env = dict(os.environ)

    def tearDown(self):
        for k, v in self.old.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    def test_cap_respected_with_concurrent_children(self):
        out = os.path.join(self.tmp.name, "spans")
        os.makedirs(out)
        code = ("import sys,time,os;t0=time.time();time.sleep(0.8);t1=time.time();"
                "open(os.path.join(sys.argv[1],str(os.getpid())),'w').write('%f %f'%(t0,t1))")
        procs = [subprocess.Popen([sys.executable, SCRIPT, "run", "--max-wait", "60", "--",
                                   sys.executable, "-c", code, out],
                                  env=self.env, stderr=subprocess.DEVNULL) for _ in range(CHILDREN)]
        for p in procs:
            self.assertEqual(p.wait(timeout=90), 0)
        spans = [tuple(float(x) for x in open(os.path.join(out, f)).read().split()) for f in os.listdir(out)]
        self.assertEqual(len(spans), CHILDREN)
        events = sorted([(a, 1) for a, _ in spans] + [(b, -1) for _, b in spans], key=lambda e: (e[0], e[1]))
        live = peak = 0
        for _, d in events:
            live += d
            peak = max(peak, live)
        self.assertLessEqual(peak, CAP)
        self.assertGreater(peak, 1)

    def test_stale_pid_reclaimed(self):
        dead = subprocess.Popen([sys.executable, "-c", "pass"])
        dead.wait()
        for i in range(CAP):
            with open(os.path.join(self.tmp.name, "slot_%d.json" % i), "w") as fh:
                json.dump({"pid": dead.pid, "label": "x", "start": time.time()}, fh)
        i = godot_slots.acquire("t", wait_s=5)
        self.assertIn(i, range(CAP))
        godot_slots.release(i)

    def test_live_pid_blocks_and_times_out(self):
        held = [godot_slots.acquire("a"), godot_slots.acquire("b")]
        with self.assertRaises(TimeoutError):
            godot_slots.acquire("c", wait_s=1)
        r = subprocess.run([sys.executable, SCRIPT, "run", "--max-wait", "1", "--", sys.executable, "-c", "pass"],
                           env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, godot_slots.TIMEOUT_EXIT)
        self.assertIn("waiting for Godot slot (2/2 busy)", r.stderr)
        for i in held:
            godot_slots.release(i)

    def test_run_propagates_exit_code_and_releases(self):
        r = subprocess.run([sys.executable, SCRIPT, "run", "--", sys.executable, "-c", "import sys;sys.exit(7)"],
                           env=self.env)
        self.assertEqual(r.returncode, 7)
        self.assertEqual(godot_slots.busy_count(), 0)

    def test_context_manager_releases(self):
        with godot_slots.godot_slot("ctx"):
            self.assertEqual(godot_slots.busy_count(), 1)
        self.assertEqual(godot_slots.busy_count(), 0)


if __name__ == "__main__":
    unittest.main()
