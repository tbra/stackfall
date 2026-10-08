"""Create an agent worktree with its off-screen override.cfg (Bontago-fca.46).

Usage: python tools/new_worktree.py <name> [--branch wt/<name>] [--base main]
                                    [--root M:/Bontago-worktrees] [--repo <repo>] [--no-import]

Runs `git worktree add -b <branch> <root>/<name> <base>`, then tools/agent_worktree_setup.py on
the new path (keeps agent Godot windows off-screen), and prints
`worktree <path> branch <branch> base <short-sha>`. Then (Bontago-fca.63) runs a headless
`godot --headless --editor --path <wt> --quit` import (timeout 600 s; executable from env GODOT, else
`godot` on PATH; skip with --no-import) and prints `import ok|failed(<code>)|timeout`; the worktree is
never deleted on import failure (exit stays 0 so the path is still usable; rerun the import by hand). Refuses an existing path, an existing
branch, or the main checkout itself. Default root: sibling `Bontago-worktrees` of the repo.
Never use bare `git worktree add` for agent worktrees.
"""
import argparse
import contextlib
import io
import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_worktree_setup  # noqa: E402

GIT_TIMEOUT_S = 300
DEFAULT_REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT_DIRNAME = "Bontago-worktrees"
IMPORT_TIMEOUT_S = 600


def _git(repo, *a):
    p = subprocess.run(["git", "-C", repo, *a], capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=GIT_TIMEOUT_S)
    return p.returncode, ((p.stdout or "") + (p.stderr or "")).strip()


def _norm(p):
    return os.path.normcase(os.path.realpath(p))


def main_checkout(repo):
    """Path of the main checkout (first `git worktree list` entry)."""
    code, text = _git(repo, "worktree", "list", "--porcelain")
    if code != 0:
        raise RuntimeError("git worktree list failed: " + text[:200])
    return text.splitlines()[0][len("worktree "):].strip()


def create(name, repo, branch=None, base="main", root=None):
    """Returns (path, branch, short_sha). Raises ValueError on refusal, RuntimeError on git failure."""
    repo = os.path.abspath(repo)
    branch = branch or "wt/" + name
    root = root or os.path.join(os.path.dirname(main_checkout(repo)), ROOT_DIRNAME)
    path = os.path.abspath(os.path.join(root, name))
    if _norm(path) == _norm(main_checkout(repo)):
        raise ValueError("refusing: %s is the main checkout" % path)
    if os.path.exists(path):
        raise ValueError("refusing: path already exists: %s" % path)
    if _git(repo, "show-ref", "--verify", "--quiet", "refs/heads/" + branch)[0] == 0:
        raise ValueError("refusing: branch already exists: %s" % branch)
    code, sha = _git(repo, "rev-parse", "--short", base + "^{commit}")
    if code != 0:
        raise ValueError("unknown base %s: %s" % (base, sha[:200]))
    os.makedirs(root, exist_ok=True)
    code, text = _git(repo, "worktree", "add", "-b", branch, path, base)
    if code != 0:
        raise RuntimeError("git worktree add failed: " + text[:300])
    project_file = os.path.join(path, "project.godot")
    if os.path.isfile(project_file):
        with contextlib.redirect_stdout(io.StringIO()):
            rc = agent_worktree_setup.main(["agent_worktree_setup.py", path])
        if rc != 0:
            raise RuntimeError("agent_worktree_setup failed for " + path)
    return path.replace("\\", "/"), branch, sha


def godot_exe():
    return os.environ.get("GODOT") or shutil.which("godot") or "godot"


def import_project(path):
    """Headless import so .godot exists. Returns 'ok', 'failed(<code>)' or 'timeout'."""
    try:
        p = subprocess.run([godot_exe(), "--headless", "--editor", "--path", path, "--quit"],
                           capture_output=True, text=True, encoding="utf-8", errors="replace",
                           timeout=IMPORT_TIMEOUT_S)
    except subprocess.TimeoutExpired:
        return "timeout"
    except OSError as e:
        return "failed(%s)" % type(e).__name__
    return "ok" if p.returncode == 0 else "failed(%d)" % p.returncode


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("name")
    ap.add_argument("--branch", default=None)
    ap.add_argument("--base", default="main")
    ap.add_argument("--root", default=None)
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--no-import", action="store_true", help="skip the headless godot import")
    args = ap.parse_args(argv)
    try:
        path, branch, sha = create(args.name, args.repo, args.branch, args.base, args.root)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 2
    except (RuntimeError, subprocess.SubprocessError) as e:
        print(e, file=sys.stderr)
        return 1
    print("worktree %s branch %s base %s" % (path, branch, sha))
    if not args.no_import and os.path.isfile(os.path.join(path, "project.godot")):
        print("import " + import_project(path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
