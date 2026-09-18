#!/usr/bin/env python
"""Unit tests for triage_log.py's deterministic half (extraction, id
normalisation, grouping) and the confidence-gated CI exit code. Uses only
the stdlib `unittest`, consistent with the tool itself being
dependency-light.

Run with:
    python tools/test_triage_log.py
or:
    python -m unittest tools.test_triage_log -v   (from the repo root)
"""

from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import triage_log as tl  # noqa: E402


class NormalizationTests(unittest.TestCase):
    """Regression coverage for a real false-negative: three warnings that
    should have collapsed into one signature (count=3) instead produced
    three distinct ones, because the ids were embedded in a quoted node
    name ('Block_7741') and a space-separated `net_id 7741` rather than the
    `key=value` shape the first version of the normaliser assumed."""

    def test_quoted_node_name_and_net_id_collapse_to_one_group(self) -> None:
        text = (
            "WARNING: Node 'Block_7741' was freed while a snapshot referenced net_id 7741\n"
            "       [0] apply_state (res://net/Interpolator.gd:88)\n"
            "WARNING: Node 'Block_1180' was freed while a snapshot referenced net_id 1180\n"
            "       [0] apply_state (res://net/Interpolator.gd:88)\n"
            "WARNING: Node 'Block_9032' was freed while a snapshot referenced net_id 9032\n"
            "       [0] apply_state (res://net/Interpolator.gd:88)\n"
        )
        records = tl.extract_records(text)
        self.assertEqual(len(records), 3, "all three WARNING lines must be recognised as records")

        groups = tl.group_records(records)
        self.assertEqual(len(groups), 1, f"expected one signature, got {[g.signature for g in groups]}")
        self.assertEqual(groups[0].count, 3)
        # The collapsed signature must not still contain any of the raw ids.
        for raw_id in ("7741", "1180", "9032"):
            self.assertNotIn(raw_id, groups[0].signature)

    def test_godot_auto_name_at_class_at_number_collapses(self) -> None:
        rec = tl.ErrorRecord(
            marker="WARNING",
            message="Node '@RigidBody3D@4711' was freed unexpectedly.",
            backtrace=["at: apply_state (res://net/Interpolator.gd:88)"],
        )
        sig = tl.normalize(rec)
        self.assertNotIn("4711", sig)
        self.assertIn("@RigidBody3D@<ID>", sig)

        # A second occurrence with a different auto-name counter must match.
        rec2 = tl.ErrorRecord(
            marker="WARNING",
            message="Node '@RigidBody3D@9982' was freed unexpectedly.",
            backtrace=["at: apply_state (res://net/Interpolator.gd:88)"],
        )
        self.assertEqual(tl.normalize(rec), tl.normalize(rec2))

    def test_script_line_reference_survives_normalisation_intact(self) -> None:
        rec = tl.ErrorRecord(
            marker="SCRIPT ERROR",
            message="Invalid get index 'shape' (on base: 'null instance').",
            backtrace=["at: apply_state (res://net/Interpolator.gd:88)"],
        )
        sig = tl.normalize(rec)
        self.assertIn("res://net/Interpolator.gd:88", sig, "the script:line must not be touched")

        # Two records whose only difference is the script line must NOT
        # collapse together -- the line is what distinguishes the bugs.
        rec_other_line = tl.ErrorRecord(
            marker="SCRIPT ERROR",
            message="Invalid get index 'shape' (on base: 'null instance').",
            backtrace=["at: apply_state (res://net/Interpolator.gd:91)"],
        )
        self.assertNotEqual(tl.normalize(rec), tl.normalize(rec_other_line))

    def test_engine_cpp_file_line_reference_also_survives(self) -> None:
        rec = tl.ErrorRecord(
            marker="ERROR",
            message='Failed to instantiate an autoload, script does not inherit from "Node".',
            backtrace=["at: start (main/main.cpp:4539)"],
        )
        sig = tl.normalize(rec)
        self.assertIn("main/main.cpp:4539", sig)

    def test_small_numbers_survive_when_not_id_tagged(self) -> None:
        # A GUT summary-style count is not an id and should not be masked.
        rec = tl.ErrorRecord(marker="WARNING", message="266 tests, 265 passing.", backtrace=[])
        sig = tl.normalize(rec)
        self.assertIn("266", sig)
        self.assertIn("265", sig)

    def test_large_bare_integer_is_still_collapsed(self) -> None:
        rec = tl.ErrorRecord(marker="WARNING", message="Physics tick 48213 took too long.", backtrace=[])
        sig = tl.normalize(rec)
        self.assertNotIn("48213", sig)
        self.assertIn("<ID>", sig)

    def test_hex_address_and_objectid_wrapper_still_collapse(self) -> None:
        rec = tl.ErrorRecord(
            marker="ERROR",
            message="Object 0x00007ffbeead3210 (ObjectID<37821>) was queued for deletion twice.",
            backtrace=[],
        )
        sig = tl.normalize(rec)
        self.assertNotIn("0x00007ffbeead3210", sig)
        self.assertNotIn("37821", sig)


