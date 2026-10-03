"""One-shot orchestrator integration sequence (Bontago-fca.7).

  python tools/integrate_batch.py --branches wt/a wt/b --beads Bontago-1 Bontago-2 [--no-game-code]

Steps (each step's full output goes to <log-dir>/NN_name.log; stdout stays compact):
  1 worktree  temp integration worktree + branch from local main (origin/main must be an ancestor)
  2 merge     git merge --no-ff each branch; on conflict stop and list conflicting files
  3 import    godot --headless --editor --path <wt> --quit (bounded error/warning lines)
  4 check-only (always): godot --check-only -s for each added/modified tools/*.gd (120s timeout)
  5 gate      --game-code (default): tools/full_gate.py --path <wt>; ONLY a `FULL GATE GREEN`
              line passes (missing verdict line = RED)
  6 ff        fast-forward the main checkout (refuses on dirty touched files or a moved main)
  7 push      git push origin main (separate step), git fetch, verify HEAD == origin/main
  8 close     bd close for each bead, only after remote verification (--force-close adds
              --force for reviewed handoffs whose claim another agent such as codex holds)
  9 postimport  godot import check in the main checkout
The temp worktree and branch are removed on every success (incl. --no-push) and kept on failure. --dry-run stops after step 5 (no ff/push/close),
then removes the temp worktree and branch. Exit 0 = success, 1 = failed step (named).
"""

import argparse
import datetime
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_REPO = "M:/Bontago"
STEP_TIMEOUT_S = 600
GATE_TIMEOUT_S = 1500
GIT_TIMEOUT_S = 120
BD_ACTOR = "stackfall-orchestrator"
MAX_ISSUE_LINES = 8
VERDICT_RE = re.compile(r"^FULL GATE (GREEN|RED|ERROR)\b", re.M)
ISSUE_RE = re.compile(r"(ERROR|WARNING|Parse Error)", re.I)
OUT_PATH_RE = re.compile(r"; out=(\S+)(?:\s|$)")


class StepFailed(Exception):
    def __init__(self, step, detail):
        super().__init__(step + ": " + detail)
        self.step = step
        self.detail = detail


class Ctx:
    def __init__(self, log_dir):
        self.log_dir = log_dir
        self.n = 0

    def log_path(self, name):
        self.n += 1
        return os.path.join(self.log_dir, "%02d_%s.log" % (self.n, name))


def run_cmd(ctx, name, args, cwd, timeout):
    """Run an argument list (no shell); full output to a log file. Returns (code, text, log_path)."""
    path = ctx.log_path(name)
    try:
        p = subprocess.run(args, cwd=cwd, capture_output=True, text=True,
                           encoding="utf-8", errors="replace", timeout=timeout)
        code, text = p.returncode, (p.stdout or "") + (p.stderr or "")
    except subprocess.TimeoutExpired:
        code, text = 124, "TIMEOUT after %ds" % timeout
    except OSError as e:
        code, text = 127, "cannot run %s: %s" % (args[0], e)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("$ %s (cwd %s)\n%s" % (" ".join(args), cwd, text))
    return code, text, path


def git(ctx, name, repo, *a, timeout=GIT_TIMEOUT_S):
    return run_cmd(ctx, name, ["git", "-C", repo, *a], repo, timeout)


def git_out(ctx, name, repo, *a):
    code, text, _ = git(ctx, name, repo, *a)
    if code != 0:
        raise StepFailed(name, "git %s failed (%d)" % (" ".join(a), code))
    return text.strip()


def godot_exe():
    return shutil.which("godot") or shutil.which("godot.exe") or "godot"


def bd_exe():
    # npm installs bd as bd.CMD on Windows; CreateProcess (no shell) cannot find it by
    # bare name, so resolve it the way the shell would (Bontago-fca.13).
    return shutil.which("bd") or "bd"


def close_args(repo, bead, reason, force):
    """bd close argv. --force only for reviewed handoffs whose claim another agent holds."""
    argv = [bd_exe(), "-C", repo, "close", bead, "--actor", BD_ACTOR, "--reason", reason]
    if force:
        argv.append("--force")
    return argv


