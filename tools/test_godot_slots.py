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
        self.over = {"STACKFALL_GODOT_SLOTS_DIR": self.tmp.name, "STACKFALL_GODOT_SLOTS": str(CAP), "STACKFALL_GODOT_SLOTS_EXTERNAL": "0"}
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


class ExclusiveTest(unittest.TestCase):
    setUp = SlotsTest.setUp
    tearDown = SlotsTest.tearDown

    def _sleeper(self):
        p = subprocess.Popen([sys.executable, "-c", "import time;time.sleep(60)"])
        self.addCleanup(lambda: (p.kill(), p.wait()))
        return p

    def test_exclusive_waits_for_holder_then_runs(self):
        held = godot_slots.acquire("a")
        with self.assertRaises(TimeoutError) as cm:
            godot_slots.acquire_exclusive("x", wait_s=1)
        self.assertIn("holders still running", str(cm.exception))
        self.assertFalse(os.path.exists(godot_slots._gate_path(self.tmp.name)))  # gate dropped on timeout
        godot_slots.release(held)
        godot_slots.acquire_exclusive("x", wait_s=5)
        self.assertIn("RUNNING", godot_slots.status()[0])
        godot_slots.release_exclusive()
        self.assertIn("none", godot_slots.status()[0])

    def test_normal_acquirer_queues_behind_waiting_exclusive(self):
        holder = self._sleeper()
        ex = self._sleeper()
        i = godot_slots.acquire("a", pid=holder.pid)  # a live holder keeps the exclusive waiting
        self.assertTrue(godot_slots._take_gate(self.tmp.name, ex.pid, "x"))
        self.assertIn("WAITING", godot_slots.status()[0])
        self.assertIsNone(godot_slots.try_acquire("late"))  # free slot exists, yet blocked
        with self.assertRaises(TimeoutError):
            godot_slots.acquire("late", wait_s=1)
        godot_slots.release(i)
        godot_slots.release_exclusive(ex.pid)
        j = godot_slots.acquire("late", wait_s=5)  # released: queued acquirer proceeds
        godot_slots.release(j)

    def test_stale_gate_from_dead_pid_reclaimed(self):
        dead = subprocess.Popen([sys.executable, "-c", "pass"])
        dead.wait()
        with open(godot_slots._gate_path(self.tmp.name), "w") as fh:
            json.dump({"pid": dead.pid, "state": "running", "start": time.time()}, fh)
        j = godot_slots.acquire("a", wait_s=3)  # stale gate must not block
        godot_slots.release(j)
        godot_slots.acquire_exclusive("x", wait_s=3)
        godot_slots.release_exclusive()

    def test_stale_holder_does_not_block_exclusive(self):
        dead = subprocess.Popen([sys.executable, "-c", "pass"])
        dead.wait()
        with open(os.path.join(self.tmp.name, "slot_0.json"), "w") as fh:
            json.dump({"pid": dead.pid, "label": "x", "start": time.time()}, fh)
        godot_slots.acquire_exclusive("x", wait_s=3)
        godot_slots.release_exclusive()

    def test_second_exclusive_times_out_with_clear_error(self):
        holder = self._sleeper()
        godot_slots.acquire_exclusive("first", pid=holder.pid, wait_s=3)
        os.environ.pop(godot_slots.OWNER_ENV)  # act as an unrelated process
        with self.assertRaises(TimeoutError) as cm:
            godot_slots.acquire_exclusive("second", wait_s=1)
        self.assertIn("another exclusive run has the gate", str(cm.exception))
        godot_slots.release_exclusive(holder.pid)

    def test_cli_exclusive_run_alone_and_timeout_exit(self):
        r = subprocess.run([sys.executable, SCRIPT, "run", "--exclusive", "--wait-timeout", "5", "--",
                            sys.executable, "-c", "print('ok')"], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, 0)
        self.assertIn("ok", r.stdout)
        self.assertFalse(os.path.exists(godot_slots._gate_path(self.tmp.name)))
        held = godot_slots.acquire("a")
        r = subprocess.run([sys.executable, SCRIPT, "run", "--exclusive", "--wait-timeout", "1", "--",
                            sys.executable, "-c", "pass"], env=self.env, capture_output=True, text=True)
        self.assertEqual(r.returncode, godot_slots.TIMEOUT_EXIT)
        self.assertIn("could not run exclusively", r.stderr)
        godot_slots.release(held)

    def test_nested_acquires_under_exclusive_are_reentrant(self):
        with godot_slots.godot_exclusive("outer", wait_s=3):
            self.assertEqual(godot_slots.acquire("inner", wait_s=1), godot_slots.REENTRANT)
            godot_slots.release(godot_slots.REENTRANT)
            self.assertFalse(godot_slots.acquire_exclusive("inner2", wait_s=1))
            with godot_slots.godot_exclusive("inner3", wait_s=1):
                pass
            self.assertIn("RUNNING", godot_slots.status()[0])  # inner exits did not drop the gate
            self.assertEqual(godot_slots.busy_count(), 0)
        self.assertIn("none", godot_slots.status()[0])
        self.assertNotIn(godot_slots.OWNER_ENV, os.environ)

    def test_nested_child_process_inherits_marker_unrelated_blocks(self):
        code = "import sys;sys.path.insert(0,sys.argv[1]);import godot_slots as g;print(g.acquire('c',wait_s=1))"
        with godot_slots.godot_exclusive("outer", wait_s=3):
            r = subprocess.run([sys.executable, "-c", code, HERE], env=dict(os.environ), capture_output=True, text=True)
            self.assertEqual(r.stdout.strip(), "-1", r.stderr)
            env = dict(os.environ)
            env.pop(godot_slots.OWNER_ENV)  # unrelated process: no marker
            r = subprocess.run([sys.executable, "-c", code, HERE], env=env, capture_output=True, text=True)
            self.assertIn("TimeoutError", r.stderr)

    def test_stale_marker_ignored(self):
        os.environ[godot_slots.OWNER_ENV] = "deadbeef"
        self.addCleanup(os.environ.pop, godot_slots.OWNER_ENV, None)
        i = godot_slots.acquire("a", wait_s=2)  # no gate: marker ignored, real slot
        self.assertNotEqual(i, godot_slots.REENTRANT)
        godot_slots.release(i)
        dead = subprocess.Popen([sys.executable, "-c", "pass"])
        dead.wait()
        with open(godot_slots._gate_path(self.tmp.name), "w") as fh:
            json.dump({"pid": dead.pid, "token": "deadbeef", "state": "running", "start": time.time()}, fh)
        i = godot_slots.acquire("b", wait_s=2)  # dead holder's token: ignored too
        self.assertNotEqual(i, godot_slots.REENTRANT)
        godot_slots.release(i)


if __name__ == "__main__":
    unittest.main()
