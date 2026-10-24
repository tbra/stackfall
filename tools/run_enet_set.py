"""Run the whole ENet multiplayer harness set, one harness at a time.

  python tools/run_enet_set.py [--path <checkout>] [--out <dir>] [--only name,name] [--timeout-s N]

The single home of the harness list: every tools/run_*_enet.ps1 in the checkout is one harness
(add a runner there and it joins the set). Callers: tools/integrate_batch.py (after a green gate
when the merged diff touches net/ or tests/enet/) and the session-close step.

Each harness runs as `powershell -File tools/run_<name>_enet.ps1 -Path <checkout> -Out <dir>` under
a wall-clock limit that kills the whole process tree. Every runner declares how many Godot processes
it has running at once (host + clients + a late joiner) on a header line `# ENET-PROCESSES: <n>`
(ENET_PROCESSES_RE); that line is the single source of the count, and a runner without it fails the
harness (test_run_enet_set fails for it too). The harness holds one tools/godot_slots.py slot per
declared process, all taken at once (godot_slots.godot_slots); one that declares more processes than godot_slots.cap() runs under
`godot_slots.godot_exclusive` instead, because no slot count could ever cover it. A harness passes only
on its single `ENET RESULT PASS` line; `ENET RESULT FAIL: <reason>`, a missing result line or a
timeout is a failure. Prints one line per harness and a final `ENET SET GREEN|RED: p/n passed`.
Exit 0 = GREEN. Expected duration: several minutes per harness, roughly 30-45 min for the set.
"""

import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

HARNESS_TIMEOUT_S = 1100  # longest runner deadline is 900 s; headroom for startup
RESULT_RE = re.compile(r"^ENET RESULT (PASS|FAIL\b.*)$", re.M)
RUNNER_RE = re.compile(r"^run_(.+)_enet\.ps1$")
ENET_PROCESSES_RE = re.compile(r"^#\s*ENET-PROCESSES:\s*(\d+)", re.M)
EXCLUSIVE_WAIT_S = 3600.0  # how long a harness over the slot cap queues for the whole machine


def kill_tree(pid):
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True, check=False)
    else:
        try:
            os.killpg(os.getpgid(pid), 9)
        except OSError:
            pass


def discover(path):
    """Sorted [(name, runner_path)] of the harness runners in <path>/tools."""
    found = []
    for f in sorted(glob.glob(os.path.join(path, "tools", "run_*_enet.ps1"))):
        m = RUNNER_RE.match(os.path.basename(f))
        if m:
            found.append((m.group(1), f))
    return found


def process_count(runner_path):
    """Godot processes the runner has running at once, from its `# ENET-PROCESSES: <n>` header line;
    None when the line is missing, unreadable or not a positive number."""
    try:
        with open(runner_path, encoding="utf-8", errors="replace") as fh:
            m = ENET_PROCESSES_RE.search(fh.read())
    except OSError:
        return None
    return int(m.group(1)) if m and int(m.group(1)) > 0 else None


def hold_capacity(name, processes, slots=None):
    """Context manager holding the machine capacity for `processes` Godot processes: one slot each,
    or the whole machine (godot_exclusive) when that exceeds the slot cap."""
    if slots is None:
        import godot_slots as slots
    if processes > slots.cap():
        return slots.godot_exclusive("enet:%s x%d" % (name, processes), wait_s=EXCLUSIVE_WAIT_S)
    # All slots at once: holding some while waiting for the rest deadlocks against another set's
    # exclusive request, which blocks new slots until every holder drains.
    return slots.godot_slots("enet:%s" % name, processes)


def parse_result(text):
    """('PASS'|'FAIL', detail). A missing or ambiguous result line is a FAIL."""
    found = RESULT_RE.findall(text)
    if not found:
        return "FAIL", "no ENET RESULT line"
    if len(found) > 1 and set(found) != {"PASS"}:
        return "FAIL", "; ".join(f for f in found if f != "PASS")[:200]
    if found[-1] == "PASS":
        return "PASS", ""
    return "FAIL", found[-1][len("FAIL"):].lstrip(": ")[:200] or "FAIL"


def run_one(name, runner, path, out_dir, timeout_s):
    """Run one harness under its declared process capacity and a tree-killing wall-clock limit.
    Returns (verdict, detail, seconds, log_path)."""
    os.makedirs(out_dir, exist_ok=True)
    log = os.path.join(out_dir, "%s.log" % name)
    processes = process_count(runner)
    if processes is None:
        return "FAIL", "runner declares no `# ENET-PROCESSES: <n>` line", 0.0, log
    start = time.time()
    with hold_capacity(name, processes):
        args = ["powershell", "-NoProfile", "-File", runner, "-Path", path, "-Out", out_dir]
        try:
            p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 text=True, encoding="utf-8", errors="replace")
        except OSError as e:
            return "FAIL", "cannot run powershell: %s" % e, 0.0, log
        timed_out = False
        try:
            text, _ = p.communicate(timeout=timeout_s)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_tree(p.pid)
            try:
                text, _ = p.communicate(timeout=60)
            except subprocess.TimeoutExpired:
                text = ""
    text = text or ""
    with open(log, "w", encoding="utf-8") as fh:
        fh.write(text)
    secs = time.time() - start
    if timed_out:
        return "FAIL", "timeout after %ds (process tree killed)" % timeout_s, secs, log
    verdict, detail = parse_result(text)
    return verdict, detail, secs, log


def run_set(path, out_dir, say=print, only=None, timeout_s=HARNESS_TIMEOUT_S, runner=run_one):
    """Run every harness. Returns [(name, verdict, detail, seconds, log)]; runner is injectable.
    A failing harness reruns once alone; pass-on-rerun is verdict FLAKY (reported, not a failure)."""
    results = []
    for name, script in discover(path):
        if only and name not in only:
            continue
        verdict, detail, secs, log = runner(name, script, path, out_dir, timeout_s)
        say("enet %-22s %s%s (%ds) %s" % (name, verdict, " " + detail if detail else "", secs, log))
        if verdict != "PASS":
            first = detail or verdict
            rerun_dir = os.path.join(out_dir, "rerun")
            verdict, detail, secs2, log = runner(name, script, path, rerun_dir, timeout_s)
            secs += secs2
            if verdict == "PASS":
                verdict, detail = "FLAKY", "first run: %s" % first
            say("enet %-22s rerun %s%s (%ds) %s" % (name, verdict, " " + detail if detail else "", secs2, log))
        results.append((name, verdict, detail, secs, log))
    return results


def summary(results):
    """(green, line). FLAKY harnesses count as passed and are named in the line as enet_flaky."""
    passed = sum(1 for r in results if r[1] in ("PASS", "FLAKY"))
    flaky = [r[0] for r in results if r[1] == "FLAKY"]
    green = bool(results) and passed == len(results)
    line = "ENET SET %s: %d/%d passed" % ("GREEN" if green else "RED", passed, len(results))
    return green, line + (" enet_flaky=%s" % ",".join(flaky) if flaky else "")


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--out", default="")
    ap.add_argument("--only", default="", help="comma-separated harness names (e.g. qol,rocket)")
    ap.add_argument("--timeout-s", type=int, default=HARNESS_TIMEOUT_S)
    a = ap.parse_args(argv)
    out = a.out or tempfile.mkdtemp(prefix="enet_set_")
    only = set(x for x in a.only.split(",") if x)
    results = run_set(os.path.abspath(a.path), out, only=only or None, timeout_s=a.timeout_s)
    green, line = summary(results)
    print(line, flush=True)
    return 0 if green else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
