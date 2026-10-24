"""Tests for tools/agent_evals.py on a temp Git repo (python only, no Godot game run).

Run: python tools/test_agent_evals.py

Fixture: a repo whose base commit has a tiny `feature` module returning 1, an accepted commit that
returns 2 and adds the hidden unittest module, and a later setup commit that carries a changed
CLAUDE.md, .claude/ and tools/. Worker runs are made through prep_run and scored through
score_run / main, the way the orchestrator drives them.
"""
import datetime
import json
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import agent_evals as ev  # noqa: E402

EVAL = "fix_feature"
LABEL = "abc1234"
BASELINE = "tools/dead_baseline.json"
BEAD = "task-a"
OTHER_BEAD = "task-b"
HIDDEN = "test_hidden.py"
HIDDEN_TEXT = "import unittest\nimport feature\n\n\nclass T(unittest.TestCase):\n" \
              "    def test_value(self):\n        self.assertEqual(feature.value(), 2)\n"
REGRESSION_TEXT = "import unittest\nimport feature\n\n\nclass T(unittest.TestCase):\n" \
                  "    def test_int(self):\n        self.assertIsInstance(feature.value(), int)\n"
GIT_ENV = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t",
           "GIT_COMMITTER_EMAIL": "t@t"}


def write(root, rel, text):
    path = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)


def read(root, rel):
    with open(os.path.join(root, *rel.split("/")), encoding="utf-8") as fh:
        return fh.read()


def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), check=True, capture_output=True,
                          text=True).stdout.strip()


def baseline(*entries):
    return json.dumps({"checks": {"test-only-func": list(entries)}, "allow": []})


def counts(checks):
    """(hidden_pass, hidden_total, regression_pass, regression_total) of a CheckResult-like value."""
    if isinstance(checks, dict):
        return (checks["hidden_pass"], checks["hidden_total"], checks["regression_pass"],
                checks["regression_total"])
    return tuple(checks[:4])


class AgentEvalsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        base = self.tmp.name
        self.repo = os.path.join(base, "repo")
        self.worktrees = os.path.join(base, "worktrees")
        self.tools_root = os.path.join(base, "tools-root")
        saved = {k: os.environ.get(k) for k in list(GIT_ENV) + ["STACKFALL_WORKTREES", "STACKFALL_TOOLS_ROOT"]}
        self.addCleanup(self._restore, saved)
        os.environ.update(GIT_ENV)
        os.environ["STACKFALL_WORKTREES"] = self.worktrees
        os.environ["STACKFALL_TOOLS_ROOT"] = self.tools_root
        os.makedirs(self.repo)
        git(self.repo, "init", "-q")
        write(self.repo, "feature.py", "def value():\n    return 1\n")
        write(self.repo, "test_regression.py", REGRESSION_TEXT)
        write(self.repo, "CLAUDE.md", "rules\n")
        write(self.repo, BASELINE, baseline("a.gd:f"))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "base")
        self.base_rev = git(self.repo, "rev-parse", "HEAD")
        write(self.repo, "feature.py", "def value():\n    return 2\n")
        write(self.repo, HIDDEN, HIDDEN_TEXT)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "accepted")
        self.accepted_rev = git(self.repo, "rev-parse", "HEAD")
        write(self.repo, "CLAUDE.md", "rules\n" + "setup line\n" * 30)
        write(self.repo, ".claude/agents/x.md", "agent\n" * 20)
        write(self.repo, BASELINE, baseline("a.gd:f", "z.gd:z"))
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "setup")
        self.setup_rev = git(self.repo, "rev-parse", "HEAD")
        write(self.repo, "tools/evals/briefs/fix.md", "Make feature.value() return 2.\n")
        self.manifest_path = os.path.join(self.repo, "tools", "evals", "manifest.json")
        self.entry = {"area": "core/ rules", "base": self.base_rev, "accepted": self.accepted_rev,
                      "brief": "briefs/fix.md", "hidden": [HIDDEN], "regression": ["test_regression"],
                      "interface_lines": ["def value() -> int in feature.py"], "runner": "unittest",
                      "lint_floor": None}
        self.write_manifest({EVAL: self.entry})

    def _restore(self, saved):
        for key, value in saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def write_manifest(self, data):
        write(self.repo, "tools/evals/manifest.json", json.dumps(data))
        self.manifest = ev.load_manifest(self.manifest_path, self.repo)

    def prep(self, run):
        return ev.prep_run(self.manifest, EVAL, run, self.setup_rev, self.repo, self.worktrees)

    def score(self, wt, run=1, usage=None, bead=BEAD):
        return ev.score_run(self.manifest, EVAL, run, wt,
                            usage or {"turns": 4, "tokens": 1000, "seconds": 60}, bead)

    def write_handbacks(self, rows):
        log = os.path.join(self.tools_root, "scratch", "_orchestrator", "handbacks.jsonl")
        os.environ.pop("STACKFALL_HANDBACK_LOG", None)
        write(os.path.dirname(os.path.dirname(log)), "_orchestrator/handbacks.jsonl",
              "".join(json.dumps(r) + chr(10) for r in rows))

    def fix(self, wt, extra_line=False):
        write(wt, "feature.py", "def value():\n    return 2\n" + ("# note\n" if extra_line else ""))

    # (a) hidden checks are applied only after the candidate snapshot, scored RED then GREEN
    def test_hidden_file_is_withheld_then_applied_after_the_snapshot(self):
        wt = self.prep(1)
        self.assertFalse(os.path.exists(os.path.join(wt, HIDDEN)))
        self.fix(wt)
        candidate = ev.snapshot_candidate(wt)
        self.assertNotIn(HIDDEN, git(wt, "ls-tree", "-r", "--name-only", candidate).splitlines())
        self.assertEqual(ev.apply_hidden(wt, self.entry), [HIDDEN])
        self.assertEqual(read(wt, HIDDEN), HIDDEN_TEXT)

    def test_unfixed_candidate_scores_red_and_fixed_candidate_scores_green(self):
        red = self.prep(1)
        write(red, "notes.txt", "gave up\n")
        red_record = self.score(red, 1)
        self.assertEqual(counts(red_record["checks"])[:2], (0, 1))
        self.assertEqual(counts(red_record["checks"])[2:], (1, 1))
        green = self.prep(2)
        self.fix(green)
        green_record = self.score(green, 2)
        self.assertEqual(counts(green_record["checks"]), (1, 1, 1, 1))

    def test_run_checks_separates_hidden_from_regression_failures(self):
        wt = self.prep(1)
        write(wt, "feature.py", "def value():\n    return 'two'\n")
        ev.snapshot_candidate(wt)
        ev.apply_hidden(wt, self.entry)
        self.assertEqual(counts(ev.run_checks(wt, self.entry, 120)), (0, 1, 0, 1))

    def test_prep_commits_the_overlay_as_the_eval_base(self):
        wt = self.prep(1)
        subjects = git(wt, "log", "--format=%s").splitlines()
        self.assertEqual(subjects[0], "eval base %s r1" % EVAL)
        self.assertEqual(subjects[1], "base")
        self.assertEqual(git(wt, "status", "--porcelain"), "")

    # (b) the overlay commit is the eval base: its lines never count as the worker's
    def test_lines_count_only_the_worker_diff_not_the_overlay(self):
        wt = self.prep(1)
        self.assertIn("setup line", read(wt, "CLAUDE.md"))
        self.fix(wt, extra_line=True)
        record = self.score(wt)
        self.assertEqual((record["lines_added"], record["lines_removed"]), (2, 1))
        self.assertEqual(record["guard_entries_added"], 0)

    def test_usage_is_copied_into_the_record(self):
        wt = self.prep(1)
        self.fix(wt)
        record = self.score(wt, 1, {"turns": 7, "tokens": 12345, "seconds": 99})
        self.assertEqual((record["turns"], record["tokens"], record["seconds"]), (7, 12345, 99))

    # (c) a guard entry the worker adds is counted
    def test_a_guard_entry_added_by_the_worker_is_counted(self):
        wt = self.prep(1)
        self.fix(wt)
        write(wt, BASELINE, baseline("a.gd:f", "z.gd:z", "new.gd:n"))
        self.assertEqual(self.score(wt)["guard_entries_added"], 1)

    # (d) one bead's handback rows, another bead's rows ignored
    def test_handback_numbers_come_from_this_runs_bead_only(self):
        now = datetime.datetime.now().isoformat(timespec="seconds")
        rows = [{"ts": now, "bead": BEAD, "accepted": False, "verdict": "", "finding": ""},
                {"ts": now, "bead": OTHER_BEAD, "accepted": False, "verdict": "", "finding": ""},
                {"ts": now, "bead": OTHER_BEAD, "accepted": False, "verdict": "", "finding": ""},
                {"ts": now, "bead": BEAD, "accepted": True, "verdict": "done", "finding": ""},
                {"ts": now, "bead": OTHER_BEAD, "accepted": True, "verdict": "partial", "finding": ""}]
        self.write_handbacks(rows)
        wt = self.prep(1)
        self.fix(wt)
        record = self.score(wt, 1, bead=BEAD)
        self.assertEqual((record["handback_attempts"], record["first_try_denials"], record["verdict"]),
                         (2, 1, "done"))
        other = self.score(wt, 1, bead=OTHER_BEAD)
        self.assertEqual((other["handback_attempts"], other["first_try_denials"], other["verdict"]),
                         (3, 2, "partial"))

    # verify: hidden RED on the overlaid base, GREEN on the accepted commit
    def test_verify_accepts_an_eval_whose_hidden_checks_flip(self):
        self.assertTrue(ev.verify_eval(self.manifest, EVAL, self.repo))

    def test_verify_rejects_hidden_checks_that_already_pass_on_the_base(self):
        write(self.repo, "feature.py", "def value():\n    return 2\n")
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-qm", "base that already passes")
        self.entry = dict(self.entry, base=git(self.repo, "rev-parse", "HEAD"))
        self.write_manifest({EVAL: self.entry})
        self.assertFalse(ev.verify_eval(self.manifest, EVAL, self.repo))

    # main(argv): score writes one result file per run, card renders them
    def run_main(self, *args):
        return ev.main(["--manifest", self.manifest_path, "--path", self.repo] + list(args))

    def results_dir(self):
        return os.path.join(self.tools_root, "scratch", "_evals", LABEL)

    def score_via_main(self, run, fixed, tokens, extra_lines):
        wt = self.prep(run)
        if fixed:
            self.fix(wt)
        write(wt, "padding.txt", "x\n" * extra_lines)
        code = self.run_main("score", EVAL, "--run", str(run), "--worktree", wt, "--setup-label", LABEL,
                             "--tokens", str(tokens), "--turns", "3", "--seconds", "30")
        self.assertEqual(code, 0)
        with open(os.path.join(self.results_dir(), "%s-r%d.json" % (EVAL, run)), encoding="utf-8") as fh:
            return json.load(fh)

    def test_main_score_writes_a_result_file_per_run(self):
        record = self.score_via_main(1, True, 1000, 2)
        self.assertEqual(counts(record["checks"]), (1, 1, 1, 1))
        self.assertEqual((record["lines_added"], record["tokens"]), (3, 1000))

    # (e) the card shows each run and the means over both runs
    def test_card_means_cover_both_runs(self):
        self.score_via_main(1, False, 1000, 0)
        self.score_via_main(2, True, 3000, 0)
        card = ev.render_card(self.results_dir(), LABEL)
        self.assertIn(EVAL, card)
        mean_lines = [ln for ln in card.splitlines() if "mean" in ln.lower()]
        self.assertTrue(mean_lines, card)
        self.assertTrue(any("2000" in ln for ln in mean_lines), card)
        self.assertEqual(read(self.results_dir(), "scorecard.md").strip(), card.strip())
        self.assertEqual(sum(1 for ln in card.splitlines() if "mean" in ln.lower()), 2, card)
        self.assertEqual(self.run_main("card", LABEL), 0)


if __name__ == "__main__":
    unittest.main()
