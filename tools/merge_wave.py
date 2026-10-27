"""Integrate a wave of parallel worker branches whose packages both touched tools/*baseline*.json.

  python tools/merge_wave.py --branches wt/a wt/b [--base main] [--branch-name wt/wave-xxxx]
                             [--allow-new-files path ...]

Builds a combined branch off --base in a temp worktree and merges the branches in order
(git merge --no-ff). A conflict confined to the regenerated baselines
(layer, dead, magic_number, shader_uniform) keeps the combined side and the merge is committed
(dead and shader_uniform also keep the union of both sides' reviewed `allow` entries; one key with
different content on each side is a real conflict and aborts);
any other conflict aborts the merge and the run fails naming the conflicting files. Then only
lowering updates run, with the merged tree's own lints:
  lint_layers.py --update [--allow-new <file> ...]   lint_dead.py --update-baseline
  lint_magic_numbers.py --update                     lint_shader_uniforms.py --update-baseline
--allow-new-files names the new files the plan allows into the layer baseline (and only those;
it also exempts them from the rising check). Each branch's own additions count automatically: the
closure / main_closure / l1_exceptions entries that `git diff <base>...<branch> -- tools/layer_baseline.json`
added become --allow-new files (one `allow-new` line per file names its branch); an entry no branch's
own diff added still fails the rising check. The wave FAILS when a lint refuses a new finding,
when a baseline entry or count is higher than on --base (the `allow` section is ignored), when a
lint still reports a finding after its update, or when a changed path belongs to none of the merged
branches and is not a baseline file. A failure names the branch whose changed files the finding
points at ("unattributed" when none). The baseline refresh is committed on the combined branch and
the last line is `MERGE WAVE READY <branch> <sha>` or `MERGE WAVE FAILED <reason>`; the orchestrator
then passes the branch to tools/integrate_batch.py. No Godot is started. Exit 0 = READY, 1 = FAILED.
A failed run keeps its worktree and branch and prints the cleanup command.
"""

import argparse
import datetime
import fnmatch
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import integrate_batch as ib  # noqa: E402
import repo_paths  # noqa: E402

BASELINE_GLOB = "tools/*baseline*.json"
LINT_TIMEOUT_S = ib.STEP_TIMEOUT_S
# name -> (script, lowering flags, baseline file under tools/)
LOWERING = {
    "layers": ("lint_layers.py", ["--update"], "layer_baseline.json"),
    "dead": ("lint_dead.py", ["--update-baseline"], "dead_baseline.json"),
    "magic": ("lint_magic_numbers.py", ["--update"], "magic_number_baseline.json"),
    "shader": ("lint_shader_uniforms.py", ["--update-baseline"], "shader_uniform_baseline.json"),
}
REGENERATED = sorted("tools/" + v[2] for v in LOWERING.values())
TOKEN_SPLIT = re.compile(r"[\s:,;()'\"]+")
PROBLEM_RE = re.compile(r"^(VIOLATION |MAGIC LINT FAIL |not baselined |\S+:\d+: )")
MAX_SHOWN = 6
SCC_KEY = "autoload_scc_pairs:"


def is_baseline_path(path):
    return fnmatch.fnmatch(path.replace("\\", "/"), BASELINE_GLOB)


def conflict_kind(files):
    """'baseline' when every conflicted file is a baseline this tool regenerates, else 'other'."""
    files = [f.replace("\\", "/") for f in files]
    return "baseline" if files and all(f in REGENERATED for f in files) else "other"


def scope_violations(changed, branch_files):
    """Changed paths that no merged branch touched and that are not baseline files.
    branch_files: {branch: set(paths)}."""
    allowed = set()
    for files in branch_files.values():
        allowed |= files
    return sorted(p for p in (c.replace("\\", "/") for c in changed)
                  if p and p not in allowed and not is_baseline_path(p))


