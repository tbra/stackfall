"""Soak report: join the host and client soak logs, print the tick-cost curve, classify violations.

  python tools/soak_report.py --host host.log --client client.log [--config soak_config.tres]
                              [--known soak_known.json] [--scenario load]

Pure over text (no Godot, no files except the ones named): tools/run_soak.py imports it. The line
format is core/soak/SoakLine.gd (SOAK_PLAN section 7.1): a tag, then `key=value` tokens split on the
first `=`; foreign lines (engine output, a `[host]`/`[client]` prefix) are tolerated. The
agreement invariants are SOAK_PLAN section 6.1: a client sample at epoch e is compared with the host
samples of epochs e-k..e, k = ceil(agree_window_s / sample_interval_s). Tolerances come from the
run's own SOAK_CONFIG line, else from soak_config.tres read as text.

Verdicts: PASS = no failing violation, REPORT = every failing violation id is in soak_known.json,
FAIL = any other failing violation; sev=warn lines are listed but never gate. INVALID (a truncated
log, a client that never played) is decided before the verdict, so a bad run is never a false RED.
Exit codes of the CLI: 0 PASS/REPORT, 1 FAIL, 2 INVALID.
"""

import argparse
import collections
import json
import math
import os
import re
import sys

TAGS = ("SOAK_CONFIG", "SOAK_SAMPLE", "SOAK_BODY", "SOAK_FUZZ", "SOAK_VIOLATION", "SOAK_CURVE", "SOAK_END")
LINE_RE = re.compile(r"(?:^|\s)(%s)((?:\s+[^\s=]+=\S*)+)\s*$" % "|".join(TAGS))
ROLES = ("host", "client")
PLAYING = "PLAYING"
SEV_FAIL = "fail"
SEV_WARN = "warn"
EXIT = {"PASS": 0, "REPORT": 0, "FAIL": 1, "INVALID": 2}

# Fallbacks when neither the log nor soak_config.tres gives a tolerance (the SoakConfig defaults).
DEFAULTS = {
    "sample_interval_s": 5.0, "warmup_s": 30.0, "agree_window_s": 1.5, "spawn_grace_s": 3.0,
    "converge_pos_tol_m": 0.01, "converge_angle_tol_deg": 1.0, "at_rest_min_dumps": 2,
    "body_count_slack": 8, "share_tol": 0.005, "timer_tol_s": 2.0, "score_tol": 0,
    "curve_bands": [250, 500, 1000, 1500], "curve_min_ticks": 600,
}

Violation = collections.namedtuple("Violation", "inv role epoch sev subject value limit detail")


# --- parsing ---------------------------------------------------------------

def parse_line(line):
    """(tag, {key: value-string}) for a soak line, None for any other line."""
    m = LINE_RE.search(line.rstrip("\r\n"))
    if not m:
        return None
    fields = {}
    for tok in m.group(2).split():
        k, _, v = tok.partition("=")
        fields[k] = v
    return m.group(1), fields


def _num(text, default=0.0):
    try:
        return float(text)
    except (TypeError, ValueError):
        return default


def _list(text, conv=float):
    return [conv(x) for x in text.split(";") if x != ""] if text else []


def _pairs(text):
    """'0:41;1:39' -> {0: 41, 1: 39}."""
    out = {}
    for part in _list(text, str):
        k, _, v = part.partition(":")
        out[int(k)] = int(_num(v))
    return out


def _vec(text):
    return tuple(float(x) for x in text.split(","))


class RoleLog:
    """Everything one process wrote."""

    def __init__(self):
        self.config = {}
        self.samples = []      # dicts, in file order
        self.dumps = {}        # epoch -> {id: (p, q, rest)}
        self.fuzz = 0
        self.violations = []   # Violation, from the process's own SOAK_VIOLATION lines
        self.curves = {}       # band -> dict
        self.end = None

    def playing(self):
        return any(s.get("state") == PLAYING for s in self.samples)


