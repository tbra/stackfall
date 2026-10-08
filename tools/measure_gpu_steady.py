#!/usr/bin/env python
"""Bontago-1pi.11.67: steady-state whole-GPU measurement driver.

Runs res://tests/bench/bench_gpu_frame.tscn in --steady mode (one configuration per
process, Engine.max_fps capped, vsync off, 3440x1440 off-screen render viewport) while
sampling nvidia-smi every 250 ms between the bench's STEADY_BEGIN / STEADY_END markers.
Per run it records util %, graphics clock, power and the clock-normalised cost
util * clock / max_clock, plus the bench's own fps and viewport-timer GPU ms.

  python tools/measure_gpu_steady.py run low high:ssr low:probe_once --repeat 3 --out runs.jsonl
  python tools/measure_gpu_steady.py run low --uncapped --repeat 1 --out runs.jsonl
  python tools/measure_gpu_steady.py report runs.jsonl

A plan item is <preset>[:<feature>[+<feature>...]]. Refuses to run while the owner's
windowed Godot (Godot_v4.7.2-stable_win64) is alive. Not part of the shipped game.
"""
import argparse
import json
import os
import statistics
import subprocess
import sys
import threading
import time

GODOT_CONSOLE = os.path.expandvars(
    r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe"
    r"\Godot_v4.7.2-stable_win64_console.exe"
)
SMI_QUERY = "utilization.gpu,clocks.gr,clocks.max.gr,power.draw"
SMI_PERIOD_MS = "250"
RUN_TIMEOUT_S = 280
DEFAULT_CHECKOUT = r"M:\Bontago-worktrees\gpu-audit"
SCENE = "res://tests/bench/bench_gpu_frame.tscn"


def owner_game_running():
    """True while a windowed (non-headless, non-probe) Godot is alive: it shares the GPU.
    Headless runs by other agents do not use it; agent probes are off-screen and tiny."""
    cmd = ("(Get-CimInstance Win32_Process -Filter \"Name='Godot_v4.7.2-stable_win64.exe'\" | "
           "Where-Object { $_.CommandLine -notmatch '--headless' -and $_.CommandLine -notmatch 'agent-probe' } | "
           "Measure-Object).Count")
    out = subprocess.run(["powershell", "-NoProfile", "-Command", cmd],
                         stdout=subprocess.PIPE, universal_newlines=True).stdout.strip()
    return int(out or "0") > 0


def run_once(preset, off, checkout, max_fps, warmup, steady, profile, log_path):
    waited = 0
    while owner_game_running():  # owner's game shares the GPU: wait it out (up to ~10 min), then give up
        waited += 1
        if waited > 40:
            raise SystemExit("owner's Godot_v4.7.2-stable_win64 is running; refusing to measure")
        time.sleep(15)
    args = [GODOT_CONSOLE, "--windowed", "--position", "10000,10000", "--resolution", "320x180",
            "--audio-driver", "Dummy", "--path", checkout]
    if profile:
        args.append("--gpu-profile")
    args += [SCENE, "--", "--agent-probe", "--render-size=3440x1440", "--steady", "--preset=" + preset,
             "--max-fps=%d" % max_fps, "--warmup-seconds=%g" % warmup, "--steady-seconds=%g" % steady]
    if off:
        args.append("--gpu-off=" + ",".join(off))
    samples = []
    marks = {}
    lines = []
    stop = threading.Event()
    smi = subprocess.Popen(["nvidia-smi", "--query-gpu=" + SMI_QUERY, "--format=csv,noheader,nounits",
                            "-lms", SMI_PERIOD_MS], stdout=subprocess.PIPE, universal_newlines=True)

    def read_smi():
        for line in smi.stdout:
            try:
                u, c, cm, p = [float(x) for x in line.strip().split(",")]
            except ValueError:
                continue
            samples.append((time.time(), u, c, cm, p))
            if stop.is_set():
                break

    t_smi = threading.Thread(target=read_smi, daemon=True)
    t_smi.start()
    proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, universal_newlines=True)
    deadline = time.time() + RUN_TIMEOUT_S

    def read_out():
        for line in proc.stdout:
            line = line.rstrip()
            lines.append(line)
            if line.startswith("STEADY_BEGIN"):
                marks["b"] = time.time()
            elif line.startswith("STEADY_END"):
                marks["e"] = time.time()

    t_out = threading.Thread(target=read_out, daemon=True)
    t_out.start()
    while proc.poll() is None and time.time() < deadline:
        time.sleep(0.5)
    timed_out = proc.poll() is None
    if timed_out:
        proc.kill()
    t_out.join(5)
    stop.set()
    smi.kill()
    with open(log_path, "a") as f:
        f.write("### %s off=%s\n" % (preset, off))
        f.write("\n".join(lines) + "\n")
    result = {"preset": preset, "off": "+".join(off) or "none", "max_fps": max_fps, "timed_out": timed_out}
    if "b" not in marks or "e" not in marks:
        result["error"] = "no steady markers"
        return result
    win = [s for s in samples if marks["b"] <= s[0] <= marks["e"]]
    if not win:
        result["error"] = "no smi samples"
        return result
    util = statistics.mean(s[1] for s in win)
    clock = statistics.mean(s[2] for s in win)
    max_clock = win[0][3]
    result.update({
        "n": len(win), "util": round(util, 1), "util_sd": round(statistics.pstdev(s[1] for s in win), 1),
        "clock": round(clock), "clock_sd": round(statistics.pstdev(s[2] for s in win)),
        "power": round(statistics.mean(s[4] for s in win), 1),
        "norm": round(statistics.mean(s[1] * s[2] for s in win) / max_clock, 1),
    })
    for line in lines:
        if line.startswith("GPU_STEADY"):
            for tok in line.split():
                if tok.startswith(("fps=", "vp_gpu_ms_median=", "draws=")):
                    k, v = tok.split("=")
                    result[k] = float(v)
    for line in lines:
        if line.startswith("VP_INFO type=0"):
            result["vis_prims"] = float(line.split("prims=")[1].split()[0])
        if line.startswith("PERF_MON"):
            result["prims"] = float(line.split("prims=")[1].split()[0])
    if profile:
        result["profile"] = [l for l in lines if "GPU PROFILE" in l or l.startswith("\t-")][-40:]
    return result