def parse_verdict(text):
    """GREEN only when every verdict line is `FULL GATE GREEN`; a missing line is RED."""
    found = VERDICT_RE.findall(text)
    return "GREEN" if found and set(found) == {"GREEN"} else "RED"


def verdict_line(text):
    lines = [l for l in text.splitlines() if l.startswith("FULL GATE ")]
    return lines[-1][:300] if lines else "FULL GATE (no verdict line) -> RED"


def extract_out_path(text):
    """Extract the out= directory path from the verdict line, if present."""
    m = OUT_PATH_RE.search(text)
    return m.group(1) if m else None


def issue_lines(text):
    return [l.strip()[:200] for l in text.splitlines() if ISSUE_RE.search(l)][:MAX_ISSUE_LINES]


MERGE_TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"


def merge_subject(branch, beads):
    """'Merge <branch> (<bead ids>)': the bead whose id (or its suffix) appears in the branch name,
    else every --beads id, else no parenthesis."""
    low = branch.lower()
    hit = [b for b in beads if re.search(r"(?<![a-z0-9])%s(?![a-z0-9])" % re.escape(b.lower().split("-", 1)[-1]), low)]
    ids = hit[:1] or list(beads)
    return "Merge %s (%s)" % (branch, ", ".join(ids)) if ids else "Merge " + branch


def import_check(ctx, name, path):
    cmd = [godot_exe(), "--headless", "--editor", "--path", path, "--quit"]
    run_cmd(ctx, name + "_warm", cmd, path, STEP_TIMEOUT_S)  # first run builds .godot
    code, text, log = run_cmd(ctx, name, cmd, path, STEP_TIMEOUT_S)
    return code, issue_lines(text), log


def check_tools_scripts(ctx, base, wt):
    """Check all added/modified tools/*.gd scripts with godot --check-only.
    Returns (code, errors_list, num_files, log_path). code=0 is success, any other code or SCRIPT ERROR/Parse Error is failure."""
    # Get list of added/modified tools/*.gd files
    code, text, _ = git(ctx, "diff_tools", wt, "diff", "--name-only", "--diff-filter=AM", base + "..HEAD", "--", "tools/*.gd")
    if code != 0:
        return code, ["git diff failed"], 0, _
    files = [f.strip() for f in text.split('\n') if f.strip()]
    if not files:
        return 0, [], 0, ctx.log_path("check_tools_empty")

    all_errors = []
    path = ctx.log_path("check_tools")
    with open(path, "w", encoding="utf-8") as log_fh:
        log_fh.write(f"$ godot --check-only -s for {len(files)} files\n")
        for file in files:
            res_path = "res://" + file
            cmd = [godot_exe(), "--headless", "--path", wt, "--check-only", "-s", res_path]
            code, text, _ = run_cmd(ctx, "check_" + file.replace("/", "_").replace(".", "_"), cmd, wt, 120)
            log_fh.write(f"\n{res_path}:\n{text}\n")
            if code != 0:
                all_errors.append(f"{file}: exit {code}")
            if "SCRIPT ERROR" in text or "Parse Error" in text:
                # Extract the first error line
                for line in text.split('\n'):
                    if "SCRIPT ERROR" in line or "Parse Error" in line:
                        all_errors.append(f"{file}: {line.strip()[:200]}")
                        break
    return 1 if all_errors else 0, all_errors, len(files), path


