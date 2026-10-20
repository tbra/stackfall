"""Bounded mutation check: do the GUT tests for res://core/ fail when that logic breaks?

Usage:
  python tools/mutate_core.py [<core script or dir> ...] [--max-mutations N] [--time-limit S]
         [--ops cmp,eq,bool,if_true,int,range] [--seed N] [--tests a,b] [--include-slow]
         [--work DIR] [--keep-work] [--no-prime] [--out DIR] [--list]

Targets default to all of core/. For each target script the tool finds the tests that name its
class_name or file stem (tools/affected_tests.py's whole-word search over tests/**/*.gd; --tests
overrides), applies one small mutation at a time and runs only those tests through
tools/run_gut.ps1 -Path <work>:
  cmp      relational flip: < <-> <=, > <-> >=
  eq       equality flip: == <-> !=
  bool     and <-> or, && <-> ||
  if_true  an if/elif condition replaced by `true` (the guard is dropped)
  int      integer literal n -> n + 1
  range    a non-literal range() stop bound x -> x - 1
Strings, comments, annotation/enum/class_name/extends lines and lines carrying
`# mutate: skip` are never mutated. More sites than --max-mutations are sampled with --seed.

Safety: mutations happen in a scratch copy of the checkout (no .git; default under the
scratch root, deleted afterwards unless --keep-work) or in --work DIR, an existing checkout
that is not this one. Each mutated file is journalled (.mutate_core_journal.json + a backup)
before it is written and restored and hash-checked after its run; a journal left by a killed
run is restored first. Each target's tests run once unmutated (baseline); a red baseline skips
that target. Before the first run the work copy's class cache is rebuilt with two headless
`--editor --quit` passes (a copied .godot can predate new class_names; --no-prime skips it).
One Godot process at a time, through run_gut.ps1's tools/godot_slots.py slot.
--time-limit bounds the whole run; mutations that would not fit are reported as not run.

Output: survivors as `path:line: <op> '<old>' -> '<new>'`, `UNTESTED`/`BASELINE RED` lines,
then one `MUTATION <killed>/<total> killed` line. A timeout counts as killed; a mutation that
breaks compilation is `invalid` and left out of the total. Details (per-mutation status,
timings, test totals, failing-run tails) go to <out>/details.json and <out>/summary.txt.
--list prints the sampled mutations and runs nothing.
Exit codes: 0 run completed, 1 setup failed (copy, baseline of every target, restore), 2 usage.
"""
import argparse
import hashlib
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time
from typing import Dict, List, NamedTuple, Optional, Sequence, Tuple

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import affected_tests  # noqa: E402
import repo_paths  # noqa: E402

DEFAULT_MAX_MUTATIONS = 20
DEFAULT_TIME_LIMIT_S = 1800.0
DEFAULT_SEED = 0
# Per-mutation timeout: a mutated run may loop forever, so cap it relative to the baseline.
TIMEOUT_FACTOR = 3.0
TIMEOUT_MARGIN_S = 60.0
TAIL_LINES = 40
MAX_ERROR_LINES = 20
PRIME_PASSES = 2  # the first pass on a stale cache can itself report parse errors
PRIME_TIMEOUT_S = 900.0
CORE_DIR = "core"
ALL_OPS = ("cmp", "eq", "bool", "if_true", "int", "range")
SKIP_PRAGMA = "mutate: skip"
SKIP_LINE_RE = re.compile(r"^\s*(?:@|enum\b|class_name\b|extends\b)")
# Suites that take minutes; included only with --include-slow.
SLOW_TESTS = frozenset(("test_match_flow", "test_match_lifecycle"))
JOURNAL = ".mutate_core_journal.json"
BACKUP = ".mutate_core_backup"
COPY_IGNORE_TOP = frozenset((".git", ".beads", ".claude", "docs", "build"))
COPY_IGNORE_ANY = frozenset((".gut_targeted",))

CMP_RE = re.compile(r"(?<![<>=!\-])(<=|>=|==|!=|<|>)(?![<>=])")
CMP_SWAP = {"<": "<=", "<=": "<", ">": ">=", ">=": ">", "==": "!=", "!=": "=="}
BOOL_RE = re.compile(r"\band\b|\bor\b|&&|\|\|")
BOOL_SWAP = {"and": "or", "or": "and", "&&": "||", "||": "&&"}
IF_RE = re.compile(r"^(\s*)(if|elif)(\s+)")
INT_RE = re.compile(r"(?<![\w.])(\d+)(?![\w.])")
RANGE_RE = re.compile(r"\brange\s*\(")
INT_ARG_RE = re.compile(r"^-?\d+$")
SIMPLE_EXPR_RE = re.compile(r"^[\w.]+(?:\(\))?$")
OPEN = "([{"
CLOSE = ")]}"


