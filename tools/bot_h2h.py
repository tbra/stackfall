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

P1b options (Bontago-1t5.20; evaluation plan docs/BOT_AI_REDESIGN.md section 2.5):
  --candidate is optional when the --godot-args template has no {weights_file}/{weights_json}.
  --players N      adds --players=N (passive human seats, e.g. E3/E4 vs passive).
  --no-swap        runs only the A-seat half of each seed and prints one `H2H seed=` line per
                   match. The gate verdict then reads INSUFFICIENT (under 100 matches) by design;
                   read the win/time lines instead.
  --mode M         adds --mode=M (classic|ctf|elimination|sky).
  Summary          adds the candidate win time median and max in game seconds (the
                   HEADLESS_MATCH duration= field, Bontago-1t5.16). Draws and timeouts stay separate.
  --battery E1..E5|all   only with --dry-run: prints the section 2.5 command lines. Their templates
                   carry <...> placeholders (e.g. <v2>) that must be filled in by hand; a real launch
                   refuses a template that still contains one.

SEAM DEPENDENCY (plan BT5): the game has no per-slot weight override or match
seed flag yet. Weight runs therefore need `--godot-args`, a template appended
after `--` on the Godot command line, with the placeholders
    {seed} {weights_file} {weights_json} {cand_slots}
Without it a candidate run refuses to launch (use --dry-run to print the commands).
No game file is touched here; when BT5 lands, pass e.g.
    --godot-args "--match-seed={seed} --bot-weights={weights_file} --bot-weights-slots={cand_slots}"

    python -I tools/bot_h2h.py --candidate proposal.txt --pairs 50 \\
        --godot-args "..." [--dry-run]
    python -I tools/bot_h2h.py --dry-run --battery E1 --bots 8

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
import statistics
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable, Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import godot_slots  # noqa: E402

GATE_WIN_SHARE = 0.75
GATE_MIN_MATCHES = 100
Z95 = 1.959964
_MATCH_RE = re.compile(r"HEADLESS_MATCH\b.*?\bwinner_team=(-?\d+)")
_TIMEOUT_RE = re.compile(r"HEADLESS_MATCH\b.*\btimeout=1\b")
_DURATION_RE = re.compile(r"HEADLESS_MATCH\b.*?\bduration=(-?[0-9]+(?:\.[0-9]+)?)")
_WEIGHT_LINE = re.compile(r"^\s*(weight_\w+)\s*=\s*(-?[0-9.eE+-]+)\s*$")
_WEIGHT_PLACEHOLDER = re.compile(r"\{weights_file\}|\{weights_json\}")
_TEMPLATE_PLACEHOLDER = re.compile(r"<[^<>\s]+>")  # battery templates: <v2>, <hard|normal>


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


def parse_duration(output: str) -> Optional[float]:
    """duration= (game seconds) of the LAST HEADLESS_MATCH line, else None."""
    found = _DURATION_RE.findall(output)
    return float(found[-1]) if found else None


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
              seed: int, weights_file: str, weights_json: str, cand_slots: str, port: int = H2H_PORT_BASE,
              players: Optional[int] = None, mode: Optional[str] = None) -> List[str]:
    weights_file = weights_file.replace("\\", "/")  # shlex.split would eat Windows backslashes
    tail = godot_args.format(seed=seed, weights_file=weights_file, weights_json=weights_json,
                             cand_slots=cand_slots)
    cmd = [godot, "--headless", "--fixed-fps", "60", "--path", project, "--",
           "--headless-host", "--bots=%d" % bots, "--seconds=%s" % seconds,
           "--port=%d" % port]
    if players is not None:
        cmd.append("--players=%d" % players)
    cmd += shlex.split(tail)
    if mode:
        cmd.append("--mode=%s" % mode)
    return cmd


def plan_jobs(pairs: int, base_seed: int, slots_a: str, slots_b: str, swap: bool = True,
              **kw: object) -> List[MatchJob]:
    """One job per seed (A seats), plus the swapped-seat job (B seats) when swap is on."""
    jobs: List[MatchJob] = []
    halves: List[Tuple[bool, str]] = [(False, slots_a)] + ([(True, slots_b)] if swap else [])
    for i in range(pairs):
        seed = base_seed + i
        for swapped, slots in halves:
            port = H2H_PORT_BASE + len(jobs) % H2H_PORT_SPAN
            jobs.append(MatchJob(seed, swapped, build_cmd(seed=seed, cand_slots=slots, port=port, **kw)))
    return jobs