def counters(kind, data):
    """Flatten one baseline into {key: int} so a higher value or a new key is a rise.
    The dead/shader `allow` section (reviewed exceptions) is not a count and is ignored."""
    out = {}
    if kind == "magic":
        out.update({k: v for k, v in data.items() if isinstance(v, int)})
    elif kind in ("dead", "shader"):
        for check, entries in data.get("checks", {}).items():
            for e in entries:
                out["%s:%s" % (check, e)] = 1
    else:
        out["largest_scc"] = data.get("largest_scc", 0)
        for field in ("closure", "main_closure", "l1_exceptions"):
            for e in data.get(field, []):
                out["%s:%s" % (field, e)] = 1
        for pair in data.get("autoload_scc_pairs", []):
            out[SCC_KEY + " ".join(sorted(pair))] = 1
    return out


def rising(kind, before, after, allow_new=()):
    """Keys whose count in `after` is above `before` (a key `before` lacks counts as 0), except
    entries that name an --allow-new file."""
    allow = set(allow_new)
    old, new = counters(kind, before), counters(kind, after)
    # An autoload SCC whose members are a subset of a baselined one shrank (lint_layers allows it).
    old_sccs = [set(p) for p in before.get("autoload_scc_pairs", [])] if kind == "layers" else []
    hits = []
    for k, n in sorted(new.items()):
        if n <= old.get(k, 0):
            continue
        if k.startswith(SCC_KEY) and any(set(k[len(SCC_KEY):].split(" ")) <= s for s in old_sccs):
            continue
        if allow and (k == "largest_scc" or allow & set(TOKEN_SPLIT.split(k))):
            continue
        hits.append(k)
    return hits


def branch_added_files(before, after):
    """Files the layer baseline `after` (a branch's) adds over `before` (the base's): the path of each
    new closure / main_closure entry and the source file of each new l1_exceptions entry. SCC data is not
    a file and is never auto-allowed."""
    out = set()
    for key in rising("layers", before, after):
        field, _, entry = key.partition(":")
        if field in ("closure", "main_closure", "l1_exceptions"):
            out.add(entry.split(" -> ")[0])
    return sorted(out)


def attribute(text, branch_files):
    """The first merged branch (in merge order) whose changed files contain a path named in text."""
    for tok in TOKEN_SPLIT.split(text):
        for branch, files in branch_files.items():
            if tok in files:
                return branch
    return None


def problem_lines(text):
    return [l.strip() for l in text.splitlines() if PROBLEM_RE.match(l.strip())]


def blame(lines, branch_files):
    """'branch: first lines | other: ...' grouping of finding lines by the branch that caused them."""
    groups = {}
    for l in lines:
        groups.setdefault(attribute(l, branch_files) or "unattributed", []).append(l)
    return "; ".join("%s: %s" % (b, " | ".join(ls[:MAX_SHOWN]) + (" | +%d more" % (len(ls) - MAX_SHOWN) if len(ls) > MAX_SHOWN else ""))
                     for b, ls in groups.items())


ALLOW_BASELINES = ("tools/dead_baseline.json", "tools/shader_uniform_baseline.json")


def merge_allow(ours_text, theirs_text):
    """Ours with the union of both sides' reviewed `allow` entries (keyed by id+entry).
    Returns (json_text, None) or (None, reason) when a key carries different content on each side."""
    ours, theirs = json.loads(ours_text), json.loads(theirs_text)
    merged = {(a.get("id"), a.get("entry")): a for a in ours.get("allow", [])}
    for a in theirs.get("allow", []):
        key = (a.get("id"), a.get("entry"))
        if merged.setdefault(key, a) != a:
            return None, "allow entry %s %s differs: ours %r vs theirs %r" % (key[0], key[1], merged[key], a)
    ours["allow"] = sorted(merged.values(), key=lambda a: (str(a.get("id")), str(a.get("entry"))))
    return json.dumps(ours, indent=1) + "\n", None


