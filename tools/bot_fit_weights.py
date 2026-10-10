#!/usr/bin/env python
"""T1 offline refit of the bot placement scorer's linear weights (Bontago-1t5.12).

Docs/BOT_TRAINING_SOAK_PLAN.md section 3 T1. Reads schema-v1 decision files
(tools/bot_dataset.py), and fits the four linear weights (height, goal,
stability, risk) with a listwise softmax objective:

    loss = sum_n  w_n * -log softmax_c( theta . f_nc + mode_nc )[chosen_n]
           / sum_n w_n  +  l2 * ||theta - theta0||^2

* f_nc are the signed unweighted scorer terms, so score = sum_k theta_k f_k
  (+ the mode term, which carries its own weights and is held fixed). Signs
  mirror BotPlacementScorer.score(): +height, -goal, +stability, -risk.
* w_n is the AWR-style outcome weight exp(adv_n / beta), clipped, where
  adv_n = d_share_30s minus the mean over the same (file, team, time bucket).
* theta0 are the shipped weights, read from config/BotTuning.gd defaults
  overlaid by config/bot_tuning.tres; the L2 pulls toward them.
* Solved with damped Newton (the objective is convex), pure stdlib.

Held-out matches (by file) report top-1 agreement with the recorded choice and
regret, for the shipped and the fitted weights. Honest limit: data from one
weight vector has weak identifiability; read the diff as a sanity check of
term scales and dead terms, then confirm with tools/bot_h2h.py.

Never edits config/. `--write-proposal <path>` writes the proposed values to
a file outside config/ only.

    python -I tools/bot_fit_weights.py <data dir|files> [--mode N] [--write-proposal out.txt]
"""

from __future__ import annotations

import argparse
import math
import os
import re
import sys
import zlib
from dataclasses import dataclass
from typing import Dict, List, Optional, Sequence, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bot_dataset as ds  # noqa: E402

FIT_NAMES: Tuple[str, ...] = ("weight_height", "weight_goal_progress", "weight_stability", "weight_risk")
# Sign of each fitted term inside BotPlacementScorer.score(): the goal and risk terms are subtracted.
FIT_SIGNS: Tuple[float, ...] = (1.0, -1.0, 1.0, -1.0)
MODE_TERM_INDEX = 4
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_EXPORT_RE = re.compile(r"@export\s+var\s+(weight_\w+)\s*:\s*float\s*=\s*(-?[0-9.]+)")
_TRES_RE = re.compile(r"^(weight_\w+)\s*=\s*(-?[0-9.eE+-]+)\s*$")


