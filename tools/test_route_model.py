"""Policy checks for bounded dispatch decisions, without a live TypeSafe call."""

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
        self.assertEqual(result["max_windowed_probes"], 0)

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
        self.assertEqual(result["max_windowed_probes"], 0)

    def test_unavailable_service_uses_bounded_fallback(self):
        with patch.dict(os.environ, {"TYPESAFE_API_KEY": ""}):
            result = router.route("Fix menu", "Selected item", ["ui/Menu.gd"], "bugfix", 0)
        self.assertEqual(result["source"], "fallback-rules")
        self.assertEqual(result["verification_tier"], "targeted")
        self.assertLessEqual(result["max_targeted_runs"], 2)


if __name__ == "__main__":
    unittest.main()
