"""Prepare a worker dispatch in one command.

Usage (the brief comes from stdin):
    python tools/dispatch_prep.py --bead Bontago-123 --role stackfall-implementer \
        --title "Fix X" --files <owned,files> --kind bugfix < brief.md
    ... [--prior-attempts N] [--model sonnet --reason "why the verdict is overridden"] [--redispatch]

Steps: save the brief under the bead's scratchpad; ask tools/route_model.py for the verdict;
claim the bead with `bd update --if-status=open --status=in_progress --assignee "<role> (<model>)"`
(with --redispatch, an in-progress bead only gets the new assignee, forced past the previous
worker's claim: use it only after that worker has handed back); post the dispatch comment
with the verdict, any override and the brief path. Prints one `DISPATCH ...` line naming the
model to pass in the Agent call; exit 1 names the failed step.
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
sys.path.insert(0, TOOLS)
from bd_cli import bd_executable  # noqa: E402

ACTOR = "stackfall-orchestrator"
STEP_TIMEOUT_S = 120


def run(cmd, stdin_text=None):
    """(returncode, stdout, stderr) for `cmd` run in the repo root."""
    proc = subprocess.run(cmd, input=stdin_text, cwd=ROOT, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", timeout=STEP_TIMEOUT_S)
    return proc.returncode, proc.stdout, proc.stderr


def prepare(args, brief, runner=run):
    """Run every step; returns (exit_code, summary_line)."""
    bd = bd_executable()
    code, out, err = runner([sys.executable, os.path.join(TOOLS, "scratch.py"), "path", args.bead, "dispatch"])
    if code != 0:
        return 1, "FAILED scratch: %s" % (err or out).strip()[:200]
    brief_path = os.path.join(out.strip(), "brief-%s.md" % datetime.now().strftime("%Y%m%d-%H%M%S"))
    with open(brief_path, "w", encoding="utf-8") as handle:
        handle.write(brief)
    route = [sys.executable, os.path.join(TOOLS, "route_model.py"), "--title", args.title, "--files", args.files,
             "--kind", args.kind, "--prior-attempts", str(args.prior_attempts), "--json"]
    code, out, err = runner(route, brief)
    try:
        verdict = json.loads(out)
    except ValueError:
        return 1, "FAILED route_model: %s" % (err or out).strip()[:200]
    model = args.model or verdict.get("model", "sonnet")
    assignee = "%s (%s)" % (args.role, model)
    claim = [bd, "update", args.bead, "--actor", ACTOR, "--assignee", assignee]
    if args.redispatch:
        claim.append("--force")
    else:
        claim[3:3] = ["--if-status=open", "--status=in_progress"]
    code, out, err = runner(claim)
    if code != 0:
        return 1, "FAILED claim (use --redispatch for an in-progress bead): %s" % (err or out).strip()[:200]
    summary = "model=%s review=%s split=%s tier=%s source=%s" % (
        model, "yes" if verdict.get("needs_review") else "no", "yes" if verdict.get("split_first") else "no",
        verdict.get("verification_tier"), verdict.get("source"))
    override = " override from %s: %s" % (verdict.get("model"), args.reason) if args.model else ""
    comment = "Dispatch: %s; %s;%s brief: %s" % (assignee, summary, override, brief_path.replace("\\", "/"))
    code, out, err = runner([bd, "comments", "add", args.bead, "--actor", ACTOR, comment])
    if code != 0:
        return 1, "FAILED dispatch comment: %s" % (err or out).strip()[:200]
    return 0, "DISPATCH %s %s %s brief=%s" % (args.bead, args.role, summary, brief_path.replace("\\", "/"))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bead", required=True)
    ap.add_argument("--role", required=True, help="worker profile, e.g. stackfall-implementer")
    ap.add_argument("--title", required=True)
    ap.add_argument("--files", default="", help="comma-separated owned files")
    ap.add_argument("--kind", default="feature", help="feature|bugfix|refactor|review|gate|triage|mechanical|prose|plan")
    ap.add_argument("--prior-attempts", type=int, default=0)
    ap.add_argument("--model", default="", help="override the routed model (needs --reason)")
    ap.add_argument("--reason", default="", help="why the routed model is overridden")
    ap.add_argument("--redispatch", action="store_true", help="re-assign an in-progress bead after its previous worker handed back")
    args = ap.parse_args(argv)
    if args.model and not args.reason.strip():
        ap.error("--model overrides the routed verdict and needs --reason")
    if not args.role.startswith("stackfall-"):
        ap.error("--role must be a stackfall-* worker profile")
    code, line = prepare(args, sys.stdin.read())
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