def run_process(cmd: Sequence[str], timeout_s: float) -> str:
    """Run one match; return its combined output ('' on timeout or launch failure)."""
    try:
        with godot_slots.godot_slot("bot_h2h"):  # machine-wide Godot cap (Bontago-fca.89)
            proc = subprocess.run(list(cmd), capture_output=True, text=True, timeout=timeout_s)
    except (subprocess.TimeoutExpired, OSError, TimeoutError):
        return ""
    return (proc.stdout or "") + (proc.stderr or "")


def classify(job: MatchJob, output: str, teams_a: Sequence[int], teams_b: Sequence[int]) -> str:
    """One of win / loss / draw / timeout (a --seconds-cap draw) / failed (no HEADLESS_MATCH line)."""
    winner = parse_winner(output)
    if winner is None:
        return "failed"
    cand = set(teams_b if job.swapped else teams_a)
    if winner in cand:
        return "win"
    if winner < 0:
        return "timeout" if timed_out(output) else "draw"
    return "loss"


def tally(jobs: Sequence[MatchJob], outputs: Sequence[str], teams_a: Sequence[int],
          teams_b: Sequence[int]) -> Dict[str, int]:
    """Candidate wins / losses / draws / failed matches.

    `draws` counts winner -1 matches, including the --seconds-cap stops; `timeouts` is the subset
    that hit the cap (timeout=1); `failed` means no HEADLESS_MATCH line at all (launch failure,
    crash, kill)."""
    r = {"wins": 0, "losses": 0, "draws": 0, "failed": 0, "timeouts": 0}
    for job, out in zip(jobs, outputs):
        kind = classify(job, out, teams_a, teams_b)
        if kind == "failed":
            r["failed"] += 1
        elif kind == "win":
            r["wins"] += 1
        elif kind == "loss":
            r["losses"] += 1
        else:
            r["draws"] += 1
            if kind == "timeout":
                r["timeouts"] += 1
    return r


def win_times(jobs: Sequence[MatchJob], outputs: Sequence[str], teams_a: Sequence[int],
              teams_b: Sequence[int]) -> List[float]:
    """Game-second durations of the candidate's wins (matches without a duration= are skipped)."""
    times: List[float] = []
    for job, out in zip(jobs, outputs):
        if classify(job, out, teams_a, teams_b) == "win":
            d = parse_duration(out)
            if d is not None:
                times.append(d)
    return times


def seed_lines(jobs: Sequence[MatchJob], outputs: Sequence[str], teams_a: Sequence[int],
               teams_b: Sequence[int]) -> List[str]:
    lines: List[str] = []
    for job, out in zip(jobs, outputs):
        winner = parse_winner(out)
        dur = parse_duration(out)
        lines.append("H2H seed=%d side=%s result=%s winner_team=%s duration=%s" % (
            job.seed, "b" if job.swapped else "a", classify(job, out, teams_a, teams_b),
            "none" if winner is None else winner, "n/a" if dur is None else "%.1f" % dur))
    return lines


def _csv_ints(text: str) -> List[int]:
    return [int(x) for x in text.split(",") if x.strip()]


@dataclass(frozen=True)
class Preset:
    label: str
    note: str
    template: str
    bots: int
    pairs: int
    slots_a: str
    slots_b: str
    seconds: float
    players: Optional[int] = None
    mode: Optional[str] = None
    swap: bool = True


