"""Sharded full GUT gate (the full suite was too slow and
blocked progress).

Splits every tests/**/test_*.gd script across N headless Godot processes that
run in parallel, merges the totals, then re-runs any failing script alone once.
A script that fails in parallel but passes alone is reported as
PARALLEL-FLAKY (shared user:// state or timing) and does not fail the gate;
a script that fails both times does.

Run it in the background from Claude (Bash run_in_background) and keep
working; the last line is the verdict:
  python tools/full_gate.py                      # main checkout, auto shards
  python tools/full_gate.py --path <checkout> --shards 4
Exit status: 0 green, 1 failures, 2 harness error. Logs and result.json go to
--out (default: <checkout>/tests/.gut_targeted/gate_<time>/).
Watchers (a status pane) read live progress from one JSON file per run in a machine-wide
folder: <tools root>/scratch/full_gate/<time>_<pid>.json (env STACKFALL_GATE_PROGRESS_DIR).
It holds the phase, shards, tests run/passed/failed so far and, at the end, the verdict line and
`not_run`: every pending or risky (no asserts) test by name, which the totals only count.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_exe as godot_exe_mod  # noqa: E402
import godot_slots  # noqa: E402
import repo_paths  # noqa: E402
import lint_magic_numbers  # noqa: E402
import lint_single_source  # noqa: E402
import lint_layers  # noqa: E402
import lint_ui_components  # noqa: E402
import lint_dead  # noqa: E402
import lint_instructions  # noqa: E402
import lint_public  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMINGS = os.path.join(ROOT, "tests", ".gut_targeted", "gate_timings.json")
# GUT prints one "Risky/Pending" total.
TOTAL_RE = re.compile(r"^(Scripts|Tests|Passing Tests|Failing Tests|Risky/Pending|Pending|Risky)\s+(\d+)", re.M)
SCRIPT_RE = re.compile(r"^(?:\x1b\[[0-9;]*m)*(res://tests/\S+\.gd)", re.M)
FAILED_RE = re.compile(r"\[Failed\]")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
TEST_RE = re.compile(r"^\*\s*test_\w+")
# failure evidence kept per failing script in result.json.
DETAIL_LINES_AFTER = 3
DETAIL_MAX_LINES = 8
DETAIL_MAX_CHARS = 400
DEFAULT_TIMEOUT_S = 1200
# GUT drops a test script it cannot load and its totals simply omit it, so the
# gate cross-checks every scheduled script against the per-script result headers and these lines.
LOAD_FAIL_RE = re.compile(r'Failed to load script "(res://tests/\S+?\.gd)" with error "([^"]*)"')
IGNORED_RE = re.compile(r"Ignoring script (res://tests/\S+?\.gd) because")
MISSING_ERROR = "no results in GUT output (script dropped, load error or shard died)"
SUMMARY_RE = re.compile(r"=\s*Run Summary")
# JUnit testcase statuses that reached a verdict; any other (pending, "no asserts") did not.
JUNIT_RAN = ("pass", "fail")
PROGRESS_ENV = "STACKFALL_GATE_PROGRESS_DIR"
PROGRESS_KEEP = 20
PROGRESS_EVERY_S = 2.0


# --fixed-fps disables wall-clock pacing, so physics ticks
# (one per frame at 60) run as fast as the CPU allows instead of 60 Hz real time.
FIXED_FPS = "60"


def run_lint(path, name, fallback_module):
    """Run the candidate tree's own lint (its rules and reviewed allowances travel with the
    change; a branch that moved an allowance was judged by main's stale copy).
    Falls back to this checkout's module when the candidate has no such script."""
    script = os.path.join(path, "tools", name + ".py")
    if not os.path.isfile(script):
        return fallback_module.main(["--path", path])
    proc = subprocess.run([sys.executable, script, "--path", path], timeout=DEFAULT_TIMEOUT_S)
    return proc.returncode


def godot_exe():
    return godot_exe_mod.resolve()  # real .exe behind PATH shims


def collect(path):
    tests = []
    base = os.path.join(path, "tests")
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        for name in filenames:
            if name.startswith("test_") and name.endswith(".gd"):
                rel = os.path.relpath(os.path.join(dirpath, name), path).replace("\\", "/")
                tests.append("res://" + rel)
    return sorted(tests)


