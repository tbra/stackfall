"""Mocked-subprocess/filesystem tests for tools/stage_codex_handoffs.py.
Run: python tools/test_stage_codex_handoffs.py
"""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stage_codex_handoffs as sch  # noqa: E402

CX = "M:/Bontago/.claude/worktrees/"
DEST_ROOT = "W"
NOW = 1_000_000.0
MIN = 60.0


def codex_comment(text, created="2026-10-03T10:00:00Z", author="codex"):
    return {"id": "c", "issue_id": "B", "author": author, "text": text, "created_at": created}


class World:
    """Scripted environment: beads, Codex worktrees (porcelain + file stats), base tree, recorded calls."""

    def __init__(self):
        self.comments = {}
        self.titles = {}
        self.status = {}       # worktree path -> porcelain text
        self.files = {}        # absolute path -> (size, mtime)
        self.dirs = set()
        self.base_files = ["README.md"]
        self.calls = []        # (name, argv, cwd)
        self.copied = []       # (src, dst)
        self.existing = set()  # paths path_exists() reports present (dest side)
        self.overrides = {}    # run_cmd name -> (code, text)
        self.branch_exists = False
        self.added = []
        self.diff_extra = []

    def add_bead(self, bead, name, files, age_min=MIN * 2, xy="??", title=None, size=1000, comment=None):
        wt = CX + name
        self.comments[bead] = [codex_comment(comment if comment is not None else
                                             "CODEX ASSET HANDOFF worktree %s, base abc" % wt)]
        self.titles[bead] = title or ("Title of " + bead)
        self.dirs.add(wt)
        rows = []
        for f in files:
            rows.append("%s %s" % (xy, f))
            self.files[wt + "/" + f] = (size, NOW - age_min * 60)
        self.status[wt] = "\n".join(rows) + ("\n" if rows else "")
        return wt

    # --- patched seams
    def run_cmd(self, ctx, name, args, cwd, timeout):
        self.calls.append((name, list(args), cwd))
        if name in self.overrides:
            code, text = self.overrides[name]
        elif name.startswith("bd_comments_"):
            code, text = 0, "warning: noise\n" + json.dumps(self.comments[name[len("bd_comments_"):]])
        elif name.startswith("bd_show_"):
            b = name[len("bd_show_"):]
            code, text = 0, json.dumps([{"id": b, "title": self.titles[b]}])
        elif name.startswith("status_"):
            wt = args[args.index("-C") + 1]
            code, text = 0, "warning: CRLF will be replaced\n" + self.status[wt]
        elif name == "rev_base":
            code, text = 0, "base1111111111\n"
        elif name == "ls_tree":
            code, text = 0, "\0".join(self.base_files) + "\0"
        elif name == "branch_exists":
            code, text = (0, "x\n") if self.branch_exists else (1, "")
        elif name.startswith("add_"):
            self.added.extend(args[args.index("--") + 1:])
            code, text = 0, ""
        elif name == "rev_head":
            code, text = 0, "headhead9999\n"
        elif name == "verify_diff":
            code, text = 0, "\0".join(self.added + self.diff_extra) + "\0"
        else:
            code, text = 0, ""
        return code, text, "/log/" + name

    def names(self):
        return [c[0] for c in self.calls]

    def argv(self, name):
        return [a for n, a, _ in self.calls if n == name]

    # --- seams
    def file_stat(self, path):
        return self.files.get(path)

    def is_dir(self, path):
        return path in self.dirs

    def path_exists(self, path):
        return path in self.existing

    def copy_file(self, src, dst):
        self.copied.append((src, dst))

    def now(self):
        return NOW


def args_for(**kw):
    ns = dict(beads=["B-1", "B-2"], branch="wt/assets-x", repo="R", worktree_root=DEST_ROOT, base="main",
              dry_run=False, min_age_min=30.0, allow_missing=False, log_dir=tempfile.gettempdir())
    ns.update(kw)
    return type("A", (), ns)()


@contextlib.contextmanager
def patched(world, which=None):
    with contextlib.ExitStack() as st:
        st.enter_context(mock.patch.object(sch, "run_cmd", world.run_cmd))
        st.enter_context(mock.patch.object(sch, "file_stat", world.file_stat))
        st.enter_context(mock.patch.object(sch, "is_dir", world.is_dir))
        st.enter_context(mock.patch.object(sch, "path_exists", world.path_exists))
        st.enter_context(mock.patch.object(sch, "copy_file", world.copy_file))
        st.enter_context(mock.patch.object(sch, "now", world.now))
        st.enter_context(mock.patch.object(sch.shutil, "which", which or (lambda n: None)))
        yield


