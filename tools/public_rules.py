"""Shared rules for the public repository: what must not appear in tracked text.

Used by lint_public.py (fails on findings) and scrub_provenance.py (rewrites comments and
docstrings). The rules themselves:

  - no provenance in tracked text: no tags saying who asked for something or when (see RULES), no
    Beads ids (placeholders Bontago-123 and Bontago-<id> are fine) and no dates except functional
    ones (an expiry date in a legacy marker, a timestamp such as 2026-01-01T00:00:00Z);
  - no machine-specific paths or names (drive-letter paths, user folders, user names);
  - "the user" where a human is meant; the word for a slot, file or concept owner in the technical
    sense stays (OWNER_BEFORE / OWNER_AFTER list the accepted contexts).

Rule scopes: "all" rules apply to every character of a tracked text file; "prose" rules apply only to
comment text and docstrings in code files (.gd .gdshader .gdshaderinc .py .ps1) and to every character of
other text files, so identifiers such as a variable named like the person word are not findings. A line
containing `lint-public: allow <reason>` is exempt (genuine fixtures only).
"""
from __future__ import annotations

import io
import os
import re
import subprocess
import tokenize
from typing import List, Tuple

ALLOW_MARK = "lint-public: allow"
CODE_EXTS = (".gd", ".gdshader", ".gdshaderinc", ".py", ".ps1")

BEAD_ID = r"Bontago-(?!123\b)[a-z0-9]{3}(?:\.\d+)*\b"
DATE = r"\b20\d\d-\d\d-\d\d\b"
# Contexts that make the person word technical (slot X, exclusive X, X pid, ONE X, ...).
OWNER_BEFORE = r"(?<!slot )(?<!file )(?<!single )(?<!exclusive )(?<!gate )(?<!sole )(?<!class )(?<!its )(?<!process )" \
               r"(?<!concept )(?<!each )(?<!home )(?<!unique )(?<!lock )(?<!one )(?<!ONE )(?<!the single )(?<!static )"
OWNER_AFTER = r"(?![ \t]+(?:pid|PID|api|API|file|files|token|info|consumers|class|index|env|path)\b)"
OWNER = OWNER_BEFORE + r"\b[Oo]wner\b" + OWNER_AFTER

PRIVATE_TERMS_ENV = "STACKFALL_PRIVATE_TERMS"
# Words that are never personal names, so a generic home folder or git name cannot ban them.
_NOT_NAMES = frozenset(("user", "users", "admin", "administrator", "runner", "root", "home", "owner",
                        "default", "public", "guest", "claude", "stackfall"))


def private_terms() -> List[str]:
    """Personal names to keep out of tracked text, read from this machine so they are never written
    in the repo: the home folder name, the words of git `user.name`, and STACKFALL_PRIVATE_TERMS
    (comma-separated)."""
    terms = {os.path.basename(os.path.expanduser("~").rstrip("/\\"))}
    try:
        name = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True,
                              timeout=5).stdout
    except (OSError, subprocess.SubprocessError):
        name = ""
    terms.update(name.split())
    terms.update(t.strip() for t in os.environ.get(PRIVATE_TERMS_ENV, "").split(","))
    return sorted(t for t in terms if len(t) >= 3 and t.lower() not in _NOT_NAMES)


def _user_name_rule():
    terms = private_terms()
    if not terms:
        return ()
    pattern = r"\b(?:" + "|".join(re.escape(t) for t in terms) + r")\b"
    return (("user-name", re.compile(pattern, re.IGNORECASE), "all"),)


# (id, compiled regex, scope)
RULES: Tuple[Tuple[str, "re.Pattern[str]", str], ...] = (
    ("drive-path", re.compile(r"\b[A-Za-z]:(?:/(?!/)|\\(?![nrt]\b))"), "all"),
    *_user_name_rule(),
    ("bead-id", re.compile(BEAD_ID), "all"),
    ("date", re.compile(r"(?<!expires )" + DATE + r"(?!T\d)"), "all"),
    ("owner", re.compile(OWNER), "prose"),
    # Only the provenance tag forms: the word inside a parenthesised note, or followed by a date.
    # The session-close review step and its memory key are procedure, not provenance.
    ("debrief", re.compile(r"\([^)\n]*(?<![-\w])[Dd]ebrief\b[^)\n]*\)|(?<![-\w])[Dd]ebrief,? " + DATE), "prose"),
    ("incident", re.compile(r"\([^)\n]*(?<![-\w])[Ii]ncident\b[^)\n]*\)|(?<![-\w])[Ii]ncident,? " + DATE), "prose"),
)