def parse_log(text):
    """RoleLog from the text of one process's log."""
    log = RoleLog()
    for raw in text.splitlines():
        parsed = parse_line(raw)
        if parsed is None:
            continue
        tag, f = parsed
        try:
            if tag == "SOAK_CONFIG":
                log.config = f
            elif tag == "SOAK_SAMPLE":
                log.samples.append(f)
            elif tag == "SOAK_BODY":
                log.dumps.setdefault(int(f["epoch"]), {})[int(f["id"])] = (_vec(f["p"]), _vec(f["q"]), f.get("rest") == "1")
            elif tag == "SOAK_FUZZ":
                log.fuzz += 1
            elif tag == "SOAK_VIOLATION":
                log.violations.append(Violation(
                    f.get("inv", "?"), f.get("role", ""), int(_num(f.get("epoch"))), f.get("sev", SEV_FAIL),
                    f.get("subject", ""), f.get("value", ""), f.get("limit", ""), f.get("detail", "")))
            elif tag == "SOAK_CURVE":
                log.curves[int(f["band"])] = f
            elif tag == "SOAK_END":
                log.end = f
        except (KeyError, ValueError):
            continue  # a torn or truncated line is a foreign line
    return log


def split_merged(text):
    """(host_text, client_text) from a merged log whose lines start with `[host]` or `[client]`."""
    out = {"host": [], "client": []}
    for line in text.splitlines():
        m = re.match(r"\[(host|client)\] ?(.*)$", line)
        if m:
            out[m.group(1)].append(m.group(2))
    return "\n".join(out["host"]), "\n".join(out["client"])


def read_tres(text):
    """`key = value` lines of a .tres as {key: int|float|[int]|str}; PackedInt32Array becomes a list."""
    out = {}
    for line in text.splitlines():
        m = re.match(r"^(\w+)\s*=\s*(.+?)\s*$", line)
        if not m:
            continue
        key, val = m.group(1), m.group(2)
        arr = re.match(r"^Packed\w*Array\((.*)\)$", val)
        if arr:
            out[key] = [int(x) for x in arr.group(1).split(",") if x.strip()]
        elif re.match(r"^-?\d+$", val):
            out[key] = int(val)
        elif re.match(r"^-?\d*\.?\d+(e-?\d+)?$", val, re.I):
            out[key] = float(val)
        else:
            out[key] = val.strip('"')
    return out


def effective_config(host, tres_cfg=None):
    """Tolerances: defaults, then soak_config.tres, then the host's SOAK_CONFIG line (the run's own)."""
    cfg = dict(DEFAULTS)
    cfg.update(tres_cfg or {})
    for k, v in host.config.items():
        if k == "curve_bands":
            cfg[k] = _list(v, lambda x: int(float(x)))
        elif re.match(r"^-?\d+$", v):
            cfg[k] = int(v)
        elif re.match(r"^-?\d*\.?\d+$", v):
            cfg[k] = float(v)
    return cfg


# --- agreement join (SOAK_PLAN 6.1) ------------------------------------------

def _angle_deg(qa, qb):
    # Relative rotation qa^-1 * qb; atan2 of its vector and scalar parts is exact near identity,
    # where acos of a rounded dot product is not.
    ax, ay, az, aw = qa
    bx, by, bz, bw = qb
    vx = aw * bx - ax * bw - ay * bz + az * by
    vy = aw * by - ay * bw - az * bx + ax * bz
    vz = aw * bz - az * bw - ax * by + ay * bx
    w = aw * bw + ax * bx + ay * by + az * bz
    return math.degrees(2.0 * math.atan2(math.sqrt(vx * vx + vy * vy + vz * vz), abs(w)))


def _pose_close(a, b, cfg):
    return (math.dist(a[0], b[0]) <= cfg["converge_pos_tol_m"]
            and _angle_deg(a[1], b[1]) <= cfg["converge_angle_tol_deg"])


def _at_rest(host_dumps, epoch, cfg, body_id):
    """True when body_id is at rest in the last at_rest_min_dumps host dumps up to epoch, same pose."""
    epochs = [e for e in sorted(host_dumps) if e <= epoch][-int(cfg["at_rest_min_dumps"]):]
    if len(epochs) < cfg["at_rest_min_dumps"]:
        return False
    poses = [host_dumps[e].get(body_id) for e in epochs]
    if any(p is None or not p[2] for p in poses):
        return False
    return all(_pose_close(poses[0], p, cfg) for p in poses[1:])