def integrate(args, ctx, say, res):
    repo = args.repo
    # 1 worktree
    if git(ctx, "fetch", repo, "fetch", "origin")[0] != 0:
        raise StepFailed("worktree", "git fetch origin failed")
    if git(ctx, "cur_branch", repo, "symbolic-ref", "--short", "HEAD")[1].strip() != "main":
        raise StepFailed("worktree", "main checkout is not on branch main")
    base = git_out(ctx, "rev_main", repo, "rev-parse", "main")
    if git(ctx, "anc", repo, "merge-base", "--is-ancestor", "origin/main", "main")[0] != 0:
        raise StepFailed("worktree", "origin/main is not an ancestor of local main (pull or reconcile first)")
    for b in args.branches:
        if git(ctx, "exists", repo, "rev-parse", "--verify", "--quiet", b + "^{commit}")[0] != 0:
            raise StepFailed("worktree", "branch not found: " + b)
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    branch = "integrate/tmp-" + stamp
    wt = os.path.join(args.worktree_root, "integrate-tmp-" + stamp).replace("\\", "/")
    if git(ctx, "worktree_add", repo, "worktree", "add", "-b", branch, wt, base)[0] != 0:
        raise StepFailed("worktree", "git worktree add failed")
    res["worktree"], res["branch"] = wt, branch
    run_cmd(ctx, "override", [sys.executable, os.path.join(ROOT, "tools", "agent_worktree_setup.py"), wt], ROOT, GIT_TIMEOUT_S)
    say("worktree  ok   %s @ %s" % (wt, base[:9]))
    # 2 merge
    for b in args.branches:
        code, text, _ = git(ctx, "merge_" + b.replace("/", "_"), wt, "merge", "--no-ff",
                            "-m", merge_subject(b, args.beads), "-m", MERGE_TRAILER, b)
        if code != 0:
            files = git(ctx, "conflicts", wt, "diff", "--name-only", "--diff-filter=U")[1].split()
            git(ctx, "merge_abort", wt, "merge", "--abort")
            raise StepFailed("merge", "conflict merging %s: %s" % (b, ", ".join(files[:15]) or text.strip()[:200]))
    result = git_out(ctx, "rev_result", wt, "rev-parse", "HEAD")
    res["result"] = result
    say("merge     ok   %d branch(es) -> %s" % (len(args.branches), result[:9]))
    # 3 import
    code, issues, log = import_check(ctx, "import", wt)
    if code != 0 or issues:
        for l in issues:
            say("  import: " + l)
        raise StepFailed("import", "exit %d, %d error/warning line(s); log %s" % (code, len(issues), log))
    say("import    ok   no errors/warnings")
    # 4 check-only (tools scripts; also for --no-game-code tooling batches)
    code, errors, num_files, log = check_tools_scripts(ctx, base, wt)
    if code != 0 or errors:
        for e in errors[:MAX_ISSUE_LINES]:
            say("  check-only: " + e)
        raise StepFailed("check-only", "tools scripts have errors; log %s" % log)
    if num_files > 0:
        say("check-only ok   %d tools script(s) OK" % num_files)
    # 5 gate
    verdict = "skipped"
    gate_output_path = None
    if args.game_code:
        code, text, log = run_cmd(ctx, "gate", [sys.executable, os.path.join(ROOT, "tools", "full_gate.py"), "--path", wt], wt, GATE_TIMEOUT_S + 120)
        verdict = parse_verdict(text)
        # Preserve gate output directory before worktree cleanup
        out_path = extract_out_path(text)
        if out_path and os.path.isdir(out_path):
            gate_output_path = os.path.join(args.log_dir, "gate_output")
            try:
                shutil.copytree(out_path, gate_output_path, dirs_exist_ok=True)
                vline = verdict_line(text) + "; preserved in " + gate_output_path
            except Exception as e:
                say("  warning: could not copy gate output: %s" % str(e)[:200])
                vline = verdict_line(text)
        else:
            vline = verdict_line(text)
        say("gate      %s %s" % ("ok  " if verdict == "GREEN" else "FAIL", vline))
        if verdict != "GREEN":
            raise StepFailed("gate", "verdict %s; log %s" % (verdict, log))
    else:
        say("gate      skip not game code")
    res["verdict"] = verdict
    if args.dry_run:
        say("dry-run   stop before ff/push/close")
        return
    # 6 ff main
    if git_out(ctx, "rev_main2", repo, "rev-parse", "main") != base:
        raise StepFailed("ff", "main moved during integration")
    touched = set(git_out(ctx, "touched", repo, "diff", "--name-only", base, result).split())
    code, status, _ = git(ctx, "dirty", repo, "status", "--porcelain", "--untracked-files=no")
    if code != 0:
        raise StepFailed("ff", "git status failed")
    # porcelain: "XY path" (renames "XY old -> new"); keep the raw text, leading space is meaningful
    dirty = set(p.strip().strip('"') for l in status.splitlines() for p in l[3:].split(" -> "))
    clash = sorted(touched & dirty)
    if clash:
        raise StepFailed("ff", "dirty tracked files in main would be touched: " + ", ".join(clash[:10]))
    code, text, _ = git(ctx, "ff", repo, "merge", "--ff-only", branch)
    if code != 0:
        raise StepFailed("ff", "fast-forward failed: " + text.strip()[:200])
    say("ff        ok   main -> %s" % result[:9])
    # 7 push (separate step), then verify the remote
    if args.no_push:
        say("push      skip --no-push (beads not closed)")
        return
    code, text, log = git(ctx, "push", repo, "push", "origin", "main", timeout=STEP_TIMEOUT_S)
    if code != 0:
        raise StepFailed("push", "git push failed; log " + log)
    git(ctx, "fetch2", repo, "fetch", "origin")
    head = git_out(ctx, "head", repo, "rev-parse", "HEAD")
    remote = git_out(ctx, "remote", repo, "rev-parse", "origin/main")
    if head != remote or head != result:
        raise StepFailed("push", "verify mismatch HEAD %s origin/main %s expected %s" % (head[:9], remote[:9], result[:9]))
    say("push      ok   origin/main == HEAD == %s" % head[:9])
    # 8 close beads, only after remote verification
    for bead in args.beads:
        reason = "%s pushed+verified; gate %s" % (head[:9], verdict)
        argv = close_args(repo, bead, reason, getattr(args, "force_close", False))
        code, text, log = run_cmd(ctx, "close_" + bead, argv, repo, GIT_TIMEOUT_S)
        if code != 0:
            raise StepFailed("close", "bd close %s failed; log %s" % (bead, log))
    say("close     ok   %s" % (", ".join(args.beads) or "(none)"))
    # 9 post-pull import check in the main checkout
    code, issues, log = import_check(ctx, "postimport", repo)
    for l in issues:
        say("  postimport: " + l)
    if code != 0 or issues:
        raise StepFailed("postimport", "main checkout import not clean; log " + log)
    say("postimport ok")