def read_shipped_weights(repo: str = REPO_ROOT) -> Dict[str, float]:
    """BotTuning.gd export defaults overlaid by [resource] overrides in config/bot_tuning.tres."""
    weights: Dict[str, float] = {}
    with open(os.path.join(repo, "config", "BotTuning.gd"), encoding="utf-8") as fh:
        for line in fh:
            m = _EXPORT_RE.match(line.strip())
            if m:
                weights[m.group(1)] = float(m.group(2))
    in_resource = False
    with open(os.path.join(repo, "config", "bot_tuning.tres"), encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line.startswith("["):
                in_resource = line == "[resource]"
                continue
            m = _TRES_RE.match(line) if in_resource else None
            if m:
                weights[m.group(1)] = float(m.group(2))
    missing = [n for n in FIT_NAMES if n not in weights]
    if missing:
        raise RuntimeError("shipped weights not found: %s" % ", ".join(missing))
    return weights


@dataclass
class Example:
    group: str          # file the decision came from
    w: float            # outcome weight
    adv: float
    feats: List[List[float]]   # per candidate, signed fitted terms
    offset: List[float]        # per candidate, fixed mode term
    chosen: int


def advantages(rows: Sequence[Tuple[str, int, float, float]], bucket_s: float) -> List[float]:
    """rows: (file, team, t, d_share). Advantage = d_share minus its (file, team, time bucket) mean."""
    sums: Dict[Tuple[str, int, int], List[float]] = {}
    keys: List[Tuple[str, int, int]] = []
    for f, team, t, d in rows:
        k = (f, team, int(t // bucket_s))
        keys.append(k)
        s = sums.setdefault(k, [0.0, 0.0])
        s[0] += d
        s[1] += 1.0
    return [d - sums[k][0] / sums[k][1] for k, (_, _, _, d) in zip(keys, rows)]


def build_examples(files: Sequence[ds.DatasetFile], mode: Optional[int] = None,
                   difficulty: Optional[str] = None, use_outcomes: bool = True,
                   bucket_s: float = 60.0, wmax: float = 5.0) -> List[Example]:
    picked: List[Tuple[str, dict]] = []
    for f in files:
        h = f.header or {}
        if mode is not None and h.get("mode") != mode:
            continue
        if difficulty is not None and h.get("difficulty") != difficulty:
            continue
        for row in ds.join_outcomes(f):
            if row.get("policy") == "special" or row["chosen"] < 0:
                continue
            if use_outcomes and (row["outcome"] is None or row["outcome"].get("complete") is False):
                continue
            picked.append((f.path, row))
    advs = [0.0] * len(picked)
    weights = [1.0] * len(picked)
    if use_outcomes and picked:
        advs = advantages([(p, r["team"], r["t"], r["outcome"]["d_share_30s"]) for p, r in picked], bucket_s)
        mean = sum(advs) / len(advs)
        beta = math.sqrt(sum((a - mean) ** 2 for a in advs) / len(advs)) or 1.0
        weights = [min(wmax, math.exp(a / beta)) for a in advs]
    out: List[Example] = []
    for (path, r), a, w in zip(picked, advs, weights):
        feats = [[s * c["terms"][k] for k, s in enumerate(FIT_SIGNS)] for c in r["cands"]]
        offset = [float(c["terms"][MODE_TERM_INDEX]) for c in r["cands"]]
        out.append(Example(path, w, a, feats, offset, r["chosen"]))
    return out


def split_examples(examples: Sequence[Example], holdout: float) -> Tuple[List[Example], List[Example]]:
    """Hold out whole matches (files) deterministically; one-file data splits by time order instead."""
    if holdout <= 0.0:
        return list(examples), []
    groups = sorted({e.group for e in examples})
    if len(groups) >= 2:
        step = max(2, round(1.0 / holdout))
        held = {g for i, g in enumerate(groups) if zlib.crc32(os.path.basename(g).encode()) % step == 0}
        if not held:
            held = {groups[-1]}
        if len(held) == len(groups):
            held = {groups[-1]}
        return [e for e in examples if e.group not in held], [e for e in examples if e.group in held]
    cut = int(len(examples) * (1.0 - holdout))
    return list(examples[:cut]), list(examples[cut:])


def _softmax(scores: List[float]) -> List[float]:
    m = max(scores)
    ex = [math.exp(s - m) for s in scores]
    z = sum(ex)
    return [e / z for e in ex]


def scores_for(e: Example, theta: Sequence[float]) -> List[float]:
    return [sum(t * f for t, f in zip(theta, fv)) + off for fv, off in zip(e.feats, e.offset)]


def objective(examples: Sequence[Example], theta: Sequence[float], theta0: Sequence[float], l2: float) -> float:
    total_w = sum(e.w for e in examples) or 1.0
    nll = 0.0
    for e in examples:
        s = scores_for(e, theta)
        m = max(s)
        lse = m + math.log(sum(math.exp(x - m) for x in s))
        nll += e.w * (lse - s[e.chosen])
    reg = l2 * sum((t - t0) ** 2 for t, t0 in zip(theta, theta0))
    return nll / total_w + reg


def gradient_hessian(examples: Sequence[Example], theta: Sequence[float], theta0: Sequence[float],
                     l2: float) -> Tuple[List[float], List[List[float]]]:
    k = len(theta)
    total_w = sum(e.w for e in examples) or 1.0
    g = [0.0] * k
    h = [[0.0] * k for _ in range(k)]
    for e in examples:
        p = _softmax(scores_for(e, theta))
        mean = [0.0] * k
        for pc, fv in zip(p, e.feats):
            for a in range(k):
                mean[a] += pc * fv[a]
        cov = [[0.0] * k for _ in range(k)]
        for pc, fv in zip(p, e.feats):
            d = [fv[a] - mean[a] for a in range(k)]
            for a in range(k):
                for b in range(a, k):
                    cov[a][b] += pc * d[a] * d[b]
        wn = e.w / total_w
        fc = e.feats[e.chosen]
        for a in range(k):
            g[a] += wn * (mean[a] - fc[a])
            for b in range(a, k):
                h[a][b] += wn * cov[a][b]
    for a in range(k):
        g[a] += 2.0 * l2 * (theta[a] - theta0[a])
        h[a][a] += 2.0 * l2
        for b in range(a):
            h[a][b] = h[b][a]
    return g, h


def solve_linear(a: List[List[float]], b: List[float]) -> List[float]:
    n = len(b)
    m = [row[:] + [b[i]] for i, row in enumerate(a)]
    for c in range(n):
        piv = max(range(c, n), key=lambda r: abs(m[r][c]))
        if abs(m[piv][c]) < 1e-12:
            raise ZeroDivisionError("singular Hessian (raise --l2)")
        m[c], m[piv] = m[piv], m[c]
        for r in range(c + 1, n):
            f = m[r][c] / m[c][c]
            for j in range(c, n + 1):
                m[r][j] -= f * m[c][j]
    x = [0.0] * n
    for r in range(n - 1, -1, -1):
        x[r] = (m[r][n] - sum(m[r][j] * x[j] for j in range(r + 1, n))) / m[r][r]
    return x


def fit(examples: Sequence[Example], theta0: Sequence[float], l2: float = 1e-3,
        max_iter: int = 50, tol: float = 1e-9) -> List[float]:
    theta = list(theta0)
    cur = objective(examples, theta, theta0, l2)
    for _ in range(max_iter):
        g, h = gradient_hessian(examples, theta, theta0, l2)
        step = solve_linear(h, g)
        t = 1.0
        while t > 1e-6:
            cand = [x - t * s for x, s in zip(theta, step)]
            val = objective(examples, cand, theta0, l2)
            if val <= cur:
                break
            t *= 0.5
        else:
            break
        improvement = cur - val
        theta, cur = cand, val
        if improvement < tol:
            break
    return theta


def evaluate(examples: Sequence[Example], theta: Sequence[float], ref: Sequence[float]) -> Dict[str, float]:
    """Top-1 agreement with the recorded choice; regret in score units under theta;
    ref_regret = regret of theta's pick under the reference (shipped) weights."""
    n = len(examples)
    if n == 0:
        return {"n": 0, "top1": float("nan"), "top1_adv_weighted": float("nan"),
                "regret": float("nan"), "ref_regret": float("nan")}
    hit = whit = wsum = regret = ref_regret = 0.0
    for e in examples:
        s = scores_for(e, theta)
        pick = max(range(len(s)), key=lambda i: s[i])
        ok = 1.0 if (pick == e.chosen or s[pick] == s[e.chosen]) else 0.0
        hit += ok
        whit += e.w * ok
        wsum += e.w
        regret += s[pick] - s[e.chosen]
        r = scores_for(e, ref)
        ref_regret += r[max(range(len(r)), key=lambda i: r[i])] - r[pick]
    return {"n": n, "top1": hit / n, "top1_adv_weighted": whit / wsum,
            "regret": regret / n, "ref_regret": ref_regret / n}


def dead_terms(examples: Sequence[Example]) -> List[str]:
    """Fitted terms whose value never varies across candidates inside a decision."""
    out: List[str] = []
    for k, name in enumerate(FIT_NAMES):
        spread = 0.0
        for e in examples:
            vals = [fv[k] for fv in e.feats]
            spread = max(spread, max(vals) - min(vals))
        if spread < 1e-9:
            out.append(name)
    return out


def format_diff(old: Dict[str, float], new: Sequence[float]) -> str:
    lines = ["%-24s %9s %9s %9s %8s" % ("weight", "shipped", "fitted", "delta", "pct")]
    for name, n in zip(FIT_NAMES, new):
        o = old[name]
        pct = ("%+.1f%%" % (100.0 * (n - o) / o)) if o else "n/a"
        lines.append("%-24s %9.4f %9.4f %+9.4f %8s" % (name, o, n, n - o, pct))
    return "\n".join(lines)


def write_proposal(path: str, new: Sequence[float], repo: str = REPO_ROOT) -> None:
    target = os.path.normcase(os.path.abspath(path))
    cfg = os.path.normcase(os.path.abspath(os.path.join(repo, "config")))
    try:
        inside = os.path.commonpath([target, cfg]) == cfg
    except ValueError:  # different drives
        inside = False
    if inside:
        raise ValueError("refusing to write a proposal under config/ (%s)" % target)
    with open(target, "w", encoding="utf-8") as fh:
        fh.write("# Proposed BotTuning weights (T1 refit). NOT applied; review, then H2H-gate.\n")
        for name, v in zip(FIT_NAMES, new):
            fh.write("%s = %.4f\n" % (name, v))


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="T1 offline refit of the bot scorer's linear weights.")
    ap.add_argument("paths", nargs="+", help="dataset files / directories / globs")
    ap.add_argument("--mode", type=int, default=None, help="only matches with this header mode")
    ap.add_argument("--difficulty", default=None, help="only matches with this header difficulty")
    ap.add_argument("--l2", type=float, default=1e-3, help="L2 strength toward shipped weights")
    ap.add_argument("--holdout", type=float, default=0.2, help="fraction of matches held out")
    ap.add_argument("--uniform-weights", action="store_true",
                    help="ignore outcomes (every decision weight 1); needed when no outcome records exist")
    ap.add_argument("--bucket-s", type=float, default=60.0, help="advantage baseline time bucket (s)")
    ap.add_argument("--repo", default=REPO_ROOT, help="checkout to read shipped weights from")
    ap.add_argument("--write-proposal", metavar="PATH", default=None,
                    help="write proposed weights to PATH (must be outside config/)")
    args = ap.parse_args(argv)

    files = ds.load_many(args.paths)
    bad = [e for f in files for e in f.errors]
    if bad:
        for e in bad[:10]:
            print(e, file=sys.stderr)
        print("dataset fails schema v1 validation (%d errors); fix before fitting" % len(bad), file=sys.stderr)
        return 2
    shipped = read_shipped_weights(args.repo)
    theta0 = [shipped[n] for n in FIT_NAMES]
    examples = build_examples(files, args.mode, args.difficulty, use_outcomes=not args.uniform_weights,
                              bucket_s=args.bucket_s)
    if not examples:
        print("no usable decisions (filters / missing outcomes; try --uniform-weights)", file=sys.stderr)
        return 2
    for f in files:
        hw = (f.header or {}).get("weights", {})
        diff = [n for n in FIT_NAMES if n[len("weight_"):] in hw and abs(hw[n[len("weight_"):]] - shipped[n]) > 1e-9]
        if diff:
            print("note: %s was recorded with weights differing from the shipped ones (%s); L2 anchors to shipped"
                  % (os.path.basename(f.path), ", ".join(diff)))
    train, held = split_examples(examples, args.holdout)
    theta = fit(train, theta0, l2=args.l2)
    print("decisions: train=%d heldout=%d (files=%d)" % (len(train), len(held), len(files)))
    dead = dead_terms(train)
    if dead:
        print("dead terms (constant within every decision, not identifiable): %s" % ", ".join(dead))
    print(format_diff(shipped, theta))
    for label, th in (("shipped", theta0), ("fitted ", theta)):
        for split, data in (("train  ", train), ("heldout", held)):
            m = evaluate(data, th, theta0)
            print("%s %s n=%d top1=%.3f top1_adv_weighted=%.3f regret=%.4f regret_vs_shipped=%.4f" % (
                label, split, m["n"], m["top1"], m["top1_adv_weighted"], m["regret"], m["ref_regret"]))
    if args.write_proposal:
        write_proposal(args.write_proposal, theta, args.repo)
        print("proposal written: %s (config/ untouched)" % args.write_proposal)
    return 0


if __name__ == "__main__":
    sys.exit(main())