def run_stage(world, **kw):
    out, res = [], {}
    err = result = None
    with patched(world):
        try:
            result = sch.stage(args_for(**kw), sch.Ctx(tempfile.gettempdir()), out.append, res)
        except (sch.Refused, sch.StepFailed) as e:
            err = e
    return err, out, res, result


def run_main(world, extra=None, **kw):
    argv = ["--beads", "B-1", "B-2", "--branch", "wt/assets-x", "--repo", "R", "--worktree-root", DEST_ROOT,
            "--log-dir", tempfile.gettempdir()] + (extra or [])
    buf = io.StringIO()
    with patched(world), contextlib.redirect_stdout(buf):
        code = sch.main(argv)
    return code, buf.getvalue()


def two_beads(world=None, **kw):
    w = world or World()
    w.add_bead("B-1", "codex-assets-one", ["assets/a/one.svg", "assets/a/one.svg.import"], **kw)
    w.add_bead("B-2", "codex-assets-two", ["assets/b/two.glb", "docs/art_mockups/two.png"], **kw)
    return w


class PathExtraction(unittest.TestCase):
    def test_backslash_and_forward_slash(self):
        a = [codex_comment("worktree M:\\Bontago\\.claude\\worktrees\\codex-assets-menu-icons, base e35")]
        b = [codex_comment("worktree M:/Bontago/.claude/worktrees/codex-assets-menu-icons, base e35")]
        want = "M:/Bontago/.claude/worktrees/codex-assets-menu-icons"
        self.assertEqual(sch.extract_worktree(a), want)
        self.assertEqual(sch.extract_worktree(b), want)

    def test_last_path_wins_within_and_across_comments(self):
        t = "first M:/Bontago/.claude/worktrees/codex-old then M:\\Bontago\\.claude\\worktrees\\codex-mid."
        cs = [codex_comment(t, "2026-10-01T00:00:00Z"),
              codex_comment("moved to M:/Bontago/.claude/worktrees/codex-new now", "2026-10-02T00:00:00Z")]
        self.assertEqual(sch.extract_worktree(cs), "M:/Bontago/.claude/worktrees/codex-new")
        self.assertEqual(sch.extract_worktree(cs[:1]), "M:/Bontago/.claude/worktrees/codex-mid")

    def test_created_at_orders_when_listed_out_of_order(self):
        cs = [codex_comment("M:/Bontago/.claude/worktrees/codex-new", "2026-10-02T00:00:00Z"),
              codex_comment("M:/Bontago/.claude/worktrees/codex-old", "2026-10-01T00:00:00Z")]
        self.assertEqual(sch.extract_worktree(cs).rsplit("/", 1)[-1], "codex-new")

    def test_only_codex_comments_count(self):
        cs = [codex_comment("M:/Bontago/.claude/worktrees/codex-real", "2026-10-01T00:00:00Z"),
              codex_comment("staged from M:/Bontago/.claude/worktrees/codex-other", "2026-10-02T00:00:00Z",
                            author="stackfall-orchestrator")]
        self.assertEqual(sch.extract_worktree(cs).rsplit("/", 1)[-1], "codex-real")
        self.assertIsNone(sch.extract_worktree(cs[1:]))
        self.assertIsNone(sch.extract_worktree([codex_comment("no path here, branch codex/assets-x")]))
        self.assertIsNone(sch.extract_worktree([]))

    def test_other_worktree_root(self):
        cs = [codex_comment("at M:\\Bontago-worktrees\\codex-assets-y/ done")]
        self.assertEqual(sch.extract_worktree(cs), "M:/Bontago-worktrees/codex-assets-y")


