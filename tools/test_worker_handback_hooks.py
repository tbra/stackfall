"""Focused tests for the project Claude worker handback hooks."""

import json
import subprocess
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import repo_paths  # noqa: E402

R = repo_paths.repo_dir()
W = repo_paths.worktrees_root()


ROOT = Path(__file__).resolve().parent


def run_hook(script, event):
    result = subprocess.run(
        [sys.executable, str(ROOT / script)],
        input=json.dumps(event), text=True, capture_output=True, check=True,
    )
    return json.loads(result.stdout) if result.stdout.strip() else None


class HandbackTests(unittest.TestCase):
    def test_self_contained_handback_passes(self):
        message = json.dumps({"bead": "Bontago-123", "verdict": "done",
                              "candidate": "/work/wt/a@abc123", "files": "core/rules.gd;tests/test_rules.gd",
                              "checks": "test_rules: 12/12 pass", "finding": "Fixed overlap scoring; no known risk",
                              "next": "integrate candidate", "record": "bd:Bontago-123"})
        self.assertIsNone(run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        }))

    def test_list_fields_aliases_and_fence_pass(self):
        # the shapes most first handbacks used (lists, synonym keys, a fence).
        report = {"bead": "Bontago-123", "verdict": "review", "candidate": "/work/wt/a@abc123",
                  "files": ["core/rules.gd", "tests/test_rules.gd"],
                  "checks": {"test_rules": "12/12 pass", "import": True},
                  "findings": ["APPROVE: no blocking issue"], "next_action": "integrate",
                  "record": "bd:Bontago-123"}
        for message in (json.dumps(report), "```json\n%s\n```" % json.dumps(report)):
            self.assertIsNone(run_hook("validate_worker_handback.py", {
                "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
                "tool_input": {"message": message},
            }))

    def test_empty_or_unmatched_structured_fields_are_denied(self):
        base = {"bead": "Bontago-123", "verdict": "done", "candidate": "/work/wt/a@abc123",
                "files": "core/rules.gd", "checks": "test_rules: 12/12 pass",
                "finding": "Fixed overlap scoring", "next": "integrate", "record": "bd:Bontago-123"}
        for report in (dict(base, files=[]), dict(base, checks={"lint": ""}),
                       dict(base, bead=["Bontago-123"]), dict(base, verdict="pass")):
            result = run_hook("validate_worker_handback.py", {
                "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
                "tool_input": {"message": json.dumps(report)},
            })
            self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_prose_is_denied_before_handback(self):
        result = run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": "A long informal report"},
        })
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_comment_failure_keeps_longer_escape_hatch(self):
        message = json.dumps({"bead": "Bontago-123", "verdict": "blocked",
                              "candidate": "/work/wt/a@uncommitted", "files": "core/rules.gd",
                              "checks": "test_rules: blocked by import error",
                              "finding": "x" * 1500, "next": "orchestrator persist finding",
                              "record": "comment-failed:database locked"})
        self.assertIsNone(run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        }))

    def test_pointer_only_and_wrong_record_are_denied(self):
        base = {"bead": "Bontago-123", "verdict": "done", "candidate": "/work/wt/a@abc123",
                "files": "core/rules.gd", "checks": "test_rules: 12/12 pass",
                "finding": "Fixed overlap scoring", "next": "integrate", "record": "bd:Bontago-123"}
        for report in ({key: value for key, value in base.items() if key != "candidate"},
                       dict(base, record="bd:Bontago-other"),
                       dict(base, record="comment-failed:")):
            result = run_hook("validate_worker_handback.py", {
                "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
                "tool_input": {"message": json.dumps(report)},
            })
            self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_oversized_success_is_denied(self):
        message = json.dumps({"bead": "Bontago-123", "verdict": "done",
                              "candidate": "/work/wt/a@abc123", "files": "core/rules.gd",
                              "checks": "test_rules: 12/12 pass", "finding": "x" * 1800,
                              "next": "integrate", "record": "bd:Bontago-123"})
        result = run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        })
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def _denied(self, report):
        result = run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": json.dumps(report)},
        })
        return result is not None and result["hookSpecificOutput"]["permissionDecision"] == "deny"

    def _base(self, **over):
        base = {"bead": "Bontago-123", "verdict": "done", "candidate": "/work/wt/a@abc123",
                "files": "core/rules.gd", "checks": "test_rules: 12/12 pass",
                "finding": "Fixed overlap scoring", "next": "integrate", "record": "bd:Bontago-123"}
        base.update(over)
        return base

    def test_multi_bead_shapes_pass(self):
        for bead, record in (("Bontago-epic.30,Bontago-epic.34,Bontago-epic.31", "bd:Bontago-epic.34"),
                             ("Bontago-epic.39+Bontago-epic.37", "bd:Bontago-epic.39,bd:Bontago-epic.37"),
                             ("Bontago-epic.38 + Bontago-epic.29", "bd:Bontago-epic.38;bd:Bontago-epic.29"),
                             ("Bontago-epic.60-64", "bd:Bontago-epic.60"),
                             ("Bontago-epic.43", "bd:Bontago-epic.43 and bd:Bontago-epic.28"),
                             ("Bontago-epic.27", "bd:Bontago-epic.27 (also commented on epic.36)")):
            self.assertFalse(self._denied(self._base(bead=bead, record=record)), bead)

    def test_multi_bead_record_must_still_point_at_an_assigned_bead(self):
        self.assertTrue(self._denied(self._base(bead="Bontago-1,Bontago-2", record="bd:Bontago-3")))
        self.assertTrue(self._denied(self._base(record="bd:Bontago-123 and a long story " + "y" * 200)))

    def test_raised_caps_accept_mid_size_reports(self):
        self.assertFalse(self._denied(self._base(finding="x" * 1500)))
        self.assertFalse(self._denied(self._base(verdict="partial", finding="x" * 2000)))
        self.assertTrue(self._denied(self._base(verdict="partial", finding="x" * 2400)))

    def test_plain_stop_blocks_once(self):
        event = {"hook_event_name": "SubagentStop", "last_assistant_message": "verbose report"}
        self.assertEqual(run_hook("validate_worker_handback.py", event)["decision"], "block")
        event["stop_hook_active"] = True
        self.assertIsNone(run_hook("validate_worker_handback.py", event))

    def test_reviewer_shell_only_allows_comment(self):
        allowed = {"tool_input": {"command": f'bd -C {R} comments add Bontago-123 --actor stackfall-reviewer "HIGH src/file.gd:5 missing guard"'}}
        self.assertIsNone(run_hook("guard_reviewer_bash.py", allowed))
        for command in ("git status", f'bd -C {R} close Bontago-123 --actor stackfall-reviewer', f'bd -C {R} comments add Bontago-123 --actor stackfall-reviewer "ok"; git push'):
            self.assertEqual(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}})["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_reviewer_shell_allows_read_only_bd_and_git(self):
        for command in (
            f'bd -C {R} show Bontago-123.1 --json --brief-deps',
            f'bd -C {R} comments Bontago-123.2 --json',
            f'bd -C {R} children Bontago-123',
            f'git -C {W}/x log --oneline -20',
            f'git -C {R} show --stat abc123',
            f'git -C {R} diff a1b2c3..HEAD -- game/field/Field.gd',
            f'bd -C {R} comments add Bontago-1 --actor stackfall-reviewer "HIGH a.gd:3 x<y; a|b & c"',
        ):
            self.assertIsNone(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}}), command)
        for command in (
            f'git -C {R} diff --output={R}/x.txt',
            f'git -C {R} log | head',
            f'git -C {R} diff > out.txt',
            f'git -C {R} commit -m x',
            f'git -C {R} diff --ext-diff',
            f'bd -C {R} update Bontago-1 --status closed',
            f'bd -C {R} show Bontago-1 && rm -rf x',
            f'bd -C {R} comments add Bontago-1 --actor stackfall-reviewer "$(whoami)"',
        ):
            self.assertEqual(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}})["hookSpecificOutput"]["permissionDecision"], "deny", command)


if __name__ == "__main__":
    unittest.main()
