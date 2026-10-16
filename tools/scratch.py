#!/usr/bin/env python3
"""Organise and prune the agent scratch directory (default <tools root>/scratch).

Usage:
  python tools/scratch.py path <bead-id> [slug]      create + print root/<bead-id>[/<slug>]
  python tools/scratch.py index                      write root/INDEX.md (newest first)
  python tools/scratch.py prune [--apply] [--keep-days N]   dry-run by default
  python tools/scratch.py selftest                   run the built-in temp-root test

Global option: --root DIR (must resolve inside the tools root).
Prune candidates: top-level entries whose newest inner mtime is older than keep-days
AND (a bead dir whose bead is closed, OR a legacy non-bead entry). Always kept:
live git worktree names, non-closed or unknown-status bead dirs, recent entries.
`_orchestrator`, `editor` and INDEX.md are kept themselves but their children are
pruned by the same age rule. Symlinks/junctions are never followed.
Exit codes: 0 ok, 2 usage error.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Callable, Dict, List, Optional, Set, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repo_paths  # noqa: E402

DEFAULT_ROOT = repo_paths.scratch_root()
SAFE_PARENT = repo_paths.tools_root()
REPO = repo_paths.repo_dir()
BEAD_RE = re.compile(r"^Bontago-[a-z0-9]+(?:\.[a-z0-9]+)*$")
BEAD_PREFIX_RE = re.compile(r"^(Bontago-[a-z0-9]+(?:\.[a-z0-9]+)*)")
CONTAINERS = {"_orchestrator", "editor"}
DAY = 86400.0

StatusFn = Callable[[List[str]], Dict[str, str]]


class Usage(Exception):
    pass


def is_link(path: str) -> bool:
    try:
        st = os.lstat(path)
    except OSError:
        return False
    if stat.S_ISLNK(st.st_mode):
        return True
    return bool(getattr(st, "st_file_attributes", 0) & 0x400)  # reparse point (junction)


def _walk(path: str) -> Tuple[float, int]:
    """(newest mtime, total bytes) of path, via lstat, never following links."""
    try:
        st0 = os.lstat(path)
    except OSError:
        return 0.0, 0
    best = st0.st_mtime
    total = st0.st_size
    if is_link(path) or not os.path.isdir(path):
        return best, total
    stack = [path]
    while stack:
        cur = stack.pop()
        try:
            with os.scandir(cur) as it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    best = max(best, st.st_mtime)
                    total += st.st_size
                    if e.is_dir(follow_symlinks=False) and not is_link(e.path):
                        stack.append(e.path)
        except OSError:
            continue
    return best, total


def newest_mtime(path: str) -> float:
    return _walk(path)[0]


def tree_size(path: str) -> int:
    return _walk(path)[1]


def bead_of(name: str) -> Optional[str]:
    m = BEAD_PREFIX_RE.match(name)
    return m.group(1) if m else None


def bd_statuses(ids: List[str]) -> Dict[str, str]:
    """One bd call; returns {id: status}. Empty dict on any failure."""
    try:
        r = subprocess.run([shutil.which("bd") or "bd", "-C", REPO, "list", "--all", "--json", "--limit", "0"],
                           capture_output=True, text=True, timeout=120, check=False)
        data = json.loads(r.stdout)
        return {d["id"]: str(d.get("status", "?")) for d in data if "id" in d}
    except Exception as ex:  # noqa: BLE001
        print(f"warning: bd status lookup failed ({ex}); statuses unknown", file=sys.stderr)
        return {}


_SEP = r"(?:/|\\)+"
REF_RE = re.compile(re.escape(os.path.basename(SAFE_PARENT)) + _SEP + "scratch" + _SEP + r"([A-Za-z0-9._-]+)(?:" + _SEP
                    + r"([A-Za-z0-9._-]+))?")


def open_bead_refs() -> Optional[Set[str]]:
    """Names (and 'container/child' pairs) under scratch referenced by any non-closed bead.

    None when the bd export fails (callers then keep all legacy entries)."""
    fd, tmp = tempfile.mkstemp(prefix="scratch_export_", suffix=".jsonl")
    os.close(fd)
    try:
        r = subprocess.run([shutil.which("bd") or "bd", "-C", REPO, "export", "-o", tmp],
                           capture_output=True, text=True, timeout=300, check=False)
        if r.returncode != 0:
            raise RuntimeError(r.stderr.strip()[:200] or f"rc={r.returncode}")
        refs: Set[str] = set()
        with open(tmp, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                rec = json.loads(line)
                if not isinstance(rec, dict) or rec.get("status") == "closed":
                    continue
                for m in REF_RE.finditer(json.dumps(rec)):
                    refs.add(m.group(1))
                    if m.group(2):
                        refs.add(m.group(1) + "/" + m.group(2))
        return refs
    except Exception as ex:  # noqa: BLE001
        print(f"warning: bd export failed ({ex}); keeping ALL legacy entries", file=sys.stderr)
        return None
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass


def live_worktree_names() -> Set[str]:
    try:
        r = subprocess.run(["git", "-C", REPO, "worktree", "list", "--porcelain"],
                           capture_output=True, text=True, timeout=60, check=False)
    except Exception:  # noqa: BLE001
        return set()
    names: Set[str] = set()
    for line in r.stdout.splitlines():
        if line.startswith("worktree "):
            names.add(Path(line[9:].strip()).name)
    return names


def check_root(root: Path, allow_any: bool) -> Path:
    real = Path(os.path.realpath(root))
    if not allow_any:
        safe = Path(os.path.realpath(SAFE_PARENT))
        try:
            real.relative_to(safe)
        except ValueError:
            raise Usage(f"root {real} resolves outside {SAFE_PARENT}")
    return real


def cmd_path(root: Path, bead: str, slug: Optional[str]) -> str:
    if not BEAD_RE.match(bead):
        raise Usage(f"bad bead id {bead!r} (want Bontago-[a-z0-9.]+)")
    p = root / bead
    if slug:
        if not re.match(r"^[A-Za-z0-9._-]+$", slug) or slug in (".", ".."):
            raise Usage(f"bad slug {slug!r}")
        p = p / slug
    p.mkdir(parents=True, exist_ok=True)
    return str(p).replace("\\", "/")


def entries(root: Path) -> List[Path]:
    return sorted(root.iterdir(), key=lambda p: p.name)


def cmd_index(root: Path, status_fn: StatusFn) -> str:
    items: List[Tuple[float, int, Path]] = []
    for e in entries(root):
        if e.name == "INDEX.md":
            continue
        mt, sz = _walk(str(e))
        items.append((mt, sz, e))
    items.sort(key=lambda t: -t[0])
    bead_ids = sorted({b for _, _, e in items if (b := bead_of(e.name))})
    st = status_fn(bead_ids) if bead_ids else {}
    lines = ["# Scratch index", "",
             f"Generated {time.strftime('%Y-%m-%d %H:%M')}. "
             "New logs: `python tools/scratch.py path <bead-id> [slug]`.", "",
             "| name | bead | status | MB | last modified |", "|---|---|---|---|---|"]
    total = 0
    for mt, sz, e in items:
        total += sz
        b = bead_of(e.name)
        status = st.get(b, "?") if b else ""
        date = time.strftime("%Y-%m-%d %H:%M", time.localtime(mt)) if mt else "?"
        lines.append(f"| {e.name} | {b or ''} | {status} | {sz / 1048576:.1f} | {date} |")
    (root / "INDEX.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    return f"INDEX.md written: {len(items)} entries, {total / 1048576:.0f} MB"


def candidates(root: Path, keep_days: float, status_fn: StatusFn, live: Set[str],
               refs: Optional[Set[str]] = None, now: Optional[float] = None,
               stats: Optional[Dict[str, int]] = None) -> List[Tuple[str, int, float]]:
    """Return [(path, size_bytes, mtime)] of prunable entries.

    refs: names referenced by non-closed beads (kept). None = unknown (export failed):
    every legacy non-bead entry is kept. stats['kept_ref'] counts entries kept for that reason."""
    if stats is None:
        stats = {}
    stats.setdefault("kept_ref", 0)
    now = time.time() if now is None else now
    cutoff = now - keep_days * DAY
    top = entries(root)
    bead_ids = sorted({b for e in top if (b := bead_of(e.name))})
    st = status_fn(bead_ids) if bead_ids else {}
    out: List[Tuple[str, int, float]] = []

    def consider(p: Path, is_top: bool, key: str) -> None:
        mt, sz = _walk(str(p))
        if mt >= cutoff:
            return
        b = bead_of(p.name) if is_top else None
        if b is not None and st.get(b) != "closed":
            return  # open/unknown bead dir: keep
        if b is None and (refs is None or key in refs):
            stats["kept_ref"] += 1
            return  # referenced by an open bead (or references unknown): keep
        out.append((str(p), sz, mt))

    for e in top:
        if e.name == "INDEX.md" or e.name in live:
            continue
        if e.name in CONTAINERS:
            if is_link(str(e)) or not e.is_dir():
                continue
            for c in sorted(e.iterdir(), key=lambda p: p.name):
                consider(c, False, e.name + "/" + c.name)
            continue
        consider(e, True, e.name)
    return out


def _onerror(func: Callable[..., object], path: str, _exc: object) -> None:
    os.chmod(path, stat.S_IWRITE)
    func(path)


def delete_entry(path: str) -> None:
    if is_link(path):
        # remove only the link itself, never the target
        try:
            os.unlink(path)
        except OSError:
            os.rmdir(path)
        return
    if os.path.isdir(path):
        shutil.rmtree(path, onerror=_onerror)
    else:
        try:
            os.unlink(path)
        except PermissionError:
            os.chmod(path, stat.S_IWRITE)
            os.unlink(path)


def cmd_prune(root: Path, apply: bool, keep_days: float, status_fn: StatusFn,
              live: Set[str], refs: Optional[Set[str]]) -> str:
    stats: Dict[str, int] = {}
    cands = candidates(root, keep_days, status_fn, live, refs, None, stats)
    total = sum(s for _, s, _ in cands)
    kept_live = sorted(n for n in live if (root / n).exists())
    out = [f"{'APPLY' if apply else 'DRY-RUN'}: {len(cands)} candidates, "
           f"{total / 1048576:.0f} MB (keep-days {keep_days:g}); "
           f"live worktrees kept: {len(kept_live)} {kept_live}; "
           f"kept by open-bead reference: {stats['kept_ref']}"
           + ("" if refs is not None else " (export failed: all legacy kept)")]
    for p, s, mt in sorted(cands, key=lambda t: -t[1])[:15]:
        d = time.strftime('%Y-%m-%d', time.localtime(mt))
        out.append(f"  {s / 1048576:9.1f} MB  {d}  {Path(p).name}")
    if apply:
        freed = 0
        fails: List[str] = []
        for p, s, _ in cands:
            try:
                delete_entry(p)
                freed += s
            except Exception as ex:  # noqa: BLE001
                fails.append(f"{p}: {ex}")
        out.append(f"freed {freed / 1048576:.0f} MB; {len(fails)} failures")
        out.extend("  FAIL " + f for f in fails[:20])
    return "\n".join(out)


def selftest() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="scratch_selftest_"))
    try:
        root = tmp / "scratch"
        root.mkdir()
        now = time.time()
        old, new = now - 10 * DAY, now - 3600

        def mk(rel: str, mt: float) -> None:
            p = root / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_bytes(b"x" * 1000)
            os.utime(p, (mt, mt))
            os.utime(p.parent, (mt, mt))

        mk("Bontago-aaaa.1/log.txt", old)          # closed + old -> delete
        mk("Bontago-bbbb.2/log.txt", old)          # open + old -> keep
        mk("Bontago-cccc.3/log.txt", new)          # closed + new -> keep
        mk("legacy-old/f.txt", old)               # legacy old -> delete
        mk("legacy-new/f.txt", new)               # legacy new -> keep
        mk("wt-live/f.txt", old)                  # live worktree -> keep
        mk("Bontago-dddd.4/f.txt", old)            # unknown status -> keep
        mk("_orchestrator/oldchild/f.txt", old)   # child old -> delete
        mk("_orchestrator/newchild/f.txt", new)   # child new -> keep
        mk("INDEX.md", old)                       # keep
        os.chmod(root / "legacy-old" / "f.txt", stat.S_IREAD)  # read-only must still delete
        os.utime(root / "legacy-old", (old, old))
        outside = tmp / "outside"
        outside.mkdir()
        (outside / "keep.txt").write_text("precious")
        link_made = False
        try:
            os.symlink(outside, root / "legacy-link", target_is_directory=True)
            link_made = True
        except OSError:
            pass

        def sfn(ids: List[str]) -> Dict[str, str]:
            return {"Bontago-aaaa.1": "closed", "Bontago-bbbb.2": "open", "Bontago-cccc.3": "closed"}

        mk("legacy-ref/f.txt", old)               # referenced by open bead -> keep
        mk("_orchestrator/refchild/f.txt", old)   # container child referenced -> keep
        live = {"wt-live"}
        refs = {"legacy-ref", "_orchestrator/refchild"}
        stats: Dict[str, int] = {}
        cands = {Path(p).relative_to(root).as_posix()
                 for p, _, _ in candidates(root, 3, sfn, live, refs, None, stats)}
        assert stats["kept_ref"] == 2, stats
        # export failure (refs None) keeps every legacy entry, still prunes closed bead dir
        failsafe = {Path(p).relative_to(root).as_posix()
                    for p, _, _ in candidates(root, 3, sfn, live, None)}
        assert failsafe == {"Bontago-aaaa.1"}, failsafe
        td = os.path.basename(SAFE_PARENT)
        ref_text = "/%s/scratch/_orchestrator/x-1 and /%s/scratch/dropsound/a" % (td, td)
        m = REF_RE.search(json.dumps({"c": ref_text.replace("/", chr(92), 4)}))
        assert m and m.group(1) == "_orchestrator" and m.group(2) == "x-1", m
        expect = {"Bontago-aaaa.1", "legacy-old", "_orchestrator/oldchild"}
        cands.discard("legacy-link")  # link mtime is "now" or platform-specific
        assert cands == expect, cands
        cmd_prune(root, False, 3, sfn, live, refs)
        assert (root / "legacy-old").exists(), "dry-run deleted"
        cmd_prune(root, True, 3, sfn, live, refs)
        for gone in expect:
            assert not (root / gone).exists(), gone
        for kept in ("Bontago-bbbb.2", "Bontago-cccc.3", "legacy-new", "wt-live", "Bontago-dddd.4",
                     "_orchestrator/newchild", "legacy-ref", "_orchestrator/refchild", "INDEX.md", "_orchestrator"):
            assert (root / kept).exists(), kept
        assert (outside / "keep.txt").exists(), "followed link"
        # force-delete the link directly: target must survive
        if link_made:
            delete_entry(str(root / "legacy-link"))
            assert (outside / "keep.txt").exists(), "link delete hit target"
        assert cmd_path(root, "Bontago-zz.9", "s").endswith("Bontago-zz.9/s")  # lint-public: allow fixture
        try:
            cmd_path(root, "bad id", None)
            raise AssertionError("bad id accepted")
        except Usage:
            pass
        try:
            check_root(tmp, False)
            raise AssertionError("outside root accepted")
        except Usage:
            pass
        print(cmd_index(root, sfn))
        print(f"selftest OK (symlink case {'run' if link_made else 'skipped'})")
        return 0
    finally:
        def _rm(f: Callable[..., object], p: str, _e: object) -> None:
            os.chmod(p, stat.S_IWRITE)
            f(p)
        shutil.rmtree(tmp, onerror=_rm)


def main(argv: List[str]) -> int:
    args = list(argv)
    root_s = DEFAULT_ROOT
    allow_any = False
    pos: List[str] = []
    apply = False
    keep_days = 3.0
    try:
        i = 0
        while i < len(args):
            a = args[i]
            if a == "--root":
                i += 1
                root_s = args[i]
            elif a == "--apply":
                apply = True
            elif a == "--keep-days":
                i += 1
                keep_days = float(args[i])
            elif a == "--allow-any-root":  # hidden: tests only
                allow_any = True
            elif a.startswith("--"):
                raise Usage(f"unknown option {a}")
            else:
                pos.append(a)
            i += 1
        if not pos:
            raise Usage("command required: path | index | prune | selftest")
        cmd = pos[0]
        if cmd == "selftest":
            return selftest()
        root = check_root(Path(root_s), allow_any)
        if cmd == "path":
            if len(pos) not in (2, 3):
                raise Usage("path <bead-id> [slug]")
            root.mkdir(parents=True, exist_ok=True)
            print(cmd_path(root, pos[1], pos[2] if len(pos) == 3 else None))
        elif cmd == "index":
            print(cmd_index(root, bd_statuses))
        elif cmd == "prune":
            print(cmd_prune(root, apply, keep_days, bd_statuses, live_worktree_names(), open_bead_refs()))
        else:
            raise Usage(f"unknown command {cmd}")
    except (Usage, IndexError, ValueError) as ex:
        print(f"usage error: {ex}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
