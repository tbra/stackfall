"""Remove git worktrees whose branch is already merged into main.

Usage: python tools/prune_worktrees.py [--repo M:/Bontago] [--apply] [--branches wt/a wt/b] [--protect PATTERN ...]

A worktree is removable only if ALL hold: it is not the main checkout, its branch is not
protected (fnmatch patterns; defaults codex/*, wt/assets-batch6, integrate/*), the branch is an
ancestor of main, and `git status --porcelain` shows nothing but untracked *.import / *.uid files.
Removal: `git worktree remove --force`, then `git branch -d` (never -D), then `git worktree prune`.
Dry-run unless --apply. Prints one line: PRUNE removed=N kept_dirty=N kept_unmerged=N protected=N
"""
import argparse
import fnmatch
import subprocess
import sys

DEFAULT_REPO = "M:/Bontago"
DEFAULT_PROTECT = ["codex/*", "wt/assets-batch6", "integrate/*"]
GIT_TIMEOUT_S = 120
SIDECAR_SUFFIXES = (".import", ".uid")


def _git(repo, *a):
    p = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=GIT_TIMEOUT_S)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def list_worktrees(repo):
    """[(path, branch or None)] in `git worktree list --porcelain` order; first is the main checkout."""
    code, text = _git(repo, "worktree", "list", "--porcelain")
    if code != 0:
        raise RuntimeError("git worktree list failed: " + text.strip()[:200])
    out, path, branch = [], None, None
    for line in text.splitlines() + [""]:
        if line.startswith("worktree "):
            path, branch = line[9:].strip(), None
        elif line.startswith("branch "):
            branch = line[7:].strip()
            if branch.startswith("refs/heads/"):
                branch = branch[len("refs/heads/"):]
        elif not line and path is not None:
            out.append((path, branch))
            path = None
    return out


def is_protected(branch, patterns):
    return any(fnmatch.fnmatchcase(branch, p) for p in patterns)


def is_clean(path):
    """True if status shows nothing except untracked .import/.uid files. None if status failed."""
    code, text = _git(path, "status", "--porcelain")
    if code != 0:
        return None
    for line in text.splitlines():
        if line.startswith("?? ") and line[3:].strip().strip('"').endswith(SIDECAR_SUFFIXES):
            continue
        if line.strip():
            return False
    return True


def prune(repo, apply=False, branches=None, protect=None, say=print):
    """Returns counts: removed/kept_dirty/kept_unmerged/protected/failed."""
    patterns = DEFAULT_PROTECT if protect is None else protect
    counts = {"removed": 0, "kept_dirty": 0, "kept_unmerged": 0, "protected": 0, "failed": 0}
    wts = list_worktrees(repo)
    for path, branch in wts[1:]:  # first entry is the main checkout
        if branch is None:
            say("keep  %s: detached HEAD" % path)
            counts["kept_unmerged"] += 1
            continue
        if branches is not None and branch not in branches:
            continue
        if is_protected(branch, patterns):
            say("keep  %s (%s): protected" % (path, branch))
            counts["protected"] += 1
            continue
        if _git(repo, "merge-base", "--is-ancestor", branch, "main")[0] != 0:
            say("keep  %s (%s): unmerged" % (path, branch))
            counts["kept_unmerged"] += 1
            continue
        clean = is_clean(path)
        if not clean:
            say("keep  %s (%s): dirty%s" % (path, branch, "" if clean is False else " (status failed)"))
            counts["kept_dirty"] += 1
            continue
        if not apply:
            say("would remove %s (%s): merged and clean" % (path, branch))
            counts["removed"] += 1
            continue
        code, text = _git(repo, "worktree", "remove", "--force", path)
        if code != 0:
            say("FAIL  remove %s: %s" % (path, text.strip()[:200]))
            counts["failed"] += 1
            continue
        code, text = _git(repo, "branch", "-d", branch)
        if code != 0:
            say("warn  worktree removed but branch %s kept: %s" % (branch, text.strip()[:200]))
        say("removed %s (%s)" % (path, branch))
        counts["removed"] += 1
    if apply:
        _git(repo, "worktree", "prune")
    return counts


def summary(c):
    return "PRUNE removed=%d kept_dirty=%d kept_unmerged=%d protected=%d" % (
        c["removed"], c["kept_dirty"], c["kept_unmerged"], c["protected"])


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--apply", action="store_true", help="actually remove (default: dry-run)")
    ap.add_argument("--branches", nargs="+", default=None, help="limit to these branches")
    ap.add_argument("--protect", nargs="+", default=None, help="protected branch patterns (replaces defaults)")
    args = ap.parse_args(argv)
    c = prune(args.repo, args.apply, args.branches, args.protect)
    print(summary(c))
    return 0 if c["failed"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