def cmd_run(a):
    for rep in range(a.repeat):
        for item in a.plan:  # interleaved: repeats cycle through the whole plan
            preset, _, feats = item.partition(":")
            off = [f for f in feats.split("+") if f]
            r = run_once(preset, off, a.checkout, 0 if a.uncapped else a.max_fps, a.warmup, a.steady,
                         a.profile, a.out + ".log")
            r["uncapped"] = a.uncapped
            r["rep"] = rep
            print(json.dumps(r), flush=True)
            with open(a.out, "a") as f:
                f.write(json.dumps(r) + "\n")


def eff_ms(r):
    """Whole-GPU busy ms per frame = util fraction x frame time. Works for GPU-bound runs
    (util ~97%, fps drops) and capped runs (util < 100%, fps = cap); util alone saturates."""
    return r["util"] / 100.0 * 1000.0 / max(r.get("fps", 1.0), 1.0)


def cmd_report(a):
    rows = [json.loads(l) for l in open(a.file) if l.strip()]
    rows = [r for r in rows if "norm" in r and not r.get("uncapped")]
    groups = {}
    for r in rows:
        groups.setdefault((r["preset"], r["off"]), []).append(r)
    out = []
    for preset in ("low", "medium", "high"):
        base = groups.get((preset, "none"))
        if not base:
            continue
        bm = statistics.mean(eff_ms(r) for r in base)
        spread = max(eff_ms(r) for r in base) - min(eff_ms(r) for r in base)
        out.append("\n## %s: baseline %.2f ms GPU/frame (n=%d, spread %.2f ms = %.0f%%)\n" % (
            preset, bm, len(base), spread, 100.0 * spread / bm))
        out.append("| off | n | util % | clock MHz | power W | fps | GPU ms/frame | saving ms | saving % | norm (util x clk/max) | vis prims | draws |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|---|")
        table = []
        for (p, off), rs in groups.items():
            if p == preset:
                table.append((bm - statistics.mean(eff_ms(r) for r in rs), off, rs))
        for sav, off, rs in sorted(table, key=lambda t: -t[0]):
            m = lambda k: statistics.mean(r.get(k, 0) for r in rs)
            ms = statistics.mean(eff_ms(r) for r in rs)
            out.append("| %s | %d | %.1f | %.0f | %.1f | %.0f | %.2f | %+.2f | %+.0f%% | %.1f | %.0f | %.0f |" % (
                off, len(rs), m("util"), m("clock"), m("power"), m("fps"), ms, sav, 100.0 * sav / bm, m("norm"), m("vis_prims"), m("draws")))
    print("\n".join(out))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("run")
    r.add_argument("plan", nargs="+")
    r.add_argument("--repeat", type=int, default=1)
    r.add_argument("--out", default=r"M:\Bontago-tools\scratch\gpu\runs.jsonl")
    r.add_argument("--checkout", default=DEFAULT_CHECKOUT)
    r.add_argument("--max-fps", type=int, default=144)
    r.add_argument("--uncapped", action="store_true")
    r.add_argument("--warmup", type=float, default=14.0)
    r.add_argument("--steady", type=float, default=12.0)
    r.add_argument("--profile", action="store_true")
    r.set_defaults(fn=cmd_run)
    p = sub.add_parser("report")
    p.add_argument("file")
    p.set_defaults(fn=cmd_report)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
