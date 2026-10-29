#!/usr/bin/env python3
"""HUD pixel-parity capture: reference set, noise floor and compare gate for the HUD refactor.

  python tools/hud_parity.py --path <checkout> --out <dir>                  # capture the set into <dir>
  python tools/hud_parity.py --path <checkout> --out <dir> --compare <ref>  # capture, then diff vs <ref>
  python tools/hud_parity.py --path <checkout> --floor <dirA> <dirB>        # floor table of two reference runs

Each shot of tools/hud_parity_shots.json runs in its own Godot process (no state bleed) through
tools/godot_slots.py, off-screen (CLAUDE.md flags), at 1280x720 with --fixed-fps 60, a fixed rng seed and a
pinned sky. Diffs use tools/image_diff.gd. --compare passes when every shot is within
floor + margin, where the floor is read from <ref>/floor.json (written by --floor) and the margin is
MARGIN_MEAN / MARGIN_OVER (absolute, added to the floor). Prints PARITY RESULT PASS|FAIL and exits 0|1.

Not covered by captures (the shot keys cannot reach them; cover with unit tests, never a test-only hook):
4 teams LIVE (an rng_seed does not reach a match with more than one seat, so it is not reproducible),
countdown (the match target waits for PLAYING), sudden death (latched flags, overtime timer), an
eliminated team, a held gift slot.
"""
import argparse
import json
import os
import re
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
SHOTS_FILE = os.path.join(TOOLS, "hud_parity_shots.json")
SIZE = "1280x720"
SHOT_TIMEOUT_S = 900
DIFF_TIMEOUT_S = 300
MARGIN_MEAN = 0.05  # 8-bit units added to the floor mean_abs
MARGIN_OVER = 0.0005  # fraction added to the floor over1/over8
DIFF_RE = re.compile(r"IMAGE_DIFF mean_abs=([\d.eE+-]+) over1=([\d.eE+-]+) over8=([\d.eE+-]+)")
OFFSCREEN = ["--windowed", "--position", "10000,10000", "--resolution", "320x180", "--audio-driver", "Dummy"]


def _godot(args, timeout):
    cmd = [sys.executable, os.path.join(TOOLS, "godot_slots.py"), "run", "--label", "hud_parity", "--", "godot"] + args
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def load_shots():
    with open(SHOTS_FILE, encoding="utf-8") as handle:
        return json.load(handle)


def capture(path, out):
    os.makedirs(out, exist_ok=True)
    ok = True
    for shot in load_shots():
        args = OFFSCREEN + ["--fixed-fps", "60", "--path", path, "res://tools/shot.tscn", "--", "--agent-probe",
                            "--out=" + out, "--render-size=" + SIZE, "--shots=" + json.dumps([shot])]
        result = _godot(args, SHOT_TIMEOUT_S)
        saved = "SHOT_SAVED" in result.stdout
        print("%s: %s" % (shot["name"], "saved" if saved and result.returncode == 0 else "FAILED rc=%d" % result.returncode))
        if not saved or result.returncode != 0:
            ok = False
            print(result.stdout[-600:])
    return ok


def diff(path, a, b):
    args = ["--headless", "--path", path, "-s", "res://tools/image_diff.gd", "--", a, b]
    result = _godot(args, DIFF_TIMEOUT_S)
    match = DIFF_RE.search(result.stdout)
    if match is None:
        return None
    return {"mean_abs": float(match.group(1)), "over1": float(match.group(2)), "over8": float(match.group(3))}


def diff_sets(path, dir_a, dir_b):
    rows = {}
    for shot in load_shots():
        name = "%s_%s.png" % (shot["name"], SIZE)
        rows[shot["name"]] = diff(path, os.path.join(dir_a, name), os.path.join(dir_b, name))
    return rows


def cmd_floor(path, dir_a, dir_b):
    rows = diff_sets(path, dir_a, dir_b)
    print("%-28s %10s %10s %10s" % ("shot", "mean_abs", "over1", "over8"))
    for name, row in rows.items():
        print("%-28s %10s %10s %10s" % ((name,) + ((row["mean_abs"], row["over1"], row["over8"]) if row else ("MISSING",) * 3)))
    if any(row is None for row in rows.values()):
        return 1
    with open(os.path.join(dir_a, "floor.json"), "w", encoding="utf-8") as handle:
        json.dump(rows, handle, indent=1)
    return 0


def cmd_compare(path, out, ref):
    with open(os.path.join(ref, "floor.json"), encoding="utf-8") as handle:
        floor = json.load(handle)
    rows = diff_sets(path, ref, out)
    passed = True
    for name, row in rows.items():
        base = floor[name]
        good = (row is not None and row["mean_abs"] <= base["mean_abs"] + MARGIN_MEAN
                and row["over1"] <= base["over1"] + MARGIN_OVER and row["over8"] <= base["over8"] + MARGIN_OVER)
        passed = passed and good
        print("%-28s %s %s (floor %s)" % (name, "ok  " if good else "FAIL", row, base))
    print("PARITY RESULT " + ("PASS" if passed else "FAIL"))
    return 0 if passed else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", default=os.path.dirname(TOOLS))
    parser.add_argument("--out")
    parser.add_argument("--compare")
    parser.add_argument("--floor", nargs=2, metavar=("DIR_A", "DIR_B"))
    args = parser.parse_args()
    path = os.path.abspath(args.path)
    if args.floor:
        return cmd_floor(path, *[os.path.abspath(d) for d in args.floor])
    if not args.out:
        parser.error("--out is required")
    out = os.path.abspath(args.out)
    if not capture(path, out):
        print("PARITY RESULT FAIL (capture)")
        return 1
    return cmd_compare(path, out, os.path.abspath(args.compare)) if args.compare else 0


if __name__ == "__main__":
    sys.exit(main())
