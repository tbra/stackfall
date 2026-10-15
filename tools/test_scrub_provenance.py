"""Tests for tools/scrub_provenance.py and the shared rules in tools/public_rules.py."""
import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import public_rules as pr  # noqa: E402
import scrub_provenance as sp  # noqa: E402


def scrub(path, text):
    new, changes, residuals = sp.scrub_text(path, text)
    return new, residuals


class RulesTest(unittest.TestCase):
    def issues(self, path, text):
        return [(rid, m) for _, rid, m in pr.find_issues(path, text)]

    def test_bead_ids_and_placeholders(self):
        self.assertEqual(self.issues("a.md", "see Bontago-1pi.209 and Bontago-uwq")[0][0], "bead-id")  # lint-public: allow fixture
        self.assertEqual(self.issues("a.md", "Bontago-123 Bontago-<id> Bontago-ID Bontago-tools"), [])

    def test_dates_functional_exceptions(self):
        self.assertEqual(self.issues("a.md", "on 2026-10-15 we")[0][0], "date")  # lint-public: allow fixture
        self.assertEqual(self.issues("a.md", "(expires 2026-10-15)"), [])
        self.assertEqual(self.issues("a.md", "at 2026-10-15T20:00:00Z"), [])

    def test_drive_paths_and_names(self):
        self.assertEqual(self.issues("a.md", "see M:/x/y")[0][0], "drive-path")  # lint-public: allow fixture
        self.assertEqual(self.issues("a.md", "see C:" + chr(92) + "Users")[0][0], "drive-path")
        self.assertEqual(self.issues("a.gd", 'load("res://a.gd")'), [])
        self.assertEqual(self.issues("a.py", 'x = "match s:' + chr(92) + 'n"'), [])
        self.assertEqual(self.issues("a.md", "ask Tony")[0][0], "user-name")  # lint-public: allow fixture

    def test_owner_technical_sense_stays(self):
        for ok in ("the slot owner holds it", "an exclusive owner pid", "each concept has ONE owner",
                   "file owner API", "owner PID is dead"):
            self.assertEqual(self.issues("a.md", ok), [], ok)
        self.assertEqual(self.issues("a.md", "the owner's monitor")[0][0], "owner")

    def test_code_scope_is_prose_only(self):
        text = "owner = 1  # the owner decided\nbead = 'Bontago-abc'\n"  # lint-public: allow fixture
        got = self.issues("a.py", text)
        self.assertEqual([r for r, _ in got], ["owner", "bead-id"])
        self.assertEqual(self.issues("a.py", "owner = 1\nowner[3] = 2\n"), [])
        self.assertEqual(self.issues("a.gd", 'var s := "owner"  # fine\n'), [])
        self.assertEqual([r for r, _ in self.issues("a.gd", 'var s := "# not a comment"\n# owner said\n')], ["owner"])

    def test_python_docstring_is_prose_but_string_literal_is_not(self):
        text = 'def f():\n    """The owner wanted it."""\n    x = "the owner"\n'
        self.assertEqual([r for r, _ in self.issues("a.py", text)], ["owner"])

    def test_allow_marker(self):
        self.assertEqual(self.issues("a.md", "Tony  lint-public: allow fixture"), [])


class ScrubTest(unittest.TestCase):
    def test_removes_ids_dates_and_provenance_parentheticals(self):
        src = ("# DECISION (Bontago-fca.14): keep it\n"  # lint-public: allow fixture
               "# Owner 2026-10-13: deferred work is not auto-run.\n"  # lint-public: allow fixture
               "x = 1  # Bontago-1pi.2\n"  # lint-public: allow fixture
               "# Bontago-abc.1 (owner request): fix the thing\n")  # lint-public: allow fixture
        new, res = scrub("a.py", src)
        self.assertEqual(new, "# DECISION: keep it\n# deferred work is not auto-run.\nx = 1\n# fix the thing\n")
        self.assertEqual(res, [])

    def test_never_touches_code_or_string_literals(self):
        src = 'x = "Bontago-abc.1 owner 2026-10-13"\nowner = x  # ok\ny = owner\n'  # lint-public: allow fixture
        new, res = scrub("a.py", src)
        self.assertEqual(new, src)

    def test_docstring_cleaned_gd_comments_cleaned(self):
        new, _ = scrub("a.py", '"""Guard (Bontago-fca.2).\n\nMore (owner 2026-10-01) text.\n"""\nA = 1\n')  # lint-public: allow fixture
        self.assertEqual(new, '"""Guard.\n\nMore text.\n"""\nA = 1\n')
        gd = 'var a := 1  # (owner decision 2026-09-28)\n## Doc, Bontago-xtq.45: note\nvar s := "Bontago-abc"\n'  # lint-public: allow fixture
        new, _ = scrub("a.gd", gd)
        self.assertEqual(new, 'var a := 1\n## Doc, note\nvar s := "Bontago-abc"\n')  # lint-public: allow fixture

    def test_multiline_parenthetical_is_removed_whole(self):
        src = "# Owner controller update (feedback/x.md, re-confirmed\n# 2026-09-28): RT must rotate.\n"  # lint-public: allow fixture
        new, _ = scrub("a.gd", src)
        self.assertNotIn("2026", new)
        self.assertNotIn("(", new.replace("(feedback/x.md", ""))

    def test_the_owner_becomes_the_user_and_residuals_are_reported(self):
        new, res = scrub("a.gd", "# the owner's monitor shows it\n# a debrief item\n")
        self.assertEqual(new.split("\n")[0], "# the user's monitor shows it")
        # A bare "debrief" is procedure, not provenance, so it is no residual.
        self.assertEqual(res, [])

    def test_allow_marker_line_untouched(self):
        src = "# Bontago-abc.1 lint-public: allow fixture\n"
        self.assertEqual(scrub("a.py", src)[0], src)

    def test_powershell_and_shader_comments(self):
        new, _ = scrub("a.ps1", "$a = 1 # (owner 2026-10-01)\n# Bontago-abc.1: note\n")  # lint-public: allow fixture
        self.assertEqual(new, "$a = 1\n# note\n")
        new, _ = scrub("a.gdshader", "// Bontago-abc.1: tweak\nfloat x = 1.0;\n")  # lint-public: allow fixture
        self.assertEqual(new, "// tweak\nfloat x = 1.0;\n")

    def test_cli_dry_run_then_apply(self):
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "a.gd")
            with open(p, "w", encoding="utf-8", newline="") as fh:
                fh.write("# Bontago-abc.1: note\n")  # lint-public: allow fixture
            self.assertEqual(sp.main(["--path", d, "--quiet", "a.gd"]), 0)
            self.assertIn("Bontago", open(p, encoding="utf-8").read())
            self.assertEqual(sp.main(["--path", d, "--quiet", "--apply", "a.gd"]), 0)
            self.assertEqual(open(p, encoding="utf-8").read(), "# note\n")


if __name__ == "__main__":
    unittest.main()
