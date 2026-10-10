#!/usr/bin/env python
"""Bot decision dataset tooling (Bontago-1t5.12 / BT4).

Reads the JSONL files written by the BotDecisionRecorder (schema v1 --
docs/BOT_TRAINING_SOAK_PLAN.md section 1), validates them strictly, joins
outcome / match_end records onto decisions, and prints summaries and a size
report. Pure stdlib; `.jsonl` and `.jsonl.gz` both work.

    python -I tools/bot_dataset.py validate <file|dir> [...]
    python -I tools/bot_dataset.py summarise <file|dir> [...]
    python -I tools/bot_dataset.py size <file|dir> [...]

Schema v1 as implemented here (the contract; drift is reported, not guessed):
  header     {"kind":"header","schema_version":1,"seed","mode","map_id",
              "bot_count","difficulty","weights":{weight_*: float},
              "git_revision"}                     (first line)
  decision   {"kind":"decision","id","t","slot","team","shape_id","feed_seq",
              "piece_index","cands":[{"o":[x,z],"r","h","sh","ct","top",
              "terms":[height,goal,stability,risk,mode]}],"chosen",
              "placed_origin":[x,z],"reason","scored_best"}
              optional "policy":"special" (trainers drop these) plus state
              fields (own_share, enemy_share, ...) which are type-checked when
              present but not required.
  outcome    {"kind":"outcome","id","d_share_10s","d_share_30s","d_share_60s",
              "placed_block_alive_60s","home_alive_60s"}
  match_end  {"kind":"match_end","slot","winner_team","final_share","won",
              "eliminated_at"}
  footer     {"kind":"footer","policy_mismatch":int,...}   (optional)

The exact key names for header fields, the decision `id` (the join key the
outcome record carries) and the state fields are inferred from plan section 1;
the real sample (tests/fixtures/bot_record_sample.jsonl) should be validated
against this tool as soon as it lands and any naming drift fixed here.
"""

from __future__ import annotations

import argparse
import glob
import gzip
import json
import os
import sys
from dataclasses import dataclass, field
from typing import Any, Dict, Iterable, List, Optional, Tuple

SCHEMA_VERSION = 1
TERM_NAMES: Tuple[str, ...] = ("height", "goal", "stability", "risk", "mode")
KINDS = ("header", "decision", "outcome", "match_end", "footer")
DECISION_KEYS = (
    "id", "t", "slot", "team", "shape_id", "feed_seq", "piece_index",
    "cands", "chosen", "placed_origin", "reason", "scored_best",
)
HEADER_KEYS = ("schema_version", "seed", "mode", "map_id", "bot_count",
               "difficulty", "weights", "git_revision")
OUTCOME_KEYS = ("id", "d_share_10s", "d_share_30s", "d_share_60s")
MATCH_END_KEYS = ("slot", "winner_team", "final_share", "won")
OPTIONAL_STATE_NUMBERS = (
    "own_share", "enemy_share", "own_blocks", "own_tower_max_height",
    "enemies_alive", "nearest_enemy_dist", "active_specials",
)


