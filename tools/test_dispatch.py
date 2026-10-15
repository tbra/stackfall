"""Focused tests for the dispatch guard and dispatch_prep (Bontago-fca.122)."""

import argparse
import json
import os
import shutil
import tempfile
import unittest

import dispatch_prep
import guard_dispatch

BRIEF = "Bontago-123: fix overlap scoring in M:/Bontago-worktrees/a (base abc123)."


class GuardDispatchTest(unittest.TestCase):
    def test_complete_worker_dispatch_passes(self):
        self.assertIsNone(guard_dispatch.problem(
            {"subagent_type": "stackfall-implementer", "model": "sonnet", "prompt": BRIEF}))

    def test_missing_model_bead_or_checkout_is_denied(self):
        reason = guard_dispatch.problem({"subagent_type": "stackfall-reviewer", "prompt": "review it"})
        for part in ("explicit `model`", "Bead id", "checkout path"):
            self.assertIn(part, reason)
        self.assertIn("checkout path", guard_dispatch.problem(
            {"subagent_type": "stackfall-triage", "model": "haiku", "prompt": "Bontago-9 grep logs"}))

    def test_other_agents_pass(self):
        self.assertIsNone(guard_dispatch.problem({"subagent_type": "Explore", "prompt": "find x"}))
        self.assertIsNone(guard_dispatch.problem({"prompt": "no type"}))


class DispatchPrepTest(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.mkdtemp()
        self.calls = []

    def tearDown(self):
        shutil.rmtree(self.scratch)

    def runner(self, claim_code=0, verdict=None):
        verdict = verdict or {"model": "sonnet", "needs_review": True, "split_first": False,
                              "verification_tier": "targeted", "source": "jev"}

        def run(cmd, stdin_text=None):
            self.calls.append(cmd)
            joined = " ".join(cmd)
            if "scratch.py" in joined:
                return 0, self.scratch + "\n", ""
            if "route_model.py" in joined:
                return 0, json.dumps(verdict), ""
            if " update " in " %s " % joined:
                return claim_code, "", "refused: status is in_progress" if claim_code else ""
            return 0, "", ""
        return run

    def args(self, **extra):
        base = dict(bead="Bontago-123", role="stackfall-implementer", title="Fix X", files="core/a.gd",
                    kind="bugfix", prior_attempts=0, model="", reason="", redispatch=False)
        base.update(extra)
        return argparse.Namespace(**base)

    def test_routes_claims_and_comments(self):
        code, line = dispatch_prep.prepare(self.args(), BRIEF, self.runner())
        self.assertEqual(code, 0)
        self.assertIn("model=sonnet review=yes", line)
        claim = next(c for c in self.calls if "update" in c)
        self.assertIn("--if-status=open", claim)
        self.assertIn("stackfall-implementer (sonnet)", claim)
        comment = next(c for c in self.calls if "comments" in c)[-1]
        self.assertIn("Dispatch: stackfall-implementer (sonnet)", comment)
        brief_files = [f for f in os.listdir(self.scratch) if f.startswith("brief-")]
        self.assertEqual(len(brief_files), 1)

    def test_override_is_logged_with_its_reason(self):
        code, line = dispatch_prep.prepare(self.args(model="opus", reason="cross-system invariant"), BRIEF,
                                           self.runner())
        self.assertEqual(code, 0)
        self.assertIn("model=opus", line)
        comment = next(c for c in self.calls if "comments" in c)[-1]
        self.assertIn("override from sonnet: cross-system invariant", comment)

    def test_refused_claim_stops_before_the_comment(self):
        code, line = dispatch_prep.prepare(self.args(), BRIEF, self.runner(claim_code=1))
        self.assertEqual(code, 1)
        self.assertIn("FAILED claim", line)
        self.assertFalse(any("comments" in c for c in self.calls))

    def test_redispatch_only_reassigns(self):
        dispatch_prep.prepare(self.args(redispatch=True), BRIEF, self.runner())
        claim = next(c for c in self.calls if "update" in c)
        self.assertNotIn("--if-status=open", claim)


if __name__ == "__main__":
    unittest.main()
