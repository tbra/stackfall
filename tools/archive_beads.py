#!/usr/bin/env python3
"""Archive Beads issues that have been closed for at least N days (default 7).

Usage: python tools/archive_beads.py [--days N] [--apply] [--path <checkout>]

Dry-run by default: prints how many closed beads are old enough and how many `bd prune` would
remove. With --apply:
  1. appends the full `bd export` record (comments, dependencies and labels included) of every
     bead closed for at least N days to .beads/archive/closed.jsonl, one per id;
  2. runs `bd prune --older-than <N>d --force`, which skips pinned beads and beads that an open
     bead still cites (those stay on the board until nothing cites them);
  3. rewrites .beads/issues.jsonl with `bd export`: the git post-merge hook imports that file, and
     a stale copy re-imported pruned beads onto the board once.
The archive is local and untracked. Restore beads with `bd import <file>` on a JSONL holding their
lines from the archive.
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bd_cli  # noqa: E402

DEFAULT_DAYS = 7
ARCHIVE_REL = os.path.join(".beads", "archive", "closed.jsonl")
EXPORT_REL = os.path.join(".beads", "issues.jsonl")
ACTOR = "stackfall-orchestrator"
BD_TIMEOUT_S = 300


def bd(root, *args):
    """stdout of `bd <args>` run in `root`; raises on a non-zero exit."""
    proc = subprocess.run([bd_cli.bd_executable(), *args], cwd=root, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=BD_TIMEOUT_S)
    if proc.returncode != 0:
        raise RuntimeError("bd %s failed: %s" % (" ".join(args), (proc.stderr or proc.stdout).strip()[:400]))
    return proc.stdout


def parse_time(text):
    """An aware datetime from a Beads ISO 8601 timestamp, or None."""
    if not text:
        return None
    # Python 3.8 parses at most 6 fractional digits; Dolt may write nanoseconds.
    text = re.sub(r"(\.\d{6})\d+", r"\1", text.replace("Z", "+00:00"))
    try:
        stamp = datetime.datetime.fromisoformat(text)
    except ValueError:
        return None
    return stamp if stamp.tzinfo else stamp.replace(tzinfo=datetime.timezone.utc)


def due(records, days, now):
    """Closed, unpinned records whose closed_at is at least `days` days before `now`."""
    cutoff = now - datetime.timedelta(days=days)
    out = []
    for rec in records:
        closed = parse_time(rec.get("closed_at"))
        if rec.get("status") == "closed" and not rec.get("pinned") and closed is not None and closed <= cutoff:
            out.append(rec)
    return out


def append_archive(path, records):
    """Appends the records not yet in the archive at `path`; returns how many were new."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    known = set()
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if line.strip():
                    known.add(json.loads(line).get("id"))
    fresh = [r for r in records if r.get("id") not in known]
    with open(path, "a", encoding="utf-8", newline="\n") as fh:
        for rec in fresh:
            fh.write(json.dumps(rec, ensure_ascii=False) + "\n")
    return len(fresh)


def export_records(root):
    """Every issue as `bd export` writes it."""
    fd, tmp = tempfile.mkstemp(suffix=".jsonl")
    os.close(fd)
    try:
        bd(root, "export", "-o", tmp)
        with open(tmp, encoding="utf-8") as fh:
            return [json.loads(line) for line in fh if line.strip()]
    finally:
        os.remove(tmp)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--days", type=int, default=DEFAULT_DAYS)
    ap.add_argument("--apply", action="store_true", help="archive and prune (default: dry-run)")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path)
    if args.days < 1:
        print("ARCHIVE refused: --days must be at least 1")
        return 2

    records = export_records(root)
    old = due(records, args.days, datetime.datetime.now(datetime.timezone.utc))
    preview = json.loads(bd(root, "prune", "--older-than", "%dd" % args.days, "--dry-run", "--json"))
    prune_count = int(preview.get("prune_count", 0))
    kept = int(preview.get("referenced_count", 0))
    if prune_count > len(old):
        # The archive must hold everything prune deletes; a mismatch means the age rules differ.
        print("ARCHIVE refused: bd prune would delete %d beads but only %d are closed for %d+ days"
              % (prune_count, len(old), args.days))
        return 1
    if not args.apply:
        print("ARCHIVE dry-run: %d closed for %d+ days; prune would remove %d, %d stay (cited by open beads)"
              % (len(old), args.days, prune_count, kept))
        return 0

    archive = os.path.join(root, ARCHIVE_REL)
    added = append_archive(archive, old)
    if prune_count:
        bd(root, "--actor", ACTOR, "prune", "--older-than", "%dd" % args.days, "--force")
    bd(root, "export", "-o", os.path.join(root, EXPORT_REL))
    print("ARCHIVE applied: %d new in %s, %d pruned, %d stay (cited by open beads); %s refreshed"
          % (added, ARCHIVE_REL.replace(os.sep, "/"), prune_count, kept, EXPORT_REL.replace(os.sep, "/")))
    return 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main(sys.argv[1:]))
