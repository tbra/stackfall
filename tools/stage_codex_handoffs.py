"""Stage Codex asset handoffs into one integration branch, one commit per bead (Bontago-fca.14).

  python tools/stage_codex_handoffs.py --beads Bontago-mp0.52 Bontago-mp0.53 --branch wt/assets-batch3
         [--worktree-root M:/Bontago-worktrees] [--repo M:/Bontago] [--base <rev, default main>]
         [--dry-run] [--min-age-min 30] [--allow-missing] [--no-import] [--godot godot] [--log-dir DIR]

Codex leaves each package UNCOMMITTED in its own checkout (M:/Bontago/.claude/worktrees/codex-*) and names
that path in a bead comment (author "codex"; backslashes or slashes; the LAST path mentioned wins). This
tool turns those candidates into reviewable, mergeable commits without ever modifying a Codex worktree
(its only commands there are `git --no-optional-locks status` and file reads).

Per bead (`bd comments <id> --json`, `bd show <id> --json --brief-deps`):
  NO-WT        no worktree path in the codex comments, or the directory is gone (skipped; non-zero
               exit unless --allow-missing)
  MODIFIED(n)  `git status --porcelain -uall` shows a tracked modification/deletion/rename: asset
               packages must be pure additions ("??" or "A"), the paths are listed
  EMPTY        nothing to stage (already committed or cleaned)
  MISSING(n)   a listed addition is not on disk
  TOO-RECENT   newest file is younger than --min-age-min (Codex may still be writing)
Across beads: OVERLAP(n) a path claimed by two candidates, COLLIDE(n) a path already in the --base tree
(case-insensitive, as Windows checks out). Any flagged bead refuses the whole run (all or nothing, so a
failed run never leaves a half-staged branch); --allow-missing only forgives NO-WT. Non-asset paths (outside
assets/, source_art/, docs/art_mockups/, docs/audio_review/, tools/generate_*) are reported, not refused.

Unless --dry-run: `git worktree add -b <branch> <root>/<branch tail> <base>`, copy each bead's files
(never overwrites), `git add -- <files>` (chunked for the Windows command-line limit) and one commit
"<title> (<bead>)" per bead, then verify the branch diff against <base> is exactly the staged files. A
failure after the worktree exists removes that worktree and branch (the Codex sources are untouched).

Import metadata (Bontago-fca.25): after the per-bead commits, `godot --headless --editor --path <staging
worktree> --quit` runs once (--godot to override the executable) so Godot generates the `.import` / `.uid`
sidecars; only the untracked sidecars belonging to the staged paths (`<path>.import`, `<path>.uid`) are
committed, as a final "Import metadata for staged assets" commit (nothing else Godot touches is added).
The branch diff check then expects staged files + those sidecars. --dry-run creates nothing but lists the
staged paths expected to gain sidecars ("import metadata candidates"); --no-import skips the step.

Stdout is compact: one line per bead, then `STAGE OK branch=<b> head=<sha> beads=N files=M`,
`STAGE REFUSED: <reason>` or `STAGE FAILED at <step>: <detail>`; full detail goes to <log-dir>/detail.txt
and one log per command. Exit 0 = staged (or dry-run clean), 1 = refused or failed.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

DEFAULT_REPO = "M:/Bontago"
DEFAULT_WORKTREE_ROOT = "M:/Bontago-worktrees"
DEFAULT_MIN_AGE_MIN = 30.0
GIT_TIMEOUT_S = 120
STEP_TIMEOUT_S = 600
CODEX_AUTHOR = "codex"
ASSET_PREFIXES = ("assets/", "source_art/", "docs/art_mockups/", "docs/audio_review/", "tools/generate_")
BYTES_PER_MB = 1_000_000
SECONDS_PER_MIN = 60.0
MAX_LISTED = 3  # paths listed per stdout line; detail.txt has every one
IMPORT_TIMEOUT_S = 1800
SIDECAR_SUFFIXES = (".import", ".uid")
NO_SIDECAR_SUFFIXES = (".import", ".uid", ".md", ".txt", ".json", ".py", ".cfg", ".ps1", ".csv")
ADD_CHUNK_CHARS = 20000  # stay well under the ~32k Windows command-line limit
COMMIT_TRAILER = "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
# Drive path whose parent directory name ends in "worktrees" (.claude/worktrees/x, Bontago-worktrees/x).
# DECISION (Bontago-fca.14): path segments may not contain spaces; Codex worktrees never do.
WORKTREE_RE = re.compile(r"[A-Za-z]:/(?:[\w.\-]+/)*[\w.\-]*worktrees/[\w.\-]+")
STATUS_RE = re.compile(r"^([ MADRCUT?!]{2}) (.+)$")
_ESCAPES = {"n": 10, "t": 9, "r": 13, '"': 34, "\\": 92, "a": 7, "b": 8, "f": 12, "v": 11}


class StepFailed(Exception):
    def __init__(self, step, detail):
        super().__init__(step + ": " + detail)
        self.step = step
        self.detail = detail


class Refused(Exception):
    """Expected, reported outcome: the batch is not stageable as asked."""

    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason


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


# Filesystem/clock seams (patched in tests; the Codex worktrees are only ever read through these).
def file_stat(path):
    """(size_bytes, mtime) of a regular file, or None."""
    try:
        if not os.path.isfile(path):
            return None
        st = os.stat(path)
        return st.st_size, st.st_mtime
    except OSError:
        return None


def is_dir(path):
    return os.path.isdir(path)


def path_exists(path):
    return os.path.exists(path)


def copy_file(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(src, dst)


def now():
    return time.time()


def fwd_join(base, rel):
    """Join with forward slashes (git and Windows both accept them; keeps logs and tests portable)."""
    return base.replace("\\", "/").rstrip("/") + "/" + rel


def bd_exe():
    # npm installs bd as bd.CMD on Windows; CreateProcess (no shell) cannot find it by bare name.
    return shutil.which("bd") or "bd"


def git(ctx, name, repo, *a, timeout=GIT_TIMEOUT_S):
    return run_cmd(ctx, name, ["git", "-C", repo, *a], repo, timeout)


def git_out(ctx, name, repo, *a):
    code, text, _ = git(ctx, name, repo, *a)
    if code != 0:
        raise StepFailed(name, "git %s failed (%d)" % (" ".join(a), code))
    return text.strip()


def parse_json(text):
    """First JSON list/dict that starts a line (tolerates bd warnings merged from stderr)."""
    dec = json.JSONDecoder()
    for m in re.finditer(r"(?m)^[\[{]", text):
        try:
            return dec.raw_decode(text, m.start())[0]
        except ValueError:
            continue
    raise ValueError("no JSON in output")


def codex_comments(comments):
    cx = [c for c in comments if str(c.get("author", "")).lower() == CODEX_AUTHOR]
    if cx and all(c.get("created_at") for c in cx):
        cx.sort(key=lambda c: c["created_at"])  # stable: same-second comments keep bd's order
    return cx


def extract_worktree(comments):
    """Last worktree path named in a codex-authored comment (backslashes normalised), else None."""
    last = None
    for c in codex_comments(comments):
        for m in WORKTREE_RE.finditer(str(c.get("text", "")).replace("\\", "/")):
            last = m.group(0).rstrip(".-")
    return last


def unquote_path(p):
    """Undo git's C-style quoting of a porcelain path (spaces/specials are wrapped in quotes)."""
    if len(p) < 2 or p[0] != '"' or p[-1] != '"':
        return p
    body, out, i = p[1:-1], bytearray(), 0
    while i < len(body):
        ch = body[i]
        if ch == "\\" and i + 1 < len(body):
            nxt = body[i + 1]
            if nxt in "01234567":
                j = i + 1
                digits = ""
                while j < len(body) and len(digits) < 3 and body[j] in "01234567":
                    digits += body[j]
                    j += 1
                out.append(int(digits, 8) & 0xFF)
                i = j
                continue
            if nxt in _ESCAPES:
                out.append(_ESCAPES[nxt])
                i += 2
                continue
        out.extend(ch.encode("utf-8"))
        i += 1
    return out.decode("utf-8", "replace")