class Parsing(unittest.TestCase):
    def test_porcelain_quoted_and_noise(self):
        text = ('warning: in the working copy of x, CRLF will be replaced\n'
                '?? assets/a.svg\n?? "assets/with space.png"\n?? "assets/caf\\303\\251.png"\n'
                ' M tracked.gd\nR  old.png -> new.png\nA  staged.svg\nAM both.svg\n')
        rows = sch.parse_porcelain(text)
        self.assertEqual([r[1] for r in rows], ["assets/a.svg", "assets/with space.png", "assets/caf\u00e9.png",
                                                "tracked.gd", "old.png -> new.png", "staged.svg", "both.svg"])
        self.assertEqual([sch.is_addition(r[0]) for r in rows], [True, True, True, False, False, True, True])
        self.assertFalse(sch.is_addition("AD"))
        self.assertFalse(sch.is_addition(" D"))

    def test_parse_json_skips_noise(self):
        self.assertEqual(sch.parse_json('warn [x]\n[{"a": 1}]\n'), [{"a": 1}])
        self.assertEqual(sch.parse_json('{"a": 2}'), {"a": 2})
        with self.assertRaises(ValueError):
            sch.parse_json("nothing")

    def test_asset_paths_and_chunking(self):
        for p in ("assets/x", "source_art/x", "docs/art_mockups/x", "docs/audio_review/x", "tools/generate_x.py"):
            self.assertTrue(sch.is_asset_path(p), p)
        for p in ("tools/scan_x.gd", "docs/NOTES.md", "ui/x.gd"):
            self.assertFalse(sch.is_asset_path(p), p)
        chunks = list(sch.add_chunks(["a" * 10] * 10, limit=35))
        self.assertEqual([len(c) for c in chunks], [3, 3, 3, 1])
        self.assertEqual(list(sch.add_chunks([])), [])

    def test_commit_message_parts(self):
        s, b, t = sch.commit_message("Art: glyphs", "B-9", "M:/x/codex-y")
        self.assertEqual(s, "Art: glyphs (B-9)")
        self.assertEqual(b, "Staged from Codex handoff worktree M:/x/codex-y (uncommitted candidate).")
        self.assertEqual(t, "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>")


class Assessment(unittest.TestCase):
    def test_report_numbers_and_nonasset(self):
        w = World()
        w.add_bead("B-1", "codex-assets-one", ["assets/a.bin", "tools/scan_keys.gd", "tools/generate_one.py"],
                   size=2_000_000, age_min=75.4)
        w.files[CX + "codex-assets-one/assets/a.bin"] = (5_000_000, NOW - 75.4 * 60)
        err, out, _, result = run_stage(w, beads=["B-1"], dry_run=True)
        self.assertIsNone(err)
        self.assertEqual(result, ("dry-run", 1, 3))
        line = out[0]
        for part in ("B-1", "codex-assets-one", "files=3", "9.00MB", "age=75m", "OK"):
            self.assertIn(part, line)
        self.assertTrue(any("non-asset paths (1)" in l and "tools/scan_keys.gd" in l for l in out))
        with open(os.path.join(tempfile.gettempdir(), "detail.txt"), encoding="utf-8") as fh:
            detail = fh.read()
        self.assertIn("largest=assets/a.bin (5.000MB)", detail)
        self.assertIn("NONASSET tools/scan_keys.gd", detail)

    def test_no_worktree_path_is_no_wt_and_refuses(self):
        w = two_beads()
        w.comments["B-2"] = [codex_comment("handoff without a path")]
        err, out, res, _ = run_stage(w)
        self.assertIsInstance(err, sch.Refused)
        self.assertTrue(any(l.startswith("B-2") and "NO-WT" in l for l in out))
        self.assertIn("B-2 NO-WT", err.reason)
        self.assertNotIn("worktree_add", w.names())

    def test_missing_directory_is_no_wt(self):
        w = two_beads()
        w.dirs.discard(CX + "codex-assets-two")
        err, out, _, _ = run_stage(w)
        self.assertIsInstance(err, sch.Refused)
        self.assertTrue(any("worktree directory not found" in l for l in out))

    def test_allow_missing_skips_and_stages_the_rest(self):
        w = two_beads()
        w.comments["B-2"] = [codex_comment("no path")]
        err, out, res, result = run_stage(w, allow_missing=True)
        self.assertIsNone(err)
        self.assertEqual(result, ("headhead9", 1, 2))
        self.assertEqual(len(w.argv("commit_B-1")), 1)
        self.assertEqual(w.argv("commit_B-2"), [])

    def test_all_missing_still_refuses_with_allow_missing(self):
        w = two_beads()
        w.comments["B-1"] = [codex_comment("none")]
        w.comments["B-2"] = [codex_comment("none")]
        err, _, _, _ = run_stage(w, allow_missing=True)
        self.assertIsInstance(err, sch.Refused)
        self.assertIn("no candidate", err.reason)

    def test_modified_tracked_refused_with_paths(self):
        for xy in (" M", "M ", " D", "D ", "R "):
            w = two_beads()
            path = "tools/existing.gd"
            wt = CX + "codex-assets-two"
            w.status[wt] += "%s %s\n" % (xy, path)
            w.files[wt + "/" + path] = (10, NOW - 7200)
            err, out, _, _ = run_stage(w)
            self.assertIsInstance(err, sch.Refused, xy)
            self.assertIn("B-2 MODIFIED(1)", err.reason)
            self.assertTrue(any("modified (not additions)" in l and path in l for l in out), xy)
            self.assertNotIn("worktree_add", w.names())
            self.assertEqual(w.copied, [])

    def test_staged_added_files_are_additions(self):
        w = two_beads(xy="A ")
        err, _, _, result = run_stage(w, dry_run=True)
        self.assertIsNone(err)
        self.assertEqual(result[1:], (2, 4))

    def test_too_recent_refused(self):
        w = two_beads()
        w.files[CX + "codex-assets-one/assets/a/one.svg"] = (10, NOW - 5 * 60)
        err, out, _, _ = run_stage(w)
        self.assertIsInstance(err, sch.Refused)
        self.assertIn("B-1 TOO-RECENT", err.reason)
        self.assertTrue(any(l.startswith("B-1") and "age=5m" in l and "TOO-RECENT" in l for l in out))
        err, _, _, _ = run_stage(w, min_age_min=4.0, dry_run=True)
        self.assertIsNone(err)

    def test_empty_worktree_refused(self):
        w = two_beads()
        w.status[CX + "codex-assets-one"] = ""
        err, _, _, _ = run_stage(w)
        self.assertIn("B-1 EMPTY", err.reason)

    def test_missing_listed_file_refused(self):
        w = two_beads()
        del w.files[CX + "codex-assets-one/assets/a/one.svg"]
        err, _, _, _ = run_stage(w)
        self.assertIn("B-1 MISSING(1)", err.reason)

    def test_status_failure_refused(self):
        w = two_beads()
        w.overrides["status_B-1"] = (128, "fatal: not a git repository")
        err, _, _, _ = run_stage(w)
        self.assertIn("B-1 GIT-FAIL", err.reason)

    def test_bd_failure_is_a_step_failure(self):
        w = two_beads()
        w.overrides["bd_comments_B-1"] = (1, "no such issue")
        err, _, _, _ = run_stage(w)
        self.assertIsInstance(err, sch.StepFailed)
        self.assertEqual(err.step, "bd")
        w = two_beads()
        w.overrides["bd_show_B-1"] = (0, "not json")
        self.assertEqual(run_stage(w)[0].step, "bd")