def cleanup(args, ctx, res):
    if res.get("worktree"):
        git(ctx, "wt_remove", args.repo, "worktree", "remove", "--force", res["worktree"])
        git(ctx, "br_delete", args.repo, "branch", "-D", res["branch"])


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--branches", nargs="+", required=True)
    ap.add_argument("--beads", nargs="*", default=[])
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--worktree-root", default="M:/Bontago-worktrees")
    ap.add_argument("--log-dir", default="")
    ap.add_argument("--game-code", dest="game_code", action="store_true", default=True)
    ap.add_argument("--no-game-code", dest="game_code", action="store_false")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--no-push", action="store_true")
    # DECISION (Bontago-fca.13): opt-in rather than automatic, so a bead held by a live
    # worker is never force-closed by default; pass it only for reviewed Codex handoffs.
    ap.add_argument("--force-close", action="store_true",
                    help="pass --force to bd close (reviewed handoffs whose claim another agent holds, e.g. codex)")
    args = ap.parse_args(argv)
    log_dir = args.log_dir or tempfile.mkdtemp(prefix="integrate_batch_")
    os.makedirs(log_dir, exist_ok=True)
    ctx = Ctx(log_dir)
    res = {}

    def say(line):
        print(line, flush=True)

    try:
        integrate(args, ctx, say, res)
    except StepFailed as e:
        say("FAILED step=%s: %s" % (e.step, e.detail[:500]))
        say("INTEGRATE FAILED at %s; worktree kept: %s; logs: %s" % (e.step, res.get("worktree"), log_dir))
        return 1
    cleanup(args, ctx, res)  # success (dry-run, --no-push or full): drop temp worktree + branch
    say("INTEGRATE OK%s commit=%s gate=%s logs=%s" % (
        " (dry-run)" if args.dry_run else (" (no-push, main ff only)" if args.no_push else ""),
        res.get("result", "?")[:9], res.get("verdict"), log_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