# Section 2.5 battery (E1-E5). The <...> placeholders are filled in by hand before a real launch.
# DECISION (Bontago-1t5.20): section 2.5 gives no seconds for E2 and E5; they use 600 like E1.
# E5 needs a per-side difficulty flag the game may not have yet, so its lines are dry-run only.
_HARD_V2 = "--match-seed={seed} --bot-difficulty=hard --bot-brain=<v2> --bot-brain-slots={cand_slots}"
BATTERY: Tuple[Preset, ...] = (
    Preset("E1", "classic 8 seats, v2 Hard x4 vs legacy Hard x4, seats swapped", _HARD_V2,
           bots=8, pairs=50, slots_a="0,2,4,6", slots_b="1,3,5,7", seconds=600.0),
    Preset("E2", "classic duel 1v1, slots 0/1", _HARD_V2,
           bots=2, pairs=30, slots_a="0", slots_b="1", seconds=600.0),
    Preset("E3", "vs passive, classic M, 4 seats (1 bot), no swap", _HARD_V2,
           bots=1, pairs=20, slots_a="0", slots_b="0", seconds=600.0, players=4, mode="classic", swap=False),
    Preset("E4", "elimination 8 seats, seats swapped", _HARD_V2,
           bots=8, pairs=30, slots_a="0,2,4,6", slots_b="1,3,5,7", seconds=600.0, mode="elimination"),
    Preset("E4-passive", "elimination vs passive, 5 seats, no swap", _HARD_V2,
           bots=1, pairs=10, slots_a="0", slots_b="0", seconds=600.0, players=5, mode="elimination", swap=False),
    Preset("E5a", "tier ladder: v2 Hard vs v2 Normal, 1v1",
           "--match-seed={seed} --bot-brain=<v2> --bot-difficulty=<hard|normal> --bot-brain-slots={cand_slots}",
           bots=2, pairs=20, slots_a="0", slots_b="1", seconds=600.0),
    Preset("E5b", "tier ladder: v2 Normal vs v2 Easy, 1v1",
           "--match-seed={seed} --bot-brain=<v2> --bot-difficulty=<normal|easy> --bot-brain-slots={cand_slots}",
           bots=2, pairs=20, slots_a="0", slots_b="1", seconds=600.0),
    Preset("E5c", "tier ladder: v2 Normal vs legacy Hard, 1v1",
           "--match-seed={seed} --bot-brain=<v2> --bot-difficulty=<normal|hard> --bot-brain-slots={cand_slots}",
           bots=2, pairs=20, slots_a="0", slots_b="1", seconds=600.0),
    Preset("E5d", "v2 Easy vs passive, 1v1, no swap (10/10 within 600 s)",
           "--match-seed={seed} --bot-brain=<v2> --bot-difficulty=easy --bot-brain-slots={cand_slots}",
           bots=1, pairs=10, slots_a="0", slots_b="0", seconds=600.0, players=2, swap=False),
)


def battery_presets(name: str) -> List[Preset]:
    """`all`, or every preset whose label starts with the name (E4 -> E4 and E4-passive, E5 -> E5a-d)."""
    if name == "all":
        return list(BATTERY)
    return [p for p in BATTERY if p.label.startswith(name)]


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description="Paired head-to-head runs against the owner's 75% gate.")
    ap.add_argument("--candidate", default=None,
                    help="proposal file (weight_x = v) or JSON weights; optional when --godot-args has no "
                         "{weights_file}/{weights_json}")
    ap.add_argument("--pairs", type=int, default=50, help="seeds; each runs 2 matches (seats swapped)")
    ap.add_argument("--base-seed", type=int, default=1000)
    ap.add_argument("--parallel", type=int, default=1,
                    help="concurrent matches; default 1 for the owner's CPU cap (Bontago-1t5.20)")
    ap.add_argument("--seconds", type=float, default=300.0, help="--seconds= match bound")
    ap.add_argument("--timeout-s", type=float, default=900.0, help="hard wall-clock kill per match")
    ap.add_argument("--bots", type=int, default=8)
    ap.add_argument("--players", type=int, default=None, help="--players=N passive/human seats (E3/E4)")
    ap.add_argument("--mode", default=None, help="--mode=M match mode (classic|ctf|elimination|sky)")
    ap.add_argument("--no-swap", action="store_true",
                    help="run only the A-seat half of each seed; print one H2H seed= line per match")
    ap.add_argument("--battery", default=None, choices=["E1", "E2", "E3", "E4", "E5", "all"],
                    help="section 2.5 presets; only with --dry-run (prints their command lines)")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--cand-slots-a", default="0,2,4,6", help="candidate seats in the first match")
    ap.add_argument("--cand-slots-b", default="1,3,5,7", help="candidate seats in the swapped match")
    ap.add_argument("--godot-args", default="", help="seam template appended after `--` (see docstring)")
    ap.add_argument("--out-dir", default=".", help="where the candidate weights JSON is written")
    ap.add_argument("--dry-run", action="store_true", help="print the commands and exit")
    return ap


