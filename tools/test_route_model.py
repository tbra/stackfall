"""Policy checks for bounded dispatch decisions, without a live TypeSafe call."""

import json
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))
import route_model as router  # noqa: E402


class RoutePolicyTests(unittest.TestCase):
    def test_mechanical_work_skips_network_and_visual_runs(self):
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": "test"}), patch.object(router, "_request") as request:
            result = router.route("Rename HUD label", "Exact text supplied", ["ui/Hud.gd"], "mechanical", 0)
        request.assert_not_called()
        self.assertEqual((result["model"], result["verification_tier"]), ("haiku", "quick"))
        self.assertIsNone(result["max_windowed_probes"])

    def test_core_review_and_specialized_gate_cannot_be_waived_by_jev(self):
        reply = {
            "answers": {
                "model": {"choice": "sonnet", "confidence": 0.9},
                "needs_review": {"noul": 0.01},
                "split_first": {"noul": 0.01},
                "verification_tier": {"choice": "quick"},
                "visual_probe": {"noul": 0.99},
            }
        }
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": "test"}), patch.object(router, "_request", return_value=reply):
            result = router.route("Fix host intent", "Validate ownership", ["net/Session.gd"], "bugfix", 0)
        self.assertTrue(result["needs_review"])
        self.assertEqual(result["verification_tier"], "specialized")
        self.assertEqual(result["max_targeted_runs"], 2)
        self.assertIsNone(result["max_windowed_probes"])

    def test_unavailable_service_uses_bounded_fallback(self):
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}):
            result = router.route("Fix menu", "Selected item", ["ui/Menu.gd"], "bugfix", 0)
        self.assertEqual(result["source"], "fallback-rules")
        self.assertEqual(result["verification_tier"], "targeted")
        self.assertLessEqual(result["max_targeted_runs"], 2)


SAMPLE = """Memories matching "x":

  stackfall-debrief
    session note

  startup-pump-exit-leak
    1pi.11.57 summary

  other-key
    more
"""


class MemoryTests(unittest.TestCase):
    def test_keywords_drop_short_stop_numeric_and_ids(self):
        kws = router.extract_keywords("Bontago-fca.67 StartupPump exit leak on 12345 quit update tooling")
        self.assertEqual(kws, ["startuppump", "startup", "tooling"])

    def test_keywords_prefer_longer_and_cap(self):
        kws = router.extract_keywords("alpha bravoo charlie delta1 echoes foxtrots")
        self.assertEqual(len(kws), 4)
        self.assertEqual(kws[0], "foxtrots")

    def test_parse_keys(self):
        self.assertEqual(
            router.parse_memory_keys(SAMPLE), ["stackfall-debrief", "startup-pump-exit-leak", "other-key"]
        )

    def test_parse_no_hit_notice_is_not_a_key(self):
        self.assertEqual(router.parse_memory_keys('No memories matching "shader"\n'), [])

    def test_find_excludes_session_notes_and_dedupes(self):
        keys = router.find_memories("StartupPump tooling", runner=lambda kw, t: SAMPLE)
        self.assertEqual(keys, ["startup-pump-exit-leak", "other-key"])

    def test_failures_yield_no_memories(self):
        def boom(kw, t):
            raise FileNotFoundError("bd")

        self.assertEqual(router.find_memories("StartupPump tooling", runner=boom), [])

    def test_json_includes_memories_and_no_memories_flag(self):
        import io
        from contextlib import redirect_stdout

        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}), patch.object(
            router, "find_memories", return_value=["k1"]
        ), patch("sys.stdin", io.StringIO("")):
            buf = io.StringIO()
            with redirect_stdout(buf):
                router.main(["--title", "Fix menu", "--json"])
            self.assertEqual(json.loads(buf.getvalue())["memories"], ["k1"])
            buf = io.StringIO()
            with redirect_stdout(buf):
                router.main(["--title", "Fix menu", "--json", "--no-memories"])
            self.assertEqual(json.loads(buf.getvalue())["memories"], [])


if __name__ == "__main__":
    unittest.main()