def parse_porcelain(text):
    """[(XY, path)] from `git status --porcelain`; non-status lines (CRLF warnings etc.) are ignored."""
    rows = []
    for line in text.splitlines():
        m = STATUS_RE.match(line)
        if not m:
            continue
        xy, rest = m.group(1), m.group(2)
        if xy[0] in "RC" and " -> " in rest:
            path = rest  # "old -> new": reported, never staged (renames are refused)
        else:
            path = unquote_path(rest)
        rows.append((xy, path))
    return rows


def is_addition(xy):
    return xy == "??" or (xy[0] == "A" and xy[1] in " M")


def is_asset_path(path):
    return path.startswith(ASSET_PREFIXES)


def normalize_eol(ctx, dest, c):
    """CRLF -> LF in the copied text files so `git add` prints no line-ending warnings (fca.26)."""
    for i, chunk in enumerate(add_chunks(c.paths)):
        code, text, log = run_cmd(ctx, "eol_%s_%d" % (c.bead, i),
                                  [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "normalize_eol.py"),
                                   "--path", dest, *chunk],
                                  dest, STEP_TIMEOUT_S)
        if code != 0:
            raise StepFailed("eol", "normalize_eol failed for %s; log %s" % (c.bead, log))


def sidecar_candidates(paths):
    """Staged paths expected to gain a .import (assets) or .uid (scripts/shaders) sidecar from an editor import."""
    return [p for p in paths if not p.lower().endswith(NO_SIDECAR_SUFFIXES)]


