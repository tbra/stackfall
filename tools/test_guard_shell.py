"""Focused tests for the project shell guard (Bontago-fca.121)."""

import json
import os
import subprocess
import sys
import unittest

import guard_shell as g

OFF = "--windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy"


class GodotLaunchTest(unittest.TestCase):
    def test_headless_and_off_screen_launches_pass(self):
        for command in (
            "godot --headless --editor --path . --quit",
            "godot --headless --path . -- --headless-host --bots=8",
            "godot %s --path . res://tools/shot.tscn -- --agent-probe" % OFF,
            "python tools/godot_slots.py run --exclusive -- godot --headless --path . res://x.tscn",
            "cd M:/wt/a && timeout 600 godot --headless -s tools/x.gd",
            '& "C:/Godot/Godot_v4.7.2-stable_win64_console.exe" --headless --path .',
            "godot --version",
        ):
            self.assertIsNone(g.problem(command), command)

    def test_visible_launches_are_denied(self):
        for command in (
            "godot --path .",
            "godot --path . -- --headless-host --bots=8",
            "cd M:/wt/a; godot --editor --path .",
            "python tools/godot_slots.py run -- godot --path . res://x.tscn",
            '"C:/Godot/Godot_v4.7.2-stable_win64_console.exe" --path . res://main.tscn',
        ):
            self.assertEqual(g.problem(command), g.REASON_WINDOW, command)

    def test_mentions_outside_command_position_pass(self):
        for command in (
            'git commit -m "fix godot --path launch"',
            "tasklist | grep -i godot",
            "python tools/godot_slots.py status",
            "grep -rn godot tools/",
            "./tools/godot_slots.py status",
        ):
            self.assertIsNone(g.problem(command), command)


class KillAndSuiteTest(unittest.TestCase):
    def test_image_name_kills_are_denied(self):
        for command in ("taskkill //F //IM Godot*", "taskkill /f /im godot.exe",
                        "Stop-Process -Name godot", "Get-Process godot | Stop-Process", "pkill godot"):
            self.assertEqual(g.problem(command), g.REASON_KILL, command)
        self.assertIsNone(g.problem("taskkill //F //PID 4242"))

    def test_full_suite_only_denied_for_writer_roles(self):
        suite = "godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit"
        gate = "python tools/full_gate.py --path M:/wt/a"
        for command in (suite, gate):
            self.assertEqual(g.problem(command, "stackfall-implementer"), g.REASON_SUITE)
            self.assertIsNone(g.problem(command, "stackfall-integrator"))
            self.assertIsNone(g.problem(command, "stackfall-orchestrator"))
            self.assertIsNone(g.problem(command))
        self.assertIsNone(g.problem("godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit/net -gexit",
                                    "stackfall-implementer"))
        self.assertIsNone(g.problem("sed -n 1,20p tools/full_gate.py", "stackfall-implementer"))

    def test_heredoc_and_here_string_bodies_are_data(self):
        note = "taskkill //IM Godot*\ngodot --path .\n-gdir=res://tests\npython3 x.py"
        self.assertIsNone(g.problem("python - <<'EOF'\n%s\nEOF" % note, "stackfall-implementer"))
        self.assertIsNone(g.problem("cat > notes.md <<EOF\n%s\nEOF\ngit status" % note))
        self.assertIsNone(g.problem("$t = @'\n%s\n'@" % note))
        self.assertEqual(g.problem("cat > a.txt <<'EOF'\nx\nEOF\ngodot --path ."), g.REASON_WINDOW)
        self.assertEqual(g.problem('python - <<EOF | tee log\nprint(1)\nEOF\ntaskkill //IM godot.exe'),
                         g.REASON_KILL)

    def test_kill_words_in_text_pass(self):
        self.assertIsNone(g.problem('git commit -m "guard: deny taskkill //IM godot"'))

    def test_store_alias_still_denied(self):
        self.assertEqual(g.problem("python3 x.py"), g.guard_store_python.REASON)


class HookIoTest(unittest.TestCase):
    def run_hook(self, event):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "guard_shell.py")
        result = subprocess.run([sys.executable, "-I", "-S", script], input=json.dumps(event),
                                text=True, capture_output=True, check=True)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def test_deny_json_and_pass_through(self):
        denied = self.run_hook({"tool_input": {"command": "godot --path ."}})
        self.assertEqual(denied["hookSpecificOutput"]["permissionDecision"], "deny")
        self.assertIsNone(self.run_hook({"tool_input": {"command": "git status"}}))
        self.assertIsNone(self.run_hook({"tool_input": {"command": "python tools/full_gate.py"},
                                         "agent_type": "stackfall-integrator"}))


if __name__ == "__main__":
    unittest.main()
