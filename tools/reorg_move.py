#!/usr/bin/env python3
"""Scripted project reorganisation: git mv a move map and rewrite every reference (Bontago-uwq.6).

  python tools/reorg_move.py --map <tsv> [--path <checkout>] [--rules <tsv>] [--extra <file>...]
         (--dry-run | --apply | --verify) [--base-ref REV] [--report FILE]

The map (TSV, header `old_path new_path action reason`, `#` comment lines ignored) has one row per
tracked file. Actions: move / restore-move (git mv; companions .uid/.import are rows of their own),
keep (no change), delete / delete-owner / delete-toolscut (git rm, skipped when already gone).

--dry-run  Validate the map and print the plan: git operations, files that would be rewritten
           and how many references, unmapped tracked files, references to a split directory prefix
           (e.g. `res://game/`) that no rule resolves. Nothing is touched. Exit 1 on any error.
--apply    The same plan, then execute it: git rm / git mv (restore-move first checks the file out
           of --base-ref, default HEAD, when it is missing), delete emptied folders, rewrite the
           text of every tracked .gd .tscn .tres .gdshader .gdshaderinc .cfg .json .py .ps1 .md
           .toml .yaml .txt file plus project.godot, export_presets.cfg, .gutconfig.json,
           .gitignore, .gitattributes, .claude/** .agents/** .codex/** and each --extra file.
           Refuses to start while the plan has errors (--allow-unresolved overrides). Idempotent:
           a second run (or a run on another branch) only does what that tree still needs.
--verify   Exit non-zero unless: (a) no old path or old directory string is left outside
           docs/archive, .git, .beads, addons and the map/rules files, and no split-prefix
           reference is unresolved; (b) the editor opens clean (two runs); (c) every script
           compiles (tools/check_scripts.gd); (d) dep_graph reports no more broken references
           than --expect-broken (default 0) and the .uid count is unchanged; (e) lint_layers is
           GREEN; (f) the lint membership (tools/layer_rules.json) maps old -> new exactly;
           class_name set unchanged. --skip-godot omits (b) and (c).

References are rewritten as `res://<old>`, `<old>` and the Windows `old\\path` forms at path
boundaries (a token is a run of [\\w./\\-] after a non-path character; its longest
separator-cut prefix found in the map is replaced, so `old.gd.uid` and `res://olddir/x` work).
.import files rewrite only their `source_file=` / `path*=` keys. tools/layer_rules.json lists are
regenerated so the lint membership stays exactly the image of the old membership.

--rules (default tools/reorg_move_rules.tsv beside this script) holds the manual part:
  rewrite<TAB>old<TAB>new       extra token rewrite (a dir or a file) applied with the map
  allow<TAB>file-glob<TAB>token-glob   a split-prefix token that is intended (fnmatch)
  replace<TAB>file<TAB>old literal<TAB>new literal   exact one-line edit of a file (named by its OLD
                path) for data the token rewrite cannot express, e.g. a name-prefix list
Comment lines of .gd/.py/.ps1 files and all .md files are not scanned for split prefixes
(prose names layers); they are still rewritten and still checked for old paths.
"""
from __future__ import print_function

import argparse
import collections
import fnmatch
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
DEFAULT_RULES = os.path.join(HERE, "reorg_move_rules.tsv")
LAYER_RULES = "tools/layer_rules.json"

MOVE_ACTIONS = ("move", "restore-move")
SKIP_PREFIXES = ("docs/archive/", ".git/", ".godot/", ".beads/", "addons/")
TEXT_EXT = frozenset([".gd", ".tscn", ".tres", ".gdshader", ".gdshaderinc", ".cfg", ".json", ".py",
                      ".ps1", ".md", ".toml", ".yaml", ".yml", ".txt", ".import"])
SPECIAL_FILES = frozenset(["project.godot", "export_presets.cfg", ".gutconfig.json", ".gitignore",
                           ".gitattributes"])
SPECIAL_PREFIXES = (".claude/", ".agents/", ".codex/")
COMMENT_EXT = frozenset([".gd", ".py", ".ps1", ".gdshader", ".gdshaderinc"])
IMPORT_KEY_RE = re.compile(r"^(source_file|path[\w.]*)=")
GIT_TIMEOUT_S = 600
GODOT_TIMEOUT_S = 900
CHECK_CHUNK = 150
TOKEN_RE = re.compile(r"(?<![\w.\\/-])(res://|(?:\.{1,2}/)+)?([\w.][\w.\-/\\]*)")
SEPARATORS = "./\\"
GROUPS = (("source_prefixes", "source_files"), ("forbidden_prefixes", "forbidden_files"))
PLAIN_FILE_KEYS = ("main_forbidden",)
PLAIN_STR_KEYS = ("late_scripts_file", "main_scene")


