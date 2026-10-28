"""Focused tests for the dispatch guard and dispatch_prep."""

import argparse
import json
import os
import shutil
import tempfile
import unittest

import dispatch_prep
import guard_dispatch

BRIEF = "Bontago-123: fix overlap scoring in /repo-worktrees/a (base abc123)."


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
        self.assertIn("--force", claim)

    def test_composed_brief_fills_the_bead_checkout_and_notes(self):
        package = os.path.join(self.scratch, "P1.md")
        with open(package, "w", encoding="utf-8") as handle:
            handle.write("Bead: new - P1 (program X). Role: stackfall-tester.\nOwned: tests/a.gd.\n")

        def git(cmd, stdin_text=None):
            joined = " ".join(cmd)
            if "--abbrev-ref" in joined:
                return 0, "wt/p1\n", ""
            if "--short" in joined:
                return 0, "abc1234\n", ""
            if "--grep" in joined:
                return 0, "def5678 Earlier work (Bontago-123)\n", ""
            return 1, "", ""
        brief = dispatch_prep.compose_brief(self.args(package=package, checkout="work\\wt\\p1",
                                                      note=["Pair: P1t in work/wt/p1t."]), git)
        self.assertTrue(brief.startswith("Bead: Bontago-123 - P1 (program X)"))
        self.assertIn("Owned: tests/a.gd.", brief)
        self.assertIn("Checkout: work/wt/p1, branch wt/p1, base abc1234.", brief)
        self.assertIn("Prior commits for this bead on main: def5678 Earlier work (Bontago-123).", brief)
        self.assertIn("python tools/scratch.py path Bontago-123", brief)
        self.assertTrue(brief.endswith("- Pair: P1t in work/wt/p1t.\n"))

    def test_rpc_surface_files_get_the_contract_note_once(self):
        no_git = lambda cmd, stdin_text=None: (1, "", "")
        text = "Bead: Bontago-123 (fix).\n"
        for files in ("autoload/Net.gd,core/a.gd", "core/a.gd, net/Lobby.gd", "core/net/Wire.gd"):
            brief = dispatch_prep.compose_brief(self.args(files=files, checkout="wt", note=[]), no_git, text=text)
            self.assertEqual(brief.count("is on the RPC surface"), 1, files)
        brief = dispatch_prep.compose_brief(self.args(files="core/a.gd,ui/net_panel.gd", checkout="wt", note=[]), no_git, text=text)
        self.assertNotIn("is on the RPC surface", brief)

    def test_package_without_a_placeholder_keeps_its_first_line(self):
        package = os.path.join(self.scratch, "P2.md")
        with open(package, "w", encoding="utf-8") as handle:
            handle.write("# Package P2\nObjective: x\n")
        brief = dispatch_prep.compose_brief(self.args(package=package, checkout="work/wt/p2", note=[]),
                                            lambda cmd, stdin_text=None: (1, "", ""))
        self.assertTrue(brief.startswith("# Package P2\n"))
        self.assertIn("branch ?, base ?.", brief)
        self.assertIn("Prior commits for this bead on main: none.", brief)

    def test_hand_written_brief_also_gets_the_dispatch_block(self):
        brief = dispatch_prep.compose_brief(self.args(package="", checkout="work/wt/p3", note=["Extra."]),
                                            lambda cmd, stdin_text=None: (1, "", ""),
                                            text="Bead: Bontago-123 (fix).\nOwned: a.gd.\n")
        self.assertTrue(brief.startswith("Bead: Bontago-123 (fix).\nOwned: a.gd.\n"))
        self.assertIn("Checkout: work/wt/p3, branch ?, base ?.", brief)
        self.assertTrue(brief.endswith("- Extra.\n"))


if __name__ == "__main__":
    unittest.main()
