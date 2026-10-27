"""Checks for merge_wave: pure scope/rise/attribution rules and the wave on a throwaway git repo."""

import argparse
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import integrate_batch as ib  # noqa: E402
import merge_wave as mw  # noqa: E402

# Stand-in lint: prints (and fails with) the text of tools/stub_<update|check>_<script>.txt when present.
STUB = '''import os, sys
root = sys.argv[sys.argv.index("--path") + 1]
mode = "update" if any(a.startswith("--update") for a in sys.argv) else "check"
f = os.path.join(root, "tools", "stub_%s_" % mode + os.path.basename(__file__) + ".txt")
if os.path.exists(f):
    print(open(f).read())
    sys.exit(1)
'''


class PureRuleTests(unittest.TestCase):
    def test_conflict_kind(self):
        self.assertEqual(mw.conflict_kind(["tools/magic_number_baseline.json", "tools/dead_baseline.json"]), "baseline")
        self.assertEqual(mw.conflict_kind([]), "other")
        self.assertEqual(mw.conflict_kind(["tools/magic_number_baseline.json", "game/a.gd"]), "other")
        self.assertEqual(mw.conflict_kind(["tools/ui_components_baseline.json"]), "other")

    def test_scope_violations(self):
        files = {"wt/a": {"game/a.gd"}, "wt/b": {"game/b.gd"}}
        self.assertEqual(mw.scope_violations(["game/a.gd", "game/b.gd", "tools/public_baseline.json"], files), [])
        self.assertEqual(mw.scope_violations(["game/c.gd", "game/a.gd"], files), ["game/c.gd"])
        self.assertEqual(mw.scope_violations([], files), [])

    def test_rising_magic(self):
        self.assertEqual(mw.rising("magic", {"a.gd": 3, "b.gd": 2}, {"a.gd": 3, "b.gd": 1}), [])
        self.assertEqual(mw.rising("magic", {"a.gd": 3}, {"a.gd": 4}), ["a.gd"])
        self.assertEqual(mw.rising("magic", {"a.gd": 3}, {"a.gd": 3, "n.gd": 1}), ["n.gd"])
        self.assertEqual(mw.rising("magic", {"a.gd": 3}, {"a.gd": 3, "n.gd": 1}, allow_new=["n.gd"]), [])

    def test_rising_set_baselines_ignore_allow(self):
        old = {"checks": {"dead-file": ["a.gd"]}, "allow": []}
        new = {"checks": {"dead-file": ["a.gd", "b.gd"]}, "allow": [{"id": "x", "entry": "y", "reason": "z"}]}
        self.assertEqual(mw.rising("dead", old, new), ["dead-file:b.gd"])
        self.assertEqual(mw.rising("shader", new, old), [])

    def test_rising_layers(self):
        old = {"largest_scc": 4, "closure": ["a.gd"], "l1_exceptions": [], "autoload_scc_pairs": [["x.gd"]]}
        new = {"largest_scc": 5, "closure": ["a.gd", "n.gd"], "l1_exceptions": [], "autoload_scc_pairs": [["x.gd"]]}
        self.assertEqual(mw.rising("layers", old, new), ["closure:n.gd", "largest_scc"])
        self.assertEqual(mw.rising("layers", old, new, allow_new=["n.gd"]), [])
        self.assertEqual(mw.rising("layers", new, old), [])

    def test_rising_layers_scc_shrink_is_not_a_rise(self):
        old = {"autoload_scc_pairs": [["a/Match.gd"], ["a/Net.gd", "n/Sync.gd"]]}
        shrunk = {"autoload_scc_pairs": [["a/Match.gd"], ["a/Net.gd"]]}
        self.assertEqual(mw.rising("layers", old, shrunk), [])
        grown = {"autoload_scc_pairs": [["a/Match.gd", "a/Net.gd"]]}
        self.assertEqual(mw.rising("layers", old, grown), ["autoload_scc_pairs:a/Match.gd a/Net.gd"])

    def test_branch_added_files_only_new_file_entries(self):
        old = {"largest_scc": 1, "closure": ["a.gd"], "main_closure": [], "l1_exceptions": ["s.gd -> d.gd"],
               "autoload_scc_pairs": [["x.gd"]]}
        new = {"largest_scc": 2, "closure": ["a.gd", "n.gd"], "main_closure": ["m.gd"],
               "l1_exceptions": ["s.gd -> d.gd", "t.gd -> d.gd"], "autoload_scc_pairs": [["x.gd", "y.gd"]]}
        self.assertEqual(mw.branch_added_files(old, new), ["m.gd", "n.gd", "t.gd"])
        self.assertEqual(mw.branch_added_files(new, old), [])
        self.assertEqual(mw.branch_added_files({}, {}), [])

    def test_attribution(self):
        files = {"wt/a": {"game/a.gd"}, "wt/b": {"autoload/Net.gd", "game/b.gd"}}
        self.assertEqual(mw.attribute("test-only-func:autoload/Net.gd:report_stats", files), "wt/b")
        self.assertEqual(mw.attribute("game/a.gd:12: dead-file: x", files), "wt/a")
        self.assertIsNone(mw.attribute("game/other.gd: 3 literals", files))
        self.assertIn("unattributed: game/other.gd", mw.blame(["game/other.gd: 3 literals"], files))