class MapError(Exception):
    pass


Row = collections.namedtuple("Row", "old new action reason")


# ------------------------------------------------------------------ git helpers
def git(root, *args, **kw):
    check = kw.pop("check", True)
    res = subprocess.run(["git", "-C", root, "-c", "core.quotepath=off"] + list(args), capture_output=True,
                         timeout=GIT_TIMEOUT_S, **kw)
    if check and res.returncode != 0:
        raise MapError("git %s failed: %s" % (" ".join(args[:3]), res.stderr.decode("utf-8", "replace").strip()))
    return res


def tracked_files(root):
    out = git(root, "ls-files", "-z").stdout.decode("utf-8")
    return [p for p in out.split("\0") if p]


def chunks(items, size):
    for i in range(0, len(items), size):
        yield items[i:i + size]


# ------------------------------------------------------------------ map loading
def load_rows(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    header = False
    for line in lines:
        line = line.rstrip("\r")
        if not line.strip() or line.startswith("#"):
            continue
        if not header:
            if not line.startswith("old_path\t"):
                raise MapError("bad header: %r" % line[:60])
            header = True
            continue
        cols = line.split("\t")
        cols += [""] * (4 - len(cols))
        old, new, action, reason = cols[:4]
        if action not in ("move", "restore-move", "keep") and not action.startswith("delete"):
            raise MapError("unknown action %r for %s" % (action, old))
        if action in MOVE_ACTIONS and not new:
            raise MapError("%s row for %s has no new_path" % (action, old))
        rows.append(Row(old, new or old, action, reason))
    return rows


def load_rules(path):
    rewrites, allows, replaces = [], [], []
    if path and os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            for line in fh.read().split("\n"):
                line = line.rstrip("\r")
                if not line.strip() or line.startswith("#"):
                    continue
                cols = line.split("\t")
                if cols[0] == "rewrite" and len(cols) >= 3:
                    rewrites.append((cols[1].strip("/"), cols[2].strip("/")))
                elif cols[0] == "allow" and len(cols) >= 3:
                    allows.append((cols[1], cols[2]))
                elif cols[0] == "replace" and len(cols) >= 4:
                    replaces.append((cols[1], cols[2], cols[3]))
                else:
                    raise MapError("bad rules line: %r" % line)
    return rewrites, allows, replaces


def parent_dirs(path):
    parts = path.split("/")
    return ["/".join(parts[:i]) for i in range(1, len(parts))]


class Plan(object):
    """Everything derived from the map and the tracked file list (no disk access)."""

    def __init__(self, rows, tracked, rewrites=(), replaces=()):
        self.rows = rows
        self.tracked = set(tracked)
        self.by_old = {}
        for r in rows:
            if r.old in self.by_old:
                raise MapError("duplicate old_path %s" % r.old)
            self.by_old[r.old] = r
        self.moves = [r for r in rows if r.action in MOVE_ACTIONS and r.new != r.old]
        self.deletes = [r for r in rows if r.action.startswith("delete")]
        self.survivors = [r for r in rows if not r.action.startswith("delete")]
        self.file_map = dict((r.old, r.new) for r in self.moves)
        self.dir_map, self.split_dirs = self._derive_dirs()
        self.extra_rewrites = dict(rewrites)
        self.replaces = list(replaces)
        self.token_map = dict(self.file_map)
        self.token_map.update(self.dir_map)
        self.token_map.update(self.extra_rewrites)
        self.deleted_set = set(r.old for r in self.deletes)

    def _derive_dirs(self):
        under = collections.defaultdict(list)
        for r in self.survivors:
            for d in parent_dirs(r.old):
                under[d].append(r)
        dir_map, split = {}, set()
        for d, members in under.items():
            if not any(m.new != m.old for m in members):
                continue
            first = members[0]
            rel = first.old[len(d) + 1:]
            if first.new == rel or not first.new.endswith("/" + rel):
                split.add(d)
                continue
            target = first.new[:-(len(rel) + 1)]
            if target != d and not target.startswith(d + "/") and all(m.new == target + "/" + m.old[len(d) + 1:] for m in members):
                if len(set(m.old[len(d) + 1:].split("/")[0] for m in members)) == 1 and "/" in first.old[len(d) + 1:]:
                    continue  # one child holds everything: the child's own entry covers it
                dir_map[d] = target
            elif target == d and all(m.new == m.old for m in members):
                continue
            else:
                split.add(d)
        return dir_map, split

    def validate(self, tracked_present=None):
        """Return a list of error strings about the map itself."""
        errs = []
        news = {}
        for r in self.survivors:
            if r.new in news:
                errs.append("duplicate new_path %s (%s, %s)" % (r.new, news[r.new], r.old))
            news[r.new] = r.old
        for r in self.moves:
            other = self.by_old.get(r.new)
            if other is not None and other.old != r.old and other.new == other.old and not other.action.startswith("delete"):
                errs.append("%s -> %s lands on a kept file" % (r.old, r.new))
        for old, new in sorted(self.token_map.items()):
            hit = lookup_prefix(new, self.token_map)
            if hit is not None:
                errs.append("not idempotent: new path %s contains old path %s" % (new, hit))
        for r in self.moves:
            for ext in (".uid", ".import"):
                if r.old.endswith(ext) or r.new.endswith(ext):
                    continue
                comp = self.by_old.get(r.old + ext)
                if comp is not None and not comp.action.startswith("delete") and comp.new != r.new + ext:
                    errs.append("companion %s does not follow %s" % (comp.old, r.old))
        applied = set(r.new for r in self.survivors)
        unmapped = sorted(p for p in self.tracked if p not in self.by_old and p not in applied)
        for p in unmapped:
            errs.append("unmapped tracked file %s" % p)
        return errs


def norm_token(text):
    return re.sub(r"[\\/]+", "/", text)


def lookup_prefix(body, token_map):
    """Longest separator-cut prefix of `body` (slash-normalised) that is a key; (cut index, key) or None."""
    hit = longest_cut(body, token_map)
    return None if hit is None else hit[1]


def longest_cut(body, token_map):
    cuts = [len(body)] + [i for i in range(len(body) - 1, 0, -1) if body[i] in SEPARATORS]
    cuts.sort(reverse=True)
    seen = set()
    for i in cuts:
        if i in seen:
            continue
        seen.add(i)
        cand = norm_token(body[:i])
        if cand in token_map:
            return i, cand
    return None


def style_for(segment):
    """Separator style of a matched path segment: '/' | '\\' | '\\\\'."""
    m = re.search(r"[\\/]+", segment)
    if not m:
        return "/"
    return m.group(0) if m.group(0).startswith("\\") else "/"


def rewrite_text(text, token_map):
    """Replace mapped path tokens. Returns (new text, count)."""
    count = [0]

    def sub(m):
        pre = m.group(1) or ""
        body = m.group(2)
        hit = longest_cut(body, token_map)
        if hit is None:
            return m.group(0)
        i, key = hit
        new = token_map[key]
        sep = style_for(body[:i])
        if sep != "/":
            new = new.replace("/", sep)
        if new == body[:i]:
            return m.group(0)
        count[0] += 1
        return pre + new + body[i:]

    return TOKEN_RE.sub(sub, text), count[0]


def find_old_tokens(text, token_map):
    """Tokens in `text` whose cut prefix is a key of token_map (-> list of keys)."""
    out = []
    for m in TOKEN_RE.finditer(text):
        hit = longest_cut(m.group(2), token_map)
        if hit is not None:
            out.append(hit[1])
    return out


def unresolved_tokens(text, ext, post_files, post_dirs, split_dirs, deleted=frozenset()):
    """Split-prefix references no rule resolved (post-rewrite text)."""
    out = []
    comment_aware = ext in COMMENT_EXT
    for line in text.split("\n"):
        if comment_aware and line.lstrip().startswith(("#", "//")):
            continue
        for m in TOKEN_RE.finditer(line):
            body = norm_token(m.group(2))
            if "/" not in body and not m.group(1):
                continue
            cuts = [body] + [body[:i] for i in range(1, len(body)) if body[i] in "./"]
            if any(c in post_files or c in deleted for c in cuts):
                continue
            tt = body.rstrip("/.")
            if not tt:
                continue
            if tt in split_dirs:
                out.append(body)
            elif tt in post_dirs:
                continue
            elif "/" in tt and tt.rsplit("/", 1)[0] in split_dirs:
                out.append(body)
    return out


# ------------------------------------------------------------------ file discovery
def is_text_target(path):
    if path.startswith(SKIP_PREFIXES):
        return False
    if path.endswith(".uid"):
        return False
    base = os.path.basename(path)
    ext = os.path.splitext(path)[1].lower()
    return ext in TEXT_EXT or base in SPECIAL_FILES or path.startswith(SPECIAL_PREFIXES)


def read_text(path):
    with open(path, "rb") as fh:
        data = fh.read()
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def write_text(path, text):
    with open(path, "wb") as fh:
        fh.write(text.encode("utf-8"))


def rewrite_file_text(path, text, plan):
    """Apply the rewrite for one file (handles .import keys and layer_rules.json). Returns (text, count)."""
    if path.endswith(".import"):
        total = 0
        lines = text.split("\n")
        for n, line in enumerate(lines):
            if IMPORT_KEY_RE.match(line):
                lines[n], c = rewrite_text(line, plan.token_map)
                total += c
        return "\n".join(lines), total
    return rewrite_text(text, plan.token_map)


# ------------------------------------------------------------------ layer_rules.json membership
def is_member(path, prefixes, files):
    return path in files or path.startswith(tuple(prefixes))


def rewrite_membership(prefixes, files, plan, old_tree, new_tree):
    """New (prefixes, files) whose membership over `new_tree` is exactly the image of the old
    membership over `old_tree` (old_tree: iterable of old paths, new_tree: iterable of new paths)."""
    def image(p):
        r = plan.by_old.get(p)
        if r is None:
            return p
        return None if r.action.startswith("delete") else r.new

    members = set()
    for p in old_tree:
        if is_member(p, prefixes, files):
            img = image(p)
            if img is not None:
                members.add(img)
    new_tree = set(new_tree)
    total = collections.Counter()
    hit = collections.Counter()
    for p in new_tree:
        for d in parent_dirs(p):
            total[d] += 1
            if p in members:
                hit[d] += 1
    new_prefixes = []
    for pref in prefixes:
        d = pref.rstrip("/")
        if d in plan.dir_map:
            new_prefixes.append(plan.dir_map[d] + "/")
            continue
        old_under = [p for p in old_tree if p.startswith(pref)]
        if not old_under:
            continue
        imgs = set(image(p) for p in old_under) - set([None])
        if not imgs:
            continue
        if d not in plan.split_dirs and total[d] == hit[d]:
            new_prefixes.append(pref)
            continue
        if all(p.startswith(pref) for p in imgs) and total[d] == hit[d]:
            new_prefixes.append(pref)
            continue
        for x in sorted(imgs):
            picked = None
            for anc in parent_dirs(x):
                if total[anc] == hit[anc]:
                    picked = anc + "/"
                    break
            new_prefixes.append(picked or x)
    new_files = []
    for f in files:
        img = image(f)
        if img is not None:
            new_files.append(img)
    dirs = sorted(set(p for p in new_prefixes if p.endswith("/")))
    dirs = [p for p in dirs if not any(q != p and p.startswith(q) for q in dirs)]
    singles = set(p for p in new_prefixes if not p.endswith("/")) | set(new_files)
    final_files = sorted(f for f in singles if not f.startswith(tuple(dirs)))
    return dirs, final_files


def rewrite_layer_rules(text, plan, old_tree, new_tree):
    data = json.loads(text)
    changed = 0
    for pk, fk in GROUPS:
        if pk in data or fk in data:
            np_, nf = rewrite_membership(data.get(pk, []), data.get(fk, []), plan, old_tree, new_tree)
            if np_ != data.get(pk, []) or nf != data.get(fk, []):
                changed += 1
            data[pk], data[fk] = np_, nf
    for key in PLAIN_FILE_KEYS:
        if key in data:
            new = sorted(set(plan.file_map.get(f, f) for f in data[key] if f not in plan.deleted_set))
            if new != data[key]:
                changed += 1
            data[key] = new
    for key in PLAIN_STR_KEYS:
        if key in data and data[key] in plan.file_map:
            data[key] = plan.file_map[data[key]]
            changed += 1
    return json.dumps(data, indent=1, ensure_ascii=False) + "\n", changed


# ------------------------------------------------------------------ plan computation
class Report(object):
    def __init__(self):
        self.errors = []
        self.warnings = []
        self.ops = []
        self.rewritten = {}  # path (new location) -> reference count
        self.unresolved = collections.defaultdict(list)
        self.stale = collections.defaultdict(list)
        self.counts = collections.Counter()


def compute(root, plan, allows, extras, base_ref, rep):
    """Build the git operations and the rewrite results in memory. Returns {abs-or-rel path: new text}."""
    tracked = plan.tracked
    for r in plan.rows:
        exists_old = os.path.exists(os.path.join(root, r.old))
        exists_new = os.path.exists(os.path.join(root, r.new))
        if r.action in MOVE_ACTIONS and r.new != r.old:
            if exists_old:
                rep.ops.append(("mv", r.old, r.new))
            elif exists_new:
                rep.counts["already applied"] += 1
            elif r.action == "restore-move":
                rep.ops.append(("restore+mv", r.old, r.new))
            else:
                rep.errors.append("missing: %s (neither old nor new exists)" % r.old)
        elif r.action.startswith("delete"):
            if exists_old or r.old in tracked:
                rep.ops.append(("rm", r.old, ""))
            else:
                rep.counts["already deleted"] += 1
        elif r.action == "restore-move" and not exists_old:
            rep.ops.append(("restore", r.old, ""))
    deleted_now = set(o[1] for o in rep.ops if o[0] == "rm")
    old_tree = sorted(tracked)
    mv_map = dict((o[1], o[2]) for o in rep.ops if o[0] in ("mv", "restore+mv"))
    post = set(mv_map.get(p, p) for p in tracked if p not in deleted_now)
    for o in rep.ops:
        if o[0] == "restore":
            post.add(o[1])
        elif o[0] == "restore+mv":
            post.add(o[2])
    post_dirs = set(d for p in post for d in parent_dirs(p))
    results = {}
    for p in sorted(tracked):
        if p in deleted_now or not is_text_target(p):
            continue
        if os.path.exists(os.path.join(root, p)):
            text = read_text(os.path.join(root, p))
        else:
            text = git_show(root, base_ref, p)
        if text is None:
            continue
        results[p] = text
    outputs = {}
    for p, text in results.items():
        loc = mv_map.get(p, p)
        if loc == LAYER_RULES:
            new_text, rep_c = rewrite_layer_rules(text, plan, old_tree, sorted(post))
        else:
            new_text, rep_c = rewrite_file_text(p, text, plan)
            for rfile, old_lit, new_lit in plan.replaces:
                if rfile in (p, loc) and old_lit in new_text:
                    rep_c += new_text.count(old_lit)
                    new_text = new_text.replace(old_lit, new_lit)
        if new_text != text:
            rep.rewritten[loc] = max(rep_c, 1)
            outputs[p] = (loc, new_text)
        ext = os.path.splitext(loc)[1].lower()
        if ext != ".md" and ext != ".import" and loc != LAYER_RULES:
            scan_unresolved(rep, loc, new_text, ext, post, post_dirs, plan, allows)
        stale_scan(rep, loc, new_text, plan)
    for ex in extras:
        text = read_text(ex)
        if text is None:
            rep.errors.append("--extra %s is not readable text" % ex)
            continue
        new_text, c = rewrite_text(text, plan.token_map)
        if new_text != text:
            rep.rewritten[ex] = c
            outputs[ex] = (ex, new_text)
        if not ex.endswith(".md"):
            scan_unresolved(rep, ex, new_text, os.path.splitext(ex)[1].lower(), post, post_dirs, plan, allows)
    return outputs


def scan_unresolved(rep, loc, text, ext, post, post_dirs, plan, allows):
    for tok in unresolved_tokens(text, ext, post, post_dirs, plan.split_dirs, plan.deleted_set):
        if any(fnmatch.fnmatch(loc, fg) and fnmatch.fnmatch(tok, tg) for fg, tg in allows):
            continue
        rep.unresolved[loc].append(tok)


def stale_scan(rep, loc, text, plan):
    """References to files the map deletes (informational; --strict-deleted makes them errors)."""
    if loc.startswith("tools/reorg_move"):
        return
    for m in TOKEN_RE.finditer(text):
        body = norm_token(m.group(2))
        for i in [len(body)] + [k for k in range(len(body) - 1, 0, -1) if body[k] in "./"]:
            if body[:i] in plan.deleted_set:
                rep.stale[loc].append(body[:i])
                break


# ------------------------------------------------------------------ apply
def run_ops(root, rep, plan, base_ref):
    rms = [o[1] for o in rep.ops if o[0] == "rm"]
    for batch in chunks(rms, 100):
        tracked = [b for b in batch if b in plan.tracked]
        if tracked:
            git(root, "rm", "-q", "-f", "--ignore-unmatch", "--", *tracked)
        for b in batch:
            fp = os.path.join(root, b)
            if os.path.exists(fp):
                os.remove(fp)
    pending = [o for o in rep.ops if o[0] in ("mv", "restore+mv", "restore")]
    for o in pending:
        if o[0] in ("restore+mv", "restore"):
            git(root, "checkout", base_ref, "--", o[1])
            plan.tracked.add(o[1])
    moves = [(o[1], o[2]) for o in pending if o[0] in ("mv", "restore+mv")]
    olds = set(m[0] for m in moves)
    while moves:
        progress = False
        rest = []
        for old, new in moves:
            if os.path.exists(os.path.join(root, new)) and new in olds:
                rest.append((old, new))
                continue
            os.makedirs(os.path.dirname(os.path.join(root, new)) or root, exist_ok=True)
            if old in plan.tracked:
                git(root, "mv", "--", old, new)
            else:
                os.replace(os.path.join(root, old), os.path.join(root, new))
            olds.discard(old)
            progress = True
        if not progress:
            raise MapError("move cycle among %s" % ", ".join(m[0] for m in rest[:5]))
        moves = rest
    for o in pending:
        if o[0] in ("mv", "restore+mv"):
            d = os.path.dirname(os.path.join(root, o[1]))
            while d and os.path.normpath(d) != os.path.normpath(root):
                try:
                    os.rmdir(d)
                except OSError:
                    break
                d = os.path.dirname(d)


def write_outputs(root, outputs):
    for old, (loc, text) in outputs.items():
        target = loc if os.path.isabs(loc) else os.path.join(root, loc)
        write_text(target, text)


# ------------------------------------------------------------------ verify
def godot_exe():
    return os.environ.get("GODOT_EXE", "godot")


def run_godot(root, args, label, timeout=GODOT_TIMEOUT_S):
    slots = os.path.join(root, "tools", "godot_slots.py")
    cmd = [godot_exe()] + args
    if os.path.exists(slots):
        cmd = [sys.executable, slots, "run", "--label", label, "--"] + cmd
    res = subprocess.run(cmd, capture_output=True, timeout=timeout, cwd=root)
    return res.returncode, (res.stdout + res.stderr).decode("utf-8", "replace")


BAD_LOG_RE = re.compile(r"(^|\s)(ERROR|WARNING|SCRIPT ERROR|Parse Error)\b|Parse Error|Failed to load")


def verify(root, plan, allows, extras, base_ref, args, say):
    problems = []
    tracked = tracked_files(root)
    post = set(tracked)
    post_dirs = set(d for p in post for d in parent_dirs(p))
    keys = dict((k, v) for k, v in plan.token_map.items())
    own = set([os.path.relpath(a, root).replace("\\", "/") for a in [args.map, args.rules] if a and os.path.abspath(a).startswith(os.path.abspath(root))])
    own.add("tools/reorg_move.py")
    own.add("tools/test_reorg_move.py")
    own.add("tools/reorg_move_map.tsv")
    old_left = collections.defaultdict(list)
    unresolved = collections.defaultdict(list)
    stale = collections.defaultdict(list)
    files = [p for p in tracked if is_text_target(p) and p not in own and p != LAYER_RULES]
    for p in files:
        text = read_text(os.path.join(root, p))
        if text is None:
            continue
        if p.endswith(".import"):
            text = "\n".join(l for l in text.split("\n") if IMPORT_KEY_RE.match(l))
        for k in find_old_tokens(text, keys):
            old_left[p].append(k)
        ext = os.path.splitext(p)[1].lower()
        if ext not in (".md", ".import"):
            toks = unresolved_tokens(text, ext, post, post_dirs, plan.split_dirs, plan.deleted_set)
            for t in toks:
                if not any(fnmatch.fnmatch(p, fg) and fnmatch.fnmatch(t, tg) for fg, tg in allows):
                    unresolved[p].append(t)
        for m in TOKEN_RE.finditer(text):
            body = norm_token(m.group(2))
            if body in plan.deleted_set and body not in post:
                stale[p].append(body)
    for ex in extras:
        text = read_text(ex)
        if text is not None:
            for k in find_old_tokens(text, keys):
                old_left[ex].append(k)
    for k in sorted(plan.file_map):
        if k in post:
            old_left["(tree)"].append(k)
    n_old = sum(len(v) for v in old_left.values())
    say("(a) old paths left: %d in %d files; unresolved split-prefix refs: %d in %d files; refs to deleted files: %d in %d files"
        % (n_old, len(old_left), sum(len(v) for v in unresolved.values()), len(unresolved),
           sum(len(v) for v in stale.values()), len(stale)))
    for p, v in sorted(old_left.items())[:40]:
        say("    OLD %s: %s" % (p, ", ".join(sorted(set(v))[:6])))
    for p, v in sorted(unresolved.items())[:40]:
        say("    SPLIT %s: %s" % (p, ", ".join(sorted(set(v))[:6])))
    if n_old or unresolved:
        problems.append("old/unresolved path references")
    if stale and args.strict_deleted:
        problems.append("references to deleted files")
    # class_name set
    ok, msg = check_class_names(root, plan, base_ref)
    say("(class_name) " + msg)
    if not ok:
        problems.append("class_name set changed")
    ok, msg = check_uid_count(root, plan, base_ref, tracked)
    say("(d uid) " + msg)
    if not ok:
        problems.append("uid count")
    ok, msg = check_membership(root, plan, base_ref, tracked)
    say("(f) " + msg)
    if not ok:
        problems.append("lint membership")
    if not args.skip_godot:
        problems.extend(godot_checks(root, tracked, args, say))
    return problems


def godot_checks(root, tracked, args, say):
    problems = []
    for n in (1, 2):
        code, out = run_godot(root, ["--headless", "--editor", "--path", root, "--quit"], "reorg_editor%d" % n)
        bad = [l for l in out.split("\n") if BAD_LOG_RE.search(l)]
        say("(b) editor run %d: exit %d, %d error/warning lines" % (n, code, len(bad)))
        if n == 2 and (bad or code != 0):
            problems.append("editor run not clean")
            for l in bad[:15]:
                say("    " + l.strip())
    scripts = sorted("res://" + p for p in tracked if p.endswith(".gd") and not p.startswith(("addons/", "docs/")))
    failed = 0
    for batch in chunks(scripts, CHECK_CHUNK):
        code, out = run_godot(root, ["--headless", "--path", root, "-s", "res://tools/check_scripts.gd", "--"] + batch, "reorg_check")
        fails = [l for l in out.split("\n") if "CHECK FAIL" in l]
        failed += len(fails)
        for l in fails[:10]:
            say("    " + l.strip())
    say("(c) check_scripts: %d scripts, %d failed" % (len(scripts), failed))
    if failed:
        problems.append("scripts failed to compile")
    sys.path.insert(0, HERE)
    import dep_graph
    graph = dep_graph.build_graph(root)
    broken = graph.get("broken", [])
    dangling = [b for b in broken if b["ref"].replace("res://", "") in plan.deleted_set]
    broken = [b for b in broken if b not in dangling]
    say("(d) dep_graph broken references: %d (expected <= %d), plus %d pointing at files the map deletes"
        % (len(broken), args.expect_broken, len(dangling)))
    for b in broken[:15]:
        say("    BROKEN %s -> %s (%s)" % (b["src"], b["ref"], b["why"]))
    for b in dangling[:15]:
        say("    DANGLING %s -> %s" % (b["src"], b["ref"]), True)
    if len(broken) > args.expect_broken:
        problems.append("broken references")
    import lint_layers
    code, lines = lint_layers.run(root)
    say("(e) " + lines[-1])
    if code != 0:
        problems.append("layer lint red")
        for l in lines:
            if l.startswith("VIOLATION"):
                say("    " + l)
    return problems


def git_show(root, ref, path):
    res = git(root, "show", "%s:%s" % (ref, path), check=False)
    return res.stdout.decode("utf-8") if res.returncode == 0 else None


def check_class_names(root, plan, base_ref):
    pat = re.compile(r"^class_name\s+(\w+)", re.M)
    out = git(root, "grep", "-I", "-E", "^class_name ", base_ref, "--", "*.gd", check=False).stdout.decode("utf-8", "replace")
    old = set()
    for line in out.splitlines():
        mm = re.match(r"^[^:]+:(.+?\.gd):class_name\s+(\w+)", line)
        if mm and not mm.group(1).startswith("addons/"):
            r = plan.by_old.get(mm.group(1))
            if r is None or not r.action.startswith("delete"):
                old.add(mm.group(2))
    new = set()
    for p in tracked_files(root):
        if p.endswith(".gd") and not p.startswith("addons/"):
            text = read_text(os.path.join(root, p))
            if text:
                for m in pat.finditer(text):
                    new.add(m.group(1))
    gone = sorted(old - new)
    added = sorted(new - old)
    return (not gone and not added), "%d class_name entries, missing %s, added %s" % (len(new), gone[:6], added[:6])


def check_uid_count(root, plan, base_ref, tracked):
    base = git(root, "ls-tree", "-r", "--name-only", base_ref).stdout.decode("utf-8").split("\n")
    exp = 0
    for p in base:
        if p.endswith(".uid"):
            r = plan.by_old.get(p)
            if r is None or not r.action.startswith("delete"):
                exp += 1
    have = sum(1 for p in tracked if p.endswith(".uid"))
    return exp == have, ".uid files expected %d, found %d" % (exp, have)


def check_membership(root, plan, base_ref, tracked):
    old_text = git_show(root, base_ref, LAYER_RULES)
    new_path = os.path.join(root, LAYER_RULES)
    if old_text is None or not os.path.exists(new_path):
        return True, "no %s at base or in tree: skipped" % LAYER_RULES
    old = json.loads(old_text)
    new = json.loads(read_text(new_path))
    base = git(root, "ls-tree", "-r", "--name-only", base_ref).stdout.decode("utf-8").split("\n")
    bad = []
    for pk, fk in GROUPS:
        members = set()
        for p in base:
            if p and is_member(p, old.get(pk, []), set(old.get(fk, []))):
                r = plan.by_old.get(p)
                if r is None:
                    members.add(p)
                elif not r.action.startswith("delete"):
                    members.add(r.new)
        got = set(p for p in tracked if is_member(p, new.get(pk, []), set(new.get(fk, []))))
        if members != got:
            bad.append("%s/%s: missing %s extra %s" % (pk, fk, sorted(members - got)[:4], sorted(got - members)[:4]))
    return not bad, "membership %s" % ("identical" if not bad else "; ".join(bad))


# ------------------------------------------------------------------ CLI
def print_plan(rep, plan, say, detail):
    c = collections.Counter(o[0] for o in rep.ops)
    say("moves: %d  restores: %d  deletes: %d  already applied: %d  already deleted: %d" % (
        c["mv"] + c["restore+mv"], c["restore"] + c["restore+mv"], c["rm"], rep.counts["already applied"], rep.counts["already deleted"]))
    say("directory map: %d clean dirs, %d split dirs, %d token rules" % (
        len(plan.dir_map), len(plan.split_dirs), len(plan.token_map)))
    say("files rewritten: %d, references rewritten: %d" % (len(rep.rewritten), sum(rep.rewritten.values())))
    nstale = sum(len(v) for v in rep.stale.values())
    say("references to deleted files (informational): %d in %d files" % (nstale, len(rep.stale)))
    nun = sum(len(v) for v in rep.unresolved.values())
    say("unresolved split-prefix references: %d in %d files" % (nun, len(rep.unresolved)))
    for p, v in sorted(rep.unresolved.items())[:40]:
        say("    SPLIT %s: %s" % (p, ", ".join(sorted(set(v))[:6])))
    for e in rep.errors[:60]:
        say("ERROR " + e)
    if len(rep.errors) > 60:
        say("ERROR ... %d more" % (len(rep.errors) - 60))
    if detail:
        for o in rep.ops:
            say("OP %s %s %s" % o, True)
        for p, n in sorted(rep.rewritten.items()):
            say("REWRITE %5d %s" % (n, p), True)
        for p, v in sorted(rep.unresolved.items()):
            say("SPLIT %s: %s" % (p, ", ".join(sorted(set(v)))), True)
        for p, v in sorted(rep.stale.items()):
            say("STALE %s: %s" % (p, ", ".join(sorted(set(v)))), True)


def build_parser():
    ap = argparse.ArgumentParser(description="Scripted project reorganisation (Bontago-uwq.6)")
    ap.add_argument("--map", required=True, help="move map TSV")
    ap.add_argument("--path", default=REPO, help="checkout to operate on")
    ap.add_argument("--rules", default=DEFAULT_RULES, help="manual rules TSV (rewrite/allow lines)")
    ap.add_argument("--extra", nargs="*", default=[], help="extra files outside the repo to rewrite/check")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    ap.add_argument("--base-ref", default="HEAD", help="revision restore-move files and verify compare against")
    ap.add_argument("--report", help="write the full plan/verify detail to this file")
    ap.add_argument("--allow-unresolved", action="store_true", help="--apply despite unresolved split-prefix refs")
    ap.add_argument("--strict-deleted", action="store_true", help="--verify fails on references to deleted files")
    ap.add_argument("--skip-godot", action="store_true", help="--verify without the Godot runs")
    ap.add_argument("--expect-broken", type=int, default=0, help="--verify: tolerated dep_graph broken references")
    return ap


def main(argv=None):
    args = build_parser().parse_args(argv)
    root = os.path.abspath(args.path)
    lines = []

    def say(s, quiet=False):
        lines.append(s)
        if not quiet:
            print(s)

    try:
        rows = load_rows(args.map)
        rewrites, allows, replaces = load_rules(args.rules)
        tracked = tracked_files(root)
        plan = Plan(rows, tracked, rewrites, replaces)
        errs = plan.validate()
        extras = [os.path.abspath(e) for e in args.extra]
        for e in extras:
            if not os.path.isfile(e):
                raise MapError("--extra %s is not a file" % e)
        if args.verify:
            problems = verify(root, plan, allows, extras, args.base_ref, args, say)
            say("REORG VERIFY %s%s" % ("GREEN" if not problems else "RED", "" if not problems else " (" + "; ".join(problems) + ")"))
            code = 1 if problems else 0
        else:
            rep = Report()
            rep.errors.extend(errs)
            outputs = compute(root, plan, allows, extras, args.base_ref, rep)
            print_plan(rep, plan, say, bool(args.report))
            hard = bool(rep.errors) or (bool(rep.unresolved) and not args.allow_unresolved)
            if args.apply and not hard:
                run_ops(root, rep, plan, args.base_ref)
                outputs_final = outputs
                write_outputs(root, outputs_final)
                say("applied: %d git operations, %d files rewritten" % (len(rep.ops), len(outputs_final)))
            elif args.apply:
                say("not applied: fix the errors above (or --allow-unresolved)")
            say("REORG %s %s" % ("APPLY" if args.apply else "DRY-RUN", "RED" if hard else "GREEN"))
            code = 1 if hard else 0
    except MapError as exc:
        say("ERROR %s" % exc)
        say("REORG RED")
        code = 1
    if args.report:
        with open(args.report, "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    return code


if __name__ == "__main__":
    sys.exit(main())
