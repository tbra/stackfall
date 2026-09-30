#!/usr/bin/env python3
"""Summarise a Stackfall perf log (Bontago-470.8).

Usage:
    python tools/perf_log_summary.py [log.csv]        # default: newest log
    python tools/perf_log_summary.py --dir <dir> ...   # override log directory
    python tools/perf_log_summary.py log.csv --json    # machine-readable

Logs are written by game/PerfLogger.gd when debug mode is on, to
%APPDATA%/Godot/app_userdata/<project>/perf_logs/<timestamp>.csv. Reports
percentiles (p50/p95/p99/max), spikes, and start->end trends per metric.
"""
import argparse
import csv
import json
import math
import os
import sys
from pathlib import Path

# Metrics summarised with percentiles, in report order.
METRICS = [
    "fps", "frame_ms", "frame_ms_max", "physics_ms", "physics_ms_max",
    "territory_ms", "territory_peak_ms", "weather_ms", "gifts_ms", "registry_ms",
    "block_effects_ms", "snapshot_ms",
    "blocks_total", "blocks_awake",
    "draw_calls", "primitives", "vram_mb", "static_mem_mb",
    "node_count", "object_count", "orphan_nodes", "net_ping_ms", "net_snapshot_bps",
]
# Metrics whose growth over the session suggests a leak.
TREND_METRICS = ["static_mem_mb", "vram_mb", "node_count", "object_count", "orphan_nodes"]
SPIKE_FRAME_MS = 33.4       # a frame slower than 30 fps
SPIKE_PHYSICS_MS = 16.7
TREND_WARN_FRACTION = 0.10  # +10 % start->end
TOP_SPIKES = 5


def default_log_dir() -> Path:
    appdata = os.environ.get("APPDATA")
    if appdata:
        base = Path(appdata) / "Godot" / "app_userdata"
        if base.is_dir():
            candidates = [p / "perf_logs" for p in base.iterdir() if (p / "perf_logs").is_dir()]
            if candidates:
                return max(candidates, key=lambda p: p.stat().st_mtime)
    return Path("user_perf_logs")


def newest_log(directory: Path) -> Path:
    logs = sorted(directory.glob("*.csv"))
    if not logs:
        sys.exit(f"no .csv logs in {directory}")
    return logs[-1]


def percentile(sorted_values, fraction):
    if not sorted_values:
        return float("nan")
    index = fraction * (len(sorted_values) - 1)
    lo, hi = math.floor(index), math.ceil(index)
    if lo == hi:
        return sorted_values[lo]
    return sorted_values[lo] + (sorted_values[hi] - sorted_values[lo]) * (index - lo)


def load_rows(path: Path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def column(rows, name):
    values = []
    for row in rows:
        try:
            values.append(float(row[name]))
        except (KeyError, TypeError, ValueError):
            continue
    return values


def summarise(rows):
    result = {"rows": len(rows), "metrics": {}, "trends": {}, "spikes": [], "states": {}}
    if not rows:
        return result
    times = column(rows, "time_s")
    result["duration_s"] = (times[-1] - times[0]) if len(times) > 1 else 0.0
    for name in METRICS:
        values = column(rows, name)
        if not values:
            continue
        ordered = sorted(values)
        result["metrics"][name] = {
            "mean": sum(values) / len(values),
            "p50": percentile(ordered, 0.50),
            "p95": percentile(ordered, 0.95),
            "p99": percentile(ordered, 0.99),
            "max": ordered[-1],
        }
    for name in TREND_METRICS:
        values = column(rows, name)
        if len(values) < 2:
            continue
        # Compare the first and last fifth (>= 1 row) so one noisy row cannot decide.
        span = max(1, len(values) // 5)
        start = sum(values[:span]) / span
        end = sum(values[-span:]) / span
        growth = (end - start) / start if start else (1.0 if end else 0.0)
        result["trends"][name] = {
            "start": start, "end": end, "growth": growth,
            "warn": growth >= TREND_WARN_FRACTION and end - start > 0,
        }
    frame = column(rows, "frame_ms_max")
    physics = column(rows, "physics_ms_max")
    for index, row in enumerate(rows):
        frame_ms = frame[index] if index < len(frame) else 0.0
        physics_ms = physics[index] if index < len(physics) else 0.0
        if frame_ms >= SPIKE_FRAME_MS or physics_ms >= SPIKE_PHYSICS_MS:
            result["spikes"].append({
                "time_s": float(row.get("time_s", 0) or 0), "frame_ms_max": frame_ms,
                "physics_ms": physics_ms, "blocks": row.get("blocks_total", ""),
                "state": row.get("match_state", ""),
            })
    result["spike_count"] = len(result["spikes"])
    result["spikes"] = sorted(result["spikes"], key=lambda s: -s["frame_ms_max"])[:TOP_SPIKES]
    for row in rows:
        state = row.get("match_state", "")
        result["states"][state] = result["states"].get(state, 0) + 1
    return result


def print_report(path, summary):
    print(f"Perf log: {path}")
    print(f"  rows {summary['rows']}, duration {summary.get('duration_s', 0.0):.0f} s, "
          f"states {summary['states']}")
    if not summary["metrics"]:
        return
    print(f"  {'metric':<20}{'mean':>10}{'p50':>10}{'p95':>10}{'p99':>10}{'max':>10}")
    for name, stats in summary["metrics"].items():
        print(f"  {name:<20}{stats['mean']:>10.2f}{stats['p50']:>10.2f}"
              f"{stats['p95']:>10.2f}{stats['p99']:>10.2f}{stats['max']:>10.2f}")
    print(f"  spikes (frame >= {SPIKE_FRAME_MS} ms or physics >= {SPIKE_PHYSICS_MS} ms): "
          f"{summary['spike_count']}")
    for spike in summary["spikes"]:
        print(f"    t={spike['time_s']:.0f}s frame_max={spike['frame_ms_max']:.1f} ms "
              f"physics={spike['physics_ms']:.1f} ms blocks={spike['blocks']} state={spike['state']}")
    for name, trend in summary["trends"].items():
        flag = "  <-- growing" if trend["warn"] else ""
        print(f"  trend {name}: {trend['start']:.1f} -> {trend['end']:.1f} "
              f"({trend['growth'] * 100:+.0f}%){flag}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("log", nargs="?", help="CSV path (default: newest in the log dir)")
    parser.add_argument("--dir", help="log directory to search for the newest log")
    parser.add_argument("--json", action="store_true", help="print JSON instead of text")
    args = parser.parse_args(argv)
    path = Path(args.log) if args.log else newest_log(Path(args.dir) if args.dir else default_log_dir())
    summary = summarise(load_rows(path))
    if args.json:
        print(json.dumps({"path": str(path), **summary}, indent=2))
    else:
        print_report(path, summary)
    return 0


if __name__ == "__main__":
    sys.exit(main())
