#!/usr/bin/env python3
"""Host-tick bench campaign and report (host perf plan, package HP-BENCH-B).

Runs tests/bench/bench_host_tick.tscn once per body count under
`godot_slots.py run --exclusive`, parses its BENCH_HOST_TICK lines, prints the
per-phase and ablation tables, the reference-vs-reference floor, and the decision
gates of plan section 3.4 as text. Output with smoke=1 is never evidence.

Usage:
  python tools/bench_host_tick_report.py run --out <dir> [--path <checkout>] [--counts 400,1000,1500]
        [--layout slab] [--floor-count 1000] [--limit-s 900] [--queue-wait-s 7200]
      runs counts, then a second run of --floor-count (the floor), writes logs and report.txt in <dir>
  python tools/bench_host_tick_report.py report <log> [<log> ...]
      parses finished logs; two logs with the same body count and layout give the floor
  python tools/bench_host_tick_report.py parity --out <dir> [--path <checkout>] [--limit-s 900]
      records bench_p4_parity twice, then --compare run-vs-run and reference-vs-run (tol 0)

Each run has a wall-clock limit that starts when the exclusive gate is granted (queue
time does not count); on expiry the whole process tree is killed (exit 124).
Exit codes: 0 ok, 1 a run failed or output was refused, 2 usage, 75 queue timeout, 124 limit.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import threading
import time
from typing import Dict, List, Optional, Tuple

HERE = os.path.dirname(os.path.abspath(__file__))
SLOTS = os.path.join(HERE, "godot_slots.py")
BENCH_SCENE = "res://tests/bench/bench_host_tick.tscn"
PARITY_SCENE = "res://tests/bench/bench_p4_parity.tscn"
PARITY_REFERENCE = "tests/bench/fixtures/p4_parity_reference.json"
PREFIX = "BENCH_HOST_TICK"
GRANT_MARKER = "exclusive access granted"
QUEUE_TIMEOUT_EXIT = 75
LIMIT_EXIT = 124

PHASES = ("prelude", "frozen", "churn", "ablate", "remainder")
SUBSYSTEMS = ("stable", "registry", "effects", "batch")
# Fields that must match exactly between two runs of an unchanged checkout.
DETERMINISTIC = ("bodies", "ticks", "awake", "batch_vy_on", "batch_vy_off", "churn_added")
# Wall-clock fields whose run-to-run spread is the floor for judging a fix.
SPREAD_FIELDS = ("p50_ms", "p99_ms", "p999_ms", "max_ms", "mean_ms", "registry_ms", "effects_ms", "snapshot_ms")

# Plan section 3.4 thresholds.
GATE_SCAN_DELTA_MS = 5.0
GATE_SNAP_DELTA_MS = 2.0
GATE_FROZEN_US_PER_BODY = 5.0
GATE_AWAKE_FRACTION = 0.30
GATE_REMAINDER_FRACTION = 0.60
GATE_LOOPS_FRACTION = 0.25
US_PER_MS = 1000.0


class BenchError(Exception):
    """Output that is not usable evidence."""


class Run:
    def __init__(self, source: str) -> None:
        self.source = source
        self.phases: Dict[str, Dict[str, float]] = {}
        self.layout = ""
        self.wanted = 0
        self.pose_hash = ""
        self.churn_added = 0
        self.result = ""

    def label(self) -> str:
        return "%d/%s" % (self.wanted, self.layout)


class Gate:
    def __init__(self, name: str, hit: Optional[bool], text: str, releases: Tuple[str, ...] = (), q1: bool = False) -> None:
        self.name = name
        self.hit = hit  # None = cannot be decided from the bench
        self.text = text
        self.releases = releases  # fix packages released when hit
        self.q1 = q1  # a hit triggers owner question Q1

    def verdict(self) -> str:
        return "N/A" if self.hit is None else ("RELEASED" if self.hit else "not triggered")


def _fields(line: str) -> Tuple[str, Dict[str, str]]:
    tokens = line.split()
    fields = {}  # type: Dict[str, str]
    first = ""
    for token in tokens[1:]:
        if "=" in token:
            key, _, value = token.partition("=")
            fields[key] = value
        elif not first:
            first = token
    return first, fields


def _num(value: str) -> float:
    try:
        return float(value)
    except ValueError:
        return float("nan")


def parse_lines(lines: List[str], source: str = "<lines>") -> Run:
    """Parses one bench run; raises BenchError on smoke output, a failure line or a truncated run."""
    run = Run(source)
    seen_any = False
    for line in lines:
        line = line.strip()
        if not line.startswith(PREFIX + " "):
            continue
        seen_any = True
        word, fields = _fields(line)
        if fields.get("smoke") == "1":
            raise BenchError("%s: smoke=1 output is not evidence" % source)
        if fields.get("result") == "FAIL":
            raise BenchError("%s: bench reported FAIL (%s)" % (source, line))
        if word == "start":
            run.layout = fields.get("layout", "")
        elif "phase" in fields:
            run.phases[fields["phase"]] = {k: _num(v) for k, v in fields.items() if k != "phase" and k != "layout"}
        elif "pose_hash" in fields:
            run.pose_hash = fields["pose_hash"]
            run.wanted = int(_num(fields.get("bodies", "0")))
            run.churn_added = int(_num(fields.get("churn_added", "0")))
        elif fields.get("result") == "DONE":
            run.result = "DONE"
    if not seen_any:
        raise BenchError("%s: no %s lines" % (source, PREFIX))
    if run.result != "DONE":
        raise BenchError("%s: no result=DONE (run did not finish)" % source)
    missing = [p for p in PHASES if p not in run.phases]
    if missing or not run.pose_hash:
        raise BenchError("%s: missing phase lines %s or pose hash" % (source, missing))
    return run


def parse_file(path: str) -> Run:
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        return parse_lines(handle.read().splitlines(), path)


def _ms(value: float) -> str:
    return "%.2f" % value


def format_table(runs: List[Run]) -> str:
    out = []  # type: List[str]
    head = "%-9s %6s %6s %6s %6s %7s %5s %7s %8s %8s %8s %8s %8s %8s %8s %8s"
    cols = ("phase", "bodies", "p50", "p99", "p99.9", "max", ">16.7", "awake", "scan_top", "scan_rst", "scan_d", "snap_top", "snap_rst", "snap_d", "registry", "effects")
    for run in runs:
        out.append("== %s  bodies(wanted)=%d  pose_hash=%s  churn_added=%d  [%s]" % (
            run.label(), run.wanted, run.pose_hash[:12], run.churn_added, os.path.basename(run.source)))
        out.append(head % cols + " %8s" % "snapshot")
        for name in PHASES:
            p = run.phases[name]
            out.append(head % (
                name, "%.0f" % p["bodies"], _ms(p["p50_ms"]), _ms(p["p99_ms"]), _ms(p["p999_ms"]), _ms(p["max_ms"]), int(p["over_budget"]),
                "%.0f" % p["awake"], _ms(p["scan_tick_ms"]), _ms(p["other_tick_ms"]), _ms(p["scan_tick_ms"] - p["other_tick_ms"]),
                _ms(p["snap_tick_ms"]), _ms(p["nonsnap_tick_ms"]), _ms(p["snap_tick_ms"] - p["nonsnap_tick_ms"]),
                _ms(p["registry_ms"]), _ms(p["effects_ms"])) + " %8s" % _ms(p["snapshot_ms"]))
        ablate = run.phases["ablate"]
        out.append("ablation deltas (ms/tick, median of 5 A/B pairs, min..max):")
        for name in SUBSYSTEMS:
            out.append("  %-9s %7.3f  (%.3f .. %.3f)" % (
                name, ablate["ablate_%s_delta_ms" % name], ablate["ablate_%s_min_ms" % name], ablate["ablate_%s_max_ms" % name]))
        rem = run.phases["remainder"]
        out.append("  remainder (Jolt + sync + bench, all four OFF) %.3f ms  all-ON %.3f ms  batch max |vy| on/off %.3f/%.3f" % (
            rem["remainder_ms"], rem["all_on_ms"], ablate.get("batch_vy_on", float("nan")), ablate.get("batch_vy_off", float("nan"))))
        out.append("")
    return "\n".join(out)


def floor_report(a: Run, b: Run) -> Tuple[bool, str]:
    """Deterministic fields must be identical; wall-clock fields are reported as a spread."""
    out = ["== floor: %s vs %s" % (os.path.basename(a.source), os.path.basename(b.source))]
    same = True
    if a.pose_hash != b.pose_hash:
        same = False
        out.append("  DIFF pose_hash %s vs %s" % (a.pose_hash[:12], b.pose_hash[:12]))
    for phase in PHASES:
        for key in DETERMINISTIC:
            if key in a.phases[phase] or key in b.phases[phase]:
                left, right = a.phases[phase].get(key), b.phases[phase].get(key)
                if left != right:
                    same = False
                    out.append("  DIFF %s.%s %s vs %s" % (phase, key, left, right))
    out.append("  deterministic fields (%s, pose hash): %s" % (", ".join(DETERMINISTIC), "IDENTICAL" if same else "DIFFER"))
    out.append("  wall-clock spread between the two runs (|a-b|, ms; the floor for judging a fix):")
    for phase in ("frozen", "churn"):
        parts = []
        for key in SPREAD_FIELDS:
            parts.append("%s %.3f" % (key.replace("_ms", ""), abs(a.phases[phase][key] - b.phases[phase][key])))
        out.append("    %-7s %s" % (phase, "  ".join(parts)))
    for phase in ("frozen", "churn"):
        da = a.phases[phase]["scan_tick_ms"] - a.phases[phase]["other_tick_ms"]
        db = b.phases[phase]["scan_tick_ms"] - b.phases[phase]["other_tick_ms"]
        sa = a.phases[phase]["snap_tick_ms"] - a.phases[phase]["nonsnap_tick_ms"]
        sb = b.phases[phase]["snap_tick_ms"] - b.phases[phase]["nonsnap_tick_ms"]
        out.append("    %-7s scan delta %.3f vs %.3f   snapshot delta %.3f vs %.3f" % (phase, da, db, sa, sb))
    for name in SUBSYSTEMS:
        key = "ablate_%s_delta_ms" % name
        out.append("    ablate %-8s delta %.3f vs %.3f" % (name, a.phases["ablate"][key], b.phases["ablate"][key]))
    return same, "\n".join(out)


def pick_gate_run(runs: List[Run]) -> Optional[Run]:
    slabs = [r for r in runs if r.layout == "slab"]
    return max(slabs, key=lambda r: r.wanted) if slabs else None


def evaluate_gates(run: Run) -> List[Gate]:
    """Plan 3.4 gates on one run (the largest slab run), as text verdicts."""
    p = run.phases
    n = run.wanted
    gates = []  # type: List[Gate]
    scan = {ph: p[ph]["scan_tick_ms"] - p[ph]["other_tick_ms"] for ph in ("frozen", "churn")}
    worst_scan = max(scan.values())
    gates.append(Gate(
        "1a scan", worst_scan >= GATE_SCAN_DELTA_MS,
        "scan-tick minus other-tick: frozen %.2f ms, churn %.2f ms (threshold %.1f ms at the largest count, %d bodies)" % (
            scan["frozen"], scan["churn"], GATE_SCAN_DELTA_MS, n), ("HP-SCAN",)))
    snap = {ph: p[ph]["snap_tick_ms"] - p[ph]["nonsnap_tick_ms"] for ph in ("frozen", "churn")}
    snapshot_ms = max(p["frozen"]["snapshot_ms"], p["churn"]["snapshot_ms"])
    gates.append(Gate(
        "1b snapshot", max(snap.values()) >= GATE_SNAP_DELTA_MS or snapshot_ms >= GATE_SNAP_DELTA_MS,
        "snapshot-tick minus non-snapshot-tick: frozen %.2f ms, churn %.2f ms; PerfProbe snapshot_ms (mean over all ticks) %.2f ms (threshold %.1f ms)" % (
            snap["frozen"], snap["churn"], snapshot_ms, GATE_SNAP_DELTA_MS), ("HP-SNAP",)))
    per_body = p["frozen"]["p50_ms"] / max(float(n), 1.0) * US_PER_MS
    gates.append(Gate(
        "1c frozen floor", per_body >= GATE_FROZEN_US_PER_BODY,
        "FROZEN p50 %.2f ms = %.2f us/body (threshold %.1f us/body): separate trigger for the O(N) every-tick passes (#6, #7); the plan binds no package to it" % (
            p["frozen"]["p50_ms"], per_body, GATE_FROZEN_US_PER_BODY)))
    churn_bodies = max(p["churn"]["bodies"], 1.0)
    fraction = p["churn"]["awake"] / churn_bodies
    late = ", ".join("%s %.1f%% (%.0f of %.0f)" % (ph, p[ph]["awake"] / max(p[ph]["bodies"], 1.0) * 100.0, p[ph]["awake"], p[ph]["bodies"])
                     for ph in ("ablate", "remainder"))
    gates.append(Gate(
        "2 awake tracks N", fraction > GATE_AWAKE_FRACTION,
        "CHURN awake %.0f of %.0f bodies = %.1f%% (threshold %.0f%%; awake count stands in for islands/active, plan rev 1a). Later phases, where the pile has grown by the churn drops: %s" % (
            p["churn"]["awake"], churn_bodies, fraction * 100.0, GATE_AWAKE_FRACTION * 100.0, late), q1=True))
    # The ablation runs on the pile that CHURN keeps growing, so its deltas and the remainder are
    # compared with the all-ON means measured in the same window, not with the earlier CHURN p50.
    share = p["remainder"]["remainder_ms"] / max(p["remainder"]["all_on_ms"], 1e-9)
    net = (p["remainder"]["remainder_ms"] - p["remainder"]["snapshot_ms"]) / max(p["remainder"]["all_on_ms"], 1e-9)
    literal = p["remainder"]["remainder_ms"] / max(p["churn"]["p50_ms"], 1e-9)
    gates.append(Gate(
        "3 solver remainder", share > GATE_REMAINDER_FRACTION,
        "ablation remainder (Jolt + sync) %.2f ms = %.1f%% of the all-ON mean %.2f ms in the same window (threshold %.0f%%); plan-literal ratio to the earlier CHURN p50 %.2f ms would be %.0f%%, a different body state. The remainder still holds the host SnapshotSync (never ablated, %.2f ms/tick): net of it %.1f%%" % (
            p["remainder"]["remainder_ms"], share * 100.0, p["remainder"]["all_on_ms"], GATE_REMAINDER_FRACTION * 100.0, p["churn"]["p50_ms"], literal * 100.0,
            p["remainder"]["snapshot_ms"], net * 100.0), q1=True))
    loops = sum(p["ablate"]["ablate_%s_delta_ms" % s] for s in ("registry", "effects", "batch"))
    loops_share = loops / max(p["ablate"]["mean_ms"], 1e-9)
    loops_literal = loops / max(p["churn"]["p50_ms"], 1e-9)
    gates.append(Gate(
        "4 script loops", loops_share > GATE_LOOPS_FRACTION,
        "ablation registry + effects + batch = %.2f ms = %.1f%% of the ABLATE-window mean tick %.2f ms (threshold %.0f%%; stable delta %.2f ms is reported, not summed); plan-literal ratio to the earlier CHURN p50 %.2f ms would be %.0f%%" % (
            loops, loops_share * 100.0, p["ablate"]["mean_ms"], GATE_LOOPS_FRACTION * 100.0, p["ablate"]["ablate_stable_delta_ms"], p["churn"]["p50_ms"], loops_literal * 100.0),
        ("HP-LOOPS", "HP-SCAN")))  # HP-SCAN's header releases it on gate 1 or 4
    gates.append(Gate(
        "5 spikes outside the bench", None,
        "bots, Match territory solve and the soak monitor dump are not in this bench: HP-BOT, HP-TERR and HP-METRIC release only on a soak-side finding"))
    return gates


def format_gates(run: Run, gates: List[Gate]) -> str:
    out = ["== gates of plan 3.4 on %s (%s)" % (run.label(), os.path.basename(run.source))]
    for g in gates:
        out.append("  gate %-26s %-13s %s" % (g.name, g.verdict(), g.text))
    names = sorted(set(pkg for g in gates if g.hit for pkg in g.releases))
    out.append("  fix packages released by the bench: %s" % (", ".join(names) if names else "none"))
    out.append("  not released by the bench (soak-side trigger needed): HP-BOT, HP-TERR, HP-METRIC")
    q1 = any(g.hit and g.q1 for g in gates)
    out.append("  owner question Q1 (physics-feel levers, gates 2/3): %s" % ("TRIGGERED" if q1 else "not triggered"))
    return "\n".join(out)


def full_report(runs: List[Run]) -> str:
    sections = [format_table(runs)]
    by_key = {}  # type: Dict[Tuple[int, str], List[Run]]
    for run in runs:
        by_key.setdefault((run.wanted, run.layout), []).append(run)
    for key in sorted(by_key):
        if len(by_key[key]) >= 2:
            sections.append(floor_report(by_key[key][0], by_key[key][1])[1])
    gate_run = pick_gate_run(runs)
    if gate_run is not None:
        sections.append(format_gates(gate_run, evaluate_gates(gate_run)))
    return "\n".join(sections)


# ---- launching -------------------------------------------------------------

def kill_tree(proc: "subprocess.Popen[str]") -> None:
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.kill()


def run_exclusive(label: str, child: List[str], log_path: str, limit_s: float, queue_wait_s: float) -> int:
    """Runs `child` alone through godot_slots; the limit starts at the exclusive grant."""
    cmd = [sys.executable, SLOTS, "run", "--exclusive", "--label", label, "--wait-timeout", str(queue_wait_s), "--"] + child
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    granted = {"at": 0.0}

    def pump() -> None:
        assert proc.stdout is not None
        with open(log_path, "w", encoding="utf-8") as log:
            for line in proc.stdout:
                if GRANT_MARKER in line and not granted["at"]:
                    granted["at"] = time.time()
                log.write(line)
                log.flush()

    reader = threading.Thread(target=pump, daemon=True)
    reader.start()
    while proc.poll() is None:
        if granted["at"] and time.time() - granted["at"] > limit_s:
            kill_tree(proc)
            reader.join(5)
            print("LIMIT: %s exceeded %.0f s after the grant; tree killed; log %s" % (label, limit_s, log_path), flush=True)
            return LIMIT_EXIT
        time.sleep(1.0)
    reader.join(10)
    return int(proc.returncode)


def godot_cmd(path: str, scene: str, user_args: List[str], fixed_fps: bool = True) -> List[str]:
    cmd = ["godot", "--headless"]
    if fixed_fps:
        cmd += ["--fixed-fps", "60"]
    return cmd + ["--path", path, scene, "--"] + user_args


def cmd_run(args: argparse.Namespace) -> int:
    os.makedirs(args.out, exist_ok=True)
    counts = [int(c) for c in args.counts.split(",") if c]
    jobs = [(c, 1) for c in counts] + [(args.floor_count, 2)]
    runs = []  # type: List[Run]
    failed = False
    for bodies, repeat in jobs:
        log = os.path.join(args.out, "host_%d_%s_%d.log" % (bodies, args.layout, repeat))
        label = "bench_host_tick %d %s #%d" % (bodies, args.layout, repeat)
        print("RUN %s -> %s" % (label, log), flush=True)
        started = time.time()
        code = run_exclusive(label, godot_cmd(args.path, BENCH_SCENE, ["--bodies=%d" % bodies, "--layout=%s" % args.layout]),
                             log, args.limit_s, args.queue_wait_s)
        print("  exit %d after %.0f s" % (code, time.time() - started), flush=True)
        if code != 0:
            failed = True
            if code in (QUEUE_TIMEOUT_EXIT, LIMIT_EXIT):
                return code
            continue
        try:
            runs.append(parse_file(log))
        except BenchError as err:
            print("REFUSED: %s" % err, flush=True)
            failed = True
    if runs:
        text = full_report(runs)
        with open(os.path.join(args.out, "report.txt"), "w", encoding="utf-8") as handle:
            handle.write(text + "\n")
        print(text)
    return 1 if failed else 0


def cmd_report(args: argparse.Namespace) -> int:
    try:
        runs = [parse_file(p) for p in args.logs]
    except BenchError as err:
        print("REFUSED: %s" % err)
        return 1
    print(full_report(runs))
    return 0


def cmd_parity(args: argparse.Namespace) -> int:
    os.makedirs(args.out, exist_ok=True)
    recordings = [os.path.join(args.out, "parity_%d.json" % i) for i in (1, 2)]
    for i, rec in enumerate(recordings, start=1):
        log = os.path.join(args.out, "parity_record_%d.log" % i)
        code = run_exclusive("bench_p4_parity record #%d" % i, godot_cmd(args.path, PARITY_SCENE, ["--out=%s" % rec]), log, args.limit_s, args.queue_wait_s)
        print("record %d: exit %d (%s)" % (i, code, log), flush=True)
        if code != 0:
            return code or 1
    status = 0
    reference = os.path.join(args.path, PARITY_REFERENCE)
    pairs = (("floor_run1_run2", recordings), ("reference_run1", [reference, recordings[0]]))
    for name, pair in pairs:
        log = os.path.join(args.out, "parity_compare_%s.log" % name)
        code = run_exclusive("bench_p4_parity compare", godot_cmd(args.path, PARITY_SCENE, ["--compare=%s,%s" % (pair[0], pair[1])], fixed_fps=False),
                             log, args.limit_s, args.queue_wait_s)
        print("compare %s: exit %d (%s)" % (name, code, log), flush=True)
        status = status or code
    return status


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="action", required=True)
    checkout = os.path.dirname(HERE)
    for name in ("run", "parity"):
        p = sub.add_parser(name)
        p.add_argument("--out", required=True)
        p.add_argument("--path", default=checkout)
        p.add_argument("--limit-s", type=float, default=900.0)
        p.add_argument("--queue-wait-s", type=float, default=7200.0)
        if name == "run":
            p.add_argument("--counts", default="400,1000,1500")
            p.add_argument("--layout", default="slab")
            p.add_argument("--floor-count", type=int, default=1000)
    r = sub.add_parser("report")
    r.add_argument("logs", nargs="+")
    args = ap.parse_args(argv)
    return {"run": cmd_run, "report": cmd_report, "parity": cmd_parity}[args.action](args)


if __name__ == "__main__":
    sys.exit(main())