class CrossChecks(unittest.TestCase):
    def test_overlap_between_candidates_refused(self):
        w = World()
        w.add_bead("B-1", "codex-assets-one", ["assets/shared.svg", "assets/only1.svg"])
        w.add_bead("B-2", "codex-assets-two", ["assets/Shared.SVG", "assets/only2.svg"])
        err, out, _, _ = run_stage(w)
        self.assertIsInstance(err, sch.Refused)
        self.assertIn("B-1 OVERLAP(1)", err.reason)
        self.assertIn("B-2 OVERLAP(1)", err.reason)
        self.assertTrue(any(l.startswith("overlaps:") and "assets/shared.svg" in l for l in out))
        self.assertNotIn("worktree_add", w.names())

    def test_base_collision_refused_case_insensitive(self):
        w = two_beads()
        w.base_files = ["README.md", "assets/a/one.svg", "Docs/Art_Mockups/two.png"]
        err, out, _, _ = run_stage(w)
        self.assertIsInstance(err, sch.Refused)
        self.assertIn("B-1 COLLIDE(1)", err.reason)
        self.assertIn("B-2 COLLIDE(1)", err.reason)
        self.assertTrue(any("collides with base" in l and "assets/a/one.svg" in l for l in out))
        self.assertNotIn("worktree_add", w.names())

    def test_base_is_resolved_and_tree_listed_at_that_rev(self):
        w = two_beads()
        run_stage(w, base="main", dry_run=True)
        self.assertEqual(w.argv("rev_base")[0][-1], "main^{commit}")
        self.assertEqual(w.argv("ls_tree")[0][-3:], ["--name-only", "-z", "base1111111111"])

    def test_existing_branch_or_path_refused(self):
        w = two_beads()
        w.branch_exists = True
        err, _, _, _ = run_stage(w)
        self.assertIn("branch already exists", err.reason)
        w = two_beads()
        w.existing.add("W/assets-x")
        err, _, _, _ = run_stage(w)
        self.assertIn("worktree path already exists", err.reason)