def _window_k(cfg):
    return max(1, int(math.ceil(cfg["agree_window_s"] / cfg["sample_interval_s"])))


def _viol(inv, epoch, subject, value, limit, detail="", sev=SEV_FAIL):
    return Violation(inv, "client", epoch, sev, str(subject), value, limit, detail)


def _sample_checks(c, window, cfg):
    """Violations of one client sample c against its host window (non-empty list of host samples)."""
    e = int(c["epoch"])
    out = []
    bodies = [int(h["bodies"]) for h in window if "bodies" in h]
    if bodies and "bodies" in c:
        n = int(c["bodies"])
        lo, hi = min(bodies) - cfg["body_count_slack"], max(bodies) + cfg["body_count_slack"]
        if not lo <= n <= hi:
            out.append(_viol("agree.body_count", e, "", n, "%d..%d" % (lo, hi)))
    if "shares" in c:
        mine = _list(c["shares"])
        best = None
        for h in window:
            theirs = _list(h.get("shares", ""))
            if len(theirs) == len(mine):
                diff = max([abs(a - b) for a, b in zip(mine, theirs)] or [0.0])
                best = diff if best is None else min(best, diff)
        if best is None or best > cfg["share_tol"]:
            out.append(_viol("agree.territory_share", e, "", "%.4f" % (best if best is not None else -1.0), cfg["share_tol"]))
    if "raster_hash" in c and not any(h.get("raster_hash") == c["raster_hash"] for h in window):
        out.append(_viol("agree.raster_hash", e, "", c["raster_hash"], "host_in_window", sev=SEV_WARN))
    if "state" in c and not any(h.get("state") == c["state"] for h in window):
        out.append(_viol("agree.match_state", e, "", c["state"], "|".join(sorted(set(h.get("state", "") for h in window)))))
    if "scores" in c:
        mine = _pairs(c["scores"])  # per-slot owned tracked body counts; a slot missing on one side owns 0

        def close(theirs):
            return all(abs(mine.get(k, 0) - theirs.get(k, 0)) <= cfg["score_tol"] for k in set(mine) | set(theirs))
        ok = any(close(_pairs(h.get("scores", ""))) for h in window)
        if not ok:
            out.append(_viol("agree.scores", e, "", c["scores"], "score_tol=%s" % cfg["score_tol"]))
    if "timer" in c:
        t = _num(c["timer"])
        if not any(abs(t - _num(h.get("timer"))) <= cfg["timer_tol_s"] for h in window):
            out.append(_viol("agree.timer", e, "", c["timer"], cfg["timer_tol_s"]))
    return out


def _body_checks(epoch, client_bodies, host, k, cfg):
    """Violations of the client dump at `epoch` against the host dumps of epochs epoch-k..epoch."""
    win = [e for e in sorted(host.dumps) if epoch - k <= e <= epoch]
    if not win:
        return []
    out = []
    latest = win[-1]
    host_ids = host.dumps[latest]
    grace_epochs = int(math.ceil(cfg["spawn_grace_s"] / cfg["sample_interval_s"]))
    for bid in sorted(host_ids):
        first = min(e for e, d in host.dumps.items() if bid in d)
        if bid not in client_bodies:
            if (epoch - first) >= grace_epochs and first < epoch - k:  # seen on the host before the window: not a fresh spawn
                out.append(_viol("agree.missing_body", epoch, bid, "absent", "host_epoch=%d" % latest))
        elif _at_rest(host.dumps, latest, cfg, bid) and not _pose_close(host_ids[bid], client_bodies[bid], cfg):
            drift = math.dist(host_ids[bid][0], client_bodies[bid][0])
            out.append(_viol("agree.pose_after_sleep", epoch, bid, "%.4f" % drift, cfg["converge_pos_tol_m"]))
    seen_before = set()
    for e, d in host.dumps.items():
        if e <= epoch:
            seen_before.update(d)
    for bid in sorted(client_bodies):
        if bid not in seen_before:
            out.append(_viol("authority.client_only_body", epoch, bid, "present", "never_on_host"))
    return out


