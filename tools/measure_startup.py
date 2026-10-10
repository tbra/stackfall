"""Off-screen boot timing (Bontago-fca.85).

Usage: python tools/measure_startup.py [--path <checkout>] [--runs 3] [--godot <exe>]

Runs N real boots that quit when the main menu is ready (AgentProbe --quit-on-menu),
parses the AGENT_PROBE startup line, counts SCRIPT ERROR lines and prints one row per run
plus a STARTUP summary. Exit 1 if any run fails (timeout, non-zero exit, no line, errors).
"""
import argparse
import re
import shutil
import statistics
import subprocess
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_exe  # noqa: E402
import godot_slots  # noqa: E402

DEFAULT_RUNS = 3
RUN_TIMEOUT_S = 90
LINE_RE = re.compile(r"AGENT_PROBE startup first_frame_ms=(-?\d+) menu_ready_ms=(-?\d+)")
ARGS = ["--windowed", "--position", "10000,10000", "--resolution", "320x180",
        "--audio-driver", "Dummy", "--", "--agent-probe", "--quit-on-menu"]


def one_run(godot, path):
    try:
        with godot_slots.godot_slot("measure_startup"):  # machine-wide Godot cap (Bontago-fca.89)
            p = subprocess.run([godot, "--path", path] + ARGS, capture_output=True, text=True,
                               encoding="utf-8", errors="replace", timeout=RUN_TIMEOUT_S)
    except (subprocess.TimeoutExpired, TimeoutError):
        return None, None, 0, "timeout"
    out = p.stdout + p.stderr
    errors = out.count("SCRIPT ERROR")
    m = LINE_RE.search(out)
    if not m:
        return None, None, errors, "no startup line (exit %d)" % p.returncode
    first, menu = int(m.group(1)), int(m.group(2))
    if p.returncode != 0 or menu < 0:
        return first, menu, errors, "exit %d" % p.returncode
    return first, menu, errors, ""


def spread(vals):
    return max(vals) - min(vals) if vals else -1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", default=".")
    ap.add_argument("--runs", type=int, default=DEFAULT_RUNS)
    ap.add_argument("--godot", default="godot")
    a = ap.parse_args()
    a.godot = godot_exe.resolve(a.godot)  # real .exe behind PATH shims (Bontago-fca.93)
    firsts, menus, errs, failed = [], [], 0, False
    for i in range(a.runs):
        first, menu, e, fail = one_run(a.godot, a.path)
        errs += e
        print("run %d first_frame_ms=%s menu_ready_ms=%s errors=%d %s" % (i + 1, first, menu, e, fail or "ok"))
        if fail or e:
            failed = True
        if first is not None and menu is not None and menu >= 0:
            firsts.append(first)
            menus.append(menu)
    med = lambda v: int(statistics.median(v)) if v else -1
    print("STARTUP first_frame median=%d spread=%d menu_ready median=%d spread=%d errors=%d"
          % (med(firsts), spread(firsts), med(menus), spread(menus), errs))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
