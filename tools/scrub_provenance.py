#!/usr/bin/env python3
"""Remove provenance (see public_rules.py) from comments and docstrings.

Usage: python tools/scrub_provenance.py [--path <checkout>] [--apply] [--quiet] [paths...]

Works on .gd .gdshader .gdshaderinc .py .ps1 files (tracked ones under the given paths, default the
whole checkout). Only comment text and docstrings are edited; code tokens and other string literals are
never touched. Dry-run by default: prints each changed line as `path:line: - old` / `+ new`; --apply
writes the files. Lines that still break a rule afterwards are listed as
`RESIDUAL path:line: rule: text` for a manual rewrite and make the exit status 1.

What it does to the prose of a line: drops Beads ids and dates with their glue, drops parentheticals
that held only provenance, strips "<person> decision/request/..." tags and a leading "<person>:"
inside parentheses, turns the remaining "the <person>'s" into "the user's", and deletes comment lines
that become empty. It does not guess at sentences that need rewording: those are residuals. Lines
containing `lint-public: allow` are left alone.
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from typing import List, Optional, Tuple

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import public_rules as pr  # noqa: E402

SENT = "\x00"
TAG_WORDS = ("decision|choice|request|report|playtest|feedback|clarification|rule|update|call|"
             "preference|answer|ruling|review|approval")
OWNER_TAG = re.compile(r"\b[Oo]wner(?:'s)?\s+(?:%s)\b" % TAG_WORDS)
PARENS = re.compile(r"\(([^()]*)\)")
JUNK_ONLY = re.compile(r"[\s,;:.\-–—/]*")
ISSUE_RULES = [(rid, rx) for rid, rx, _ in pr.RULES]
SKIP_DIRS = {".git", ".godot", ".beads", "addons", "node_modules", "__pycache__"}


def has_issue(s: str) -> bool:
    return any(rx.search(s) for _, rx in ISSUE_RULES)


def _mark(s: str) -> str:
    s = pr.RULES[2][1].sub(SENT, s)  # bead ids
    s = re.sub(SENT + r"(?:[ \t]*(?:,|and|&)[ \t]*[a-z0-9]{3}(?:\.\d+)+)+", SENT, s)  # "x.1, y.2" id lists
    s = pr.RULES[3][1].sub(SENT, s)  # dates
    return s


def _tidy_marks(s: str) -> str:
    s = re.sub(r"\b(?:[Oo]wner|[Dd]ebrief|[Ii]ncident)[ \t]*" + SENT + r"[ \t]*[:,]?[ \t]*", "", s)
    s = re.sub(r"(?m)^" + SENT + r"(?:[ \t]*[,;:])*[ \t]*", "", s)
    s = re.sub(SENT + r"(?:[ \t]*[,;:])+[ \t]*", "", s)
    s = re.sub(r"[ \t]*[,;][ \t]*" + SENT, "", s)
    s = re.sub(r"[ \t]*" + SENT, "", s)
    return s


def clean_tokens(s: str) -> str:
    s = OWNER_TAG.sub("", s)
    s = _mark(s)
    s = _tidy_marks(s)
    s = re.sub(r"^\s*[Oo]wner\s*[:,]?\s*$", "", s)
    s = re.sub(r"(?m)^([ \t]*)[Oo]wner[ \t]*[:,][ \t]*", r"\1", s)
    return s


def clean_prose(seg: str) -> str:
    """Clean one run of prose (a comment, or a docstring line)."""
    if not has_issue(seg) and "owner" not in seg.lower():
        return seg
    orig = seg

    def paren(m: "re.Match[str]") -> str:
        content = m.group(1)
        if not has_issue(content) and not re.search(r"\b[Oo]wner\b", content):
            return m.group(0)
        new = clean_tokens(content)
        if JUNK_ONLY.fullmatch(new):
            return SENT + "P"
        return "(" + new.strip(" ,;:-") + ")"

    prev = None
    while prev != seg:
        prev = seg
        seg = PARENS.sub(paren, seg)
    seg = re.sub(r"[ ]?" + SENT + "P", "", seg)
    seg = clean_tokens(seg)
    # Only the person sense becomes "the user"; the game's own owner (a block's owning slot, an
    # owner byte, a shape owner) stays.
    if pr.PERSON_OWNER.search(orig):
        seg = re.sub(r"\b[Tt]he owner's\b", lambda m: "the user's" if m.group(0)[0] == "t" else "The user's", seg)
        seg = re.sub(r"\b([Tt])he owner\b", lambda m: m.group(1) + "he user", seg)
        seg = re.sub(r"(?<![\w'])owner's (?=PC|machine|monitor|checkout|screen)", "the user's ", seg)
    if seg != orig:
        seg = re.sub(r"(?<=\S)[ ]{2,}(?=\S)", " ", seg)
        seg = re.sub(r"[ \t]+([,;)])", r"\1", seg)
        seg = re.sub(r"\([ \t]+", "(", seg)
        seg = re.sub(r"^([^\w\n]*?)\(([^()]*)\)[ \t]*:", r"\1\2:", seg, flags=re.M)
        seg = re.sub(r"\s+$", "", seg) if orig.rstrip() != orig else seg
    return seg


def runs(mask: List[bool], start: int, end: int) -> List[Tuple[int, int]]:
    out: List[Tuple[int, int]] = []
    i = start
    while i < end:
        if mask[i]:
            j = i
            while j < end and mask[j]:
                j += 1
            out.append((i, j))
            i = j
        else:
            i += 1
    return out


BLOCK_PREFIX = re.compile(r"^(\s*(?:#+|//+)[ ]?)(.*)$")


def _scrub_blocks(path: str, text: str, changes: List[Tuple[int, str, str]]) -> str:
    """Clean runs of comment-only lines as one unit so a parenthetical wrapped over several lines
    is removed whole instead of leaving "(:" fragments. Line count may shrink."""
    mask = pr.prose_mask(path, text)
    starts = pr.line_starts(text)
    lines = text.split("\n")

    def is_comment(i: int) -> Optional["re.Match[str]"]:
        line = lines[i]
        if pr.ALLOW_MARK in line:
            return None
        m = BLOCK_PREFIX.match(line)
        if not m:
            return None
        pos = starts[i] + len(line) - len(line.lstrip())
        return m if pos < len(mask) and mask[pos] else None

    out: List[str] = []
    i = 0
    while i < len(lines):
        m = is_comment(i)
        if not m:
            out.append(lines[i])
            i += 1
            continue
        prefix = m.group(1)
        j = i
        bodies: List[str] = []
        while j < len(lines):
            mj = is_comment(j)
            if not mj or mj.group(1) != prefix:
                break
            bodies.append(mj.group(2))
            j += 1
        joined = "\n".join(bodies)
        fixed = clean_prose(joined)
        if fixed != joined and len(bodies) > 1:
            spare = sum(1 for b in fixed.split("\n") if not b.strip()) - sum(1 for b in bodies if not b.strip())
            new_lines = []
            for b in fixed.split("\n"):
                if not b.strip() and spare > 0:
                    spare -= 1  # an emptied line, not an original paragraph break
                    continue
                new_lines.append(prefix + b)
            changes.append((i + 1, "\n".join(lines[i:j]), "\n".join(new_lines)))
            out.extend(new_lines)
        else:
            out.extend(lines[i:j])
        i = j
    return "\n".join(out)


def scrub_text(path: str, text: str) -> Tuple[str, List[Tuple[int, str, str]], List[Tuple[int, str, str]]]:
    """(new_text, [(line, old, new)], [(line, rule, text)] residuals)."""
    if "\r" in text:
        text = text.replace("\r\n", "\n")
    changes: List[Tuple[int, str, str]] = []
    text = _scrub_blocks(path, text, changes)
    mask = pr.prose_mask(path, text)
    starts = pr.line_starts(text)
    lines = text.split("\n")
    out: List[Optional[str]] = []
    for ln, line in enumerate(lines, 1):
        if pr.ALLOW_MARK in line:
            out.append(line)
            continue
        base = starts[ln - 1]
        new = line
        for a, b in reversed(runs(mask, base, base + len(line))):
            seg = line[a - base:b - base]
            fixed = clean_prose(seg)
            if fixed != seg:
                new = new[:a - base] + fixed + new[b - base:]
        if new != line:
            changes.append((ln, line, new))
            stripped = new.strip()
            if stripped in ("#", "##", "//") or stripped == "":
                if line.strip().startswith(("#", "//")):
                    new = None  # comment-only line emptied by the scrub
                else:
                    new = new.rstrip()
            elif re.search(r"\S\s+(#+|//)\s*$", new):
                new = re.sub(r"\s+(#+|//)\s*$", "", new)  # trailing comment emptied
        out.append(new)
    result = "\n".join(x for x in out if x is not None)
    residuals = pr.find_issues(path, result)
    return result, changes, residuals


def tracked_files(root: str, paths: List[str]) -> List[str]:
    rels: List[str] = []
    try:
        p = subprocess.run(["git", "-C", root, "ls-files", "-z"] + (["--"] + paths if paths else []),
                           capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
        if p.returncode == 0:
            rels = [x for x in p.stdout.split("\0") if x]
    except (OSError, subprocess.SubprocessError):
        rels = []
    if not rels:
        for base in (paths or ["."]):
            top = os.path.join(root, base)
            if os.path.isfile(top):
                rels.append(base)
                continue
            for d, dirs, files in os.walk(top):
                dirs[:] = [x for x in dirs if x not in SKIP_DIRS]
                for f in files:
                    rels.append(os.path.relpath(os.path.join(d, f), root).replace("\\", "/"))
    return [r for r in rels if pr.is_code(r) and not r.startswith(("addons/", ".beads/"))]


def main(argv: List[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):  # Windows consoles default to a legacy code page
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    ap.add_argument("--apply", action="store_true", help="write the cleaned files (default: dry-run)")
    ap.add_argument("--quiet", action="store_true", help="print only residuals and the summary")
    ap.add_argument("paths", nargs="*", help="files or folders relative to --path")
    args = ap.parse_args(argv)
    root = os.path.abspath(args.path)
    n_files = n_lines = n_res = 0
    for rel in tracked_files(root, [p.replace("\\", "/") for p in args.paths]):
        full = os.path.join(root, rel)
        try:
            with open(full, encoding="utf-8", newline="") as fh:
                text = fh.read()
        except (OSError, UnicodeDecodeError):
            continue
        crlf = "\r\n" in text
        new, changes, residuals = scrub_text(rel, text)
        if changes:
            n_files += 1
            n_lines += len(changes)
            if not args.quiet:
                for ln, old, nw in changes:
                    print("%s:%d: - %s" % (rel, ln, old.strip()))
                    print("%s:%d: + %s" % (rel, ln, nw.strip()))
            if args.apply:
                with open(full, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new.replace("\n", "\r\n") if crlf else new)
        for ln, rid, txt in residuals:
            n_res += 1
            print("RESIDUAL %s:%d: %s: %s" % (rel, ln, rid, txt))
    print("SCRUB %s: %d lines in %d files changed, %d residual" % (
        "applied" if args.apply else "dry-run", n_lines, n_files, n_res))
    return 1 if n_res else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