def compared_dumps(host, client, cfg):
    """How many client body dumps have a host dump in their window (the ones _body_checks can judge)."""
    k = _window_k(cfg)
    return sum(1 for e in client.dumps if any(e - k <= he <= e for he in host.dumps))


def join_violations(host, client, cfg):
    """Cross-process violations of the client log against the host log. Samples before warmup_s of
    match time are skipped; a client sample with no host sample in its window is not compared."""
    k = _window_k(cfg)
    by_epoch = collections.defaultdict(list)
    for h in host.samples:
        by_epoch[int(h["epoch"])].append(h)
    out = []
    for c in client.samples:
        if _num(c.get("mt")) < cfg["warmup_s"]:
            continue
        e = int(c["epoch"])
        window = [h for ep in range(e - k, e + 1) for h in by_epoch.get(ep, [])]
        if window:
            out.extend(_sample_checks(c, window, cfg))
    for epoch in sorted(client.dumps):
        out.extend(_body_checks(epoch, client.dumps[epoch], host, k, cfg))
    return out


# --- validity, known list, verdict ------------------------------------------

def invalid_reason(host, client):
    """Why a log pair cannot be judged (a truncated log, a client that never played), or None."""
    for role, log in (("host", host), ("client", client)):
        if not log.samples and log.end is None:
            return "%s log has no soak lines (log truncated or monitor never started)" % role
    if not client.playing():
        return "client never reached PLAYING"
    for role, log in (("host", host), ("client", client)):
        if log.end is None:
            return "%s log truncated (no SOAK_END)" % role
    return None


def load_known(path):
    """{"known": [ids], "engine_noise": [signatures]}; a missing or unreadable file is empty."""
    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError):
        data = {}
    return {"known": list(data.get("known", [])), "engine_noise": list(data.get("engine_noise", []))}


def classify(violations, known_ids):
    """(new, known, warn): failing violations not in / in the known list, then the sev=warn ones."""
    new, old, warn = [], [], []
    for v in violations:
        if v.sev == SEV_WARN:
            warn.append(v)
        elif v.inv in known_ids:
            old.append(v)
        else:
            new.append(v)
    return new, old, warn


def _counts(violations):
    c = collections.Counter(v.inv for v in violations)
    return ", ".join("%s x%d" % (inv, n) for inv, n in sorted(c.items()))


def verdict(violations, known_ids):
    """('PASS'|'REPORT'|'FAIL', detail) for a list of violations."""
    new, old, warn = classify(violations, known_ids)
    tail = " (%d warn)" % len(warn) if warn else ""
    if new:
        return "FAIL", _counts(new) + tail
    if old:
        return "REPORT", "known: %s%s" % (_counts(old), tail)
    return "PASS", "0 violations" + tail


# --- curve table -------------------------------------------------------------

def band_stats(log, band, cfg):
    """The SOAK_CURVE fields of a band, or None when missing or under curve_min_ticks."""
    f = log.curves.get(band)
    if f is None or int(_num(f.get("ticks"))) < cfg["curve_min_ticks"]:
        return None
    return f


def p99_map(log, cfg):
    """{band: p99_ms or None} over the configured bands."""
    out = {}
    for band in cfg["curve_bands"]:
        f = band_stats(log, band, cfg)
        out[band] = _num(f.get("p99_ms")) if f else None
    return out


def format_p99(p99):
    return "{%s}" % ",".join("%d:%s" % (b, "n/r" if v is None else "%.1f" % v) for b, v in p99.items())