def weight(path, res_path, timings):
    if res_path in timings:
        return timings[res_path]
    try:
        with open(os.path.join(path, res_path[len("res://"):]), encoding="utf-8", errors="replace") as fh:
            return 1.0 + 0.5 * len(re.findall(r"^func test_", fh.read(), re.M))
    except OSError:
        return 1.0


SERIAL_LIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "full_gate_serial.txt")


def load_serial_list(list_path, tests):
    """Heavy scripts to run alone after the shards; entries not in `tests` are skipped."""
    try:
        with open(list_path, encoding="utf-8") as fh:
            lines = [l.split("#")[0].strip() for l in fh]
    except OSError:
        return []
    known = set(tests)
    return [l for l in dict.fromkeys(lines) if l in known]


def make_shards(path, tests, count, timings):
    shards = [[] for _ in range(count)]
    loads = [0.0] * count
    for res_path in sorted(tests, key=lambda t: -weight(path, t, timings)):
        i = loads.index(min(loads))
        shards[i].append(res_path)
        loads[i] += weight(path, res_path, timings)
    return [s for s in shards if s]


def write_config(out_dir, name, tests):
    cfg = {"dirs": [], "tests": tests, "log_level": 1, "should_exit": True,
           "should_exit_on_success": True, "prefix": "test_", "suffix": ".gd",
           "pre_run_script": "res://tests/support/jolt_overflow_hook.gd",
           "junit_xml_file": os.path.join(out_dir, name + ".xml").replace("\\", "/")}
    cfg_path = os.path.join(out_dir, name + ".json")
    with open(cfg_path, "w", encoding="ascii") as fh:
        json.dump(cfg, fh)
    return cfg_path


def res_of(path, file_path):
    return "res://" + os.path.relpath(file_path, path).replace("\\", "/")


def start(path, out_dir, name, tests):
    cfg = write_config(out_dir, name, tests)
    log_path = os.path.join(out_dir, name + ".log")
    log = open(log_path, "w", encoding="utf-8", errors="replace")
    proc = subprocess.Popen(
        [godot_exe(), "--headless", "--log-file", os.path.join(out_dir, name + ".godot.log"), "--fixed-fps", FIXED_FPS, "--path", path, "-s", "addons/gut/gut_cmdln.gd",
         "-gconfig=" + res_of(path, cfg), "-gexit"],
        cwd=path, stdout=log, stderr=subprocess.STDOUT)
    return proc, log, log_path


def parse(log_path):
    totals, failing, _detail = parse_detail(log_path)
    return totals, failing


def parse_detail(log_path):
    """Totals, failing scripts and, per failing script, the failing test name plus the
    [Failed] line and the assertion lines after it (the shard log is
    deleted with the temp integrate worktree, so result.json must keep the evidence)."""
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    totals = {k: int(v) for k, v in TOTAL_RE.findall(text)}
    failing = set()
    detail = {}
    current = None
    current_test = ""
    lines = text.splitlines()
    for i, line in enumerate(lines):
        m = SCRIPT_RE.match(line)
        if m:
            current = m.group(1)
            current_test = ""
            continue
        plain = ANSI_RE.sub("", line).strip()
        if TEST_RE.match(plain):
            current_test = plain
        elif current and FAILED_RE.search(line):
            failing.add(current)
            kept = detail.setdefault(current, [])
            if len(kept) < DETAIL_MAX_LINES:
                after = []
                for x in lines[i + 1:i + 1 + DETAIL_LINES_AFTER]:
                    x_plain = ANSI_RE.sub("", x).strip()
                    if SCRIPT_RE.match(x) or TEST_RE.match(x_plain) or FAILED_RE.search(x):
                        break
                    after.append(x_plain)
                entry = " | ".join([current_test, plain] + [x for x in after if x])
                kept.append(entry[:DETAIL_MAX_CHARS])
    return totals, failing, detail


