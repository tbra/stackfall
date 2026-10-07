"""Sharded full GUT gate (owner 2026-10-02: the full suite was too slow and
blocked progress).

Splits every tests/**/test_*.gd script across N headless Godot processes that
run in parallel, merges the totals, then re-runs any failing script alone once.
A script that fails in parallel but passes alone is reported as
PARALLEL-FLAKY (shared user:// state or timing) and does not fail the gate;
a script that fails both times does.

Run it in the background from Claude (Bash run_in_background) and keep
working; the last line is the verdict:
  python tools/full_gate.py                      # main checkout, auto shards
  python tools/full_gate.py --path M:/Bontago-worktrees/x --shards 4
Exit status: 0 green, 1 failures, 2 harness error. Logs and result.json go to
--out (default: <checkout>/tests/.gut_targeted/gate_<time>/).
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
import lint_magic_numbers  # noqa: E402
import lint_single_source  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TIMINGS = os.path.join(ROOT, "tests", ".gut_targeted", "gate_timings.json")
TOTAL_RE = re.compile(r"^(Scripts|Tests|Passing Tests|Failing Tests|Pending|Risky)\s+(\d+)", re.M)
SCRIPT_RE = re.compile(r"^(?:\x1b\[[0-9;]*m)*(res://tests/\S+\.gd)", re.M)
FAILED_RE = re.compile(r"\[Failed\]")
DEFAULT_TIMEOUT_S = 1200


# Bontago-fca.38.7: --fixed-fps disables wall-clock pacing, so physics ticks
# (one per frame at 60) run as fast as the CPU allows instead of 60 Hz real time.
FIXED_FPS = "60"


def godot_exe():
    return shutil.which("godot") or shutil.which("godot.exe") or "godot"


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
        [godot_exe(), "--headless", "--fixed-fps", FIXED_FPS, "--path", path, "-s", "addons/gut/gut_cmdln.gd",
         "-gconfig=" + res_of(path, cfg), "-gexit"],
        cwd=path, stdout=log, stderr=subprocess.STDOUT)
    return proc, log, log_path


def parse(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    totals = {k: int(v) for k, v in TOTAL_RE.findall(text)}
    failing = set()
    current = None
    for line in text.splitlines():
        m = SCRIPT_RE.match(line)
        if m:
            current = m.group(1)
        elif current and FAILED_RE.search(line):
            failing.add(current)
    return totals, failing


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


def run_batch(path, out_dir, batches, timeout_s):
    started = time.time()
    procs = {name: start(path, out_dir, name, tests) for name, tests in batches}
    finished = {}
    while len(finished) < len(procs):
        for name, (proc, log, log_path) in procs.items():
            if name in finished:
                continue
            code = proc.poll()
            if code is None and time.time() - started > timeout_s:
                proc.kill()
                code = "timeout"
            if code is not None:
                finished[name] = (code, round(time.time() - started, 1))
        time.sleep(0.5)
    results = {}
    for name, (proc, log, log_path) in procs.items():
        log.close()
        totals, failing = parse(log_path)
        code, seconds = finished[name]
        results[name] = {"exit": code, "totals": totals, "failing": sorted(failing),
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

    # Magic-number ratchet (Bontago-fca.35): <2 s, runs before the shards.
    lint_code = lint_magic_numbers.main(["--path", path])
    print("MAGIC LINT %s" % ("GREEN" if lint_code == 0 else "RED"), flush=True)
    # Single-source ratchet (Bontago-1pi.86.1): same cost, same position.
    ss_code = lint_single_source.main(["--path", path])
    print("SINGLE-SOURCE LINT %s" % ("GREEN" if ss_code == 0 else "RED"), flush=True)

    tests = collect(path)
    if not tests:
        print("FULL GATE ERROR: no tests found under", path)
        return 2
    t0 = time.time()
    shards = make_shards(path, tests, count, timings)
    results = run_batch(path, out_dir, [("shard%d" % i, s) for i, s in enumerate(shards)], args.timeout)
    sums = {}
    failing = set()
    harness = []
    for name, r in results.items():
        for k, v in r["totals"].items():
            sums[k] = sums.get(k, 0) + v
        failing.update(r["failing"])
        if "Tests" not in r["totals"]:
            harness.append("%s exit=%s (no Totals; see %s)" % (name, r["exit"], r["log"]))
    # Per-script durations (JUnit) balance the next run; fall back to the
    # shard average for scripts the export missed.
    for (name, r), shard in zip(sorted(results.items()), shards):
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
    if failing:
        retry = run_batch(path, out_dir, [("retry_%d" % i, [t]) for i, t in enumerate(sorted(failing))], args.timeout)
        for (name, r), t in zip(sorted(retry.items(), key=lambda kv: int(kv[0].split("_")[1])), sorted(failing)):
            # GUT omits the "Failing Tests" line when everything passed.
            ok = "Tests" in r["totals"] and r["totals"].get("Failing Tests", 0) == 0 and not r["failing"]
            (flaky if ok else confirmed).append(t)

    verdict = "GREEN" if not confirmed and not harness and lint_code == 0 and ss_code == 0 else "RED"
    result = {"verdict": verdict, "path": path, "shards": len(shards), "seconds": round(time.time() - t0, 1),
              "totals": sums, "failing": confirmed, "parallel_flaky": flaky, "harness_errors": harness, "magic_lint": "green" if lint_code == 0 else "red",
              "single_source_lint": "green" if ss_code == 0 else "red",
              "shard_seconds": {n: r["seconds"] for n, r in sorted(results.items())}, "out": out_dir}
    with open(os.path.join(out_dir, "result.json"), "w", encoding="utf-8") as fh:
        json.dump(result, fh, indent=1)
    sys.stdout.flush()
    print("FULL GATE %s: %s/%s passing, %d shards, %.0fs; failing=%s parallel_flaky=%s harness=%s magic_lint=%s single_source_lint=%s; out=%s" % (
        verdict, sums.get("Passing Tests", 0), sums.get("Tests", 0), len(shards), result["seconds"],
        confirmed or "none", flaky or "none", harness or "none", "green" if lint_code == 0 else "RED", "green" if ss_code == 0 else "RED", out_dir), flush=True)
    if harness:
        return 2
    return 0 if verdict == "GREEN" else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
