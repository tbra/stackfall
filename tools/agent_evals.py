"""Agent-setup evals: run a fixed set of past work packages against the current agent setup and score them.

Usage: python tools/agent_evals.py verify|prep|score|card ... (see --help of each)

Each eval in the evals manifest names a base commit, the accepted commit that
carries the hidden checks, and a brief. `prep` makes a worktree at the base with the setup
under test overlaid; after the worker is done `score` snapshots the candidate, applies the
hidden checks from the accepted commit, runs them and records one result per run; `card`
renders the scorecard; `verify` proves each eval's hidden checks are RED on the base and
GREEN on the accepted commit. Reuses tools/session_metrics.py for diff, guard and
mutation numbers.
"""
import argparse
import json
import os
import subprocess
import sys
from typing import Any, Dict, List, NamedTuple, Optional, Sequence

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)

MANIFEST_REQUIRED = ("area", "base", "accepted", "brief", "hidden", "regression",
                     "interface_lines", "runner")
MANIFEST_OPTIONAL = ("lint_floor",)
RUNNERS = ("gut", "unittest")
LIST_KEYS = ("hidden", "regression", "interface_lines")


class CheckResult(NamedTuple):
    """Outcome of run_checks: pass/fail counts for hidden and regression checks, per script."""
    hidden_pass: int
    hidden_total: int
    regression_pass: int
    regression_total: int
    per_script: Dict[str, str]


class RunRecord(NamedTuple):
    """One scored run, the row written to <scratch>/_evals/<label>/<eval>-r<N>.json."""
    eval_name: str
    run: int
    setup_label: str
    candidate: str
    checks: CheckResult
    review_high: int
    review_med: int
    review_low: int
    guard_entries_added: int
    mutation: str
    lines_added: int
    lines_removed: int
    handback_attempts: int
    first_try_denials: int
    verdict: str
    turns: int
    tokens: int
    seconds: int
    lint_new: int


def _rev_exists(repo: str, rev: str) -> bool:
    return subprocess.run(["git", "-C", repo, "cat-file", "-e", rev + "^{commit}"],
                          capture_output=True).returncode == 0


def load_manifest(path: str, repo: Optional[str] = None) -> Dict[str, Dict[str, Any]]:
    """Load and validate the manifest: required keys, list types, known runner, and base/accepted
    revisions that exist in `repo` (default: the repository holding this tool)."""
    repo = repo or os.path.dirname(TOOLS)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("manifest: top level must be an object of eval name -> entry")
    for name, entry in data.items():
        if not isinstance(entry, dict):
            raise ValueError("manifest %s: entry must be an object" % name)
        missing = [k for k in MANIFEST_REQUIRED if k not in entry]
        if missing:
            raise ValueError("manifest %s: missing keys %s" % (name, ", ".join(missing)))
        unknown = [k for k in entry if k not in MANIFEST_REQUIRED + MANIFEST_OPTIONAL]
        if unknown:
            raise ValueError("manifest %s: unknown keys %s" % (name, ", ".join(unknown)))
        for key in LIST_KEYS:
            if not isinstance(entry[key], list):
                raise ValueError("manifest %s: %s must be a list" % (name, key))
        if entry["runner"] not in RUNNERS:
            raise ValueError("manifest %s: runner must be one of %s" % (name, ", ".join(RUNNERS)))
        for key in ("base", "accepted"):
            if not _rev_exists(repo, str(entry[key])):
                raise ValueError("manifest %s: %s rev %s not found in %s" % (name, key, entry[key], repo))
    return data


def prep_run(manifest: Dict[str, Dict[str, Any]], name: str, run: int, setup_rev: str,
             repo: str, root: str) -> str:
    """Create worktree <name>-r<run> at the eval base, overlay CLAUDE.md, .claude/ and tools/ from
    setup_rev, commit it as the eval base, write the rendered brief into scratch and print the
    dispatch_prep.py line. Returns the worktree path."""
    raise NotImplementedError


def snapshot_candidate(wt: str) -> str:
    """git add -A and commit in the throwaway worktree (never merged); returns the candidate revision."""
    raise NotImplementedError


def apply_hidden(wt: str, manifest_entry: Dict[str, Any]) -> List[str]:
    """git checkout <accepted> -- <hidden paths> in wt, after the worker is done; returns the paths applied."""
    raise NotImplementedError


def run_checks(wt: str, manifest_entry: Dict[str, Any], timeout_s: int) -> CheckResult:
    """Run the hidden and regression scripts (gut: tools/run_gut.ps1 -Path wt; unittest: python -m unittest)."""
    raise NotImplementedError


def verify_eval(manifest: Dict[str, Dict[str, Any]], name: str, repo: str) -> bool:
    """True when hidden checks are RED on the overlaid base and GREEN on the accepted commit;
    records lint_all GREEN/RED of the overlaid base as lint_floor."""
    raise NotImplementedError


def score_run(manifest: Dict[str, Dict[str, Any]], name: str, run: int, wt: str,
              usage: Dict[str, int]) -> Dict[str, Any]:
    """Compose the per-run record (RunRecord fields as a dict) from run_checks and session_metrics
    with rev = the eval base commit; usage carries turns, tokens and seconds copied from the Agent tool."""
    raise NotImplementedError


def render_card(results_dir: str, setup_label: str) -> str:
    """Markdown table, one row per run plus per-eval and overall means; writes scorecard-<label>.md."""
    raise NotImplementedError


def _not_implemented(args: argparse.Namespace) -> int:
    raise NotImplementedError("agent_evals %s" % args.command)


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=os.path.join(TOOLS, "evals", "manifest.json"))
    ap.add_argument("--path", default=os.path.dirname(TOOLS), help="main checkout")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("verify", help="hidden checks RED on the base, GREEN on the accepted commit")
    p.add_argument("--eval", dest="evals", action="append", default=[], help="eval name (default: all)")

    p = sub.add_parser("prep", help="make the worktree, overlay the setup, render the brief")
    p.add_argument("eval")
    p.add_argument("--run", type=int, default=1)
    p.add_argument("--setup-rev", default="HEAD", help="revision the setup overlay is taken from")
    p.add_argument("--root", default="", help="worktree root")

    p = sub.add_parser("score", help="snapshot the candidate, apply hidden checks, record the run")
    p.add_argument("eval")
    p.add_argument("--run", type=int, default=1)
    p.add_argument("--worktree", required=True)
    p.add_argument("--setup-label", required=True)
    p.add_argument("--review-high", type=int, default=0)
    p.add_argument("--review-med", type=int, default=0)
    p.add_argument("--review-low", type=int, default=0)
    p.add_argument("--tokens", type=int, default=0)
    p.add_argument("--turns", type=int, default=0)
    p.add_argument("--seconds", type=int, default=0)

    p = sub.add_parser("card", help="render the scorecard for one setup label")
    p.add_argument("setup_label")
    p.add_argument("--results", default="", help="results directory (default: <scratch>/_evals/<label>)")

    for sp in sub.choices.values():
        sp.set_defaults(handler=_not_implemented)
    return ap


def main(argv: Sequence[str]) -> int:
    args = build_parser().parse_args(list(argv))
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