def resolve_baseline_conflict(ctx, wt, files):
    """Keep the combined side of each conflicted baseline; dead/shader also keep the union of both
    sides' allow entries. Returns None when committed, else the refusal reason."""
    if ib.git(ctx, "ours", wt, "checkout", "--ours", "--", *files)[0] != 0:
        return "git checkout --ours failed"
    for f in files:
        if f not in ALLOW_BASELINES:
            continue
        stages = [ib.git(ctx, "stage", wt, "show", ":%d:%s" % (n, f)) for n in (2, 3)]
        if any(c != 0 for c, _, _ in stages):
            return "cannot read both sides of " + f
        text, reason = merge_allow(stages[0][1], stages[1][1])
        if text is None:
            return f + ": " + reason
        with open(os.path.join(wt, f), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    if ib.git(ctx, "add", wt, "add", "--", *files)[0] != 0 or ib.git(ctx, "commit", wt, "commit", "--no-edit")[0] != 0:
        return "could not commit the resolved baselines"
    return None


def merge_all(ctx, wt, branches, say):
    """git merge --no-ff each branch; a conflict confined to regenerated baselines keeps the
    combined side and commits the merge, any other conflict aborts it and raises StepFailed."""
    for b in branches:
        code, text, _ = ib.git(ctx, "merge_" + b.replace("/", "_"), wt, "merge", "--no-ff",
                               "-m", ib.merge_subject(b), "-m", ib.MERGE_TRAILER, b)
        if code == 0:
            continue
        files = ib.git(ctx, "conflicts", wt, "diff", "--name-only", "--diff-filter=U")[1].split()
        refused = ""
        if conflict_kind(files) == "baseline":
            reason = resolve_baseline_conflict(ctx, wt, files)
            if reason is None:
                say("merge     %s: baseline-only conflict (%s), regenerated below" % (b, ", ".join(files)))
                continue
            refused = " (baseline resolve refused: %s)" % reason
        ib.git(ctx, "merge_abort", wt, "merge", "--abort")
        raise ib.StepFailed("merge", "conflict merging %s: %s%s" % (
            b, ", ".join(files[:15]) or text.strip()[:200], refused))


def branch_changes(ctx, repo, base, branches):
    """{branch: set of paths changed since the merge-base with base}."""
    out = {}
    for b in branches:
        text = ib.git_out(ctx, "files_" + b.replace("/", "_"), repo, "diff", "--no-renames", "--name-only", base + "..." + b)
        out[b] = set(text.replace("\\", "/").split())
    return out


def refresh_baselines(ctx, wt, base, branch_files, allow_new, say):
    """Lowering updates, then check-mode lints and the rising check. Raises StepFailed('baselines')."""
    before = {}
    for kind, (_, _, name) in LOWERING.items():
        code, text, _ = ib.git(ctx, "base_" + kind, wt, "show", "%s:tools/%s" % (base, name))
        before[kind] = json.loads(text) if code == 0 else {}
    bad = []
    for kind, (script, flags, _) in LOWERING.items():
        extra = list(flags)
        if kind == "layers":
            for p in allow_new:
                extra += ["--allow-new", p]
        code, text, log = ib.run_cmd(ctx, "update_" + kind, [sys.executable, os.path.join(wt, "tools", script), "--path", wt] + extra,
                                     wt, LINT_TIMEOUT_S)
        lines = problem_lines(text)
        if code != 0:
            bad.append(("%s update refused" % kind, lines or ["exit %d, log %s" % (code, log)]))
    if bad:
        raise ib.StepFailed("baselines", "; ".join("%s: %s" % (why, blame(ls, branch_files)) for why, ls in bad))
    for kind, (script, _, name) in LOWERING.items():
        with open(os.path.join(wt, "tools", name), encoding="utf-8") as fh:
            hits = rising(kind, before[kind], json.load(fh), allow_new)
        if hits:
            bad.append(("%s baseline rose above %s" % (kind, base[:9]), hits))
        code, text, log = ib.run_cmd(ctx, "check_" + kind, [sys.executable, os.path.join(wt, "tools", script), "--path", wt],
                                     wt, LINT_TIMEOUT_S)
        if code != 0:
            bad.append(("%s still red after update" % kind, problem_lines(text) or ["exit %d, log %s" % (code, log)]))
    if bad:
        raise ib.StepFailed("baselines", "; ".join("%s: %s" % (why, blame(ls, branch_files)) for why, ls in bad))
    say("baselines ok   4 lowering updates, no refusal, no rise, lints green")


def branch_allowed(ctx, repo, base, branches, say):
    """{file: branch} of the layer-baseline entries each branch's own diff against base added."""
    name = "tools/layer_baseline.json"
    texts = {}
    for ref in [base] + list(branches):
        code, text, _ = ib.git(ctx, "layer_" + ref.replace("/", "_"), repo, "show", "%s:%s" % (ref, name))
        texts[ref] = json.loads(text) if code == 0 else {}
    out = {}
    for b in branches:
        for f in branch_added_files(texts[base], texts[b]):
            out.setdefault(f, b)
            say("allow-new %s (added by %s)" % (f, b))
    return out


def check_scope(ctx, wt, base, branch_files):
    tracked = ib.git_out(ctx, "scope_tracked", wt, "diff", "--no-renames", "--name-only", base).split()
    untracked = ib.git_out(ctx, "scope_untracked", wt, "ls-files", "--others", "--exclude-standard").split()
    stray = scope_violations(tracked + untracked, branch_files)
    if stray:
        raise ib.StepFailed("scope", "changed paths in no merged branch and not a baseline: " + ", ".join(stray[:10]))


def wave(args, ctx, say, res):
    repo = args.repo
    base = ib.git_out(ctx, "base", repo, "rev-parse", "--verify", args.base + "^{commit}")
    for b in args.branches:
        if ib.git(ctx, "exists", repo, "rev-parse", "--verify", "--quiet", b + "^{commit}")[0] != 0:
            raise ib.StepFailed("worktree", "branch not found: " + b)
    branch = args.branch_name or "wt/wave-" + base[:8]
    if ib.git(ctx, "taken", repo, "rev-parse", "--verify", "--quiet", "refs/heads/" + branch)[0] == 0:
        raise ib.StepFailed("worktree", "branch already exists: " + branch)
    wt = os.path.join(args.worktree_root, "wave-" + branch.replace("/", "-")).replace("\\", "/")
    if ib.git(ctx, "worktree_add", repo, "worktree", "add", "-b", branch, wt, base)[0] != 0:
        raise ib.StepFailed("worktree", "git worktree add failed")
    res["worktree"], res["branch"] = wt, branch
    say("worktree  ok   %s @ %s" % (wt, base[:9]))
    branch_files = branch_changes(ctx, repo, base, args.branches)
    merge_all(ctx, wt, args.branches, say)
    allowed = branch_allowed(ctx, repo, base, args.branches, say)
    allow_new = list(args.allow_new_files) + [f for f in allowed if f not in args.allow_new_files]
    refresh_baselines(ctx, wt, base, branch_files, allow_new, say)
    check_scope(ctx, wt, base, branch_files)
    ib.git(ctx, "stage", wt, "add", "--", *REGENERATED)
    if ib.git(ctx, "staged", wt, "diff", "--cached", "--quiet")[0] != 0:
        code, text, log = ib.git(ctx, "commit_refresh", wt, "commit", "-m", "Refresh lint baselines for the merged wave (lowering only)",
                                 "-m", ib.MERGE_TRAILER)
        if code != 0:
            raise ib.StepFailed("commit", "baseline refresh commit failed; log " + log)
    res["sha"] = ib.git_out(ctx, "head", wt, "rev-parse", "HEAD")


def cleanup(args, ctx, res):
    ib.git(ctx, "wt_remove", args.repo, "worktree", "remove", "--force", res["worktree"])


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--branches", nargs="+", required=True)
    ap.add_argument("--base", default="main")
    ap.add_argument("--branch-name", default="")
    ap.add_argument("--allow-new-files", nargs="*", default=[], metavar="PATH")
    ap.add_argument("--repo", default=ib.DEFAULT_REPO)
    ap.add_argument("--worktree-root", default=repo_paths.worktrees_root())
    ap.add_argument("--log-dir", default="")
    args = ap.parse_args(argv)
    log_dir = args.log_dir or os.path.join(repo_paths.scratch_root(), "_orchestrator", "merge_wave",
                                           datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    os.makedirs(log_dir, exist_ok=True)
    ctx, res = ib.Ctx(log_dir), {}

    def say(line):
        print(line, flush=True)

    try:
        wave(args, ctx, say, res)
    except ib.StepFailed as e:
        say("MERGE WAVE FAILED %s (logs %s)" % (e, log_dir))
        if res.get("worktree"):
            say("cleanup after diagnosis: git -C %s worktree remove --force %s && git -C %s branch -D %s" % (
                args.repo, res["worktree"], args.repo, res["branch"]))
        return 1
    cleanup(args, ctx, res)
    say("MERGE WAVE READY %s %s" % (res["branch"], res["sha"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