def _is_num(v: Any) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _is_int(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_pair(v: Any) -> bool:
    return isinstance(v, list) and len(v) == 2 and all(_is_num(x) for x in v)


def validate_record(rec: Any) -> List[str]:
    """Return a list of schema-v1 violations for one parsed JSONL record."""
    if not isinstance(rec, dict):
        return ["record is not an object"]
    kind = rec.get("kind")
    if kind not in KINDS:
        return ["unknown kind %r" % (kind,)]
    errs: List[str] = []
    required = {"header": HEADER_KEYS, "decision": DECISION_KEYS,
                "outcome": OUTCOME_KEYS, "match_end": MATCH_END_KEYS,
                "footer": ()}[kind]
    for key in required:
        if key not in rec:
            errs.append("%s: missing %r" % (kind, key))
    if errs:
        return errs
    if kind == "header":
        if not _is_int(rec["schema_version"]) or rec["schema_version"] != SCHEMA_VERSION:
            errs.append("header: schema_version must be %d, got %r" % (SCHEMA_VERSION, rec["schema_version"]))
        w = rec["weights"]
        if not isinstance(w, dict) or not all(_is_num(v) for v in w.values()):
            errs.append("header: weights must be an object of numbers")
    elif kind == "decision":
        errs.extend(_validate_decision(rec))
    elif kind == "outcome":
        for key in ("d_share_10s", "d_share_30s", "d_share_60s"):
            if not _is_num(rec[key]):
                errs.append("outcome: %s not a number" % key)
    elif kind == "match_end":
        if not _is_int(rec["slot"]):
            errs.append("match_end: slot not an int")
        if not _is_num(rec["final_share"]):
            errs.append("match_end: final_share not a number")
        if not isinstance(rec["won"], bool):
            errs.append("match_end: won not a bool")
    elif kind == "footer":
        pm = rec.get("policy_mismatch")
        if pm is not None and not _is_int(pm):
            errs.append("footer: policy_mismatch not an int")
    return errs


def _validate_decision(rec: Dict[str, Any]) -> List[str]:
    errs: List[str] = []
    if not _is_num(rec["t"]):
        errs.append("decision: t not a number")
    for key in ("slot", "team", "feed_seq", "piece_index"):
        if not _is_int(rec[key]):
            errs.append("decision: %s not an int" % key)
    if not isinstance(rec["shape_id"], str):
        errs.append("decision: shape_id not a string")
    if "policy" in rec and rec["policy"] not in ("special", "ordinary"):
        errs.append("decision: policy %r unknown" % (rec["policy"],))
    for key in OPTIONAL_STATE_NUMBERS:
        if key in rec and not _is_num(rec[key]):
            errs.append("decision: %s not a number" % key)
    if not _is_pair(rec["placed_origin"]):
        errs.append("decision: placed_origin not [x,z]")
    cands = rec["cands"]
    if not isinstance(cands, list) or not cands:
        return errs + ["decision: cands must be a non-empty array"]
    for i, c in enumerate(cands):
        cerrs = _validate_cand(i, c)
        if cerrs:
            errs.extend(cerrs)
            break
    for key in ("chosen", "scored_best"):
        v = rec[key]
        if not _is_int(v) or not 0 <= v < len(cands):
            errs.append("decision: %s %r out of range for %d cands" % (key, v, len(cands)))
    return errs


def _validate_cand(i: int, c: Any) -> List[str]:
    if not isinstance(c, dict):
        return ["cands[%d] not an object" % i]
    missing = ["cands[%d]: missing %r" % (i, k) for k in ("o", "r", "h", "sh", "ct", "top", "terms") if k not in c]
    if missing:
        return missing
    errs: List[str] = []
    if not _is_pair(c["o"]):
        errs.append("cands[%d].o not [x,z]" % i)
    if not _is_int(c["r"]) or not _is_int(c["ct"]):
        errs.append("cands[%d]: r/ct must be ints" % i)
    if not _is_num(c["h"]) or not _is_num(c["sh"]):
        errs.append("cands[%d]: h/sh must be numbers" % i)
    if not isinstance(c["top"], bool):
        errs.append("cands[%d].top not a bool" % i)
    t = c["terms"]
    if not (isinstance(t, list) and len(t) == len(TERM_NAMES) and all(_is_num(x) for x in t)):
        errs.append("cands[%d].terms must be %d numbers" % (i, len(TERM_NAMES)))
    return errs


# ---------------------------------------------------------------- loading

def _open(path: str):
    if path.endswith(".gz"):
        return gzip.open(path, "rt", encoding="utf-8")
    return open(path, "r", encoding="utf-8")


def expand_paths(inputs: Iterable[str]) -> List[str]:
    out: List[str] = []
    for p in inputs:
        if os.path.isdir(p):
            for pat in ("*.jsonl", "*.jsonl.gz"):
                out.extend(sorted(glob.glob(os.path.join(p, "**", pat), recursive=True)))
        elif any(ch in p for ch in "*?["):
            out.extend(sorted(glob.glob(p, recursive=True)))
        else:
            out.append(p)
    return out


@dataclass
class DatasetFile:
    path: str
    header: Optional[Dict[str, Any]] = None
    decisions: List[Dict[str, Any]] = field(default_factory=list)
    outcomes: Dict[Any, Dict[str, Any]] = field(default_factory=dict)
    match_ends: Dict[int, Dict[str, Any]] = field(default_factory=dict)
    footer: Optional[Dict[str, Any]] = None
    errors: List[str] = field(default_factory=list)
    lines: int = 0
    size_bytes: int = 0


def load_file(path: str) -> DatasetFile:
    """Parse one file, collecting every schema violation as 'path:line: msg'."""
    df = DatasetFile(path=path, size_bytes=os.path.getsize(path))
    with _open(path) as fh:
        for lineno, raw in enumerate(fh, start=1):
            raw = raw.strip()
            if not raw:
                continue
            df.lines += 1
            try:
                rec = json.loads(raw)
            except json.JSONDecodeError as exc:
                df.errors.append("%s:%d: invalid JSON (%s)" % (path, lineno, exc.msg))
                continue
            errs = validate_record(rec)
            for e in errs:
                df.errors.append("%s:%d: %s" % (path, lineno, e))
            if errs:
                continue
            kind = rec["kind"]
            if kind == "header":
                if df.header is not None:
                    df.errors.append("%s:%d: second header" % (path, lineno))
                elif df.lines != 1:
                    df.errors.append("%s:%d: header must be the first line" % (path, lineno))
                else:
                    df.header = rec
            elif kind == "decision":
                df.decisions.append(rec)
            elif kind == "outcome":
                if rec["id"] in df.outcomes:
                    df.errors.append("%s:%d: duplicate outcome id %r" % (path, lineno, rec["id"]))
                df.outcomes[rec["id"]] = rec
            elif kind == "match_end":
                df.match_ends[rec["slot"]] = rec
            elif kind == "footer":
                df.footer = rec
    if df.header is None and not any(": header" in e or "kind" in e for e in df.errors):
        df.errors.append("%s: no header record" % path)
    ids = [d["id"] for d in df.decisions]
    if len(set(map(str, ids))) != len(ids):
        df.errors.append("%s: duplicate decision ids" % path)
    unknown = {str(k) for k in df.outcomes} - {str(i) for i in ids}
    if unknown:
        df.errors.append("%s: %d outcome(s) reference unknown decision ids" % (path, len(unknown)))
    return df


def join_outcomes(df: DatasetFile) -> List[Dict[str, Any]]:
    """Decisions copied with 'outcome' (by id, or None) and 'match_end' (by slot, or None)."""
    joined: List[Dict[str, Any]] = []
    for d in df.decisions:
        row = dict(d)
        row["outcome"] = df.outcomes.get(d["id"])
        row["match_end"] = df.match_ends.get(d["slot"])
        joined.append(row)
    return joined


def load_many(inputs: Iterable[str]) -> List[DatasetFile]:
    return [load_file(p) for p in expand_paths(inputs)]


# ---------------------------------------------------------------- reports

def summarise(files: List[DatasetFile]) -> Dict[str, Any]:
    n_dec = sum(len(f.decisions) for f in files)
    specials = sum(1 for f in files for d in f.decisions if d.get("policy") == "special")
    with_outcome = sum(1 for f in files for d in join_outcomes(f) if d["outcome"] is not None)
    cand_counts = [len(d["cands"]) for f in files for d in f.decisions]
    modes: Dict[str, int] = {}
    for f in files:
        key = str(f.header.get("mode")) if f.header else "?"
        modes[key] = modes.get(key, 0) + len(f.decisions)
    mismatches = sum(
        1 for f in files for d in f.decisions
        if d.get("policy") != "special" and d["scored_best"] != d["chosen"]
    )
    footer_pm = [f.footer.get("policy_mismatch") for f in files if f.footer and "policy_mismatch" in f.footer]
    wins = sum(1 for f in files for m in f.match_ends.values() if m["won"])
    return {
        "files": len(files),
        "decisions": n_dec,
        "special_decisions": specials,
        "decisions_with_outcome": with_outcome,
        "match_end_records": sum(len(f.match_ends) for f in files),
        "winning_bots": wins,
        "mean_candidates": (sum(cand_counts) / len(cand_counts)) if cand_counts else 0.0,
        "decisions_by_mode": modes,
        "chosen_ne_scored_best": mismatches,
        "footer_policy_mismatch": footer_pm,
        "schema_errors": sum(len(f.errors) for f in files),
    }


def size_report(files: List[DatasetFile]) -> Dict[str, Any]:
    total = sum(f.size_bytes for f in files)
    n_dec = sum(len(f.decisions) for f in files)
    return {
        "files": len(files),
        "total_bytes": total,
        "total_mb": round(total / 1e6, 3),
        "decisions": n_dec,
        "bytes_per_decision": round(total / n_dec, 1) if n_dec else None,
        "largest": sorted(((f.size_bytes, f.path) for f in files), reverse=True)[:3],
    }


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description="Validate / summarise bot decision datasets (schema v1).")
    ap.add_argument("command", choices=("validate", "summarise", "size"))
    ap.add_argument("paths", nargs="+", help="files, directories or globs (.jsonl / .jsonl.gz)")
    ap.add_argument("--max-errors", type=int, default=20, help="errors printed by validate")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args(argv)
    files = load_many(args.paths)
    if not files:
        print("no dataset files found", file=sys.stderr)
        return 2
    if args.command == "validate":
        errs = [e for f in files for e in f.errors]
        for e in errs[: args.max_errors]:
            print(e)
        print("VALIDATE %s files=%d errors=%d" % ("FAIL" if errs else "OK", len(files), len(errs)))
        return 1 if errs else 0
    result = summarise(files) if args.command == "summarise" else size_report(files)
    if args.json:
        print(json.dumps(result, indent=2, default=str))
    else:
        for k, v in result.items():
            print("%s: %s" % (k, v))
    return 1 if any(f.errors for f in files) else 0


if __name__ == "__main__":
    sys.exit(main())