def find_unloadable(scheduled, log_path):
    """Scheduled scripts GUT dropped: [{script, error}]. The error text is the
    parse/load lines naming the script when GUT logged any, else MISSING_ERROR."""
    try:
        with open(log_path, encoding="utf-8", errors="replace") as fh:
            text = ANSI_RE.sub("", fh.read())
    except OSError:
        text = ""
    seen = set(SCRIPT_RE.findall(text))
    errors = {}
    for script, why in LOAD_FAIL_RE.findall(text):
        errors.setdefault(script, []).append('Failed to load: "%s"' % why)
    for script in IGNORED_RE.findall(text):
        errors.setdefault(script, []).append("ignored by GUT (not loadable as a GutTest)")
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.startswith("SCRIPT ERROR:") and i + 1 < len(lines):
            for script in errors:
                if "(%s:" % script in lines[i + 1]:
                    errors[script].insert(0, line[len("SCRIPT ERROR:"):].strip())
    out = []
    for script in scheduled:
        if script in errors:
            out.append({"script": script, "error": " | ".join(dict.fromkeys(errors[script]))[:DETAIL_MAX_CHARS]})
        elif script not in seen:
            out.append({"script": script, "error": MISSING_ERROR})
    return out


def junit_not_run(out_dir, name):
    """Tests GUT counted that neither passed nor failed (pending, risky "no asserts"), named, from
    the shard's JUnit export: [{script, test, status, reason}]. The totals only count them."""
    try:
        root = ET.parse(os.path.join(out_dir, name + ".xml")).getroot()
    except (OSError, ET.ParseError):
        return []
    out = []
    for case in root.iter("testcase"):
        status = case.get("status") or ""
        if status in JUNIT_RAN:
            continue
        skipped = case.find("skipped")
        reason = (skipped.text or "").strip() if skipped is not None else ""
        script = case.get("classname") or ""
        out.append({"script": script if script.startswith("res://") else "res://" + script.lstrip("/"),
                    "test": case.get("name") or "", "status": status, "reason": reason[:DETAIL_MAX_CHARS]})
    return out


def progress_dir():
    return os.environ.get(PROGRESS_ENV) or os.path.join(repo_paths.scratch_root(), "full_gate")


class LiveCounts(object):
    """Tests started and failed so far in a shard log that is still being written, read on from
    where the last call stopped."""

    def __init__(self, log_path):
        self.log_path = log_path
        self.offset = 0
        self.rest = ""
        self.script = ""
        self.current = ""
        self.started = 0
        self.failed = set()
        self.in_summary = False

    def read(self):
        if self.in_summary:
            return
        try:
            with open(self.log_path, "rb") as fh:
                fh.seek(self.offset)
                data = fh.read()
        except OSError:
            return
        self.offset += len(data)
        lines = (self.rest + data.decode("utf-8", "replace")).split("\n")
        self.rest = lines.pop()
        for line in lines:
            m = SCRIPT_RE.match(line)
            if m:
                self.script = m.group(1)
                continue
            plain = ANSI_RE.sub("", line).strip()
            if SUMMARY_RE.search(plain):
                # The summary repeats the failures, which were counted as they ran.
                self.in_summary = True
                return
            if TEST_RE.match(plain):
                self.started += 1
                self.current = self.script + " " + plain
            elif self.current and FAILED_RE.search(line):
                self.failed.add(self.current)


