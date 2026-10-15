"""Machine-independent default locations, derived from where this checkout lives.

The main checkout is `<parent>/<name>`. Agent worktrees live in `<parent>/<name>-worktrees`
and shared tooling state (scratch notes, locks, graphs) in `<parent>/<name>-tools`.
When this file is run from inside a worktree the main checkout is found by stripping
the `-worktrees` suffix of the worktree's parent folder.

Overrides: STACKFALL_WORKTREES (worktrees root), STACKFALL_TOOLS_ROOT (tools root).
All functions return forward-slash strings so they can be used as argparse defaults.
"""
from __future__ import annotations

import os
from pathlib import Path

WORKTREES_ENV = "STACKFALL_WORKTREES"
TOOLS_ROOT_ENV = "STACKFALL_TOOLS_ROOT"
WORKTREES_SUFFIX = "-worktrees"
TOOLS_SUFFIX = "-tools"


def _fwd(p: Path) -> str:
    return str(p).replace("\\", "/")


def this_checkout() -> Path:
    """The checkout containing this tools/ folder."""
    return Path(__file__).resolve().parent.parent


def main_repo() -> Path:
    """The main checkout, even when called from one of its worktrees."""
    here = this_checkout()
    parent = here.parent
    if parent.name.endswith(WORKTREES_SUFFIX) and len(parent.name) > len(WORKTREES_SUFFIX):
        return parent.parent / parent.name[: -len(WORKTREES_SUFFIX)]
    return here


def repo_dir() -> str:
    return _fwd(main_repo())


def worktrees_root() -> str:
    env = os.environ.get(WORKTREES_ENV)
    if env:
        return env.replace("\\", "/")
    m = main_repo()
    return _fwd(m.parent / (m.name + WORKTREES_SUFFIX))


def tools_root() -> str:
    env = os.environ.get(TOOLS_ROOT_ENV)
    if env:
        return env.replace("\\", "/")
    m = main_repo()
    return _fwd(m.parent / (m.name + TOOLS_SUFFIX))


def scratch_root() -> str:
    return tools_root() + "/scratch"


def locks_dir() -> str:
    return tools_root() + "/locks/godot_slots"


def is_agent_checkout(path: str) -> bool:
    """True when `path` is the main repo or sits under the worktrees root."""
    try:
        p = Path(path).resolve()
    except OSError:
        return False
    for root in (Path(repo_dir()), Path(worktrees_root())):
        try:
            p.relative_to(root.resolve())
            return True
        except ValueError:
            continue
    return False