class Mutation(NamedTuple):
    path: str  # repo-relative, forward slashes
    line: int  # 1-based
    col: int  # 0-based offset of `old` in the line
    op: str
    old: str
    new: str

    def describe(self) -> str:
        return "%s:%d: %s '%s' -> '%s'" % (self.path, self.line, self.op, self.old, self.new)


# ---------------------------------------------------------------- generator


def mask_code(lines: Sequence[str]) -> List[str]:
    """Each line with string contents, quotes and comments replaced by spaces (same length).
    Handles "..", '..', triple-quoted strings across lines and StringName/NodePath/raw prefixes."""
    out = []
    in_triple = ""  # the open triple quote, if a multi-line string continues
    for line in lines:
        chars = list(line.rstrip("\r\n"))
        i = 0
        n = len(chars)
        while i < n:
            if in_triple:
                end = "".join(chars).find(in_triple, i)
                stop = n if end < 0 else end + len(in_triple)
                for k in range(i, stop):
                    chars[k] = " "
                if end >= 0:
                    in_triple = ""
                i = stop
                continue
            c = chars[i]
            if c == "#":
                for k in range(i, n):
                    chars[k] = " "
                break
            if c in "\"'":
                triple = c * 3
                if "".join(chars[i:i + 3]) == triple:
                    in_triple = triple
                    for k in range(i, i + 3):
                        chars[k] = " "
                    i += 3
                    continue
                k = i + 1
                while k < n and chars[k] != c:
                    k += 2 if chars[k] == "\\" else 1
                stop = min(k + 1, n)
                for j in range(i, stop):
                    chars[j] = " "
                i = stop
                continue
            i += 1
        out.append("".join(chars))
    return out


