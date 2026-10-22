"""Tests for tools/soak_report.py: parsing, the host/client join, curve table, verdicts and RESULT line.
Pure text; no Godot is launched.
Run: python tools/test_soak_report.py
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soak_report as sr  # noqa: E402

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FIXTURE = os.path.join(REPO, "tests", "unit", "soak", "fixtures", "soak_lines.txt")
TRES = os.path.join(REPO, "config", "soak", "soak_config.tres")
KNOWN = ["budget.client_tick_p99"]
POSE = "0.0000,0.5000,0.0000"
QUAT = "0.0000,0.0000,0.0000,1.0000"


def sample(role, epoch, mt=100.0, **kw):
    f = dict(bodies=100, shares="0.3000;0.2000", state="PLAYING", timer="-1.0000", scores="0:5;1:4", raster_hash=7)
    f.update(kw)
    return "SOAK_SAMPLE role=%s epoch=%d wall_ms=%d mt=%.4f %s" % (
        role, epoch, epoch * 5000, mt, " ".join("%s=%s" % kv for kv in sorted(f.items())))


def body(role, epoch, bid, pos=POSE, rest=1):
    return "SOAK_BODY role=%s epoch=%d id=%d p=%s q=%s rest=%d" % (role, epoch, bid, pos, QUAT, rest)


def end(role):
    return "SOAK_END role=%s samples=2 violations=0 sim_rate=60.0000" % role


def curve(role, band, ticks=1000, p99=10.0):
    return "SOAK_CURVE role=%s band=%d bodies_mean=%d ticks=%d p50_ms=5.0000 p99_ms=%.4f max_ms=12.0000 budget_ms=16.6700 over=0" % (
        role, band, band, ticks, p99)


def violation(inv, role="host", sev="fail"):
    return "SOAK_VIOLATION inv=%s role=%s epoch=100 wall_ms=1 mt=100.0000 sev=%s subject=3 value=1.0000 limit=0.0000 detail=x" % (inv, role, sev)


def logs(host_extra=(), client_extra=(), host_samples=None, client_samples=None):
    """(host_text, client_text) of a clean run; *_samples replace the default sample lines."""
    host = (host_samples if host_samples is not None else [sample("host", 100), sample("host", 101)]) + list(host_extra) + [end("host")]
    client = (client_samples if client_samples is not None else [sample("client", 100), sample("client", 101)]) + list(client_extra) + [end("client")]
    if not any(x.startswith("SOAK_BODY") for x in list(host_extra) + list(client_extra)):  # a clean run compares at least one dump
        host.insert(0, body("host", 100, 1))
        client.insert(0, body("client", 100, 1))
    return "\n".join(host), "\n".join(client)


def run(host_extra=(), client_extra=(), **kw):
    h, c = logs(host_extra, client_extra, **kw)
    return sr.analyze("load", h, c, KNOWN)


def invs(res):
    return sorted(set(v.inv for v in res["violations"]))


class ParseTest(unittest.TestCase):
    def test_golden_fixture_lines_parse(self):
        with open(FIXTURE, encoding="utf-8") as fh:
            text = fh.read()
        log = sr.parse_log(text)
        self.assertEqual(log.config["scenario"], "load")
        self.assertEqual(len(log.samples), 1)
        self.assertEqual(log.samples[0]["bodies"], "512")
        self.assertEqual(log.dumps[353000001][1204][2], True)
        self.assertEqual(log.fuzz, 1)
        self.assertEqual(log.violations[0].inv, "physics.below_kill_plane")
        self.assertEqual(log.violations[0].detail, "owner=3")  # value split on the first '=' only
        self.assertEqual(log.curves[1000]["ticks"], "5400")
        self.assertEqual(log.end["bodies_end"], "1480")

    def test_foreign_and_prefixed_lines(self):
        self.assertIsNone(sr.parse_line("ERROR: something SOAK_END"))
        self.assertIsNone(sr.parse_line("Godot Engine v4.7.2"))
        tag, f = sr.parse_line("[client] SOAK_FUZZ role=client seq=1 kind=FLOOD slot=1")
        self.assertEqual((tag, f["kind"]), ("SOAK_FUZZ", "FLOOD"))

    def test_torn_line_is_ignored(self):
        log = sr.parse_log("SOAK_BODY role=host epoch=5 id=\nSOAK_BODY role=host epoch=5 id=2 p=1,2,3 q=0,0,0,1 rest=0")
        self.assertEqual(list(log.dumps[5]), [2])

    def test_split_merged(self):
        h, c = sr.split_merged("[host] a\n[client] b\nnoise\n[host] c")
        self.assertEqual((h, c), ("a\nc", "b"))

    def test_read_tres_real_config(self):
        cfg = sr.read_tres(open(TRES, encoding="utf-8").read())
        self.assertEqual(cfg["curve_bands"], [250, 500, 1000, 1500])
        self.assertEqual(cfg["idle_cpu_max_pct"], 25.0)
        self.assertEqual(cfg["match_seed"], 20261020)

    def test_known_file_ships_the_di0_2_29_line(self):
        known = sr.load_known(os.path.join(os.path.dirname(os.path.abspath(__file__)), "soak_known.json"))
        self.assertEqual(known["known"], ["budget.client_tick_p99"])
        self.assertEqual(len(known["engine_noise"]), 3)
        self.assertEqual(sr.load_known("no/such/file.json"), {"known": [], "engine_noise": []})


class JoinTest(unittest.TestCase):
    def test_clean_pair_passes(self):
        res = run(host_extra=[body("host", 94, 1), body("host", 100, 1)], client_extra=[body("client", 100, 1)])
        self.assertEqual((res["verdict"], res["violations"]), ("PASS", []))

    def test_missing_body_only_when_older_than_the_window(self):
        host = [body("host", 94, 1), body("host", 100, 1), body("host", 100, 2)]  # id 2 is new at 100
        res = run(host_extra=host, client_extra=[body("client", 94, 1), body("client", 100, 3)])
        self.assertIn("agree.missing_body", invs(res))
        missing = [v.subject for v in res["violations"] if v.inv == "agree.missing_body"]
        self.assertEqual(missing, ["1"])  # id 2 is a fresh spawn (grace), id 1 has been on the host a dump ago

    def test_new_host_body_is_within_spawn_grace(self):
        res = run(host_extra=[body("host", 100, 2)], client_extra=[body("client", 100, 4)])
        self.assertNotIn("agree.missing_body", invs(res))

    def test_client_only_body(self):
        res = run(host_extra=[body("host", 100, 1)], client_extra=[body("client", 100, 1), body("client", 100, 99)])
        self.assertEqual([(v.inv, v.subject) for v in res["violations"]], [("authority.client_only_body", "99")])
        self.assertEqual(res["verdict"], "FAIL")

    def test_client_body_removed_on_host_since_is_not_local_only(self):
        res = run(host_extra=[body("host", 94, 7), body("host", 100, 1)], client_extra=[body("client", 100, 1), body("client", 100, 7)])
        self.assertNotIn("authority.client_only_body", invs(res))

    def test_pose_drift_after_rest(self):
        host = [body("host", 94, 1), body("host", 100, 1)]
        drift = body("client", 100, 1, pos="0.5000,0.5000,0.0000")
        self.assertEqual(invs(run(host_extra=host, client_extra=[drift])), ["agree.pose_after_sleep"])
        near = body("client", 100, 1, pos="0.0050,0.5000,0.0000")  # inside converge_pos_tol_m
        self.assertEqual(invs(run(host_extra=host, client_extra=[near])), [])

    def test_pose_drift_ignored_while_host_body_moves(self):
        awake = [body("host", 94, 1, rest=0), body("host", 100, 1, rest=0)]
        self.assertEqual(invs(run(host_extra=awake, client_extra=[body("client", 100, 1, pos="3.0000,0.5000,0.0000")])), [])
        one_dump = [body("host", 100, 1)]  # at_rest_min_dumps = 2: a single resting dump is not enough
        self.assertEqual(invs(run(host_extra=one_dump, client_extra=[body("client", 100, 1, pos="3.0000,0.5000,0.0000")])), [])

    def test_rotation_drift_counts(self):
        host = [body("host", 94, 1), body("host", 100, 1)]
        turned = "SOAK_BODY role=client epoch=100 id=1 p=%s q=0.0000,0.2000,0.0000,0.9798 rest=1" % POSE
        self.assertEqual(invs(run(host_extra=host, client_extra=[turned])), ["agree.pose_after_sleep"])

    def test_body_count_slack_boundary(self):
        at_edge = run(client_samples=[sample("client", 100, bodies=108)])
        over = run(client_samples=[sample("client", 100, bodies=109)])
        self.assertEqual(invs(at_edge), [])
        self.assertEqual(invs(over), ["agree.body_count"])

    def test_share_timer_state_score_mismatch(self):
        self.assertEqual(invs(run(client_samples=[sample("client", 100, shares="0.3040;0.2000")])), [])  # inside share_tol
        self.assertEqual(invs(run(client_samples=[sample("client", 100, shares="0.4000;0.2000")])), ["agree.territory_share"])
        self.assertEqual(invs(run(client_samples=[sample("client", 100, shares="0.3000")])), ["agree.territory_share"])
        self.assertEqual(invs(run(client_samples=[sample("client", 100, timer="30.0000")])), ["agree.timer"])
        self.assertEqual(invs(run(client_samples=[sample("client", 100, state="ENDED"), sample("client", 101)])), ["agree.match_state"])
        self.assertEqual(invs(run(client_samples=[sample("client", 100, scores="0:6;1:4")])), ["agree.scores"])

    def test_scores_slot_missing_on_one_side_owns_zero(self):
        self.assertEqual(invs(run(client_samples=[sample("client", 100, scores="0:5;1:4;2:0"), sample("client", 101)])), [])
        self.assertEqual(invs(run(client_samples=[sample("client", 100, scores="0:5"), sample("client", 101)])), ["agree.scores"])

    def test_no_aligned_body_dump_is_invalid_not_skipped(self):
        # a client dump at 100 against a host dump only at 90 (outside epoch-k..epoch): nothing was compared
        res = run(host_extra=[body("host", 90, 1)], client_extra=[body("client", 100, 1)])
        self.assertEqual(res["verdict"], "INVALID")
        self.assertIn("body checks never ran", res["detail"])
        res = run(host_extra=[body("host", 90, 1), violation("authority.fuzz_accepted")], client_extra=[body("client", 100, 1)])
        self.assertEqual((res["verdict"], invs(res)), ("FAIL", ["authority.fuzz_accepted"]))  # INVALID never hides a FAIL
        res = run(host_extra=[body("host", 99, 1)], client_extra=[body("client", 100, 1)])  # e-1 is aligned
        self.assertEqual(res["verdict"], "PASS")

    def test_raster_hash_is_only_a_warning(self):
        res = run(client_samples=[sample("client", 100, raster_hash=8)])
        self.assertEqual(invs(res), ["agree.raster_hash"])
        self.assertEqual((res["violations"][0].sev, res["verdict"]), ("warn", "PASS"))

    def test_window_edges(self):
        bad = sample("client", 100, shares="0.9000;0.0000")
        far = sample("host", 98)           # two epochs back: outside the window of 1
        near = sample("host", 99)          # one epoch back: inside
        later = sample("host", 101)        # host sample after the client sample: outside
        self.assertEqual(invs(run(client_samples=[bad], host_samples=[far])), [])
        self.assertEqual(invs(run(client_samples=[bad], host_samples=[later])), [])
        self.assertEqual(invs(run(client_samples=[bad], host_samples=[near])), ["agree.territory_share"])
        agrees = sample("host", 99, shares="0.9000;0.0000")  # one host sample in the window agrees: no violation
        self.assertEqual(invs(run(client_samples=[bad], host_samples=[agrees, sample("host", 100)])), [])

    def test_samples_before_warmup_are_skipped(self):
        self.assertEqual(invs(run(client_samples=[sample("client", 100, mt=10.0, bodies=900)])), [])


class VerdictTest(unittest.TestCase):
    def test_own_violation_lines_gate(self):
        res = run(host_extra=[violation("authority.fuzz_accepted"), violation("authority.fuzz_accepted")])
        self.assertEqual(res["verdict"], "FAIL")
        self.assertIn("authority.fuzz_accepted x2", res["detail"])

    def test_known_id_reports_and_new_id_fails(self):
        known = run(client_extra=[violation("budget.client_tick_p99", "client")])
        self.assertEqual(known["verdict"], "REPORT")
        mixed = run(client_extra=[violation("budget.client_tick_p99", "client"), violation("territory.fresh_solve")])
        self.assertEqual(mixed["verdict"], "FAIL")
        self.assertNotIn("budget.client_tick_p99", mixed["detail"])

    def test_warn_never_gates(self):
        self.assertEqual(run(host_extra=[violation("budget.monitor_overhead", sev="warn")])["verdict"], "PASS")

    def test_truncated_log_is_invalid(self):
        h, c = logs()
        res = sr.analyze("load", h, c.replace("SOAK_END", "SOAK_NOPE"), KNOWN)
        self.assertEqual(res["verdict"], "INVALID")
        self.assertIn("client log truncated", res["detail"])
        self.assertEqual(sr.analyze("load", "", c, KNOWN)["verdict"], "INVALID")

    def test_client_never_playing_is_invalid(self):
        res = run(client_samples=[sample("client", 100, state="LOBBY")])
        self.assertEqual((res["verdict"], res["detail"]), ("INVALID", "client never reached PLAYING"))


class CurveAndResultTest(unittest.TestCase):
    def curve_run(self, client_ticks):
        host = [curve("host", b, 1000, 10.0) for b in (250, 500, 1000, 1500)]
        client = [curve("client", 250, 1000, 11.0), curve("client", 500, client_ticks, 12.0)]
        return run(host_extra=host, client_extra=client)

    def test_band_under_min_ticks_is_not_reached(self):
        res = self.curve_run(599)  # curve_min_ticks = 600
        self.assertEqual(res["client_p99"], {250: 11.0, 500: None, 1000: None, 1500: None})
        self.assertIn("band not reached", res["table"])
        self.assertEqual(self.curve_run(600)["client_p99"][500], 12.0)

    def test_table_has_a_row_per_band(self):
        rows = self.curve_run(1000)["table"].splitlines()
        self.assertEqual(len(rows), 5)
        self.assertTrue(rows[1].startswith("250 | 5.0/10.0/12.0 | 5.0/11.0/12.0 | 1000/1000"))

    def test_result_pass_line(self):
        line, code = sr.overall([self.curve_run(1000)], KNOWN)
        self.assertEqual(code, 0)
        self.assertTrue(line.startswith("SOAK RESULT PASS: load 0 violations, host p99 {250:10.0,500:10.0,1000:10.0,1500:10.0} client p99 {"))
        self.assertIn("1000:n/r", line)

    def test_result_report_fail_invalid_and_exit_codes(self):
        report = run(client_extra=[violation("budget.client_tick_p99", "client")])
        fail = run(host_extra=[violation("authority.fuzz_accepted")] * 3 + [violation("territory.fresh_solve")])
        invalid = {"name": "authority", "verdict": "INVALID", "detail": "client never reached PLAYING", "violations": []}
        line, code = sr.overall([report], KNOWN)
        self.assertEqual((line, code), ("SOAK RESULT REPORT: 1 known (budget.client_tick_p99), 0 new violations", 0))
        line, code = sr.overall([report, fail], KNOWN)
        self.assertEqual((line, code), ("SOAK RESULT FAIL: authority.fuzz_accepted x3, territory.fresh_solve x1", 1))
        line, code = sr.overall([fail, invalid], KNOWN)  # a bad run is never a false RED
        self.assertEqual(code, 2)
        self.assertTrue(line.startswith("SOAK RESULT INVALID: authority: client never"))

    def test_cli_exit_code(self):
        import tempfile
        h, c = logs(host_extra=[violation("authority.fuzz_accepted")])
        with tempfile.TemporaryDirectory() as d:
            hp, cp = os.path.join(d, "h.log"), os.path.join(d, "c.log")
            open(hp, "w").write(h)
            open(cp, "w").write(c)
            self.assertEqual(sr.main(["--host", hp, "--client", cp]), 1)


if __name__ == "__main__":
    unittest.main()