class Staging(unittest.TestCase):
    def test_dry_run_creates_nothing(self):
        w = two_beads()
        err, out, res, result = run_stage(w, dry_run=True)
        self.assertIsNone(err)
        self.assertEqual(result, ("dry-run", 2, 4))
        for n in w.names():
            self.assertFalse(n.startswith(("worktree_add", "add_", "commit_", "wt_remove", "br_delete")), n)
        self.assertEqual(w.copied, [])
        self.assertEqual(res, {})
        code, text = run_main(two_beads(), ["--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("STAGE OK (dry-run) branch=wt/assets-x head=- beads=2 files=4", text)

    def test_worktree_add_command_and_copy_to_dest(self):
        w = two_beads()
        err, _, res, _ = run_stage(w)
        self.assertIsNone(err)
        self.assertEqual(w.argv("worktree_add")[0], ["git", "-C", "R", "worktree", "add", "-b", "wt/assets-x",
                                                     "W/assets-x", "base1111111111"])
        self.assertEqual(res["worktree"], "W/assets-x")
        self.assertEqual(len(w.copied), 4)
        self.assertEqual(w.copied[0], (CX + "codex-assets-one/assets/a/one.svg", "W/assets-x/assets/a/one.svg"))

    def test_one_commit_per_bead_with_message_and_trailer(self):
        w = two_beads()
        w.titles["B-1"] = "Art: menu icons"
        err, _, _, result = run_stage(w)
        self.assertIsNone(err)
        for bead, name in (("B-1", "codex-assets-one"), ("B-2", "codex-assets-two")):
            argv = w.argv("commit_" + bead)[0]
            self.assertEqual(len(w.argv("commit_" + bead)), 1)
            i = argv.index("-m")
            self.assertEqual(argv[:4], ["git", "-C", "W/assets-x", "commit"])
            self.assertEqual(argv[i + 1], "%s (%s)" % (w.titles[bead], bead))
            self.assertEqual(argv[i + 2:i + 4], ["-m", "Staged from Codex handoff worktree %s%s "
                                                 "(uncommitted candidate)." % (CX, name)])
            self.assertEqual(argv[i + 4:i + 6], ["-m", "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"])
        names = w.names()
        self.assertLess(names.index("worktree_add"), names.index("add_B-1_0"))
        self.assertLess(names.index("add_B-1_0"), names.index("commit_B-1"))
        self.assertLess(names.index("commit_B-1"), names.index("add_B-2_0"))
        self.assertLess(names.index("add_B-2_0"), names.index("commit_B-2"))
        self.assertEqual(result, ("headhead9", 2, 4))
        self.assertEqual(w.argv("add_B-2_0")[0][-2:], ["assets/b/two.glb", "docs/art_mockups/two.png"])

    def test_refuses_to_overwrite_and_cleans_up(self):
        w = two_beads()
        w.existing.add("W/assets-x/assets/b/two.glb")
        err, _, res, _ = run_stage(w)
        self.assertIsInstance(err, sch.StepFailed)
        self.assertEqual(err.step, "copy")
        self.assertIn("refusing to overwrite", err.detail)
        self.assertNotIn("commit_B-2", w.names())
        w2 = two_beads()
        w2.existing.add("W/assets-x/assets/b/two.glb")
        code, text = run_main(w2)
        self.assertEqual(code, 1)
        self.assertIn("STAGE FAILED at copy", text)
        self.assertIn("wt_remove", w2.names())
        self.assertEqual(w2.argv("br_delete")[0][-2:], ["-D", "wt/assets-x"])

    def test_commit_failure_cleans_up_own_worktree_only(self):
        w = two_beads()
        w.overrides["commit_B-2"] = (1, "hook rejected")
        code, text = run_main(w)
        self.assertEqual(code, 1)
        self.assertIn("STAGE FAILED at commit", text)
        removed = w.argv("wt_remove")[0]
        self.assertEqual(removed[-1], "W/assets-x")
        self.assertFalse(any(CX in " ".join(a) for n, a, _ in w.calls if n in ("wt_remove", "br_delete")))

    def test_verify_diff_mismatch_fails(self):
        w = two_beads()
        w.diff_extra = ["stray.txt"]
        err, _, _, _ = run_stage(w)
        self.assertEqual(err.step, "verify")

    def test_large_package_is_added_in_chunks(self):
        w = World()
        files = ["assets/ui/input_glyphs/key_atlas/keycap_%03d_%s.png" % (i, "x" * 40) for i in range(500)]
        w.add_bead("B-1", "codex-assets-one", files)
        err, _, _, result = run_stage(w, beads=["B-1"])
        self.assertIsNone(err)
        adds = [n for n in w.names() if n.startswith("add_B-1_")]
        self.assertGreater(len(adds), 1)
        for n in adds:
            self.assertLess(len(" ".join(w.argv(n)[0])), 32000)
        self.assertEqual(len(w.added), 500)
        self.assertEqual(len(w.argv("commit_B-1")), 1)

    def test_codex_worktrees_are_only_read(self):
        w = two_beads()
        run_stage(w)
        for name, argv, cwd in w.calls:
            target = argv[argv.index("-C") + 1] if "-C" in argv else ""
            self.assertFalse(cwd.startswith(CX), name)
            if target.startswith(CX):
                self.assertTrue(name.startswith("status_"), name)
                self.assertIn("--no-optional-locks", argv)
                self.assertEqual(argv[argv.index("status") + 1:], ["--porcelain", "-uall"])
        for src, dst in w.copied:
            self.assertTrue(src.startswith(CX))
            self.assertTrue(dst.startswith("W/assets-x/"))


class Tooling(unittest.TestCase):
    def test_bd_cmd_resolution(self):
        w = two_beads()
        out, res = [], {}
        with patched(w, which=lambda n: "C:/npm/bd.CMD" if n == "bd" else None):
            sch.stage(args_for(dry_run=True), sch.Ctx(tempfile.gettempdir()), out.append, res)
        for name, argv, _ in w.calls:
            if name.startswith("bd_"):
                self.assertEqual(argv[0], "C:/npm/bd.CMD", name)
                self.assertEqual(argv[1:3], ["-C", "R"])
        self.assertIn("--json", w.argv("bd_comments_B-1")[0])
        self.assertEqual(w.argv("bd_show_B-1")[0][-3:], ["B-1", "--json", "--brief-deps"])
        with patched(two_beads(), which=lambda n: None):
            self.assertEqual(sch.bd_exe(), "bd")

    def test_duplicate_bead_ids_are_collapsed(self):
        w = two_beads()
        err, _, _, result = run_stage(w, beads=["B-1", "B-1", "B-2"], dry_run=True)
        self.assertIsNone(err)
        self.assertEqual(result[1], 2)
        self.assertEqual(len(w.argv("bd_comments_B-1")), 1)

    def test_main_summary_lines_and_exit_codes(self):
        w = two_beads()
        code, text = run_main(w)
        lines = text.strip().splitlines()
        self.assertEqual(code, 0)
        self.assertTrue(lines[-1].startswith("STAGE OK branch=wt/assets-x head=headhead9 beads=2 files=4"), lines[-1])
        self.assertEqual(len([l for l in lines if l.startswith("B-")]), 2)
        w = two_beads()
        w.base_files.append("assets/a/one.svg")
        code, text = run_main(w)
        self.assertEqual(code, 1)
        self.assertTrue(text.strip().splitlines()[-1].startswith("STAGE REFUSED: B-1 COLLIDE(1)"), text)
        self.assertNotIn("worktree_add", w.names())
        w = two_beads()
        w.comments["B-2"] = [codex_comment("none")]
        self.assertEqual(run_main(w)[0], 1)
        w = two_beads()
        w.comments["B-2"] = [codex_comment("none")]
        self.assertEqual(run_main(w, ["--allow-missing"])[0], 0)

    def test_help_is_the_module_docstring(self):
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            with self.assertRaises(SystemExit):
                sch.main(["--help"])
        self.assertIn("UNCOMMITTED", buf.getvalue())


def _git(*a, cwd):
    p = subprocess.run(["git", *a], cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    assert p.returncode == 0, (a, p.stdout, p.stderr)
    return p.stdout.strip()


@unittest.skipUnless(shutil.which("git"), "git not installed")
class EndToEndRealGit(unittest.TestCase):
    """Real git in a throwaway repo; only bd is faked. Proves the argv sequence actually works."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="sch")
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        if " " in self.tmp:
            self.skipTest("temp path contains a space")
        self.repo = os.path.join(self.tmp, "repo")
        os.makedirs(self.repo)
        _git("init", "-q", "-b", "main", cwd=self.repo)
        for k, v in (("user.name", "t"), ("user.email", "t@t"), ("core.autocrlf", "false")):
            _git("config", k, v, cwd=self.repo)
        with open(os.path.join(self.repo, "README.md"), "w") as fh:
            fh.write("x\n")
        _git("add", "README.md", cwd=self.repo)
        _git("commit", "-q", "-m", "init", cwd=self.repo)
        self.wts = {}
        for bead, name, files in (("B-1", "codex-assets-one", ["assets/a/one.svg", "assets/a/with space.png"]),
                                  ("B-2", "codex-assets-two", ["assets/b/two.glb", "tools/generate_two.py"])):
            wt = os.path.join(self.tmp, ".claude", "worktrees", name)
            _git("worktree", "add", "-q", "-b", "codex/" + name, wt, cwd=self.repo)
            for f in files:
                path = os.path.join(wt, *f.split("/"))
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, "w") as fh:
                    fh.write("content of %s\n" % f)
                os.utime(path, (NOW, NOW - 3600 * 5))
            self.wts[bead] = wt
        self.real_run = sch.run_cmd
        # B-1's path uses backslashes, B-2's forward slashes
        self.comments = {"B-1": [codex_comment("worktree " + self.wts["B-1"].replace("/", "\\"))],
                         "B-2": [codex_comment("worktree " + self.wts["B-2"].replace("\\", "/") + ", base x")]}

    def fake_run(self, ctx, name, args, cwd, timeout):
        if name.startswith("bd_comments_"):
            return 0, json.dumps(self.comments[name[len("bd_comments_"):]]), "-"
        if name.startswith("bd_show_"):
            return 0, json.dumps([{"title": "Art: " + name[len("bd_show_"):]}]), "-"
        return self.real_run(ctx, name, args, cwd, timeout)

    def go(self, extra=None):
        argv = ["--beads", "B-1", "B-2", "--branch", "wt/assets-e2e", "--repo", self.repo,
                "--worktree-root", os.path.join(self.tmp, "wts"), "--log-dir", os.path.join(self.tmp, "logs")]
        buf = io.StringIO()
        with mock.patch.object(sch, "run_cmd", self.fake_run), mock.patch.object(sch, "now", lambda: NOW),                 contextlib.redirect_stdout(buf):
            code = sch.main(argv + (extra or []))
        return code, buf.getvalue()

    def codex_state(self):
        return {b: _git("status", "--porcelain", "-uall", cwd=wt) for b, wt in self.wts.items()}

    def test_stage_and_refuse_second_run(self):
        before = self.codex_state()
        code, text = self.go(["--dry-run"])
        self.assertEqual(code, 0, text)
        self.assertEqual(_git("branch", "--list", "wt/assets-e2e", cwd=self.repo), "")
        code, text = self.go()
        self.assertEqual(code, 0, text)
        self.assertIn("STAGE OK branch=wt/assets-e2e", text)
        dest = os.path.join(self.tmp, "wts", "assets-e2e")
        log = _git("log", "--format=%s%n%b---", "main..wt/assets-e2e", cwd=self.repo)
        self.assertEqual(log.count("---"), 2)
        self.assertIn("Art: B-2", log)
        self.assertIn("Staged from Codex handoff worktree", log)
        self.assertIn("Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>", log)
        files = _git("diff", "--name-only", "main", "wt/assets-e2e", cwd=self.repo).splitlines()
        self.assertEqual(sorted(files), sorted(["assets/a/one.svg", "assets/a/with space.png",
                                                "assets/b/two.glb", "tools/generate_two.py"]))
        self.assertTrue(os.path.isfile(os.path.join(dest, "assets", "a", "with space.png")))
        self.assertEqual(_git("status", "--porcelain", cwd=dest), "")
        self.assertEqual(self.codex_state(), before)  # Codex worktrees untouched
        code, text = self.go()  # same branch again -> refused (and collisions now in main)
        self.assertEqual(code, 1)
        self.assertIn("STAGE REFUSED", text)
        self.assertIn("branch already exists", text)


if __name__ == "__main__":
    unittest.main(verbosity=1)