def import_metadata(ctx, godot, dest, staged_paths, say):
    """Run the editor import in the staging worktree and commit the sidecars of staged paths. Returns their paths."""
    code, text, log = run_cmd(ctx, "godot_import", [shutil.which(godot) or godot, "--headless", "--editor", "--path", dest, "--quit"],
                              dest, IMPORT_TIMEOUT_S)
    if code != 0:
        raise StepFailed("import", "godot editor import exited %d; log %s" % (code, log))
    owners = set(p.lower() for p in staged_paths)
    code, text, log = git(ctx, "status_import", dest, "-c", "core.quotepath=false", "status", "--porcelain",
                          "-uall", timeout=STEP_TIMEOUT_S)
    if code != 0:
        raise StepFailed("import", "git status failed after import; log " + log)
    sidecars = []
    for xy, path in parse_porcelain(text):
        if xy == "??" and path.lower().endswith(SIDECAR_SUFFIXES):
            if path.rsplit(".", 1)[0].lower() in owners:
                sidecars.append(path)
    if not sidecars:
        say("import metadata: no new sidecars")
        return []
    for i, chunk in enumerate(add_chunks(sidecars)):
        code, text, log = git(ctx, "add_import_%d" % i, dest, "add", "--", *chunk, timeout=STEP_TIMEOUT_S)
        if code != 0:
            raise StepFailed("import", "git add of sidecars failed; log " + log)
    code, text, log = git(ctx, "commit_import", dest, "commit", "-q", "-m", "Import metadata for staged assets",
                          "-m", "Generated .import/.uid files for the staged asset paths only.",
                          "-m", COMMIT_TRAILER, timeout=STEP_TIMEOUT_S)
    if code != 0:
        raise StepFailed("import", "git commit of sidecars failed; log " + log)
    say("committed import metadata (%d files)" % len(sidecars))
    return sidecars


def commit_message(title, bead, wt):
    """(subject, body, trailer): one commit per bead."""
    return ("%s (%s)" % (title, bead),
            "Staged from Codex handoff worktree %s (uncommitted candidate)." % wt,
            COMMIT_TRAILER)


def add_chunks(paths, limit=ADD_CHUNK_CHARS):
    chunk, size = [], 0
    for p in paths:
        if chunk and size + len(p) + 1 > limit:
            yield chunk
            chunk, size = [], 0
        chunk.append(p)
        size += len(p) + 1
    if chunk:
        yield chunk


class Cand:
    def __init__(self, bead):
        self.bead = bead
        self.title = ""
        self.wt = None
        self.tail = "-"
        self.rows = []       # (xy, path, size, mtime)
        self.flags = []
        self.notes = []
        self.total = 0
        self.largest = ("", 0)
        self.age_min = None
        self.nonasset = []
        self.modified = []
        self.overlaps = []   # (path, other beads)
        self.collisions = []

    @property
    def paths(self):
        return [r[1] for r in self.rows]

    @property
    def verdict(self):
        return "+".join(self.flags) or "OK"

    def flag(self, name):
        if name not in self.flags:
            self.flags.append(name)