def main(argv: Optional[List[str]] = None, runner: Callable[[Sequence[str], float], str] = run_process) -> int:
    args = build_parser().parse_args(argv)

    if args.battery:
        if not args.dry_run:
            print("bot_h2h: --battery is dry-run only (its <...> placeholders must be filled in first).",
                  file=sys.stderr)
            return 2
        total = 0
        for preset in battery_presets(args.battery):
            jobs = plan_jobs(preset.pairs, args.base_seed, preset.slots_a, preset.slots_b, swap=preset.swap,
                             godot=args.godot, project=args.path, seconds=preset.seconds, bots=preset.bots,
                             godot_args=preset.template, weights_file="", weights_json="{}",
                             players=preset.players, mode=preset.mode)
            print("# %s %s" % (preset.label, preset.note))
            for j in jobs:
                print(" ".join(shlex.quote(c) for c in j.cmd))
            print("H2H DRY-RUN label=%s matches=%d" % (preset.label, len(jobs)))
            total += len(jobs)
        print("H2H DRY-RUN battery=%s matches=%d" % (args.battery, total))
        return 0

    if not args.godot_args and not args.dry_run and args.candidate is not None:
        print("bot_h2h: no --godot-args; the per-slot weight override + match seed seam (plan BT5 "
              "--bot-weights) does not exist yet. Pass --godot-args or use --dry-run.", file=sys.stderr)
        return 2
    template = args.godot_args or ("{seed} {weights_file} {cand_slots}" if args.candidate is not None
                                   else "--match-seed={seed}")
    if args.candidate is None and _WEIGHT_PLACEHOLDER.search(template):
        print("bot_h2h: --godot-args uses {weights_file}/{weights_json} but no --candidate was given.",
              file=sys.stderr)
        return 2
    if not args.dry_run and _TEMPLATE_PLACEHOLDER.search(template):
        print("bot_h2h: --godot-args still has a <...> placeholder; fill it in before launching.",
              file=sys.stderr)
        return 2

    weights_file = ""
    weights_json = "{}"
    if args.candidate is not None:
        weights = parse_candidate(args.candidate)
        os.makedirs(args.out_dir, exist_ok=True)
        weights_file = os.path.abspath(os.path.join(args.out_dir, "h2h_candidate_weights.json"))
        with open(weights_file, "w", encoding="utf-8") as fh:
            json.dump(weights, fh)
        weights_json = json.dumps(weights)
    jobs = plan_jobs(args.pairs, args.base_seed, args.cand_slots_a, args.cand_slots_b,
                     swap=not args.no_swap, godot=args.godot, project=args.path, seconds=args.seconds,
                     bots=args.bots, godot_args=template, weights_file=weights_file,
                     weights_json=weights_json, players=args.players, mode=args.mode)
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
    teams_a = _csv_ints(args.cand_slots_a)
    teams_b = _csv_ints(args.cand_slots_b)
    t = tally(jobs, outputs, teams_a, teams_b)
    decided = t["wins"] + t["losses"]
    lo, hi = wilson(t["wins"], decided)
    v = verdict(t["wins"], t["losses"], len(jobs))
    share = (t["wins"] / decided) if decided else float("nan")
    print("H2H matches=%d wins=%d losses=%d draws=%d (timeouts=%d) failed=%d" % (
        len(jobs), t["wins"], t["losses"], t["draws"], t["timeouts"], t["failed"]))
    print("H2H win_share=%.3f ci95=[%.3f, %.3f] gate>=%.2f over>=%d matches (match-level Wilson)" % (
        share, lo, hi, GATE_WIN_SHARE, GATE_MIN_MATCHES))
    times = win_times(jobs, outputs, teams_a, teams_b)
    if times:
        print("H2H candidate_win_time_s median=%.1f max=%.1f n=%d (game seconds)" % (
            statistics.median(times), max(times), len(times)))
    else:
        print("H2H candidate_win_time_s median=n/a max=n/a n=0 (game seconds)")
    if args.no_swap:
        for line in seed_lines(jobs, outputs, teams_a, teams_b):
            print(line)
    print("H2H RESULT %s" % v)
    return 0 if v == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
