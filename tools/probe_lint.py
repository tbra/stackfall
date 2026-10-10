"""Probe-file lint (Bontago-fca.63): keep throwaway probe/capture files out of main.

Usage: python tools/probe_lint.py [--base main] [--head HEAD] [--path <checkout>] [--untracked]

Default mode lists files ADDED between base and head (`git diff --diff-filter=A --name-only
base...head`) that match tools/screenshot_*, tools/capture_*, tools/*probe* (any extension, incl.
.gd/.tscn/.uid/.sh) or anything under tools/_scratch*/, minus the globs in tools/probe_allowlist.txt
(one glob per line, # comments). Already tracked probes are grandfathered (not in the diff).
--untracked instead flags untracked (not ignored) files in the checkout matching the same
patterns, for worker handbacks. Prints offenders; exit 1 if any, else 0.
tools/integrate_batch.py runs this check on each branch before merging (escape: --allow-probes).
Second rule (Bontago-fca.91): a branch that ADDS a *.gd/*.gdshader/*.gdshaderinc without also adding
the sibling `<file>.uid` is flagged (a missing sidecar makes Godot generate a fresh uid on main).
In --untracked mode the same rule applies to a worktree: a new (untracked or staged-added) script
with no .uid on disk, or whose .uid is still untracked while the script is staged.
"""
import argparse
import fnmatch
import os
import subprocess
import sys

GIT_TIMEOUT_S = 120
ALLOWLIST = "tools/probe_allowlist.txt"
PATTERNS = ("tools/screenshot_*", "tools/capture_*", "tools/*probe*", "tools/_scratch*/*")
# DECISION: this lint's own files contain "probe" in their names; exempt them built in so the
# allowlist can stay header-only as specified.
SELF_FILES = frozenset(("tools/probe_lint.py", "tools/test_probe_lint.py", ALLOWLIST))


def _git(repo, *a):
    p = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=GIT_TIMEOUT_S)
    if p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(a), (p.stderr or "").strip()[:300]))
    return p.stdout


def read_allowlist(repo):
    path = os.path.join(repo, *ALLOWLIST.split("/"))
    globs = []
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if line and not line.startswith("#"):
                    globs.append(line)
    return globs


def is_probe(path):
    p = path.replace("\\", "/")
    if p in SELF_FILES:
        return False
    return any(fnmatch.fnmatchcase(p, pat) for pat in PATTERNS)


def filter_probes(paths, allow=()):
    """Subset of repo-relative paths that look like probes and are not allowlisted."""
    out = []
    for raw in paths:
        p = raw.strip().replace("\\", "/")
        if p and is_probe(p) and not any(fnmatch.fnmatchcase(p, g) for g in allow):
            out.append(p)
    return out


UID_EXTS = (".gd", ".gdshader", ".gdshaderinc")  # extensions this repo tracks .uid sidecars for


def missing_uid_files(added):
    """Messages for added uid-bearing files whose `<file>.uid` is not in the same added set.
    # DECISION: reported through the same offender list and the same --allow-probes escape."""
    names = set(p.strip().replace("\\", "/") for p in added)
    return ["missing uid: %s added without %s.uid" % (p, p)
            for p in sorted(names) if p.endswith(UID_EXTS) and p + ".uid" not in names]


def new_probe_files(repo, base_ref, head_ref):
    text = _git(repo, "diff", "--diff-filter=A", "--name-only", base_ref + "..." + head_ref)
    names = text.splitlines()
    return filter_probes(names, read_allowlist(repo)) + missing_uid_files(names)


def untracked_probe_files(repo):
    text = _git(repo, "ls-files", "--others", "--exclude-standard")
    untracked = [l.strip() for l in text.splitlines() if l.strip()]
    out = filter_probes(untracked, read_allowlist(repo))
    staged = [l.strip() for l in _git(repo, "diff", "--cached", "--diff-filter=A", "--name-only").splitlines() if l.strip()]
    for p in sorted(set(untracked) | set(staged)):
        if not p.endswith(UID_EXTS):
            continue
        uid = p + ".uid"
        if not os.path.isfile(os.path.join(repo, *uid.split("/"))):
            out.append("missing uid: %s has no %s on disk" % (p, uid))
        elif uid in untracked and p in staged:
            out.append("missing uid: %s is staged but %s is untracked" % (p, uid))
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default="main")
    ap.add_argument("--head", default="HEAD")
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--untracked", action="store_true")
    args = ap.parse_args(argv)
    try:
        found = untracked_probe_files(args.path) if args.untracked else new_probe_files(args.path, args.base, args.head)
    except (RuntimeError, subprocess.SubprocessError) as e:
        print(e, file=sys.stderr)
        return 2
    for f in found:
        print(f if f.startswith("missing uid:") else "probe file: " + f)
    if found:
        print("probe_lint: %d offender(s); delete them or add a glob to %s" % (len(found), ALLOWLIST))
        return 1
    print("probe_lint: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
