"""Agent-setup evals: run a fixed set of past work packages against the current agent setup and score them.

Usage: python tools/agent_evals.py verify|prep|score|card ... (see --help of each)

The eval base commit is the overlay commit that prep makes, with the subject `eval base <name> r<N>`;
score finds it with `git log --grep` in the worktree. Hidden unittest entries are repo-relative file
paths, regression entries are module names.

Each eval in the evals manifest names a base commit, the accepted commit that
carries the hidden checks, and a brief. `prep` makes a worktree at the base with the setup
under test overlaid; after the worker is done `score` snapshots the candidate, applies the
hidden checks from the accepted commit, runs them and records one result per run; `card`
renders the scorecard; `verify` proves each eval's hidden checks are RED on the base and
GREEN on the accepted commit. Reuses tools/session_metrics.py for diff, guard and
mutation numbers.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, NamedTuple, Optional, Sequence, Tuple

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)
import new_worktree  # noqa: E402
import repo_paths  # noqa: E402
import session_metrics  # noqa: E402
from validate_worker_handback import HANDBACK_LOG  # noqa: E402

MANIFEST_REQUIRED = ("area", "base", "accepted", "brief", "hidden", "regression",
                     "interface_lines", "runner")
MANIFEST_OPTIONAL = ("lint_floor",)
RUNNERS = ("gut", "unittest")
LIST_KEYS = ("hidden", "regression", "interface_lines")
OVERLAY_PATHS = ("CLAUDE.md", ".claude", "tools")
OVERLAY_KEEP = ("tools/flag_dead_allow.json", "tools/probe_allowlist.txt",
                "tools/agent_evals.py", "tools/test_agent_evals.py")  # the last two are the harness, not the setup under test
OVERLAY_CHUNK = 200
CHECK_TIMEOUT_S = 1800
VERIFY_TIMEOUT_S = 900
LINT_TIMEOUT_S = 900


class CheckResult(NamedTuple):
    """Outcome of run_checks: pass/fail counts for hidden and regression checks, per script."""
    hidden_pass: int
    hidden_total: int
    regression_pass: int
    regression_total: int
    per_script: Dict[str, str]


class RunRecord(NamedTuple):
    """One scored run, the row written to <scratch>/_evals/<label>/<eval>-r<N>.json."""
    eval_name: str
    run: int
    setup_label: str
    candidate: str
    checks: CheckResult
    review_high: int
    review_med: int
    review_low: int
    guard_entries_added: int
    mutation: str
    lines_added: int
    lines_removed: int
    handback_attempts: int
    first_try_denials: int
    verdict: str
    turns: int
    tokens: int
    seconds: int
    lint_new: int


def _rev_exists(repo: str, rev: str) -> bool:
    return subprocess.run(["git", "-C", repo, "cat-file", "-e", rev + "^{commit}"],
                          capture_output=True).returncode == 0


def load_manifest(path: str, repo: Optional[str] = None) -> Dict[str, Dict[str, Any]]:
    """Load and validate the manifest: required keys, list types, known runner, and base/accepted
    revisions that exist in `repo` (default: the repository holding this tool)."""
    repo = repo or os.path.dirname(TOOLS)
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError("manifest: top level must be an object of eval name -> entry")
    for name, entry in data.items():
        if not isinstance(entry, dict):
            raise ValueError("manifest %s: entry must be an object" % name)
        missing = [k for k in MANIFEST_REQUIRED if k not in entry]
        if missing:
            raise ValueError("manifest %s: missing keys %s" % (name, ", ".join(missing)))
        unknown = [k for k in entry if k not in MANIFEST_REQUIRED + MANIFEST_OPTIONAL]
        if unknown:
            raise ValueError("manifest %s: unknown keys %s" % (name, ", ".join(unknown)))
        for key in LIST_KEYS:
            if not isinstance(entry[key], list):
                raise ValueError("manifest %s: %s must be a list" % (name, key))
        if entry["runner"] not in RUNNERS:
            raise ValueError("manifest %s: runner must be one of %s" % (name, ", ".join(RUNNERS)))
        for key in ("base", "accepted"):
            if not _rev_exists(repo, str(entry[key])):
                raise ValueError("manifest %s: %s rev %s not found in %s" % (name, key, entry[key], repo))
    return data


def _git(repo: str, *args: str, check: bool = True) -> str:
    p = subprocess.run(["git", "-C", repo] + list(args), capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    if check and p.returncode != 0:
        raise RuntimeError("git %s failed: %s" % (" ".join(args[:3]), (p.stderr or p.stdout).strip()[:300]))
    return p.stdout


def _commit(wt: str, message: str, paths: Sequence[str] = ()) -> str:
    """Stage `paths` (everything when empty) and commit even when nothing changed; returns the new HEAD."""
    _git(wt, "add", "-A", *((["--"] + list(paths)) if paths else []))
    _git(wt, "-c", "user.name=agent-evals", "-c", "user.email=agent-evals@localhost", "commit",
         "--allow-empty", "-q", "-m", message)
    return _git(wt, "rev-parse", "HEAD").strip()


def _protected(path: str, hidden: Sequence[str], accepted_changes: Sequence[str]) -> bool:
    """Overlay never touches baseline state, the evals folder, the hidden checks or what the accepted commit changed."""
    name = path.rsplit("/", 1)[-1]
    return (path in OVERLAY_KEEP or path.startswith("tools/evals/")
            or (path.startswith("tools/") and "baseline" in name and name.endswith(".json"))
            or path in hidden or path in accepted_changes)


def _overlay(wt: str, setup_rev: str, entry: Dict[str, Any]) -> None:
    """Replace CLAUDE.md, .claude/ and tools/ in the worktree with their state at setup_rev, except protected paths."""
    def files(rev: str) -> set:
        return set(_git(wt, "ls-tree", "-r", "--name-only", rev, "--", *OVERLAY_PATHS).splitlines())
    changed = _git(wt, "diff", "--name-only", entry["base"], entry["accepted"], "--", *OVERLAY_PATHS).splitlines()
    have, want = files("HEAD"), files(setup_rev)
    for path in sorted(p for p in have - want if not _protected(p, entry["hidden"], changed)):
        _git(wt, "rm", "-q", "-f", "--", path)
    take = sorted(p for p in want if not _protected(p, entry["hidden"], changed))
    for i in range(0, len(take), OVERLAY_CHUNK):
        _git(wt, "checkout", setup_rev, "--", *take[i:i + OVERLAY_CHUNK])


def _eval_dir(label: str) -> str:
    return os.path.join(repo_paths.scratch_root(), "_evals", label)


def prep_run(manifest: Dict[str, Dict[str, Any]], name: str, run: int, setup_rev: str,
             repo: str, root: str) -> str:
    """Create worktree <name>-r<run> at the eval base, overlay CLAUDE.md, .claude/ and tools/ from
    setup_rev, commit it as the eval base, write the rendered brief into scratch and print the
    dispatch_prep.py line. Returns the worktree path."""
    entry = manifest[name]
    rev = _git(repo, "rev-parse", setup_rev + "^{commit}").strip()
    wt, _branch, _sha = new_worktree.create("%s-r%d" % (name, run), repo, base=entry["base"], root=root or None)
    _overlay(wt, rev, entry)
    _commit(wt, "eval base %s r%d" % (name, run), OVERLAY_PATHS)
    if entry["runner"] == "gut" and os.path.isfile(os.path.join(wt, "project.godot")):
        print("import " + new_worktree.import_project(wt))
    with open(os.path.join(repo, "tools", "evals", entry["brief"]), encoding="utf-8") as f:
        brief = f.read().rstrip("\n")
    missing = [ln for ln in entry["interface_lines"] if ln not in brief]
    if missing:
        brief += "\n\nInterface the acceptance tests call:\n" + "\n".join("- " + ln for ln in missing)
    out = os.path.join(repo_paths.scratch_root(), "_evals", "briefs", "%s-r%d.md" % (name, run))
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        f.write(brief + "\n")
    print("python tools/dispatch_prep.py --bead <eval-pass-bead> --role stackfall-implementer --title \"eval %s r%d\" "
          "--files <owned files> --kind bugfix --package %s --checkout %s --redispatch" % (name, run, out, wt))
    return wt


def snapshot_candidate(wt: str) -> str:
    """git add -A and commit in the throwaway worktree (never merged); returns the candidate revision."""
    return _commit(wt, "eval candidate")


def apply_hidden(wt: str, manifest_entry: Dict[str, Any]) -> List[str]:
    """git checkout <accepted> -- <hidden paths> in wt, after the worker is done; returns the paths applied."""
    paths = list(manifest_entry["hidden"])
    if paths:
        _git(wt, "checkout", manifest_entry["accepted"], "--", *paths)
    return paths


def _run(cmd: List[str], cwd: str, timeout_s: int) -> Tuple[Optional[int], str]:
    """(exit code or None on timeout, output); a timeout kills the whole process tree."""
    env = dict(os.environ, PYTHONPATH=os.pathsep.join([cwd, os.path.join(cwd, "tools")]))  # module names resolve
    p = subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                         encoding="utf-8", errors="replace")
    try:
        out, _ = p.communicate(timeout=timeout_s)
        return p.returncode, out
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
        else:
            p.kill()
        out, _ = p.communicate()
        return None, out


def _count(code: Optional[int], out: str, runner: str) -> Tuple[int, int]:
    """(passing, total) from one script run; (0, 1) when the run produced no readable totals."""
    if runner == "gut":
        ran = re.search(r"^\s*Tests\s+(\d+)", out, re.M)
        ok = re.search(r"^\s*Passing Tests\s+(\d+)", out, re.M)
        if not ran or not ok:
            return 0, 1
        passing, total = int(ok.group(1)), int(ran.group(1))
    else:
        ran = re.search(r"^Ran (\d+) tests?", out, re.M)
        if not ran:
            return 0, 1
        total = int(ran.group(1))
        passing = total - sum(int(n) for _k, n in re.findall(r"(failures|errors)=(\d+)", out))
    if code != 0 and passing == total:
        passing = max(0, total - 1)  # script errors or a non-zero exit with every test green
    return passing, max(total, 1)


def run_checks(wt: str, manifest_entry: Dict[str, Any], timeout_s: int) -> CheckResult:
    """Run the hidden and regression scripts (gut: tools/run_gut.ps1 -Path wt; unittest: python -m unittest)."""
    runner = manifest_entry["runner"]
    suffix = ".gd" if runner == "gut" else ".py"
    hidden = [h for h in manifest_entry["hidden"] if h.endswith(suffix)]
    per_script: Dict[str, str] = {}
    sums = {"hidden": [0, 0], "regression": [0, 0]}
    for kind, scripts in (("hidden", hidden), ("regression", manifest_entry["regression"])):
        for script in scripts:
            if runner == "gut":
                label = os.path.basename(script)[:-len(suffix)] if script.endswith(suffix) else script
                cmd = ["powershell", "-NoProfile", "-File", os.path.join(TOOLS, "run_gut.ps1"), label, "-Path", wt]
            else:
                label = script
                cmd = [sys.executable, "-m", "unittest", script]
            code, out = _run(cmd, wt, timeout_s)
            passing, total = _count(code, out, runner)
            per_script["%s/%s" % (kind, label)] = ("TIMEOUT" if code is None else
                                                   "%s %d/%d" % ("PASS" if passing == total else "FAIL", passing, total))
            sums[kind][0] += passing
            sums[kind][1] += total
    return CheckResult(sums["hidden"][0], sums["hidden"][1], sums["regression"][0], sums["regression"][1], per_script)


def _lint_red(wt: str) -> int:
    """Number of RED lints lint_all reports for the checkout (0 when GREEN)."""
    p = subprocess.run([sys.executable, os.path.join(TOOLS, "lint_all.py"), "--path", wt], capture_output=True,
                       text=True, encoding="utf-8", errors="replace", timeout=LINT_TIMEOUT_S)
    last = [ln for ln in (p.stdout or "").splitlines() if ln.startswith("LINT ALL")]
    if last and last[-1].startswith("LINT ALL GREEN"):
        return 0
    return len(last[-1].split(":", 1)[1].split(",")) if last and ":" in last[-1] else 1


def _hidden_state(result: CheckResult) -> str:
    return "GREEN" if result.hidden_total > 0 and result.hidden_pass == result.hidden_total else "RED"


def _remove_worktree(repo: str, wt: str) -> None:
    branch = _git(wt, "rev-parse", "--abbrev-ref", "HEAD", check=False).strip()
    _git(repo, "worktree", "remove", "--force", wt, check=False)
    if branch.startswith("wt/"):
        _git(repo, "branch", "-D", branch, check=False)


def verify_eval(manifest: Dict[str, Dict[str, Any]], name: str, repo: str) -> bool:
    """True when hidden checks are RED on the overlaid base and GREEN on the accepted commit;
    records the number of RED lints of the overlaid base as lint_floor."""
    entry = manifest[name]
    hidden_only = dict(entry, regression=[])
    root = os.path.join(repo_paths.scratch_root(), "_evals", "_verify")
    base_wt = prep_run(manifest, name, 0, "HEAD", repo, root)
    acc_wt = ""
    try:
        entry["lint_floor"] = _lint_red(base_wt)
        apply_hidden(base_wt, entry)
        on_base = _hidden_state(run_checks(base_wt, hidden_only, VERIFY_TIMEOUT_S))
        acc_wt, _b, _s = new_worktree.create("%s-acc" % name, repo, base=entry["accepted"], root=root)
        if entry["runner"] == "gut" and os.path.isfile(os.path.join(acc_wt, "project.godot")):
            new_worktree.import_project(acc_wt)
        on_accepted = _hidden_state(run_checks(acc_wt, hidden_only, VERIFY_TIMEOUT_S))
    finally:
        _remove_worktree(repo, base_wt)
        if acc_wt:
            _remove_worktree(repo, acc_wt)
    print("VERIFY %s: base %s (want RED), accepted %s (want GREEN), lint_floor %s"
          % (name, on_base, on_accepted, entry["lint_floor"]))
    return on_base == "RED" and on_accepted == "GREEN"


def score_run(manifest: Dict[str, Dict[str, Any]], name: str, run: int, wt: str,
              usage: Dict[str, Any], bead: str) -> Dict[str, Any]:
    """Compose the per-run record (RunRecord fields as a dict) from run_checks and session_metrics
    with rev = the eval base commit; usage carries turns, tokens and seconds copied from the Agent tool,
    and optionally review_high/med/low, setup_label and check_timeout; `bead` is the eval run's bead, whose
    handback rows give attempts, first-try denials and verdict."""
    entry = manifest[name]
    base = _git(wt, "log", "-1", "--format=%H", "--grep", "^eval base %s r%d$" % (name, run)).strip()
    if not base:
        raise RuntimeError("no 'eval base %s r%d' commit in %s" % (name, run, wt))
    candidate = snapshot_candidate(wt)
    lines = list(session_metrics.delivery(wt, base)["lines"].values())
    added_guards = session_metrics.guards(wt, base)[0]
    core = session_metrics.changed_core(wt, base)
    mutation = "; ".join("%s: %s" % kv for kv in session_metrics.mutate(wt, core).items()) if core else "n/a"
    lint_new = max(0, _lint_red(wt) - int(entry.get("lint_floor") or 0))
    apply_hidden(wt, entry)  # only now: the worker's tree never held the hidden checks
    checks = run_checks(wt, entry, int(usage.get("check_timeout", CHECK_TIMEOUT_S)))
    # With a bead the filter isolates the run, so the window may open at the eval's original base; without
    # one it opens at the overlay commit.
    start = entry["base"] if bead else base
    since = session_metrics.parse_since(session_metrics.git(wt, "show", "-s", "--format=%cI", start).strip())
    # The eval reviewer hands back on the same bead; its "review" rows are not the worker's attempts.
    hb = session_metrics.handbacks(os.path.join(repo_paths.scratch_root(), *HANDBACK_LOG), since, bead,
                                   skip_verdict="review")
    verdicts = sorted(v for v in hb.get("verdicts", {}) if v != "review")
    record = RunRecord(
        eval_name=name, run=run, setup_label=str(usage.get("setup_label", "")), candidate="%s@%s" % (wt, candidate[:10]),
        checks=checks, review_high=int(usage.get("review_high", 0)), review_med=int(usage.get("review_med", 0)),
        review_low=int(usage.get("review_low", 0)), guard_entries_added=len(added_guards), mutation=mutation,
        lines_added=sum(a for a, _r in lines), lines_removed=sum(r for _a, r in lines),
        handback_attempts=hb["attempts"], first_try_denials=hb.get("denied", 0), verdict="+".join(verdicts) or "none",
        turns=int(usage.get("turns", 0)), tokens=int(usage.get("tokens", 0)), seconds=int(usage.get("seconds", 0)),
        lint_new=lint_new)
    return record._asdict()


MEAN_COLUMNS = ("review_high", "review_med", "review_low", "guard_entries_added", "lines_added", "lines_removed",
                "handback_attempts", "first_try_denials", "turns", "tokens", "seconds", "lint_new")


def _rate(passing: int, total: int) -> float:
    return passing / total if total else 0.0


def _mean(values: List[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _check(row: Dict[str, Any], key: str) -> Any:
    """A checks field whether the row holds a CheckResult or its JSON dict."""
    c = row["checks"]
    return c[key] if isinstance(c, dict) else getattr(c, key)


def _mean_row(label: str, rows: List[Dict[str, Any]]) -> str:
    cells = ["%.2f" % _mean([_rate(_check(r, "hidden_pass"), _check(r, "hidden_total")) for r in rows]),
             "%.2f" % _mean([_rate(_check(r, "regression_pass"), _check(r, "regression_total")) for r in rows])]
    cells += ["%.1f" % _mean([r[c] for r in rows]) for c in MEAN_COLUMNS]
    return "| **%s** | mean | %s | | |" % (label, " | ".join(cells))


def render_card(results_dir: str, setup_label: str) -> str:
    """Markdown table, one row per run plus per-eval and overall means; writes scorecard.md in results_dir."""
    rows: List[Dict[str, Any]] = []
    for fname in sorted(os.listdir(results_dir)):
        if fname.endswith(".json"):
            with open(os.path.join(results_dir, fname), encoding="utf-8") as f:
                data = json.load(f)
            if isinstance(data, dict) and data.get("setup_label") == setup_label and "checks" in data:
                rows.append(data)
    rows.sort(key=lambda r: (r["eval_name"], r["run"]))
    head = ["hidden", "regression"] + list(MEAN_COLUMNS)
    out = ["# Scorecard %s" % setup_label, "", "| eval | run | " + " | ".join(head) + " | mutation | verdict |",
           "|" + "---|" * (len(head) + 4)]
    for r in rows:
        cells = ["%d/%d" % (_check(r, "hidden_pass"), _check(r, "hidden_total")),
                 "%d/%d" % (_check(r, "regression_pass"), _check(r, "regression_total"))]
        cells += [str(r[k]) for k in MEAN_COLUMNS]
        out.append("| %s | %d | %s | %s | %s |" % (r["eval_name"], r["run"], " | ".join(cells), r["mutation"], r["verdict"]))
    for ev in sorted({r["eval_name"] for r in rows}):
        out.append(_mean_row(ev, [r for r in rows if r["eval_name"] == ev]))
    if rows:
        out.append(_mean_row("all", rows))
    text = "\n".join(out) + "\n"
    with open(os.path.join(results_dir, "scorecard.md"), "w", encoding="utf-8") as f:
        f.write(text)
    return text


def _cmd_verify(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest, args.path)
    names = args.evals or sorted(manifest)
    results = {n: verify_eval(manifest, n, args.path) for n in names}
    with open(args.manifest, "w", encoding="utf-8", newline="\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    bad = [n for n, ok in results.items() if not ok]
    print("VERIFY %s: %d/%d%s" % ("GREEN" if not bad else "RED", len(names) - len(bad), len(names),
                                  " failing=" + ",".join(bad) if bad else ""))
    return 1 if bad else 0


def _cmd_prep(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest, args.path)
    print("worktree " + prep_run(manifest, args.eval, args.run, args.setup_rev, args.path, args.root))
    return 0


def _cmd_score(args: argparse.Namespace) -> int:
    manifest = load_manifest(args.manifest, args.path)
    usage = {"turns": args.turns, "tokens": args.tokens, "seconds": args.seconds, "setup_label": args.setup_label,
             "review_high": args.review_high, "review_med": args.review_med, "review_low": args.review_low}
    record = score_run(manifest, args.eval, args.run, os.path.abspath(args.worktree), usage, args.bead)
    record["checks"] = record["checks"]._asdict()
    out_dir = _eval_dir(args.setup_label)
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "%s-r%d.json" % (args.eval, args.run))
    with open(path, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2)
    c = record["checks"]
    print("SCORE %s r%d: hidden %d/%d regression %d/%d -> %s" % (args.eval, args.run, c["hidden_pass"],
          c["hidden_total"], c["regression_pass"], c["regression_total"], path.replace("\\", "/")))
    return 0


def _cmd_card(args: argparse.Namespace) -> int:
    print(render_card(args.results or _eval_dir(args.setup_label), args.setup_label))
    return 0


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--manifest", default=os.path.join(TOOLS, "evals", "manifest.json"))
    ap.add_argument("--path", default=os.path.dirname(TOOLS), help="main checkout")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("verify", help="hidden checks RED on the base, GREEN on the accepted commit")
    p.add_argument("--eval", dest="evals", action="append", default=[], help="eval name (default: all)")

    p = sub.add_parser("prep", help="make the worktree, overlay the setup, render the brief")
    p.add_argument("eval")
    p.add_argument("--run", type=int, default=1)
    p.add_argument("--setup-rev", default="HEAD", help="revision the setup overlay is taken from")
    p.add_argument("--root", default="", help="worktree root")

    p = sub.add_parser("score", help="snapshot the candidate, apply hidden checks, record the run")
    p.add_argument("eval")
    p.add_argument("--run", type=int, default=1)
    p.add_argument("--worktree", required=True)
    p.add_argument("--bead", default="", help="the eval run's bead (handback rows are filtered by it)")
    p.add_argument("--setup-label", required=True)
    p.add_argument("--review-high", type=int, default=0)
    p.add_argument("--review-med", type=int, default=0)
    p.add_argument("--review-low", type=int, default=0)
    p.add_argument("--tokens", type=int, default=0)
    p.add_argument("--turns", type=int, default=0)
    p.add_argument("--seconds", type=int, default=0)

    p = sub.add_parser("card", help="render the scorecard for one setup label")
    p.add_argument("setup_label")
    p.add_argument("--results", default="", help="results directory (default: <scratch>/_evals/<label>)")

    for command, handler in (("verify", _cmd_verify), ("prep", _cmd_prep), ("score", _cmd_score), ("card", _cmd_card)):
        sub.choices[command].set_defaults(handler=handler)
    return ap


def main(argv: Sequence[str]) -> int:
    args = build_parser().parse_args(list(argv))
    return args.handler(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