def _depth0_colon(code: str, start: int) -> int:
    depth = 0
    for i in range(start, len(code)):
        c = code[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
        elif c == ":" and depth == 0:
            return i
    return -1


def _range_stop(code: str, start: int) -> Optional[Tuple[int, int]]:
    """(begin, end) of the stop argument of the range( call whose '(' is at `start`, or None."""
    depth = 0
    args = []
    arg_begin = start + 1
    for i in range(start, len(code)):
        c = code[i]
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
            if depth == 0:
                args.append((arg_begin, i))
                break
        elif c == "," and depth == 1:
            args.append((arg_begin, i))
            arg_begin = i + 1
    else:
        return None  # call continues on the next line
    if not args or len(args) > 3:
        return None
    begin, end = args[0] if len(args) == 1 else args[1]
    while begin < end and code[begin] == " ":
        begin += 1
    while end > begin and code[end - 1] == " ":
        end -= 1
    return (begin, end) if end > begin else None


def line_mutations(path: str, lineno: int, raw: str, code: str, ops: Sequence[str]) -> List[Mutation]:
    """Mutations for one line. `code` is the masked line (strings/comments blanked)."""
    if SKIP_PRAGMA in raw or SKIP_LINE_RE.match(code) or not code.strip():
        return []
    found = []
    if "cmp" in ops or "eq" in ops:
        for m in CMP_RE.finditer(code):
            op = "eq" if m.group(1) in ("==", "!=") else "cmp"
            if op in ops:
                found.append(Mutation(path, lineno, m.start(1), op, m.group(1), CMP_SWAP[m.group(1)]))
    if "bool" in ops:
        for m in BOOL_RE.finditer(code):
            found.append(Mutation(path, lineno, m.start(), "bool", m.group(0), BOOL_SWAP[m.group(0)]))
    if "if_true" in ops:
        m = IF_RE.match(code)
        if m:
            begin = m.end()
            colon = _depth0_colon(code, begin)
            if colon > begin:
                cond = raw[begin:colon].rstrip()
                if cond not in ("true", "false"):
                    found.append(Mutation(path, lineno, begin, "if_true", cond, "true"))
    if "int" in ops:
        for m in INT_RE.finditer(code):
            found.append(Mutation(path, lineno, m.start(1), "int", m.group(1), str(int(m.group(1)) + 1)))
    if "range" in ops:
        for m in RANGE_RE.finditer(code):
            span = _range_stop(code, m.end() - 1)
            if span is None:
                continue
            arg = raw[span[0]:span[1]]
            if INT_ARG_RE.match(arg.replace(" ", "")):
                continue  # the int operator already covers literal bounds
            new = ("%s - 1" if SIMPLE_EXPR_RE.match(arg) else "(%s) - 1") % arg
            found.append(Mutation(path, lineno, span[0], "range", arg, new))
    found.sort(key=lambda mu: (mu.col, mu.op))
    return found


def generate(path: str, text: str, ops: Sequence[str] = ALL_OPS) -> List[Mutation]:
    """Every mutation site in one GDScript source text."""
    raw_lines = text.splitlines()
    masked = mask_code(raw_lines)
    out = []
    for i, (raw, code) in enumerate(zip(raw_lines, masked)):
        out.extend(line_mutations(path, i + 1, raw, code, ops))
    return out


def sample(mutations: Sequence[Mutation], cap: int, seed: int) -> List[Mutation]:
    """At most `cap` mutations, chosen reproducibly with `seed`, in file/line order."""
    chosen = list(mutations)
    if cap >= 0 and len(chosen) > cap:
        chosen = random.Random(seed).sample(chosen, cap)
    return sorted(chosen, key=lambda m: (m.path, m.line, m.col, m.op))


def apply_mutation(text: str, m: Mutation) -> str:
    """`text` with `m` applied. Raises ValueError when the line no longer holds `m.old`."""
    lines = text.splitlines(True)
    if not 1 <= m.line <= len(lines):
        raise ValueError("line %d out of range" % m.line)
    line = lines[m.line - 1]
    if line[m.col:m.col + len(m.old)] != m.old:
        raise ValueError("%s: text at col %d is not %r" % (m.path, m.col, m.old))
    lines[m.line - 1] = line[:m.col] + m.new + line[m.col + len(m.old):]
    return "".join(lines)


# ---------------------------------------------------------------- apply / restore


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _read_bytes(path: str) -> bytes:
    with open(path, "rb") as fh:
        return fh.read()


def _write_bytes(path: str, data: bytes) -> None:
    with open(path, "wb") as fh:
        fh.write(data)


def recover(work: str) -> Optional[str]:
    """Restore a file left mutated by an interrupted run. Returns the restored rel path or None."""
    jpath = os.path.join(work, JOURNAL)
    if not os.path.exists(jpath):
        return None
    with open(jpath, encoding="utf-8") as fh:
        entry = json.load(fh)
    backup = _read_bytes(os.path.join(work, BACKUP))
    if _sha(backup) != entry["sha"]:
        raise RuntimeError("journal backup for %s does not match its hash; restore by hand" % entry["path"])
    target = os.path.join(work, entry["path"])
    if not os.path.exists(target) or _read_bytes(target) != backup:
        _write_bytes(target, backup)
    os.remove(os.path.join(work, BACKUP))
    os.remove(jpath)
    return entry["path"]


class Mutated:
    """Context manager: writes `m` into work/<m.path>, restores the original bytes on exit."""

    def __init__(self, work: str, m: Mutation):
        self.work = work
        self.m = m
        self.target = os.path.join(work, m.path)
        self.original = b""

    def __enter__(self) -> "Mutated":
        if os.path.exists(os.path.join(self.work, JOURNAL)):
            raise RuntimeError("a mutation is already journalled in %s" % self.work)
        self.original = _read_bytes(self.target)
        text = self.original.decode("utf-8")
        mutated = apply_mutation(text, self.m).encode("utf-8")
        _write_bytes(os.path.join(self.work, BACKUP), self.original)
        with open(os.path.join(self.work, JOURNAL), "w", encoding="utf-8") as fh:
            json.dump({"path": self.m.path, "sha": _sha(self.original), "mutation": self.m.describe()}, fh)
        _write_bytes(self.target, mutated)
        return self

    def __exit__(self, *exc: object) -> None:
        _write_bytes(self.target, self.original)
        if _sha(_read_bytes(self.target)) != _sha(self.original):
            raise RuntimeError("restore of %s failed; backup kept in %s" % (self.m.path, self.work))
        os.remove(os.path.join(self.work, BACKUP))
        os.remove(os.path.join(self.work, JOURNAL))


# ---------------------------------------------------------------- targets and tests


def norm_rel(p: str) -> str:
    p = p.replace("\\", "/")
    if p.startswith("res://"):
        p = p[len("res://"):]
    return p.strip("/")


def resolve_targets(repo: str, args: Sequence[str]) -> List[str]:
    """Repo-relative core/**/*.gd paths named by `args` (files or dirs; default all of core/)."""
    out = []
    for a in (args or [CORE_DIR]):
        rel = norm_rel(os.path.relpath(a, repo) if os.path.isabs(a) else a)
        if rel != CORE_DIR and not rel.startswith(CORE_DIR + "/"):
            raise ValueError("%s is not under %s/" % (a, CORE_DIR))
        full = os.path.join(repo, rel)
        if os.path.isdir(full):
            for dirpath, dirs, files in os.walk(full):
                dirs.sort()
                for fn in sorted(files):
                    if fn.endswith(".gd"):
                        out.append(norm_rel(os.path.relpath(os.path.join(dirpath, fn), repo)))
        elif rel.endswith(".gd") and os.path.isfile(full):
            out.append(rel)
        else:
            raise ValueError("no such core script or dir: %s" % a)
    return sorted(set(out))


def tests_for(repo: str, rel: str, include_slow: bool) -> List[str]:
    """Test script stems that name `rel`'s class_name or file stem."""
    ids = {}
    stem = os.path.splitext(os.path.basename(rel))[0]
    for name in (stem, affected_tests.file_class_name(repo, rel)):
        if affected_tests.keep(name):
            ids[name] = rel
    stems = set()
    for r in affected_tests.find_tests(repo, ids, set()):
        s = os.path.splitext(os.path.basename(r["file"]))[0]
        if s.startswith("test_") and (include_slow or s not in SLOW_TESTS):
            stems.add(s)
    return sorted(stems)


# ---------------------------------------------------------------- work copy and runs


def _copy_ignore(src_root: str):
    def ignore(d: str, names: List[str]) -> List[str]:
        top = os.path.normcase(os.path.abspath(d)) == os.path.normcase(os.path.abspath(src_root))
        return [n for n in names if n in COPY_IGNORE_ANY or (top and n in COPY_IGNORE_TOP)
                or n in (JOURNAL, BACKUP)]
    return ignore


def make_copy(repo: str, work: str) -> None:
    shutil.copytree(repo, work, ignore=_copy_ignore(repo))


def same_dir(a: str, b: str) -> bool:
    return os.path.normcase(os.path.realpath(a)) == os.path.normcase(os.path.realpath(b))


class RunResult(NamedTuple):
    status: str  # pass | fail | timeout | invalid
    seconds: float
    passing: int
    failing: int
    tail: str
    errors: str  # first engine/script error lines, which the tail often misses


GUT_PASS_RE = re.compile(r"Passing Tests\s+(\d+)")
GUT_FAIL_RE = re.compile(r"Failing Tests\s+(\d+)")
COMPILE_ERR_RE = re.compile(r"Parse Error|Compile Error|Failed to load script")
ERROR_LINE_RE = re.compile(r"SCRIPT ERROR|^ERROR:|^\s+at: ")


def classify(code: int, output: str, mutated_rel: Optional[str]) -> str:
    if code == 0:
        return "pass"
    if mutated_rel and COMPILE_ERR_RE.search(output) and ("res://" + mutated_rel) in output:
        return "invalid"
    return "fail"


def _kill_tree(proc: "subprocess.Popen[str]") -> None:
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.kill()
    try:
        proc.wait(timeout=TIMEOUT_MARGIN_S)
    except subprocess.TimeoutExpired:
        pass


def error_lines(output: str) -> str:
    return "\n".join([ln for ln in output.splitlines() if ERROR_LINE_RE.search(ln)][:MAX_ERROR_LINES])


def _run(cmd: Sequence[str], timeout_s: float) -> Tuple[Optional[int], str]:
    """(exit code or None on timeout, merged output); a timed-out process tree is killed."""
    proc = subprocess.Popen(list(cmd), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            encoding="utf-8", errors="replace")
    try:
        out, _ = proc.communicate(timeout=timeout_s)
        return proc.returncode, out or ""
    except subprocess.TimeoutExpired:
        _kill_tree(proc)
        return None, ""


def prime(work: str) -> str:
    """Rebuild the work copy's class cache; returns the last pass's error lines ('' when clean)."""
    cmd = [sys.executable, os.path.join(TOOLS, "godot_slots.py"), "run", "--label", "mutate-prime", "--",
           "godot", "--headless", "--editor", "--path", work, "--quit"]
    errs = ""
    for _ in range(PRIME_PASSES):
        code, out = _run(cmd, PRIME_TIMEOUT_S)
        errs = "prime timed out" if code is None else error_lines(out)
    return errs


def run_tests(work: str, tests: Sequence[str], timeout_s: float, mutated_rel: Optional[str]) -> RunResult:
    cmd = ["powershell", "-NoProfile", "-File", os.path.join(TOOLS, "run_gut.ps1"), ",".join(tests),
           "-Path", work]
    t0 = time.time()
    code, out = _run(cmd, timeout_s)
    status = "timeout" if code is None else classify(code, out, mutated_rel)
    secs = time.time() - t0
    p = GUT_PASS_RE.findall(out)
    f = GUT_FAIL_RE.findall(out)
    tail = "\n".join(out.splitlines()[-TAIL_LINES:])
    return RunResult(status, secs, int(p[-1]) if p else 0, int(f[-1]) if f else 0, tail, error_lines(out))


# ---------------------------------------------------------------- report


MUTATION_STATUS = {"pass": "survived", "fail": "killed", "timeout": "killed", "invalid": "invalid"}


def summarize(records: Sequence[Dict[str, object]]) -> Tuple[int, int]:
    """(killed, total) over run mutations; invalid ones are left out."""
    killed = sum(1 for r in records if r["result"] == "killed")
    total = sum(1 for r in records if r["result"] in ("killed", "survived"))
    return killed, total


def report_lines(records: Sequence[Dict[str, object]], untested: Sequence[str], red: Sequence[str],
                 not_run: int) -> List[str]:
    lines = ["SURVIVED %s" % r["mutation"] for r in records if r["result"] == "survived"]
    lines += ["UNTESTED %s (no test names it)" % p for p in untested]
    lines += ["BASELINE RED %s" % p for p in red]
    killed, total = summarize(records)
    extra = []
    invalid = sum(1 for r in records if r["result"] == "invalid")
    if invalid:
        extra.append("%d invalid" % invalid)
    timeouts = sum(1 for r in records if r["status"] == "timeout")
    if timeouts:
        extra.append("%d by timeout" % timeouts)
    if not_run:
        extra.append("%d not run: time limit" % not_run)
    lines.append("MUTATION %d/%d killed%s" % (killed, total, (" (%s)" % ", ".join(extra)) if extra else ""))
    return lines


def default_out() -> str:
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return os.path.join(repo_paths.scratch_root(), "_orchestrator", "mutate_core", stamp).replace("\\", "/")


# ---------------------------------------------------------------- main


def main(argv: Sequence[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("targets", nargs="*", help="core scripts or dirs (default: core/)")
    ap.add_argument("--path", default=os.path.dirname(TOOLS), help="source checkout (default: this one)")
    ap.add_argument("--max-mutations", type=int, default=DEFAULT_MAX_MUTATIONS)
    ap.add_argument("--time-limit", type=float, default=DEFAULT_TIME_LIMIT_S, help="wall-clock seconds")
    ap.add_argument("--ops", default=",".join(ALL_OPS))
    ap.add_argument("--seed", type=int, default=DEFAULT_SEED)
    ap.add_argument("--tests", default="", help="comma-separated test stems for every target")
    ap.add_argument("--include-slow", action="store_true")
    ap.add_argument("--work", default="", help="existing checkout to mutate (not the source)")
    ap.add_argument("--keep-work", action="store_true")
    ap.add_argument("--no-prime", action="store_true", help="skip rebuilding the work copy's class cache")
    ap.add_argument("--out", default="", help="details folder (default: scratch root)")
    ap.add_argument("--list", action="store_true", help="print the sampled mutations and exit")
    args = ap.parse_args(argv)

    repo = os.path.abspath(args.path).replace("\\", "/")
    ops = [o.strip() for o in args.ops.split(",") if o.strip()]
    bad = [o for o in ops if o not in ALL_OPS]
    if bad:
        print("mutate_core: unknown op(s) %s" % ", ".join(bad), file=sys.stderr)
        return 2
    try:
        targets = resolve_targets(repo, args.targets)
    except ValueError as e:
        print("mutate_core: %s" % e, file=sys.stderr)
        return 2

    override = [t.strip() for t in args.tests.split(",") if t.strip()]
    tests_by = {}
    untested = []
    sites = []
    for rel in targets:
        tests = override or tests_for(repo, rel, args.include_slow)
        if not tests:
            untested.append(rel)
            continue
        tests_by[rel] = tests
        with open(os.path.join(repo, rel), encoding="utf-8") as fh:
            sites.extend(generate(rel, fh.read(), ops))
    chosen = sample(sites, args.max_mutations, args.seed)

    if args.list:
        for m in chosen:
            print("%s  [%s]" % (m.describe(), ",".join(tests_by[m.path])))
        print("SITES %d sampled=%d targets=%d untested=%d" % (len(sites), len(chosen), len(tests_by), len(untested)))
        return 0

    out_dir = args.out or default_out()
    os.makedirs(out_dir, exist_ok=True)
    start = time.time()
    if args.work:
        work = os.path.abspath(args.work)
        if same_dir(work, repo) or same_dir(work, repo_paths.repo_dir()):
            print("mutate_core: --work must not be the source checkout or the main repo", file=sys.stderr)
            return 2
        if not os.path.isfile(os.path.join(work, "project.godot")):
            print("mutate_core: --work %s is not a Godot checkout" % work, file=sys.stderr)
            return 2
        owned = False
    else:
        work = os.path.join(out_dir, "work")
        print("copying checkout to %s ..." % work, flush=True)
        try:
            make_copy(repo, work)
        except (OSError, shutil.Error) as e:
            print("mutate_core: copy failed: %s" % e, file=sys.stderr)
            return 1
        owned = True
    restored = recover(work)
    if restored:
        print("restored %s left mutated by an earlier run" % restored)
    prime_errors = ""
    if not args.no_prime:
        print("priming class cache in %s ..." % work, flush=True)
        prime_errors = prime(work)
        if prime_errors:
            print("prime reported errors (see details.json): %s" % prime_errors.splitlines()[0])
    source_hashes = {rel: _sha(_read_bytes(os.path.join(repo, rel))) for rel in tests_by}

    records = []
    red = []
    baselines = {}
    not_run = 0
    try:
        for m in chosen:
            if m.path in red:
                continue
            if m.path not in baselines:
                print("baseline %s: %s" % (m.path, ",".join(tests_by[m.path])), flush=True)
                base = run_tests(work, tests_by[m.path], max(1.0, args.time_limit - (time.time() - start)), None)
                baselines[m.path] = base
                if base.status != "pass":
                    red.append(m.path)
                    continue
            base = baselines[m.path]
            if time.time() - start + base.seconds > args.time_limit:
                not_run += 1
                continue
            with Mutated(work, m):
                res = run_tests(work, tests_by[m.path], base.seconds * TIMEOUT_FACTOR + TIMEOUT_MARGIN_S, m.path)
            rec = {"mutation": m.describe(), "path": m.path, "line": m.line, "op": m.op, "old": m.old,
                   "new": m.new, "status": res.status, "result": MUTATION_STATUS[res.status],
                   "seconds": round(res.seconds, 1), "passing": res.passing, "failing": res.failing,
                   "tests": tests_by[m.path]}
            if res.status != "pass":
                rec["tail"] = res.tail
                rec["errors"] = res.errors
            records.append(rec)
            print("%-8s %s (%.0fs)" % (rec["result"], m.describe(), res.seconds), flush=True)
    finally:
        changed = [rel for rel, h in source_hashes.items() if _sha(_read_bytes(os.path.join(repo, rel))) != h]
        if changed:
            print("mutate_core: WARNING source files changed during the run: %s" % ", ".join(changed))
        if owned and not args.keep_work:
            shutil.rmtree(work, ignore_errors=True)

    lines = report_lines(records, untested, red, not_run)
    details = {"source": repo, "work": work if (args.keep_work or not owned) else "", "seed": args.seed,
               "ops": ops, "max_mutations": args.max_mutations, "sites": len(sites),
               "elapsed_s": round(time.time() - start, 1), "prime_errors": prime_errors,
               "baselines": {k: {"status": v.status, "seconds": round(v.seconds, 1), "passing": v.passing,
                                 "tail": v.tail if v.status != "pass" else "",
                                 "errors": v.errors} for k, v in baselines.items()},
               "tests": tests_by, "untested": untested, "mutations": records}
    with open(os.path.join(out_dir, "details.json"), "w", encoding="utf-8") as fh:
        json.dump(details, fh, indent=1)
    with open(os.path.join(out_dir, "summary.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    for ln in lines:
        print(ln[len("SURVIVED "):] if ln.startswith("SURVIVED ") else ln)
    print("details: %s" % out_dir.replace("\\", "/"))
    return 1 if tests_by and len(red) == len(tests_by) and not records else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
