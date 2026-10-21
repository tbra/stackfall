"""End-to-end invariant soak: one headless bot host and one lagged headless ENet client, per scenario.

  python tools/run_soak.py --idle [--path <checkout>] [--out <dir>] [--scenario load|authority|all]
                           [--duration-s N]

Refuses (exit 3) without --idle: the soak runs only when the user says the PC is idle. Holds the whole
machine (godot_slots.godot_exclusive) and checks godot_slots.cpu_load_pct() before and after against
idle_cpu_max_pct from config/soak/soak_config.tres (read as text): a busy machine is INVALID, never
red. Per scenario the host starts first; the client starts when the host log shows its first
`HEADLESS_BOTS t=` line. Both are bounded by duration + shutdown_grace_s and killed as a tree. The two
logs are merged with `[host]`/`[client]` prefixes, joined by tools/soak_report.py and gated by
`tools/triage_log.py --soak --no-classify`. Prints one line per scenario and one
`SOAK RESULT PASS|REPORT|FAIL|INVALID: ...` line; exit 0 PASS/REPORT, 1 FAIL, 2 INVALID, 3 refused.
SOAK_PLAN sections 4 and 7.4. --duration-s shortens host --seconds and the deadline for a dry run; the
monitors still end at their own duration_s, so a dry run is usually INVALID (truncated).
Expected duration: about 18 minutes for `all`.
"""

import argparse
import os
import socket
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soak_report  # noqa: E402

REFUSAL = "SOAK REFUSED: the soak runs only when the user says the PC is idle; rerun with --idle"
EXIT_REFUSED = 3
EXCLUSIVE_WAIT_S = 3600.0   # how long the soak queues for the whole machine
POLL_S = 1.0
HOST_READY_MARK = "HEADLESS_BOTS t="
HOST_PLAYERS = 8            # the player cap; bots fill the last seats
LOOPBACK = "127.0.0.1"
CONFIG_REL = os.path.join("config", "soak", "soak_config.tres")
# DECISION: the authority scenario's 180 s has no SoakConfig field (SOAK_PLAN 4.2); it lives here until one exists.
AUTHORITY_DURATION_S = 180.0
# name -> (bots, fuzzing client, duration_s or None = SoakConfig.duration_s)
SCENARIOS = {"load": (8, False, None), "authority": (6, True, AUTHORITY_DURATION_S)}


def kill_tree(pid):
    from run_enet_set import kill_tree as kill
    kill(pid)


class Proc:
    """A started process writing to a log file."""

    def __init__(self, popen, log_path):
        self.popen = popen
        self.log_path = log_path

    def poll(self):
        return self.popen.poll()

    def kill(self):
        if self.popen.poll() is None:
            kill_tree(self.popen.pid)


class RealRunner:
    def start(self, cmd, log_path):
        fh = open(log_path, "w", encoding="utf-8")
        try:
            p = subprocess.Popen(cmd, stdout=fh, stderr=subprocess.STDOUT)
        finally:
            fh.close()
        return Proc(p, log_path)


def free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.bind((LOOPBACK, 0))
        return s.getsockname()[1]


def build_host_cmd(godot, path, port, scenario, cfg, duration_s):
    bots = SCENARIOS[scenario][0]
    return [godot, "--headless", "--path", path, "--", "--headless-host", "--port=%d" % port,
            "--bots=%d" % bots, "--players=%d" % HOST_PLAYERS,
            "--match-config=res://config/soak/soak_match_%s.tres" % scenario,
            "--match-seed=%d" % cfg["match_seed"], "--seconds=%g" % duration_s, "--soak", "--debug"]


def build_client_cmd(godot, path, port, scenario, cfg):
    cmd = [godot, "--headless", "--path", path, "--", "--join=%s:%d" % (LOOPBACK, port),
           "--sim-lag=%g" % cfg["client_sim_lag_ms"], "--sim-loss=%g" % cfg["client_sim_loss"], "--soak"]
    if SCENARIOS[scenario][1]:
        cmd.append("--soak-fuzz")
    return cmd + ["--debug"]