def curve_table(host, client, cfg):
    """band | host p50/p99/max | client p50/p99/max | ticks; 'band not reached' under curve_min_ticks."""
    def cell(log, band):
        f = band_stats(log, band, cfg)
        if f is None:
            return "band not reached", 0
        return "%.1f/%.1f/%.1f" % (_num(f["p50_ms"]), _num(f["p99_ms"]), _num(f["max_ms"])), int(_num(f["ticks"]))
    rows = ["band | host p50/p99/max ms | client p50/p99/max ms | ticks (host/client)"]
    for band in cfg["curve_bands"]:
        h, ht = cell(host, band)
        c, ct = cell(client, band)
        rows.append("%d | %s | %s | %d/%d" % (band, h, c, ht, ct))
    return "\n".join(rows)


# --- one scenario and the whole run ------------------------------------------

def analyze(scenario, host_text, client_text, known_ids, tres_cfg=None):
    """Scenario result dict: name, verdict (PASS|REPORT|FAIL|INVALID), detail, violations, table,
    host_p99, client_p99."""
    host, client = parse_log(host_text), parse_log(client_text)
    cfg = effective_config(host, tres_cfg)
    res = {"name": scenario, "violations": [], "table": curve_table(host, client, cfg),
           "host_p99": p99_map(host, cfg), "client_p99": p99_map(client, cfg)}
    bad = invalid_reason(host, client)
    if bad:
        res.update(verdict="INVALID", detail=bad)
        return res
    violations = host.violations + client.violations + join_violations(host, client, cfg)
    v, detail = verdict(violations, known_ids)
    if v != "FAIL" and compared_dumps(host, client, cfg) == 0:  # never hides a FAIL
        v, detail = "INVALID", "no client body dump has a host dump at its epoch: body checks never ran"
    res.update(verdict=v, detail=detail, violations=violations)
    return res


def scenario_line(res):
    return "soak %s %s: %s" % (res["name"], "PASS" if res["verdict"] in ("PASS", "REPORT") else res["verdict"], res["detail"])


def overall(results, known_ids):
    """(RESULT line, exit code) over the scenario results; INVALID beats FAIL beats REPORT beats PASS."""
    names = "+".join(r["name"] for r in results)
    invalid = [r for r in results if r["verdict"] == "INVALID"]
    if invalid:
        return "SOAK RESULT INVALID: " + " / ".join("%s: %s" % (r["name"], r["detail"]) for r in invalid), EXIT["INVALID"]
    allv = [v for r in results for v in r["violations"]]
    v, detail = verdict(allv, known_ids)
    if v == "FAIL":
        return "SOAK RESULT FAIL: " + detail, EXIT["FAIL"]
    if v == "REPORT":
        new, old, _ = classify(allv, known_ids)
        return "SOAK RESULT REPORT: %d known (%s), 0 new violations" % (len(old), ", ".join(sorted(set(x.inv for x in old)))), EXIT["REPORT"]
    host_p99 = {}
    client_p99 = {}
    for r in results:
        host_p99.update(r["host_p99"])
        client_p99.update(r["client_p99"])
    return "SOAK RESULT PASS: %s %s, host p99 %s client p99 %s" % (
        names, detail, format_p99(host_p99), format_p99(client_p99)), EXIT["PASS"]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--host", required=True)
    ap.add_argument("--client", required=True)
    ap.add_argument("--scenario", default="load")
    ap.add_argument("--config", default=os.path.join(os.path.dirname(here), "config", "soak", "soak_config.tres"))
    ap.add_argument("--known", default=os.path.join(here, "soak_known.json"))
    a = ap.parse_args(argv)
    with open(a.host, encoding="utf-8", errors="replace") as fh:
        host_text = fh.read()
    with open(a.client, encoding="utf-8", errors="replace") as fh:
        client_text = fh.read()
    tres = {}
    if os.path.exists(a.config):
        with open(a.config, encoding="utf-8") as fh:
            tres = read_tres(fh.read())
    known = load_known(a.known)["known"]
    res = analyze(a.scenario, host_text, client_text, known, tres)
    print(res["table"])
    for v in res["violations"]:
        print("  %s %s %s epoch=%d subject=%s value=%s limit=%s" % (v.sev, v.inv, v.role, v.epoch, v.subject, v.value, v.limit))
    print(scenario_line(res))
    line, code = overall([res], known)
    print(line)
    return code


if __name__ == "__main__":
    sys.exit(main())