def assess_bead(ctx, bd, repo, bead, min_age_min):
    """Resolve and inspect one bead's Codex worktree. Reads only; flags problems on the Cand."""
    c = Cand(bead)
    code, text, log = run_cmd(ctx, "bd_comments_" + bead, [bd, "-C", repo, "comments", bead, "--json"],
                              repo, GIT_TIMEOUT_S)
    try:
        if code != 0:
            raise ValueError("exit %d" % code)
        comments = parse_json(text)
        if not isinstance(comments, list):
            raise ValueError("comments are not a list")
    except ValueError as e:
        raise StepFailed("bd", "bd comments %s unusable (%s); log %s" % (bead, e, log))
    code, text, log = run_cmd(ctx, "bd_show_" + bead, [bd, "-C", repo, "show", bead, "--json", "--brief-deps"],
                              repo, GIT_TIMEOUT_S)
    try:
        if code != 0:
            raise ValueError("exit %d" % code)
        shown = parse_json(text)
        shown = shown[0] if isinstance(shown, list) and shown else shown
        c.title = str(shown.get("title") or "").strip()
    except (ValueError, AttributeError) as e:
        raise StepFailed("bd", "bd show %s unusable (%s); log %s" % (bead, e, log))
    c.title = c.title or "Codex asset handoff"
    c.wt = extract_worktree(comments)
    if c.wt is None:
        c.flag("NO-WT")
        c.notes.append("no worktree path in codex-authored comments")
        return c
    c.tail = c.wt.rsplit("/", 1)[-1]
    if not is_dir(c.wt):
        c.flag("NO-WT")
        c.notes.append("worktree directory not found: " + c.wt)
        return c
    code, text, log = run_cmd(ctx, "status_" + bead,
                              ["git", "--no-optional-locks", "-c", "core.quotepath=false", "-C", c.wt,
                               "status", "--porcelain", "-uall"], repo, STEP_TIMEOUT_S)
    if code != 0:
        c.flag("GIT-FAIL")
        c.notes.append("git status failed (%d); log %s" % (code, log))
        return c
    porcelain = parse_porcelain(text)
    if not porcelain:
        c.flag("EMPTY")
        c.notes.append("clean worktree: nothing to stage")
        return c
    missing = []
    for xy, path in porcelain:
        if not is_addition(xy):
            c.modified.append((xy, path))
        st = file_stat(fwd_join(c.wt, path))
        if st is None:
            if is_addition(xy):
                missing.append(path)
            c.rows.append((xy, path, 0, None))
        else:
            c.rows.append((xy, path, st[0], st[1]))
    c.total = sum(r[2] for r in c.rows)
    c.largest = max(((r[1], r[2]) for r in c.rows), key=lambda t: t[1])
    c.nonasset = [r[1] for r in c.rows if not is_asset_path(r[1])]
    mtimes = [r[3] for r in c.rows if r[3] is not None]
    if mtimes:
        c.age_min = (now() - max(mtimes)) / SECONDS_PER_MIN
    if c.modified:
        c.flag("MODIFIED(%d)" % len(c.modified))
    if missing:
        c.flag("MISSING(%d)" % len(missing))
        c.notes.append("missing on disk: " + brief(missing))
    if c.age_min is not None and c.age_min < min_age_min:
        c.flag("TOO-RECENT")
        c.notes.append("newest file %.1f min old, minimum %.1f" % (c.age_min, min_age_min))
    return c


def brief(items, n=MAX_LISTED):
    items = list(items)
    s = ", ".join(items[:n])
    return s + (" (+%d more)" % (len(items) - n) if len(items) > n else "")


def cross_check(cands, base_files):
    """Flag overlaps between candidates and collisions with the base tree. Returns the overlap map."""
    base_lower = set(p.lower() for p in base_files)
    claim = {}
    for c in cands:
        for p in c.paths:
            claim.setdefault(p.lower(), []).append((c, p))
    overlaps = {}
    for key, owners in claim.items():
        beads = []
        for c, _ in owners:
            if c.bead not in beads:
                beads.append(c.bead)
        if len(beads) > 1:
            overlaps[key] = (owners[0][1], beads)
            for c, p in owners:
                if not any(o[0] == p for o in c.overlaps):
                    c.overlaps.append((p, [b for b in beads if b != c.bead]))
    for c in cands:
        c.collisions = [p for p in c.paths if p.lower() in base_lower]
        if c.overlaps:
            c.flag("OVERLAP(%d)" % len(c.overlaps))
        if c.collisions:
            c.flag("COLLIDE(%d)" % len(c.collisions))
    return overlaps