class Progress(object):
    """The run's live state as one JSON file a watcher polls, replaced whole on each write.
    Writing never fails the gate: an unwritable folder just leaves no progress file."""

    def __init__(self, path, out_dir, directory=None, now=time.time):
        self.now = now
        self.dir = directory or progress_dir()
        self.file = os.path.join(self.dir, "%s_%d.json" % (time.strftime("%Y%m%d_%H%M%S"), os.getpid()))
        self.counts = {}
        self.finished = set()
        self.last = 0.0
        self.data = {"schema": 1, "pid": os.getpid(), "path": path, "out": out_dir, "started": now(),
                     "updated": now(), "phase": "lint", "shards": 0, "expected": 0, "run": 0, "passed": 0,
                     "failed": 0, "shard_state": {}}
        try:
            os.makedirs(self.dir, exist_ok=True)
            old = sorted(n for n in os.listdir(self.dir) if n.endswith(".json"))
            for n in old[:max(0, len(old) - (PROGRESS_KEEP - 1))]:
                os.remove(os.path.join(self.dir, n))
        except OSError:
            pass
        self.write()

    def update(self, **fields):
        self.data.update(fields)
        self.write()

    def shard(self, name, state, log_path=None):
        if log_path:
            self.counts[name] = LiveCounts(log_path)
        if state != "running":
            self.finished.add(name)
        self.data["shard_state"][name] = state
        self.tick(force=True)

    def tick(self, force=False):
        if not force and self.now() - self.last < PROGRESS_EVERY_S:
            return
        run = passed = failed = 0
        for name, c in self.counts.items():
            c.read()
            # A running shard's newest test has started but not finished.
            done = c.started if name in self.finished else max(0, c.started - 1)
            run += done
            failed += len(c.failed)
            passed += max(0, done - len(c.failed))
        self.update(run=run, passed=passed, failed=failed)

    def write(self):
        self.last = self.now()
        self.data["updated"] = self.last
        tmp = self.file + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(self.data, fh)
            os.replace(tmp, self.file)
        except OSError:
            pass


def expected_tests(path, tests):
    """`func test_` count over the scheduled scripts: what a full run should reach."""
    n = 0
    for res_path in tests:
        try:
            with open(os.path.join(path, res_path[len("res://"):]), encoding="utf-8", errors="replace") as fh:
                n += len(re.findall(r"^func test_", fh.read(), re.M))
        except OSError:
            pass
    return n


def suite_times(out_dir, name):
    """Per-script seconds from GUT's JUnit export (testsuite name = res path)."""
    times = {}
    try:
        root = ET.parse(os.path.join(out_dir, name + ".xml")).getroot()
    except (OSError, ET.ParseError):
        return times
    for suite in root.iter("testsuite"):
        try:
            name_attr = suite.get("name") or ""
            key = name_attr if name_attr.startswith("res://") else "res://" + name_attr.lstrip("/")
            times[key] = float(suite.get("time") or 0.0)
        except ValueError:
            pass
    return times


def _details_for(scripts, *result_maps):
    """Failure lines per script from the given run_batch results (shards first, then retries)."""
    out = {}
    for t in scripts:
        lines = []
        for results_map in result_maps:
            for r in results_map.values():
                lines.extend(r.get("failing_detail", {}).get(t, []))
        out[t] = lines[:DETAIL_MAX_LINES]
    return out


def _kill_tree(proc):
    """Kill a launched process and all of its descendants."""
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True, check=False)
    proc.kill()


