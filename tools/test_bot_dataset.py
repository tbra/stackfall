#!/usr/bin/env python
"""Tests for bot_dataset.py and bot_fit_weights.py (Bontago-1t5.12). bot_h2h tests: test_bot_h2h.py.

Fixtures are generated here (schema v1 per docs/BOT_TRAINING_SOAK_PLAN.md
section 1); no Godot needed. Run with:
    python tools/test_bot_dataset.py
"""

from __future__ import annotations

import contextlib
import io
import json
import math
import os
import random
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bot_dataset as ds  # noqa: E402
import bot_fit_weights as fw  # noqa: E402
import bot_h2h as h2h  # noqa: E402

N_CANDS = 20
NL = chr(10)
SIGNS = fw.FIT_SIGNS


def header(seed: int = 1, mode: int = 0) -> dict:
    return {"kind": "header", "schema_version": 1, "seed": seed, "mode": mode, "map_id": "m",
            "bot_count": 8, "difficulty": "hard", "weights": {"height": 1.0},
            "git_revision": "abc"}


def candidate(rng: random.Random) -> dict:
    terms = [round(rng.uniform(0.0, 4.0), 3) for _ in range(4)] + [round(rng.uniform(-0.5, 0.5), 3)]
    return {"o": [0.0, 0.0], "r": 0, "h": 1.0, "sh": 1.0, "ct": 2, "top": False, "terms": terms}


def decision(i: int, cands: list, chosen: int, slot: int = 0, t: float = 1.0) -> dict:
    return {"kind": "decision", "id": i, "t": t, "slot": slot, "team": slot, "shape_id": "cube", "policy": "score",
            "feed_seq": i, "piece_index": i, "cands": cands, "chosen": chosen,
            "placed_origin": [0.0, 0.0], "reason": "ok", "scored_best": chosen}


def synth_file(path: str, theta_true: list, n: int, seed: int, with_outcomes: bool = False) -> None:
    rng = random.Random(seed)
    lines = [header(seed)]
    for i in range(n):
        cands = [candidate(rng) for _ in range(N_CANDS)]
        s = [sum(th * sg * c["terms"][k] for k, (th, sg) in enumerate(zip(theta_true, SIGNS)))
             + c["terms"][4] for c in cands]
        m = max(s)
        p = [math.exp(x - m) for x in s]
        pick = rng.choices(range(N_CANDS), weights=p)[0]
        lines.append(decision(i, cands, pick, slot=i % 2, t=float(i)))
        if with_outcomes:
            lines.append({"kind": "outcome", "id": i, "d_share_10s": 0.0,
                          "d_share_30s": rng.uniform(-0.02, 0.02), "d_share_60s": 0.0})
    lines.append({"kind": "match_end", "slot": 0, "winner_team": 0, "final_share": 0.4, "won": True})
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("\n".join(json.dumps(x) for x in lines) + "\n")


class ValidatorTests(unittest.TestCase):
    def good_decision(self) -> dict:
        rng = random.Random(0)
        return decision(0, [candidate(rng) for _ in range(3)], 1)

    def test_good_records_pass(self) -> None:
        self.assertEqual(ds.validate_record(header()), [])
        self.assertEqual(ds.validate_record(self.good_decision()), [])

    def test_rejects_bad_schema_version(self) -> None:
        h = header()
        h["schema_version"] = 2
        self.assertTrue(ds.validate_record(h))

    def test_rejects_missing_and_mistyped_fields(self) -> None:
        d = self.good_decision()
        del d["reason"]
        self.assertTrue(any("reason" in e for e in ds.validate_record(d)))
        d = self.good_decision()
        d["cands"][0]["terms"] = [1.0, 2.0]
        self.assertTrue(ds.validate_record(d))
        d = self.good_decision()
        d["chosen"] = 99
        self.assertTrue(any("chosen" in e for e in ds.validate_record(d)))
        d = self.good_decision()
        d["slot"] = True  # bool is not an int
        self.assertTrue(ds.validate_record(d))
        self.assertTrue(ds.validate_record({"kind": "mystery"}))

    def test_file_level_errors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "a.jsonl")
            rng = random.Random(0)
            with open(p, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(decision(0, [candidate(rng)], 0)) + "\n")  # no header first
                fh.write("{not json\n")
                fh.write(json.dumps({"kind": "outcome", "id": 77, "d_share_10s": 0, "d_share_30s": 0,
                                     "d_share_60s": 0}) + "\n")
            df = ds.load_file(p)
            joined = " | ".join(df.errors)
            self.assertIn("invalid JSON", joined)
            self.assertIn("no header", joined)
            self.assertTrue(any("absent from the file" in w for w in df.warnings))
            with contextlib.redirect_stdout(io.StringIO()) as out:
                rc = ds.main(["validate", p])
            self.assertEqual(rc, 1)
            self.assertIn("VALIDATE FAIL", out.getvalue())