def line_starts(text: str) -> List[int]:
    out = [0]
    for m in re.finditer("\n", text):
        out.append(m.end())
    return out


def _gd_mask(text: str, line_comment: str, block: bool) -> List[bool]:
    """Prose mask for GDScript/PowerShell/shader-like syntax: `#` or `//` comments, optional block
    comments, quoted strings skipped, triple-quoted strings that start a statement count as prose."""
    n = len(text)
    mask = [False] * n
    i = 0
    lc = line_comment
    while i < n:
        c = text[i]
        if text.startswith(lc, i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                mask[k] = True
            i = j
            continue
        if block and lc == "//" and text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                mask[k] = True
            i = j
            continue
        if block and lc == "#" and text.startswith("<#", i):
            j = text.find("#>", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                mask[k] = True
            i = j
            continue
        if c in "\"'":
            tri = text.startswith(c * 3, i)
            if tri:
                j = text.find(c * 3, i + 3)
                j = n if j < 0 else j + 3
                ls = text.rfind("\n", 0, i) + 1
                if text[ls:i].strip() == "" and lc == "#" and block is False:
                    for k in range(i, j):
                        mask[k] = True
                i = j
                continue
            j = i + 1
            while j < n and text[j] != "\n":
                if text[j] == "\\" and lc == "#" and not block:
                    j += 2
                    continue
                if text[j] == "`" and block and c == '"':
                    j += 2
                    continue
                if text[j] == c:
                    if block and c == "'" and text.startswith("''", j):
                        j += 2
                        continue
                    break
                j += 1
            i = j + 1
            continue
        i += 1
    return mask


def _py_mask(text: str) -> List[bool]:
    n = len(text)
    mask = [False] * n
    starts = line_starts(text)

    def off(pos: Tuple[int, int]) -> int:
        row, col = pos
        return min(n, starts[row - 1] + col) if row - 1 < len(starts) else n

    try:
        toks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return _gd_mask(text, "#", False)
    skip = {tokenize.NL, tokenize.COMMENT, tokenize.INDENT, tokenize.DEDENT, tokenize.ENCODING}
    prev_sig = tokenize.NEWLINE  # start of file counts as a statement start
    for idx, t in enumerate(toks):
        if t.type == tokenize.COMMENT:
            for k in range(off(t.start), off(t.end)):
                mask[k] = True
        elif t.type == tokenize.STRING:
            nxt = None
            for u in toks[idx + 1:]:
                if u.type not in (tokenize.NL, tokenize.COMMENT):
                    nxt = u.type
                    break
            if prev_sig == tokenize.NEWLINE and nxt in (tokenize.NEWLINE, tokenize.ENDMARKER, None):
                for k in range(off(t.start), off(t.end)):
                    mask[k] = True
        if t.type not in skip:
            prev_sig = t.type
    return mask


def prose_mask(path: str, text: str) -> List[bool]:
    """True for every character that is comment or docstring text (all True for non-code files)."""
    low = path.lower()
    if low.endswith(".py"):
        return _py_mask(text)
    if low.endswith(".gd"):
        return _gd_mask(text, "#", False)
    if low.endswith(".ps1"):
        return _gd_mask(text, "#", True)
    if low.endswith((".gdshader", ".gdshaderinc")):
        return _gd_mask(text, "//", True)
    return [True] * len(text)


def is_code(path: str) -> bool:
    return path.lower().endswith(CODE_EXTS)


def find_issues(path: str, text: str) -> List[Tuple[int, str, str]]:
    """[(line_number, rule_id, matched_text)] for every finding, skipping allow-marked lines."""
    mask = prose_mask(path, text)
    out: List[Tuple[int, str, str]] = []
    starts = line_starts(text)
    lines = text.split("\n")
    for ln, line in enumerate(lines, 1):
        if ALLOW_MARK in line:
            continue
        base = starts[ln - 1]
        for rid, rx, scope in RULES:
            for m in rx.finditer(line):
                if scope == "prose" and not (base + m.start() < len(mask) and mask[base + m.start()]):
                    continue
                out.append((ln, rid, m.group(0)))
    return out