def run_batch(path, out_dir, batches, timeout_s, progress=None):
    # Each shard takes a machine-wide Godot slot (tools/godot_slots.py); shards beyond the free
    # slots wait here and their timeout clock starts when they launch.
    pending = list(batches)
    procs = {}
    slots = {}
    t_start = {}
    finished = {}
    announced = False
    total = len(batches)
    if progress:
        for name, _tests in batches:
            progress.data["shard_state"][name] = "waiting"
    while len(finished) < total:
        while pending:
            slot = godot_slots.try_acquire("full_gate:" + pending[0][0])
            if slot is None:
                if not announced:
                    print("waiting for Godot slot (%d/%d busy)" % (godot_slots.busy_count(), godot_slots.cap()), flush=True)
                    announced = True
                break
            name, tests = pending.pop(0)
            procs[name] = start(path, out_dir, name, tests)
            slots[name] = slot
            t_start[name] = time.time()
            if progress:
                progress.shard(name, "running", procs[name][2])
        for name, (proc, log, log_path) in procs.items():
            if name in finished:
                continue
            code = proc.poll()
            if code is None and time.time() - t_start[name] > timeout_s:
                # the console Godot wrapper spawns the real Godot as a child;
                # proc.kill() only ended the wrapper and left a hung shard running.
                _kill_tree(proc)
                code = "timeout"
            if code is not None:
                finished[name] = (code, round(time.time() - t_start[name], 1))
                godot_slots.release(slots[name])
                if progress:
                    progress.shard(name, "timeout" if code == "timeout" else "done")
        if progress:
            progress.tick()
        time.sleep(0.5)
    results = {}
    for name, (proc, log, log_path) in procs.items():
        log.close()
        totals, failing, detail = parse_detail(log_path)
        code, seconds = finished[name]
        results[name] = {"exit": code, "totals": totals, "failing": sorted(failing), "failing_detail": detail,
                         "log": log_path, "seconds": seconds}
    return results


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=ROOT)
    ap.add_argument("--shards", type=int, default=0, help="parallel Godot processes (0 = auto)")
    ap.add_argument("--out", default="")
    ap.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S)
    args = ap.parse_args(argv)
    path = os.path.abspath(args.path)
    count = args.shards or max(2, min(6, (os.cpu_count() or 4) // 2))
    stamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.out or os.path.join(path, "tests", ".gut_targeted", "gate_" + stamp)
    os.makedirs(out_dir, exist_ok=True)
    try:
        with open(TIMINGS, encoding="utf-8") as fh:
            timings = json.load(fh)
    except (OSError, ValueError):
        timings = {}
    progress = Progress(path, out_dir)

    # Magic-number ratchet: <2 s, runs before the shards.
    lint_code = run_lint(path, "lint_magic_numbers", lint_magic_numbers)
    print("MAGIC LINT %s" % ("GREEN" if lint_code == 0 else "RED"), flush=True)
    # Single-source ratchet: same cost, same position.
    ss_code = run_lint(path, "lint_single_source", lint_single_source)
    print("SINGLE-SOURCE LINT %s" % ("GREEN" if ss_code == 0 else "RED"), flush=True)

    # Layer / SCC / autoload-closure ratchet (S4b): ~10 s, no Godot.
    layer_code = run_lint(path, "lint_layers", lint_layers)
    print("LAYER LINT %s" % ("GREEN" if layer_code == 0 else "RED"), flush=True)

    # UI component ratchet: same cost, no Godot.
    ui_code = run_lint(path, "lint_ui_components", lint_ui_components)
    print("UI COMPONENT LINT %s" % ("GREEN" if ui_code == 0 else "RED"), flush=True)

    # Dead-weight guard: dep_graph based, ~15 s, no Godot.
    dead_code = run_lint(path, "lint_dead", lint_dead)
    print("DEAD LINT %s" % ("GREEN" if dead_code == 0 else "RED"), flush=True)

    # Instruction drift guard: each agent rule has one home file; no Godot.
    instr_code = run_lint(path, "lint_instructions", lint_instructions)
    print("INSTRUCTIONS LINT %s" % ("GREEN" if instr_code == 0 else "RED"), flush=True)
    public_code = run_lint(path, "lint_public", lint_public)
    print("PUBLIC LINT %s" % ("GREEN" if public_code == 0 else "RED"), flush=True)

    tests = collect(path)
    if not tests:
        print("FULL GATE ERROR: no tests found under", path)
        progress.update(phase="done", verdict="ERROR", summary="FULL GATE ERROR: no tests found")
        return 2
    t0 = time.time()
    serial = load_serial_list(SERIAL_LIST, tests)
    shards = make_shards(path, [t for t in tests if t not in serial], count, timings)
    progress.update(phase="shards", started=t0, shards=len(shards), serial_scripts=len(serial),
                    expected=expected_tests(path, tests))
    results = run_batch(path, out_dir, [("shard%d" % i, s) for i, s in enumerate(shards)], args.timeout, progress) if shards else {}
    serial_seconds = 0.0
    if serial:
        # One process, nothing else running: the heavy scripts get the whole CPU.
        progress.update(phase="serial")
        results.update(run_batch(path, out_dir, [("serial", serial)], args.timeout, progress))
        serial_seconds = results["serial"]["seconds"]
    by_name = {"shard%d" % i: s for i, s in enumerate(shards)}
    if serial:
        by_name["serial"] = serial
    sums = {}
    failing = set()
    harness = []
    unloadable = []
    for name, r in results.items():
        bad = find_unloadable(by_name[name], r["log"])
        unloadable.extend(bad)
        for k, v in r["totals"].items():
            sums[k] = sums.get(k, 0) + v
        failing.update(r["failing"])
        if "Tests" not in r["totals"]:
            harness.append("%s exit=%s (no Totals; see %s)" % (name, r["exit"], r["log"]))
    if unloadable:
        harness.append("unloadable test scripts: " + "; ".join("%s (%s)" % (u["script"], u["error"]) for u in unloadable))
    # Per-script durations (JUnit) balance the next run; fall back to the
    # shard average for scripts the export missed.
    for name, r in sorted(results.items()):
        shard = by_name[name]
        measured = suite_times(out_dir, name)
        per = r["seconds"] / max(1, len(shard))
        for t in shard:
            if t in measured:
                timings[t] = round(measured[t], 2)
            else:
                timings[t] = round(0.5 * timings.get(t, per) + 0.5 * per, 2)
        r["shard_seconds"] = r["seconds"]
    os.makedirs(os.path.dirname(TIMINGS), exist_ok=True)
    with open(TIMINGS, "w", encoding="utf-8") as fh:
        json.dump(timings, fh)

    confirmed, flaky = [], []
    retry_results = {}
    if failing:
        progress.update(phase="retry", retrying=sorted(failing))
        retry = retry_results = run_batch(path, out_dir, [("retry_%d" % i, [t]) for i, t in enumerate(sorted(failing))], args.timeout)
        for (name, r), t in zip(sorted(retry.items(), key=lambda kv: int(kv[0].split("_")[1])), sorted(failing)):
            # GUT omits the "Failing Tests" line when everything passed.
            ok = "Tests" in r["totals"] and r["totals"].get("Failing Tests", 0) == 0 and not r["failing"]
            (flaky if ok else confirmed).append(t)

    verdict = "GREEN" if not confirmed and not harness and lint_code == 0 and ss_code == 0 and layer_code == 0 and ui_code == 0 and dead_code == 0 and instr_code == 0 and public_code == 0 else "RED"
    result = {"verdict": verdict, "path": path, "shards": len(shards), "serial": serial, "serial_seconds": serial_seconds, "seconds": round(time.time() - t0, 1),
              "totals": sums, "failing": confirmed, "parallel_flaky": flaky, "failing_detail": _details_for(confirmed, results, retry_results), "flaky_detail": _details_for(flaky, results), "harness_errors": harness, "unloadable": unloadable, "magic_lint": "green" if lint_code == 0 else "red",
              "single_source_lint": "green" if ss_code == 0 else "red",
              "layer_lint": "green" if layer_code == 0 else "red",
              "ui_component_lint": "green" if ui_code == 0 else "red",
              "dead_lint": "green" if dead_code == 0 else "red",
              "instructions_lint": "green" if instr_code == 0 else "red",
              "public_lint": "green" if public_code == 0 else "red",
              "shard_seconds": {n: r["seconds"] for n, r in sorted(results.items())}, "out": out_dir,
              "not_run": [t for n in sorted(results) for t in junit_not_run(out_dir, n)]}
    with open(os.path.join(out_dir, "result.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=1)
    sys.stdout.flush()
    line = ("FULL GATE %s: %s/%s passing, %d shards, %.0fs, serial=%d scripts %.0fs; failing=%s parallel_flaky=%s harness=%s magic_lint=%s single_source_lint=%s layer_lint=%s ui_component_lint=%s dead_lint=%s instructions_lint=%s public_lint=%s; out=%s" % (
        verdict, sums.get("Passing Tests", 0), sums.get("Tests", 0), result["shards"], result["seconds"], len(serial), serial_seconds,
        confirmed or "none", flaky or "none", harness or "none", "green" if lint_code == 0 else "RED", "green" if ss_code == 0 else "RED", "green" if layer_code == 0 else "RED", "green" if ui_code == 0 else "RED", "green" if dead_code == 0 else "RED", "green" if instr_code == 0 else "RED", "green" if public_code == 0 else "RED", out_dir))
    print(line, flush=True)
    progress.update(phase="done", verdict=verdict, summary=line, seconds=result["seconds"], totals=sums,
                    failing=confirmed, parallel_flaky=flaky, harness=harness, not_run=result["not_run"])
    if harness:
        return 2
    return 0 if verdict == "GREEN" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