def bead_line(c):
    age = "-" if c.age_min is None else "%dm" % c.age_min
    return "%-17s %-30s files=%-4d %8.2fMB age=%-6s %s" % (
        c.bead, c.tail[:30], len(c.rows), c.total / BYTES_PER_MB, age, c.verdict)


def report(say, cands):
    for c in cands:
        say(bead_line(c))
        for note in c.notes:
            say("    " + note)
        if c.modified:
            say("    modified (not additions): " + brief("%s %s" % (xy.strip() or "?", p) for xy, p in c.modified))
        if c.overlaps:
            say("    overlap: " + brief("%s with %s" % (p, "/".join(o)) for p, o in c.overlaps))
        if c.collisions:
            say("    collides with base: " + brief(c.collisions))
        if c.nonasset:
            say("    non-asset paths (%d): %s" % (len(c.nonasset), brief(c.nonasset, 3)))


def write_detail(path, cands, base, problems):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("base %s\n" % base)
        for p in problems:
            fh.write("PROBLEM %s\n" % p)
        for c in cands:
            fh.write("\n== %s %s\n   title: %s\n   worktree: %s\n   verdict: %s\n" % (
                c.bead, c.tail, c.title, c.wt, c.verdict))
            fh.write("   files=%d total=%.3fMB largest=%s (%.3fMB) age_min=%s\n" % (
                len(c.rows), c.total / BYTES_PER_MB, c.largest[0], c.largest[1] / BYTES_PER_MB, c.age_min))
            for n in c.notes:
                fh.write("   note: %s\n" % n)
            for xy, p, size, _ in c.rows:
                fh.write("   [%s] %10d %s\n" % (xy, size, p))
            for p in c.nonasset:
                fh.write("   NONASSET %s\n" % p)
            for p, o in c.overlaps:
                fh.write("   OVERLAP %s with %s\n" % (p, ", ".join(o)))
            for p in c.collisions:
                fh.write("   COLLIDE %s\n" % p)


def stage(args, ctx, say, res):
    """Assess, refuse or stage. Returns (head, beads, files); raises Refused / StepFailed."""
    repo = args.repo
    bd = bd_exe()
    base = git_out(ctx, "rev_base", repo, "rev-parse", "--verify", args.base + "^{commit}")
    beads = list(dict.fromkeys(args.beads))
    cands = [assess_bead(ctx, bd, repo, b, args.min_age_min) for b in beads]
    have_files = [c for c in cands if c.rows]
    overlaps = {}
    if have_files:
        base_files = git_out(ctx, "ls_tree", repo, "ls-tree", "-r", "--name-only", "-z", base).split("\0")
        overlaps = cross_check(have_files, [p for p in base_files if p])
    tail = args.branch.rstrip("/").rsplit("/", 1)[-1]
    dest = fwd_join(args.worktree_root, tail)
    problems = []
    if not tail:
        problems.append("empty branch name")
    elif git(ctx, "branch_exists", repo, "rev-parse", "--verify", "--quiet", args.branch + "^{commit}")[0] == 0:
        problems.append("branch already exists: " + args.branch)
    if tail and path_exists(dest):
        problems.append("worktree path already exists: " + dest)
    for c in cands:
        if c.flags and not (c.flags == ["NO-WT"] and args.allow_missing):
            problems.append("%s %s" % (c.bead, c.verdict))
    staged = [c for c in cands if not c.flags]
    if not staged and not problems:
        problems.append("no candidate to stage (all NO-WT)")
    write_detail(os.path.join(ctx.log_dir, "detail.txt"), cands, base, problems)
    report(say, cands)
    if overlaps:
        say("overlaps: " + brief("%s (%s)" % (p, "/".join(b)) for p, b in overlaps.values()))
    if problems:
        raise Refused("; ".join(problems)[:400])
    files = sum(len(c.rows) for c in staged)
    if args.dry_run:
        if not args.no_import:
            cand = sidecar_candidates([p for c in staged for p in c.paths])
            say("import metadata candidates (%d): %s" % (len(cand), brief(cand)))
            with open(os.path.join(ctx.log_dir, "detail.txt"), "a", encoding="utf-8") as fh:
                for p in cand:
                    fh.write("IMPORT-CANDIDATE %s\n" % p)
        return "dry-run", len(staged), files
    # worktree + one commit per bead
    code, text, log = git(ctx, "worktree_add", repo, "worktree", "add", "-b", args.branch, dest, base)
    if code != 0:
        raise StepFailed("worktree", "git worktree add failed; log " + log)
    res["worktree"], res["branch"] = dest, args.branch
    staged_paths = []
    for c in staged:
        for xy, p, _, _ in c.rows:
            dst = fwd_join(dest, p)
            if path_exists(dst):
                raise StepFailed("copy", "refusing to overwrite " + dst)
            copy_file(fwd_join(c.wt, p), dst)
        normalize_eol(ctx, dest, c)
        for i, chunk in enumerate(add_chunks(c.paths)):
            code, text, log = git(ctx, "add_%s_%d" % (c.bead, i), dest, "add", "--", *chunk,
                                  timeout=STEP_TIMEOUT_S)
            if code != 0:
                raise StepFailed("add", "git add failed for %s; log %s" % (c.bead, log))
        subject, body, trailer = commit_message(c.title, c.bead, c.wt)
        code, text, log = git(ctx, "commit_" + c.bead, dest, "commit", "-q", "-m", subject, "-m", body,
                              "-m", trailer, timeout=STEP_TIMEOUT_S)
        if code != 0:
            raise StepFailed("commit", "git commit failed for %s; log %s" % (c.bead, log))
        staged_paths.extend(c.paths)
        say("committed %s (%d files)" % (c.bead, len(c.rows)))
    if not args.no_import:
        staged_paths.extend(import_metadata(ctx, args.godot, dest, staged_paths, say))
    head = git_out(ctx, "rev_head", dest, "rev-parse", "HEAD")
    changed = git_out(ctx, "verify_diff", dest, "diff", "--name-only", "--no-renames", "-z",
                       base, "HEAD").split("\0")
    if sorted(p.lower() for p in changed if p) != sorted(p.lower() for p in staged_paths):
        raise StepFailed("verify", "branch diff vs %s is not exactly the %d staged files (%d changed)" % (
            base[:9], len(staged_paths), len([p for p in changed if p])))
    return head[:9], len(staged), files