class AllowUnionTests(unittest.TestCase):
    def test_union_and_differing_reason(self):
        a = {"checks": {"dead-file": ["x.gd"]}, "allow": [{"id": "dead-file", "entry": "a.gd", "reason": "ra"}]}
        b = {"checks": {}, "allow": [{"id": "dead-file", "entry": "b.gd", "reason": "rb"},
                                     {"id": "dead-file", "entry": "a.gd", "reason": "ra"}]}
        text, reason = mw.merge_allow(json.dumps(a), json.dumps(b))
        self.assertIsNone(reason)
        merged = json.loads(text)
        self.assertEqual([e["entry"] for e in merged["allow"]], ["a.gd", "b.gd"])
        self.assertEqual(merged["checks"], a["checks"])
        b["allow"][1]["reason"] = "other"
        text, reason = mw.merge_allow(json.dumps(a), json.dumps(b))
        self.assertIsNone(text)
        self.assertIn("a.gd", reason)


def sh(cwd, *args):
    return subprocess.run(["git", "-C", str(cwd), "-c", "user.name=t", "-c", "user.email=t@t", *args],
                          check=True, capture_output=True, text=True).stdout.strip()


def commit(repo, files, msg):
    for rel, text in files.items():
        p = Path(repo, rel)
        p.parent.mkdir(parents=True, exist_ok=True)
        with open(str(p), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(text)
    sh(repo, "add", "-A")
    sh(repo, "commit", "-m", msg)


def magic(**counts):
    return json.dumps(counts, indent=1, sort_keys=True) + "\n"


class WaveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.repo, self.wt_root = root / "repo", root / "worktrees"
        self.repo.mkdir()
        sh(self.repo, "init", "-b", "main")
        files = {"tools/" + v[0]: STUB for v in mw.LOWERING.values()}
        files["tools/magic_number_baseline.json"] = magic(**{"game/a.gd": 3, "game/b.gd": 3, "game/c.gd": 3})
        files["tools/dead_baseline.json"] = json.dumps({"checks": {"dead-file": []}, "allow": []})
        files["tools/layer_baseline.json"] = json.dumps({"largest_scc": 1, "closure": []})
        files["tools/shader_uniform_baseline.json"] = json.dumps({"checks": {}, "allow": []})
        files.update({"game/a.gd": "a\n", "game/b.gd": "b\n"})
        commit(self.repo, files, "base")

    def branch(self, name, files):
        sh(self.repo, "checkout", "-b", name, "main")
        commit(self.repo, files, name)
        sh(self.repo, "checkout", "main")

    def run_wave(self, branches, allow_new=()):
        args = argparse.Namespace(repo=str(self.repo), base="main", branches=branches, branch_name="wt/wave-test",
                                  allow_new_files=list(allow_new), worktree_root=str(self.wt_root))
        res = {}
        try:
            mw.wave(args, ib.Ctx(self.tmp.name), lambda line: None, res)
        except ib.StepFailed as e:
            return str(e), res
        return None, res

    def drop_wave(self, res):
        sh(self.repo, "worktree", "remove", "--force", res["worktree"])
        sh(self.repo, "branch", "-D", res["branch"])

    def test_baseline_only_conflict_is_resolved_and_committed(self):
        self.branch("wt/a", {"game/a.gd": "a2\n", "tools/magic_number_baseline.json": magic(**{"game/a.gd": 2, "game/b.gd": 3, "game/c.gd": 3})})
        self.branch("wt/b", {"game/b.gd": "b2\n", "tools/magic_number_baseline.json": magic(**{"game/a.gd": 3, "game/b.gd": 2, "game/c.gd": 3})})
        err, res = self.run_wave(["wt/a", "wt/b"])
        self.assertIsNone(err)
        self.assertEqual(sh(self.repo, "rev-parse", "wt/wave-test"), res["sha"])
        self.assertEqual(sh(self.repo, "show", "wt/wave-test:game/b.gd"), "b2")
        self.assertEqual(sh(self.repo, "show", "wt/wave-test:game/a.gd"), "a2")

    def allow_baseline(self, *entries):
        allow = [{"id": "dead-file", "entry": e, "reason": r} for e, r in entries]
        return json.dumps({"checks": {"dead-file": []}, "allow": allow}, indent=1) + "\n"

    def test_allow_entries_of_both_branches_survive(self):
        self.branch("wt/a", {"game/a.gd": "a2\n", "tools/dead_baseline.json": self.allow_baseline(("game/a.gd", "forwarder, removed by package a"))})
        self.branch("wt/b", {"game/b.gd": "b2\n", "tools/dead_baseline.json": self.allow_baseline(("game/b.gd", "forwarder, removed by package b"))})
        err, _ = self.run_wave(["wt/a", "wt/b"])
        self.assertIsNone(err)
        allow = json.loads(sh(self.repo, "show", "wt/wave-test:tools/dead_baseline.json"))["allow"]
        self.assertEqual([e["entry"] for e in allow], ["game/a.gd", "game/b.gd"])

    def test_same_allow_key_with_different_reasons_fails(self):
        self.branch("wt/a", {"game/a.gd": "a2\n", "tools/dead_baseline.json": self.allow_baseline(("game/x.gd", "reason a"))})
        self.branch("wt/b", {"game/b.gd": "b2\n", "tools/dead_baseline.json": self.allow_baseline(("game/x.gd", "reason b"))})
        err, _ = self.run_wave(["wt/a", "wt/b"])
        self.assertIn("baseline resolve refused", err)
        self.assertIn("reason a", err)
        self.assertIn("reason b", err)

    def test_other_conflict_stops_and_names_files(self):
        self.branch("wt/a", {"game/a.gd": "a2\n"})
        self.branch("wt/b", {"game/a.gd": "a3\n"})
        err, res = self.run_wave(["wt/a", "wt/b"])
        self.assertIn("merge: conflict merging wt/b: game/a.gd", err)
        self.assertEqual(sh(res["worktree"], "status", "--porcelain"), "")

    def test_refusal_names_the_introducing_branch(self):
        self.branch("wt/a", {"game/a.gd": "a2\n"})
        self.branch("wt/b", {"game/b.gd": "b2\n",
                             "tools/stub_update_lint_dead.py.txt": "not baselined (fix it): dead-file game/b.gd\n"})
        err, _ = self.run_wave(["wt/a", "wt/b"])
        self.assertIn("dead update refused: wt/b:", err)

    def test_rise_names_the_branch_and_allow_new_exempts_it(self):
        raised = magic(**{"game/a.gd": 3, "game/b.gd": 3, "game/c.gd": 3, "game/n.gd": 1})
        self.branch("wt/a", {"game/a.gd": "a2\n"})
        self.branch("wt/b", {"game/n.gd": "n\n", "tools/magic_number_baseline.json": raised})
        err, res = self.run_wave(["wt/a", "wt/b"])
        self.assertIn("magic baseline rose above", err)
        self.assertIn("wt/b: game/n.gd", err)
        self.drop_wave(res)
        err, _ = self.run_wave(["wt/a", "wt/b"], allow_new=["game/n.gd"])
        self.assertIsNone(err)

    def test_branch_own_layer_entry_is_auto_allowed_but_foreign_one_is_not(self):
        def layers(*closure):
            return json.dumps({"largest_scc": 1, "closure": list(closure)})
        self.branch("wt/a", {"game/a.gd": "a2\n", "tools/layer_baseline.json": layers("game/n.gd")})
        self.branch("wt/b", {"game/b.gd": "b2\n"})
        lines = []
        args = argparse.Namespace(repo=str(self.repo), base="main", branches=["wt/a", "wt/b"], branch_name="wt/wave-test",
                                  allow_new_files=[], worktree_root=str(self.wt_root))
        mw.wave(args, ib.Ctx(self.tmp.name), lines.append, {})
        self.assertIn("allow-new game/n.gd (added by wt/a)", lines)
        # an entry no branch's own diff added (smuggled into the merge) still rises
        self.assertEqual(mw.branch_allowed(ib.Ctx(self.tmp.name), str(self.repo), "main", ["wt/b"], lines.append), {})
        self.assertEqual(mw.rising("layers", {"closure": []}, {"closure": ["game/n.gd"]}), ["closure:game/n.gd"])

    def test_lint_still_red_after_update_is_attributed(self):
        self.branch("wt/a", {"game/a.gd": "a2\n"})
        self.branch("wt/b", {"game/b.gd": "b2\n", "tools/stub_check_lint_magic_numbers.py.txt": "MAGIC LINT FAIL game/b.gd: 4 literals\n"})
        err, _ = self.run_wave(["wt/a", "wt/b"])
        self.assertIn("magic still red after update: wt/b:", err)


if __name__ == "__main__":
    unittest.main()
