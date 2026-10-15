"""Focused tests for the instruction drift guard."""

import os
import shutil
import tempfile
import unittest

import lint_instructions


class LintInstructionsTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def tearDown(self):
        shutil.rmtree(self.root)

    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path) or self.root, exist_ok=True)
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(text)

    def rules(self):
        return [(rule, rel) for rule, rel, _line, _homes in lint_instructions.find_violations(self.root)]

    def test_marker_in_its_home_passes(self):
        self.write("CLAUDE.md", "pass `--windowed --position 10000,10000` always\n")
        self.write(".claude/skills/stackfall-worker/SKILL.md", "Limits: 1100 characters\n")
        self.assertEqual(self.rules(), [])

    def test_restated_marker_outside_its_home_fails(self):
        self.write("CLAUDE.md", "--position 10000,10000\n")
        self.write(".claude/agents/stackfall-implementer.md", "x\n--position 10000,10000\n")
        self.write(".claude/skills/stackfall-auto-run/SKILL.md", "fit 1100 characters\n")
        self.assertEqual(sorted(self.rules()), [
            ("handback limits", ".claude/skills/stackfall-auto-run/SKILL.md"),
            ("off-screen window flags", ".claude/agents/stackfall-implementer.md"),
        ])
        found = lint_instructions.find_violations(self.root)
        self.assertIn(2, [line for _rule, rel, line, _homes in found if rel.endswith("implementer.md")])

    def test_a_rule_may_have_several_homes(self):
        for name in ("stackfall-session-resume", "stackfall-auto-run", "stackfall-session-close"):
            self.write(".claude/skills/%s/SKILL.md" % name, "python tools/skill_versions.py --check\n")
        self.write(".claude/agents/stackfall-orchestrator.md", "run skill_versions.py at start\n")
        self.assertEqual(self.rules(), [("skill version check", ".claude/agents/stackfall-orchestrator.md")])

    def test_only_instruction_files_are_scanned(self):
        self.write("README.md", "--position 10000,10000\n")
        self.write("docs/NOTES.md", "1100 characters\n")
        self.assertEqual(self.rules(), [])
        self.assertEqual(lint_instructions.main(["--path", self.root]), 0)


    def test_post_edit_hook_reports_only_restatements_in_the_edited_file(self):
        import hook_lint_instructions as hook
        self.write("CLAUDE.md", "--position 10000,10000\n")
        self.write(".claude/agents/stackfall-implementer.md", "--position 10000,10000\n")
        self.write(".claude/skills/stackfall-auto-run/SKILL.md", "fit 1100 characters\n")
        found = hook.findings_for(os.path.join(self.root, ".claude", "agents", "stackfall-implementer.md"))
        self.assertEqual([rule for rule, _line, _homes in found], ["off-screen window flags"])
        self.assertEqual(hook.findings_for(os.path.join(self.root, "CLAUDE.md")), [])
        self.write("tools/notes.py", "--position 10000,10000\n")
        self.assertEqual(hook.findings_for(os.path.join(self.root, "tools", "notes.py")), [])


if __name__ == "__main__":
    unittest.main()