def cleanup(args, ctx, res):
    """Remove the tool's own worktree + branch after a failure (never a Codex worktree)."""
    if res.get("worktree"):
        git(ctx, "wt_remove", args.repo, "worktree", "remove", "--force", res["worktree"])
        git(ctx, "br_delete", args.repo, "branch", "-D", res["branch"])


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--beads", nargs="+", required=True)
    ap.add_argument("--branch", required=True, help="new branch to create, e.g. wt/assets-batch3")
    ap.add_argument("--worktree-root", default=DEFAULT_WORKTREE_ROOT)
    ap.add_argument("--repo", default=DEFAULT_REPO)
    ap.add_argument("--base", default="main", help="revision to branch from (default: main HEAD)")
    ap.add_argument("--dry-run", action="store_true", help="assess and report only; create nothing")
    ap.add_argument("--min-age-min", type=float, default=DEFAULT_MIN_AGE_MIN,
                    help="refuse a candidate whose newest file is younger than this (minutes)")
    ap.add_argument("--allow-missing", action="store_true",
                    help="skip beads with no usable Codex worktree (NO-WT) instead of refusing the run")
    ap.add_argument("--godot", default="godot", help="Godot executable for the import step")
    ap.add_argument("--no-import", action="store_true", help="skip the editor import + import metadata commit")
    ap.add_argument("--log-dir", default="")
    args = ap.parse_args(argv)
    log_dir = args.log_dir or tempfile.mkdtemp(prefix="stage_codex_handoffs_")
    os.makedirs(log_dir, exist_ok=True)
    ctx = Ctx(log_dir)
    res = {}

    def say(line):
        print(line, flush=True)

    try:
        head, nbeads, nfiles = stage(args, ctx, say, res)
    except Refused as e:
        say("STAGE REFUSED: %s; logs=%s" % (e.reason, log_dir))
        return 1
    except StepFailed as e:
        cleanup(args, ctx, res)
        say("STAGE FAILED at %s: %s; logs=%s%s" % (e.step, e.detail[:400], log_dir,
                                                   "; worktree+branch removed" if res.get("worktree") else ""))
        return 1
    if args.dry_run:
        say("STAGE OK (dry-run) branch=%s head=- beads=%d files=%d logs=%s" % (args.branch, nbeads, nfiles, log_dir))
    else:
        say("STAGE OK branch=%s head=%s beads=%d files=%d logs=%s" % (args.branch, head, nbeads, nfiles, log_dir))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