def _read(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def run_processes(host_cmd, client_cmd, host_log, client_log, cfg, duration_s, runner, clock, sleep):
    """Start the host, wait for its first HEADLESS_BOTS line, start the client, wait for both under
    the deadline. Returns a problem string (None when both ended on their own); processes are always killed."""
    host = client = None
    try:
        host = runner.start(host_cmd, host_log)
        ready_by = clock() + cfg["host_ready_timeout_s"]
        while HOST_READY_MARK not in _read(host_log):
            if host.poll() is not None:
                return "host exited before its first HEADLESS_BOTS line"
            if clock() >= ready_by:
                return "host not ready within %gs" % cfg["host_ready_timeout_s"]
            sleep(POLL_S)
        client = runner.start(client_cmd, client_log)
        deadline = clock() + duration_s + cfg["shutdown_grace_s"]
        while host.poll() is None or client.poll() is None:
            if clock() >= deadline:
                return "timeout after %gs (process tree killed)" % (duration_s + cfg["shutdown_grace_s"])
            sleep(POLL_S)
        return None
    finally:
        for p in (client, host):
            if p is not None:
                p.kill()


def merge_logs(host_text, client_text):
    lines = ["[host] " + x for x in host_text.splitlines()] + ["[client] " + x for x in client_text.splitlines()]
    return "\n".join(lines) + "\n"


def run_triage(merged_path):
    """(returncode, output) of triage_log.py --soak --no-classify on the merged log."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "triage_log.py")
    try:
        p = subprocess.run([sys.executable, script, "--soak", "--no-classify", merged_path],
                           capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.SubprocessError) as e:
        return -1, str(e)
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def run_scenario(name, path, out, cfg, duration_s, known, godot, runner, triage, clock, sleep, say):
    """Run and judge one scenario; returns the soak_report scenario result dict."""
    port = free_port()
    host_log = os.path.join(out, "%s_host.log" % name)
    client_log = os.path.join(out, "%s_client.log" % name)
    problem = run_processes(build_host_cmd(godot, path, port, name, cfg, duration_s),
                            build_client_cmd(godot, path, port, name, cfg),
                            host_log, client_log, cfg, duration_s, runner, clock, sleep)
    host_text, client_text = _read(host_log), _read(client_log)
    merged = os.path.join(out, "%s.log" % name)
    with open(merged, "w", encoding="utf-8") as fh:
        fh.write(merge_logs(host_text, client_text))
    res = soak_report.analyze(name, host_text, client_text, known, cfg)
    if problem and res["verdict"] != "INVALID":
        res.update(verdict="INVALID", detail=problem)
    elif problem:
        res["detail"] = "%s; %s" % (problem, res["detail"])
    if res["verdict"] != "INVALID":
        rc, text = triage(merged)
        if rc == 1:
            res["violations"].append(soak_report.Violation("log.triage_gate", "both", 0, soak_report.SEV_FAIL, "", "", "", merged))
            res["verdict"], res["detail"] = soak_report.verdict(res["violations"], known)
        elif rc != 0:
            say("soak %s: triage_log --soak unavailable (rc %s), log gate skipped: %s" % (name, rc, text.strip()[:200]))
    say(res["table"])
    say(soak_report.scenario_line(res))
    return res


def main(argv=None, runner=None, slots=None, triage=None, clock=time.time, sleep=time.sleep, say=print, godot=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--out", default="")
    ap.add_argument("--scenario", choices=("load", "authority", "all"), default="all")
    ap.add_argument("--idle", action="store_true", help="required: the user says the PC is idle")
    ap.add_argument("--duration-s", type=float, default=0.0, help="override every scenario's duration (dry runs)")
    a = ap.parse_args(argv)
    if not a.idle:
        say(REFUSAL)
        return EXIT_REFUSED
    path = os.path.abspath(a.path)
    tres = _read(os.path.join(path, CONFIG_REL))
    if not tres:
        say("SOAK RESULT INVALID: cannot read %s" % CONFIG_REL)
        return soak_report.EXIT["INVALID"]
    cfg = soak_report.read_tres(tres)
    known = soak_report.load_known(os.path.join(os.path.dirname(os.path.abspath(__file__)), "soak_known.json"))["known"]
    out = a.out or tempfile.mkdtemp(prefix="soak_")
    os.makedirs(out, exist_ok=True)
    if slots is None:
        import godot_slots as slots
    if godot is None:
        import godot_exe
        godot = godot_exe.resolve()
    runner = runner or RealRunner()
    triage = triage or run_triage
    names = list(SCENARIOS) if a.scenario == "all" else [a.scenario]
    limit = cfg["idle_cpu_max_pct"]

    def busy():
        load = slots.cpu_load_pct()
        return "machine busy (cpu %d%% > %g%%)" % (load, limit) if load > limit else None

    with slots.godot_exclusive("soak", wait_s=EXCLUSIVE_WAIT_S):
        reason = busy()
        results = []
        if reason is None:
            for name in names:
                duration = a.duration_s or SCENARIOS[name][2] or cfg["duration_s"]
                results.append(run_scenario(name, path, out, cfg, duration, known, godot, runner, triage, clock, sleep, say))
            reason = busy()
    if reason:  # a busy machine invalidates the timing, whatever the scenarios said
        results = [dict(r, verdict="INVALID", detail=reason) for r in results] or [
            {"name": "all", "verdict": "INVALID", "detail": reason, "violations": []}]
    line, code = soak_report.overall(results, known)
    say(line)
    say("soak logs: %s" % out)
    return code


if __name__ == "__main__":
    sys.exit(main())