class SeverityGateTests(unittest.TestCase):
    """A false likely-bug fails the build, which is the expensive direction
    (docs.typesafe.ai/confidence): a likely-bug answer must only gate CI
    when the model is actually confident in it."""

    def _group(self, severity: str, confidence) -> tl.Group:
        rec = tl.ErrorRecord(marker="SCRIPT ERROR", message="x", backtrace=[])
        g = tl.Group(signature="x", marker="SCRIPT ERROR", representative=rec, count=1)
        g.severity = severity
        g.severity_confidence = confidence
        return g

    def test_high_confidence_likely_bug_gates(self) -> None:
        g = self._group("likely-bug", 0.93)
        self.assertTrue(tl.severity_gates_ci(g))

    def test_low_confidence_likely_bug_does_not_gate(self) -> None:
        g = self._group("likely-bug", 0.35)
        self.assertFalse(tl.severity_gates_ci(g))
        # It must still be visible as likely-bug, not silently reclassified.
        self.assertEqual(g.severity, "likely-bug")

    def test_missing_confidence_does_not_gate(self) -> None:
        g = self._group("likely-bug", None)
        self.assertFalse(tl.severity_gates_ci(g))

    def test_non_bug_severity_never_gates(self) -> None:
        for severity in ("benign-noise", "known-limitation", None):
            g = self._group(severity, 0.99)
            self.assertFalse(tl.severity_gates_ci(g))

    def test_end_to_end_exit_code_ignores_low_confidence_bug(self) -> None:
        text = 'SCRIPT ERROR: Condition "!is_inside_tree()" is true.\n   at: get_path (scene/main/node.cpp:2136)\n'
        records = tl.extract_records(text)
        groups = tl.group_records(records)

        def fake_urlopen(req, timeout=None):
            import json

            answers = {
                "g0_subsystem": {"type": "choice", "choice": "engine-noise", "confidence": 0.4, "probabilities": {}},
                "g0_severity": {"type": "choice", "choice": "likely-bug", "confidence": 0.35, "probabilities": {}},
                "g0_novel": {"type": "noul", "noul": 0.3},
            }
            resp = {"model": "jev-latest", "answers": answers, "usage": {"input_tokens": 1, "output_tokens": 1}}
            m = MagicMock()
            m.read.return_value = json.dumps(resp).encode("utf-8")
            m.__enter__.return_value = m
            m.__exit__.return_value = False
            return m

        with patch("urllib.request.urlopen", side_effect=fake_urlopen):
            tl.classify_groups(
                groups, limitations=[], api_key="fake", chunk_size=6, max_classify=40,
                model="jev-latest", timeout=5.0,
            )

        self.assertEqual(groups[0].severity, "likely-bug")
        self.assertFalse(any(tl.severity_gates_ci(g) for g in groups))


class KnownLimitationKeywordTests(unittest.TestCase):
    """Regression coverage for a real false positive: bare class names used
    throughout the codebase (MatchConfig, CellGrid, TerritorySolver) must
    not be trusted as deterministic known-limitation match keywords."""

    def test_bare_class_name_is_not_specific(self) -> None:
        self.assertFalse(tl._is_specific_keyword("MatchConfig"))
        self.assertFalse(tl._is_specific_keyword("CellGrid"))

    def test_dotted_or_snake_or_call_or_path_is_specific(self) -> None:
        self.assertTrue(tl._is_specific_keyword("MatchConfig.TeamMode"))
        self.assertTrue(tl._is_specific_keyword("cell_overlap"))
        self.assertTrue(tl._is_specific_keyword("team_count()"))
        self.assertTrue(tl._is_specific_keyword("tests/bench/m2_acceptance.gd"))


if __name__ == "__main__":
    unittest.main()