def real_sample() -> str:
    repo = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    landed = os.path.join(repo, "tests", "fixtures", "bot_record_sample.jsonl")
    return landed if os.path.exists(landed) else os.path.join(repo, "tools", "test_data", "bot_record_sample.jsonl")


class RealSampleTests(unittest.TestCase):
    """The recorder's own trimmed output (BotDecisionRecorder, schema v1)."""

    def test_validate_summarise_join(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(ds.main(["validate", real_sample()]), 0)
        self.assertIn("VALIDATE OK", out.getvalue())
        df = ds.load_file(real_sample())
        summary = ds.summarise([df])
        self.assertEqual(summary["decisions"], 8)
        self.assertEqual(summary["decisions_with_outcome"], 8)
        self.assertEqual(summary["chosen_ne_scored_best"], 0)
        self.assertEqual(summary["footer_policy_mismatch"], [0])
        self.assertTrue(all(r["match_end"] is not None for r in ds.join_outcomes(df)))

    def test_dangling_outcome_warns_but_id_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            lines = open(real_sample(), encoding="utf-8").read().splitlines()
            dec = [i for i, l in enumerate(lines) if '"kind":"decision"' in l][0]
            trimmed = os.path.join(tmp, "trim.jsonl")
            with open(trimmed, "w", encoding="utf-8") as fh:
                fh.write(NL.join(lines[:dec] + lines[dec + 1:]))
            df = ds.load_file(trimmed)
            self.assertEqual(df.errors, [])
            self.assertEqual(len(df.warnings), 1)
            drift = os.path.join(tmp, "drift.jsonl")
            with open(drift, "w", encoding="utf-8") as fh:
                fh.write(NL.join(l.replace('"kind":"decision","id":6', '"kind":"decision","id":"6"')
                                   for l in lines))
            self.assertTrue(ds.load_file(drift).errors)

    def test_t1_fit_smoke(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            with contextlib.redirect_stdout(io.StringIO()) as out:
                rc = fw.main([real_sample(), "--holdout", "0.25", "--write-proposal", os.path.join(tmp, "p.txt")])
            self.assertEqual(rc, 0)
            self.assertIn("heldout", out.getvalue())
            self.assertIn("weight_stability", out.getvalue())


class JoinTests(unittest.TestCase):
    def test_join_outcome_by_id_and_match_end_by_slot(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = os.path.join(tmp, "a.jsonl")
            rng = random.Random(0)
            recs = [header(),
                    decision(10, [candidate(rng)], 0, slot=0),
                    decision(11, [candidate(rng)], 0, slot=1),
                    {"kind": "outcome", "id": 11, "d_share_10s": 0.01, "d_share_30s": 0.02, "d_share_60s": 0.03},
                    {"kind": "match_end", "slot": 1, "winner_team": 1, "final_share": 0.5, "won": True}]
            with open(p, "w", encoding="utf-8") as fh:
                fh.write("\n".join(json.dumps(r) for r in recs))
            df = ds.load_file(p)
            self.assertEqual(df.errors, [])
            rows = {r["id"]: r for r in ds.join_outcomes(df)}
            self.assertIsNone(rows[10]["outcome"])
            self.assertIsNone(rows[10]["match_end"])
            self.assertEqual(rows[11]["outcome"]["d_share_30s"], 0.02)
            self.assertTrue(rows[11]["match_end"]["won"])
            summary = ds.summarise([df])
            self.assertEqual(summary["decisions"], 2)
            self.assertEqual(summary["decisions_with_outcome"], 1)
            self.assertEqual(ds.size_report([df])["decisions"], 2)


class FitTests(unittest.TestCase):
    def test_fit_recovers_known_weights_and_prints_heldout(self) -> None:
        shipped = fw.read_shipped_weights()
        theta0 = [shipped[n] for n in fw.FIT_NAMES]
        theta_true = [theta0[0] * 1.6, theta0[1] * 0.6, theta0[2] * 1.3, theta0[3] * 2.0]
        with tempfile.TemporaryDirectory() as tmp:
            for k in range(5):
                synth_file(os.path.join(tmp, "m%d.jsonl" % k), theta_true, 400, seed=k)
            files = ds.load_many([tmp])
            self.assertEqual([e for f in files for e in f.errors], [])
            examples = fw.build_examples(files, use_outcomes=False)
            train, held = fw.split_examples(examples, 0.2)
            self.assertTrue(train and held)
            self.assertFalse({e.group for e in train} & {e.group for e in held})
            theta = fw.fit(train, theta0, l2=1e-6)
            for got, want in zip(theta, theta_true):
                self.assertAlmostEqual(got / want, 1.0, delta=0.12, msg="%s vs %s" % (theta, theta_true))
            fitted = fw.evaluate(held, theta, theta0)
            shipped_m = fw.evaluate(held, theta0, theta0)
            print("\n  held-out top1: shipped=%.3f fitted=%.3f (n=%d); fitted theta=%s" % (
                shipped_m["top1"], fitted["top1"], fitted["n"], [round(x, 3) for x in theta]))
            self.assertGreater(fitted["top1"], shipped_m["top1"])
            self.assertEqual(fw.dead_terms(train), [])

    def test_outcome_weights_and_cli_proposal(self) -> None:
        theta0 = [fw.read_shipped_weights()[n] for n in fw.FIT_NAMES]
        with tempfile.TemporaryDirectory() as tmp:
            for k in range(3):
                synth_file(os.path.join(tmp, "m%d.jsonl" % k), theta0, 150, seed=10 + k, with_outcomes=True)
            files = ds.load_many([tmp])
            ex = fw.build_examples(files)
            self.assertEqual(len(ex), 450)
            self.assertTrue(all(0.0 < e.w <= 5.0 for e in ex))
            prop = os.path.join(tmp, "out", "proposal.txt")
            os.makedirs(os.path.dirname(prop))
            with contextlib.redirect_stdout(io.StringIO()) as out:
                rc = fw.main([tmp, "--write-proposal", prop])
            self.assertEqual(rc, 0)
            self.assertIn("heldout", out.getvalue())
            self.assertIn("weight_height", out.getvalue())
            self.assertEqual(set(h2h.parse_candidate(prop)), set(fw.FIT_NAMES))

    def test_proposal_refuses_config_dir(self) -> None:
        with self.assertRaises(ValueError):
            fw.write_proposal(os.path.join(fw.REPO_ROOT, "config", "x.txt"), [1, 1, 1, 1])

    def test_dead_term_detected(self) -> None:
        e = fw.Example("f", 1.0, 0.0, [[1.0, 0.0, 2.0, 0.0], [2.0, 0.0, 1.0, 0.0]], [0.0, 0.0], 0)
        self.assertEqual(fw.dead_terms([e]), ["weight_goal_progress", "weight_risk"])

    def test_shipped_weights_read_from_repo(self) -> None:
        w = fw.read_shipped_weights()
        self.assertEqual(w["weight_stability"], 2.0)
        self.assertEqual(w["weight_goal_progress"], 1.5)

    def test_help_runs(self) -> None:
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(SystemExit) as cm:
                fw.main(["--help"])
        self.assertEqual(cm.exception.code, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
