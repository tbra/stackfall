"""Focused tests for the project Claude worker handback hooks."""

import json
import subprocess
import sys
import unittest
from pathlib import Path


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
                              "candidate": "M:/wt/a@abc123", "files": "core/rules.gd;tests/test_rules.gd",
                              "checks": "test_rules: 12/12 pass", "finding": "Fixed overlap scoring; no known risk",
                              "next": "integrate candidate", "record": "bd:Bontago-123"})
        self.assertIsNone(run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        }))

    def test_prose_is_denied_before_handback(self):
        result = run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": "A long informal report"},
        })
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_comment_failure_keeps_longer_escape_hatch(self):
        message = json.dumps({"bead": "Bontago-123", "verdict": "blocked",
                              "candidate": "M:/wt/a@uncommitted", "files": "core/rules.gd",
                              "checks": "test_rules: blocked by import error",
                              "finding": "x" * 1500, "next": "orchestrator persist finding",
                              "record": "comment-failed:database locked"})
        self.assertIsNone(run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        }))

    def test_pointer_only_and_wrong_record_are_denied(self):
        base = {"bead": "Bontago-123", "verdict": "done", "candidate": "M:/wt/a@abc123",
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
                              "candidate": "M:/wt/a@abc123", "files": "core/rules.gd",
                              "checks": "test_rules: 12/12 pass", "finding": "x" * 1100,
                              "next": "integrate", "record": "bd:Bontago-123"})
        result = run_hook("validate_worker_handback.py", {
            "hook_event_name": "PreToolUse", "tool_name": "SubagentHandback",
            "tool_input": {"message": message},
        })
        self.assertEqual(result["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_plain_stop_blocks_once(self):
        event = {"hook_event_name": "SubagentStop", "last_assistant_message": "verbose report"}
        self.assertEqual(run_hook("validate_worker_handback.py", event)["decision"], "block")
        event["stop_hook_active"] = True
        self.assertIsNone(run_hook("validate_worker_handback.py", event))

    def test_reviewer_shell_only_allows_comment(self):
        allowed = {"tool_input": {"command": 'bd -C M:/Bontago comments add Bontago-123 --actor stackfall-reviewer "HIGH src/file.gd:5 missing guard"'}}
        self.assertIsNone(run_hook("guard_reviewer_bash.py", allowed))
        for command in ("git status", 'bd -C M:/Bontago close Bontago-123 --actor stackfall-reviewer', 'bd -C M:/Bontago comments add Bontago-123 --actor stackfall-reviewer "ok"; git push'):
            self.assertEqual(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}})["hookSpecificOutput"]["permissionDecision"], "deny")

    def test_reviewer_shell_allows_read_only_bd_and_git(self):
        for command in (
            'bd -C M:/Bontago show Bontago-1pi.11 --json --brief-deps',
            'bd -C M:/Bontago comments Bontago-sen.9 --json',
            'bd -C M:/Bontago children Bontago-59o',
            'git -C M:/Bontago-worktrees/x log --oneline -20',
            'git -C M:/Bontago show --stat abc123',
            'git -C M:/Bontago diff a1b2c3..HEAD -- game/Field.gd',
            'bd -C M:/Bontago comments add Bontago-1 --actor stackfall-reviewer "HIGH a.gd:3 x<y; a|b & c"',
        ):
            self.assertIsNone(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}}), command)
        for command in (
            'git -C M:/Bontago diff --output=M:/Bontago/x.txt',
            'git -C M:/Bontago log | head',
            'git -C M:/Bontago diff > out.txt',
            'git -C M:/Bontago commit -m x',
            'git -C M:/Bontago diff --ext-diff',
            'bd -C M:/Bontago update Bontago-1 --status closed',
            'bd -C M:/Bontago show Bontago-1 && rm -rf x',
            'bd -C M:/Bontago comments add Bontago-1 --actor stackfall-reviewer "$(whoami)"',
        ):
            self.assertEqual(run_hook("guard_reviewer_bash.py", {"tool_input": {"command": command}})["hookSpecificOutput"]["permissionDecision"], "deny", command)


if __name__ == "__main__":
    unittest.main()
