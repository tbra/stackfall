"""Probe-file lint (Bontago-fca.63): keep throwaway probe/capture files out of main.

Usage: python tools/probe_lint.py [--base main] [--head HEAD] [--path <checkout>] [--untracked]

Default mode lists files ADDED between base and head (`git diff --diff-filter=A --name-only
base...head`) that match tools/screenshot_*, tools/capture_*, tools/*probe* (any extension, incl.
.gd/.tscn/.uid/.sh) or anything under tools/_scratch*/, minus the globs in tools/probe_allowlist.txt
(one glob per line, # comments). Already tracked probes are grandfathered (not in the diff).
--untracked instead flags untracked (not ignored) files in the checkout matching the same
patterns, for worker handbacks. Prints offenders; exit 1 if any, else 0.
tools/integrate_batch.py runs this check on each branch before merging (escape: --allow-probes).
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


def new_probe_files(repo, base_ref, head_ref):
    text = _git(repo, "diff", "--diff-filter=A", "--name-only", base_ref + "..." + head_ref)
    return filter_probes(text.splitlines(), read_allowlist(repo))


def untracked_probe_files(repo):
    text = _git(repo, "ls-files", "--others", "--exclude-standard")
    return filter_probes(text.splitlines(), read_allowlist(repo))


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
        print("probe file: " + f)
    if found:
        print("probe_lint: %d offender(s); delete them or add a glob to %s" % (len(found), ALLOWLIST))
        return 1
    print("probe_lint: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
