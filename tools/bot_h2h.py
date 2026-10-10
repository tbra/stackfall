#!/usr/bin/env python
"""Paired head-to-head driver: candidate bot weights vs the shipped ones (Bontago-1t5.12).

Ship gate (owner, decision Bontago-1t5.10): trained Hard weights need >= 75 %
win share over >= 100 paired head-to-head matches. For each seed this runs two
8-bot headless matches with the same seed and swapped seats (candidate on the
A seats, then on the B seats), as N parallel
`godot --headless --fixed-fps 60 ... -- --headless-host --bots=8 --seconds=S`
processes, parses each `HEADLESS_MATCH ... winner_team=` line, and reports the
candidate's win share with a Wilson 95 % interval against the gate.

A match stopped by the --seconds cap while still PLAYING prints a HEADLESS_MATCH line with
winner_team=-1 timeout=1 (game time; `HEADLESS_BOTS done t=` is game time too, `wall=` is wall
clock): it counts as a draw and shows in the `timeouts=` part of the summary, separate from
`failed` (no HEADLESS_MATCH line: launch failure, crash, kill).

SEAM DEPENDENCY (plan BT5): the game has no per-slot weight override or match
seed flag yet. This tool therefore needs `--godot-args`, a template appended
after `--` on the Godot command line, with the placeholders
    {seed} {weights_file} {weights_json} {cand_slots}
Without it the tool refuses to launch (use --dry-run to print the commands).
No game file is touched here; when BT5 lands, pass e.g.
    --godot-args "--match-seed={seed} --bot-weights={weights_file} --bot-weights-slots={cand_slots}"

    python -I tools/bot_h2h.py --candidate proposal.txt --pairs 50 --parallel 4 \\
        --godot-args "..." [--dry-run]

Exit code: 0 PASS, 1 FAIL/INCONCLUSIVE/INSUFFICIENT, 2 usage or launch error.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import math
import os
import re
import shlex
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Sequence, Tuple

GATE_WIN_SHARE = 0.75
GATE_MIN_MATCHES = 100
Z95 = 1.959964
_MATCH_RE = re.compile(r"HEADLESS_MATCH\b.*?\bwinner_team=(-?\d+)")
_TIMEOUT_RE = re.compile(r"HEADLESS_MATCH\b.*\btimeout=1\b")
_WEIGHT_LINE = re.compile(r"^\s*(weight_\w+)\s*=\s*(-?[0-9.eE+-]+)\s*$")


def parse_candidate(path: str) -> Dict[str, float]:
    """Weights from a bot_fit_weights proposal (`weight_x = v` lines) or a JSON object."""
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    if text.lstrip().startswith("{"):
        data = json.loads(text)
        return {k: float(v) for k, v in data.items()}
    out: Dict[str, float] = {}
    for line in text.splitlines():
        m = _WEIGHT_LINE.match(line)
        if m:
            out[m.group(1)] = float(m.group(2))
    if not out:
        raise ValueError("no weight_* entries found in %s" % path)
    return out


def parse_winner(output: str) -> Optional[int]:
    """winner_team of the LAST HEADLESS_MATCH line (loop runs print several), else None."""
    found = _MATCH_RE.findall(output)
    return int(found[-1]) if found else None


def timed_out(output: str) -> bool:
    """True when the LAST HEADLESS_MATCH line carries timeout=1 (--seconds cap hit while PLAYING)."""
    lines = [ln for ln in output.splitlines() if "HEADLESS_MATCH" in ln]
    return bool(lines) and _TIMEOUT_RE.search(lines[-1]) is not None


def wilson(wins: int, n: int, z: float = Z95) -> Tuple[float, float]:
    if n <= 0:
        return (0.0, 1.0)
    p = wins / n
    denom = 1.0 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def verdict(wins: int, losses: int, matches: int, gate: float = GATE_WIN_SHARE,
            min_matches: int = GATE_MIN_MATCHES) -> str:
    decided = wins + losses
    if matches < min_matches or decided == 0:
        return "INSUFFICIENT"
    lo, hi = wilson(wins, decided)
    if lo >= gate:
        return "PASS"
    if hi < gate:
        return "FAIL"
    return "INCONCLUSIVE"


@dataclass
class MatchJob:
    seed: int
    swapped: bool
    cmd: List[str]


H2H_PORT_BASE = 47200  # per-job host port = base + job index % H2H_PORT_SPAN (parallel hosts must not collide)
H2H_PORT_SPAN = 256


def build_cmd(godot: str, project: str, seconds: float, bots: int, godot_args: str,
              seed: int, weights_file: str, weights_json: str, cand_slots: str, port: int = H2H_PORT_BASE) -> List[str]:
    weights_file = weights_file.replace("\\", "/")  # shlex.split would eat Windows backslashes
    tail = godot_args.format(seed=seed, weights_file=weights_file, weights_json=weights_json,
                             cand_slots=cand_slots)
    return ([godot, "--headless", "--fixed-fps", "60", "--path", project, "--",
             "--headless-host", "--bots=%d" % bots, "--seconds=%s" % seconds,
             "--port=%d" % port]
            + shlex.split(tail))


def plan_jobs(pairs: int, base_seed: int, slots_a: str, slots_b: str, **kw) -> List[MatchJob]:
    jobs: List[MatchJob] = []
    for i in range(pairs):
        seed = base_seed + i
        for swapped, slots in ((False, slots_a), (True, slots_b)):
            port = H2H_PORT_BASE + len(jobs) % H2H_PORT_SPAN
            jobs.append(MatchJob(seed, swapped, build_cmd(seed=seed, cand_slots=slots, port=port, **kw)))
    return jobs


def run_process(cmd: Sequence[str], timeout_s: float) -> str:
    """Run one match; return its combined output ('' on timeout or launch failure)."""
    try:
        proc = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout_s)
    except (subprocess.TimeoutExpired, OSError):
        return ""
    return (proc.stdout or "") + (proc.stderr or "")


def tally(jobs: Sequence[MatchJob], outputs: Sequence[str], teams_a: Sequence[int],
          teams_b: Sequence[int]) -> Dict[str, int]:
    """Candidate wins / losses / draws (winner -1 or a team nobody holds) / failed matches.

    `timeouts` counts the draws that were --seconds-cap stops (timeout=1); failed means no
    HEADLESS_MATCH line at all (launch failure, crash, kill)."""
    r = {"wins": 0, "losses": 0, "draws": 0, "failed": 0, "timeouts": 0}
    for job, out in zip(jobs, outputs):
        winner = parse_winner(out)
        if winner is None:
            r["failed"] += 1
            continue
        cand = set(teams_b if job.swapped else teams_a)
        if winner in cand:
            r["wins"] += 1
        elif winner < 0:
            r["draws"] += 1
            if timed_out(out):
                r["timeouts"] += 1
        else:
            r["losses"] += 1
    return r


def _csv_ints(text: str) -> List[int]:
    return [int(x) for x in text.split(",") if x.strip()]


def main(argv: Optional[List[str]] = None, runner: Callable[[Sequence[str], float], str] = run_process) -> int:
    ap = argparse.ArgumentParser(description="Paired head-to-head runs against the owner's 75% gate.")
    ap.add_argument("--candidate", required=True, help="proposal file (weight_x = v) or JSON weights")
    ap.add_argument("--pairs", type=int, default=50, help="seeds; each runs 2 matches (seats swapped)")
    ap.add_argument("--base-seed", type=int, default=1000)
    ap.add_argument("--parallel", type=int, default=4)
    ap.add_argument("--seconds", type=float, default=300.0, help="--seconds= match bound")
    ap.add_argument("--timeout-s", type=float, default=900.0, help="hard wall-clock kill per match")
    ap.add_argument("--bots", type=int, default=8)
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--cand-slots-a", default="0,2,4,6", help="candidate seats in the first match")
    ap.add_argument("--cand-slots-b", default="1,3,5,7", help="candidate seats in the swapped match")
    ap.add_argument("--godot-args", default="", help="seam template appended after `--` (see docstring)")
    ap.add_argument("--out-dir", default=".", help="where the candidate weights JSON is written")
    ap.add_argument("--dry-run", action="store_true", help="print the commands and exit")
    args = ap.parse_args(argv)

    if not args.godot_args and not args.dry_run:
        print("bot_h2h: no --godot-args; the per-slot weight override + match seed seam (plan BT5 "
              "--bot-weights) does not exist yet. Pass --godot-args or use --dry-run.", file=sys.stderr)
        return 2
    weights = parse_candidate(args.candidate)
    os.makedirs(args.out_dir, exist_ok=True)
    weights_file = os.path.abspath(os.path.join(args.out_dir, "h2h_candidate_weights.json"))
    with open(weights_file, "w", encoding="utf-8") as fh:
        json.dump(weights, fh)
    jobs = plan_jobs(args.pairs, args.base_seed, args.cand_slots_a, args.cand_slots_b,
                     godot=args.godot, project=args.path, seconds=args.seconds, bots=args.bots,
                     godot_args=args.godot_args or "{seed} {weights_file} {cand_slots}",
                     weights_file=weights_file, weights_json=json.dumps(weights))
    if args.dry_run:
        for j in jobs:
            print(" ".join(shlex.quote(c) for c in j.cmd))
        print("H2H DRY-RUN matches=%d" % len(jobs))
        return 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, args.parallel)) as pool:
        def _run(ij: Tuple[int, MatchJob]) -> str:
            out = runner(ij[1].cmd, args.timeout_s)
            with open(os.path.join(args.out_dir, "h2h_seed%d_%s.log" % (ij[1].seed, "b" if ij[1].swapped else "a")),
                      "w", encoding="utf-8") as fh:  # per-match log so failed matches can be triaged
                fh.write(out)
            return out
        outputs = list(pool.map(_run, enumerate(jobs)))
    # Team ids equal slot ids here (every bot is its own team in the 8-bot FFA matches).
    t = tally(jobs, outputs, _csv_ints(args.cand_slots_a), _csv_ints(args.cand_slots_b))
    decided = t["wins"] + t["losses"]
    lo, hi = wilson(t["wins"], decided)
    v = verdict(t["wins"], t["losses"], len(jobs))
    share = (t["wins"] / decided) if decided else float("nan")
    print("H2H matches=%d wins=%d losses=%d draws=%d (timeouts=%d) failed=%d" % (
        len(jobs), t["wins"], t["losses"], t["draws"], t["timeouts"], t["failed"]))
    print("H2H win_share=%.3f ci95=[%.3f, %.3f] gate>=%.2f over>=%d matches (match-level Wilson)" % (
        share, lo, hi, GATE_WIN_SHARE, GATE_MIN_MATCHES))
    print("H2H RESULT %s" % v)
    return 0 if v == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
