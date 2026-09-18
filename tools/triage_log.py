#!/usr/bin/env python
"""triage_log.py -- turn a long headless Godot log into a short, ranked summary.

Stackfall's headless runs (the GUT suite, `tests/bench/*.tscn` benchmarks, the
M3a multi-instance harness, and -- from M5 on -- long `--headless-host --bots=N`
soak tests) produce thousands of lines nobody reads end to end. This tool does
the cheap, deterministic part first and for free:

  1. Pull out every `ERROR:` / `WARNING:` / `SCRIPT ERROR:` / push_error-style
     line, together with its GDScript backtrace ("   at: func (file:line)").
  2. Normalise each one (strip timestamps, addresses, net/instance/peer ids,
     coordinate tuples) into a signature.
  3. Group identical signatures and count them.

That grouping step is where almost all of the value is, and it costs nothing.
Only the resulting handful of *distinct* signatures are optionally sent to
TypeSafe (see https://docs.typesafe.ai) for a semantic pass: which subsystem
they belong to, how severe they look, and whether they look novel. TypeSafe
never sees the raw, undeduplicated log.

Usage
-----
    python tools/triage_log.py path/to/log.txt
    godot ... 2>&1 | python tools/triage_log.py
    python tools/triage_log.py path/to/log.txt --json > triage.json

Requires ``TYPESAFE_API_KEY`` in the environment for the classification pass.
Without it (or if the TypeSafe API call fails for any reason -- network,
auth, rate limit, ...) the tool still prints the full deterministic grouped
summary; it just says classification was skipped. It never crashes and never
blocks network-wise on the deterministic half.

See tools/README.md for more on when and why to run this.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Sequence, Tuple

# --------------------------------------------------------------------------
# Constants (no magic numbers scattered through the logic below)
# --------------------------------------------------------------------------

TYPESAFE_API_URL = "https://api.typesafe.ai/v1/systemone"
TYPESAFE_MODEL = "jev-latest"
TYPESAFE_TIMEOUT_S = 30.0
# Token budget per TypeSafe request is ~32k tokens for state + longest
# question (docs/models.md). Keep each request to a handful of groups so a
# few long GDScript backtraces never risk blowing that budget.
DEFAULT_CHUNK_SIZE = 6
# Distinct signatures beyond this are still counted and shown in the
# deterministic summary, just not sent to the (paid) classifier.
DEFAULT_MAX_CLASSIFY = 40
# TypeSafe's own pricing snapshot (see docs/models.md, "Price (per Btok /
# per Mtok)"): $0.042 per 1,000,000 tokens combined input+output as of
# 2026-09. Used only to print an estimate; re-check docs.typesafe.ai/models
# if this drifts.
TYPESAFE_PRICE_PER_MTOK_USD = 0.042

SUBSYSTEMS = {
    "physics": "Jolt/RigidBody/CollisionShape behavior, falling, stacking, contacts.",
    "networking": "MultiplayerAPI, ENet/Steam transport, RPCs, replication, snapshots.",
    "territory-rules": "Territory raster, connectivity, contested cells, win check, block bag, MatchConfig/team logic.",
    "input": "Input Map actions, mouse/keyboard/gamepad handling, cursor/aim.",
    "ui": "HUD, menus, lobby, debug overlay, and other scene/UI code.",
    "test-harness": "GUT itself, .gutconfig, benchmark scaffolding, CI/import/bootstrap tooling.",
    "engine-noise": "Godot engine/editor boilerplate not caused by this project's code.",
    "other": "Doesn't clearly fit any subsystem above.",
}

SEVERITY_CHOICES = {
    "likely-bug": "A genuine, previously-unlabeled defect in project code that should be looked at.",
    "benign-noise": "Expected engine/test chatter with no bearing on correctness (e.g. editor import messages, harmless deprecation notices).",
    "known-limitation": "Matches a limitation the project has already documented and accepted (see known_limitations in the state) -- do not re-report it as a new bug.",
}

# Godot's own error/warning line markers. push_error()/push_warning() and
# unhandled GDScript exceptions all funnel through one of these three.
_RECORD_START_RE = re.compile(r"^(ERROR|WARNING|SCRIPT ERROR):\s?(.*)$")
# Backtrace continuation lines look like "   at: func_name (res://foo.gd:123)"
# (sometimes with a leading "[0]" stack index for nested calls).
_BACKTRACE_RE = re.compile(r"^\s*(\[\d+\]\s*)?at:\s")

# --- Normalisation patterns, applied in order --------------------------------
_NORMALIZERS: List[Tuple[re.Pattern, str]] = [
    # ISO-ish timestamps: 2026-09-18 12:34:56(.789)
    (re.compile(r"\b\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?\b"), "<TS>"),
    # Bracketed clock timestamps: [12:34:56] or [12:34:56.789]
    (re.compile(r"\[\d{1,2}:\d{2}:\d{2}(?:\.\d+)?\]"), "<TS>"),
    # Memory addresses / object pointers
    (re.compile(r"0x[0-9A-Fa-f]{4,}"), "<ADDR>"),
    # Godot ObjectID<...> / RID(...) wrappers
    (re.compile(r"\b(ObjectID|RID)<[^>]*>"), r"\1<<ID>>"),
    # net_id / peer_id / instance_id / client_id-style key=value pairs
    (
        re.compile(
            r"\b(net_id|peer_id|peer|instance_id|instance|client_id|rid|object_id)"
            r"\s*[:=]\s*-?\d+\b",
            re.IGNORECASE,
        ),
        r"\1=<ID>",
    ),
    # 2- or 3-component numeric tuples, e.g. Vector coordinates: (1.2, -3, 4.5)
    (
        re.compile(r"\(\s*-?\d+(?:\.\d+)?\s*(?:,\s*-?\d+(?:\.\d+)?\s*){1,2}\)"),
        "<VEC>",
    ),
    # Any remaining standalone float (positions, deltas, timings, ...)
    (re.compile(r"-?\d+\.\d+"), "<NUM>"),
]


@dataclass
class ErrorRecord:
    marker: str  # "ERROR" | "WARNING" | "SCRIPT ERROR"
    message: str
    backtrace: List[str] = field(default_factory=list)
    line_no: int = 0

    @property
    def raw(self) -> str:
        lines = [f"{self.marker}: {self.message}"]
        lines.extend(self.backtrace)
        return "\n".join(lines)


@dataclass
class Group:
    signature: str  # normalised text used as the display/matching key
    marker: str
    representative: ErrorRecord
    count: int = 0
    first_line_no: int = 0
    # Filled in by classification (deterministic or TypeSafe). None means
    # "not yet judged".
    subsystem: Optional[str] = None
    subsystem_confidence: Optional[float] = None
    severity: Optional[str] = None
    severity_confidence: Optional[float] = None
    novel: Optional[float] = None  # probability from Noul, or None
    classification_source: str = "none"  # "typesafe" | "heuristic" | "known-limitation" | "none"
    matched_limitation: Optional[str] = None


# --------------------------------------------------------------------------
# Step 1: deterministic extraction
# --------------------------------------------------------------------------


def extract_records(text: str) -> List[ErrorRecord]:
    """Pull ERROR:/WARNING:/SCRIPT ERROR: lines and their backtraces out of a
    raw log. This is pure string processing -- no network, no model calls."""
    lines = text.splitlines()
    records: List[ErrorRecord] = []
    i = 0
    n = len(lines)
    while i < n:
        m = _RECORD_START_RE.match(lines[i])
        if not m:
            i += 1
            continue
        marker, message = m.group(1), m.group(2)
        line_no = i + 1
        i += 1
        backtrace: List[str] = []
        while i < n and _BACKTRACE_RE.match(lines[i]):
            backtrace.append(lines[i].strip())
            i += 1
        records.append(
            ErrorRecord(marker=marker, message=message, backtrace=backtrace, line_no=line_no)
        )
    return records


def normalize(record: ErrorRecord) -> str:
    """Collapse timestamps/addresses/ids/coordinates so that repeats of "the
    same" error (different peer, different tick, different position) share a
    signature."""
    text = record.marker + ": " + record.message
    if record.backtrace:
        text += "\n" + "\n".join(record.backtrace)
    for pattern, replacement in _NORMALIZERS:
        text = pattern.sub(replacement, text)
    return re.sub(r"\s+", " ", text).strip()


def group_records(records: Sequence[ErrorRecord]) -> List[Group]:
    groups: Dict[str, Group] = {}
    order: List[str] = []
    for record in records:
        sig = normalize(record)
        if sig not in groups:
            groups[sig] = Group(
                signature=sig,
                marker=record.marker,
                representative=record,
                first_line_no=record.line_no,
            )
            order.append(sig)
        groups[sig].count += 1
    return [groups[sig] for sig in order]


# --------------------------------------------------------------------------
# Known limitations: read from docs at runtime instead of hard-coding them.
# --------------------------------------------------------------------------


@dataclass
class KnownLimitation:
    text: str  # full paragraph, for the TypeSafe state
    keywords: List[str]  # backticked identifiers pulled out of the paragraph


def load_known_limitations(plan_path: str) -> List[KnownLimitation]:
    """Parse the "## Known limitations (...)" section of a milestone plan doc
    (e.g. docs/M2_PLAN.md) into paragraphs, and pull out any `backticked`
    identifiers as cheap deterministic match keywords."""
    try:
        with open(plan_path, "r", encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return []

    lines = text.splitlines()
    section: List[str] = []
    in_section = False
    for line in lines:
        if re.match(r"^#{1,3}\s*Known limitations", line, re.IGNORECASE):
            in_section = True
            continue
        if in_section and re.match(r"^#{1,3}\s", line):
            break
        if in_section:
            section.append(line)

    section_text = "\n".join(section)
    # Paragraphs are separated by one or more blank lines.
    paragraphs = [p.strip() for p in re.split(r"\n\s*\n", section_text) if p.strip()]

    limitations: List[KnownLimitation] = []
    for para in paragraphs:
        raw_keywords = re.findall(r"`([^`]+)`", para)
        keywords = [kw for kw in raw_keywords if _is_specific_keyword(kw)]
        limitations.append(KnownLimitation(text=para, keywords=keywords))
    return limitations


def _is_specific_keyword(keyword: str) -> bool:
    """A bare class name like `MatchConfig` or `CellGrid` is used all over
    this codebase for unrelated reasons, so matching on it alone produces
    false positives (verified against a real broken-import log: it flagged
    "class not found" parse errors from a totally different cause as the
    documented M2 known limitations). Only trust an identifier as a
    deterministic, free match when it is specific: a dotted path
    (`MatchConfig.TeamMode`), a function call (`team_count()`), a file path,
    a snake_case field/test name (`cell_overlap`, has an underscore), or a
    multi-word phrase. Bare single CamelCase/lowercase tokens are dropped
    here; TypeSafe's semantic pass (when available) still gets the full
    paragraph text and can catch those cases with real judgment instead of
    a brittle string match.
    """
    return any(ch in keyword for ch in ("_", ".", "(", "/", " "))


def find_pending_test_names(tests_dir: str) -> List[str]:
    """Scan GUT test files for functions that call pending(...) somewhere in
    their body, so the tool recognises tests the project has *already*
    marked as a known, accepted failure -- without hard-coding test names."""
    names: List[str] = []
    if not os.path.isdir(tests_dir):
        return names
    func_re = re.compile(r"^func\s+(test_\w+)\s*\(")
    for root, _dirs, files in os.walk(tests_dir):
        for fname in files:
            if not fname.endswith(".gd"):
                continue
            path = os.path.join(root, fname)
            try:
                with open(path, "r", encoding="utf-8") as f:
                    file_lines = f.readlines()
            except OSError:
                continue
            current_name: Optional[str] = None
            current_body: List[str] = []
            for line in file_lines + ["func __sentinel__():"]:
                m = func_re.match(line)
                if m:
                    if current_name and any("pending(" in bl for bl in current_body):
                        names.append(current_name)
                    current_name = m.group(1)
                    current_body = []
                else:
                    current_body.append(line)
    return names


def match_known_limitation(
    group: Group, limitations: Sequence[KnownLimitation], pending_tests: Sequence[str]
) -> Optional[KnownLimitation]:
    """Cheap, free, deterministic pre-check: does this group's raw text
    literally mention a documented limitation's identifiers, or a test the
    project has already marked pending()? If so, we don't need to spend a
    TypeSafe call on it at all."""
    haystack = group.representative.raw
    for name in pending_tests:
        if name in haystack:
            for limitation in limitations:
                # best-effort: prefer a limitation that also names this test
                if name in limitation.text:
                    return limitation
            # No specific paragraph names it, but it's still a pending test.
            return KnownLimitation(text=f"Test `{name}` is marked pending().", keywords=[name])
    for limitation in limitations:
        for kw in limitation.keywords:
            if kw and kw in haystack:
                return limitation
    return None


# --------------------------------------------------------------------------
# Cheap deterministic subsystem heuristic (used as a fallback, and to avoid
# spending an API call on groups already resolved as known-limitations).
# --------------------------------------------------------------------------

_SUBSYSTEM_KEYWORDS: Dict[str, List[str]] = {
    "physics": ["rigidbody", "jolt", "collisionshape", "physics", "contact", "rigid_body", "boxshape"],
    "networking": ["multiplayer", "rpc", "enet", "steam", "peer", "net_id", "replicat", "snapshot"],
    "territory-rules": [
        "territory", "cellgrid", "field", "blockbag", "matchconfig", "winchecker",
        "influencecircle", "hole", "contested", "teammode",
    ],
    "input": ["input", "gamepad", "joypad", "cursor", "inputmap"],
    "ui": ["hud", "menu", "lobby", "debugoverlay", "control.gd", "ui/"],
    "test-harness": ["gut", "bench_", "gutconfig", "class_names", "import", "gdunit"],
}


def heuristic_subsystem(group: Group) -> str:
    haystack = group.representative.raw.lower()
    for subsystem, keywords in _SUBSYSTEM_KEYWORDS.items():
        if any(kw in haystack for kw in keywords):
            return subsystem
    return "engine-noise" if "godot" in haystack or "core/" in haystack else "other"


# --------------------------------------------------------------------------
# Step 2: TypeSafe classification (optional, deduplicated set only)
# --------------------------------------------------------------------------


class TypeSafeUnavailable(Exception):
    """Raised internally to signal "skip classification", never escapes
    classify_groups()."""


def _typesafe_request(payload: Dict[str, Any], api_key: str, timeout: float) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        TYPESAFE_API_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:500]
        raise TypeSafeUnavailable(f"HTTP {e.code} from TypeSafe: {detail}") from e
    except urllib.error.URLError as e:
        raise TypeSafeUnavailable(f"could not reach TypeSafe API: {e.reason}") from e
    except (TimeoutError, OSError) as e:
        raise TypeSafeUnavailable(f"TypeSafe request timed out or failed: {e}") from e
    except json.JSONDecodeError as e:
        raise TypeSafeUnavailable(f"TypeSafe returned unparsable JSON: {e}") from e


@dataclass
class ClassifyStats:
    calls: int = 0
    input_tokens: int = 0
    output_tokens: int = 0
    skipped_reason: Optional[str] = None


def classify_groups(
    groups: Sequence[Group],
    limitations: Sequence[KnownLimitation],
    api_key: Optional[str],
    chunk_size: int,
    max_classify: int,
    model: str,
    timeout: float,
) -> ClassifyStats:
    """Send only the deduplicated groups to TypeSafe, a handful of Choice/
    Noul questions per group, batched several groups to a request (the
    Parallel questions cookbook: batching is far cheaper and faster than one
    call per item, with no change in answers). Mutates each Group in place.

    Never raises: any failure degrades to classification_source == "none"
    on the still-unclassified groups, with stats.skipped_reason explaining
    why.
    """
    stats = ClassifyStats()

    # Deterministic known-limitation pass first -- free, and it also keeps
    # those groups out of the (paid) TypeSafe batch below.
    pending_tests = find_pending_test_names(os.path.join(_project_root(), "tests"))
    for group in groups:
        hit = match_known_limitation(group, limitations, pending_tests)
        if hit is not None:
            group.severity = "known-limitation"
            group.severity_confidence = 1.0
            group.subsystem = heuristic_subsystem(group)
            group.subsystem_confidence = None
            group.novel = 0.0
            group.classification_source = "known-limitation"
            group.matched_limitation = hit.text

    remaining = [g for g in groups if g.classification_source == "none"]

    if not api_key:
        stats.skipped_reason = "TYPESAFE_API_KEY is not set"
        return stats

    to_classify = remaining[:max_classify]
    if len(remaining) > max_classify:
        # The rest stay deterministic-only; still shown, just not judged.
        pass

    limitations_state = [lim.text for lim in limitations] or [
        "(none documented yet)"
    ]

    for chunk_start in range(0, len(to_classify), chunk_size):
        chunk = to_classify[chunk_start : chunk_start + chunk_size]
        if not chunk:
            continue
        state: Dict[str, Any] = {
            "known_limitations": limitations_state,
            "groups": {},
        }
        questions: Dict[str, Any] = {}
        for idx, group in enumerate(chunk):
            key = f"g{idx}"
            state["groups"][key] = {
                "marker": group.marker,
                "occurrence_count_in_log": group.count,
                "representative_message": group.representative.message,
                "backtrace": group.representative.backtrace,
            }
            questions[f"{key}_subsystem"] = {
                "type": "choice",
                "instructions": (
                    f"Which subsystem of the Stackfall game does `groups.{key}` belong to?"
                ),
                "criteria": SUBSYSTEMS,
            }
            questions[f"{key}_severity"] = {
                "type": "choice",
                "instructions": (
                    f"How severe is `groups.{key}`? Check it against `known_limitations` "
                    "first -- if it matches one of those, it is known-limitation, not "
                    "likely-bug, even if it looks bad."
                ),
                "criteria": SEVERITY_CHOICES,
            }
            questions[f"{key}_novel"] = {
                "type": "noul",
                "instructions": (
                    f"Does `groups.{key}` look like a genuinely new kind of problem -- "
                    "not routine engine/test-harness noise, and not one of the "
                    "`known_limitations`?"
                ),
            }

        payload = {"model": model, "state": state, "questions": questions}
        try:
            response = _typesafe_request(payload, api_key, timeout)
        except TypeSafeUnavailable as e:
            stats.skipped_reason = str(e)
            # Leave this chunk (and everything after it) unclassified rather
            # than guessing; the deterministic summary still stands.
            for group in chunk:
                group.subsystem = group.subsystem or heuristic_subsystem(group)
            break

        stats.calls += 1
        usage = response.get("usage", {}) or {}
        stats.input_tokens += int(usage.get("input_tokens", 0) or 0)
        stats.output_tokens += int(usage.get("output_tokens", 0) or 0)
        answers = response.get("answers", {}) or {}

        for idx, group in enumerate(chunk):
            key = f"g{idx}"
            subsystem_ans = answers.get(f"{key}_subsystem", {})
            severity_ans = answers.get(f"{key}_severity", {})
            novel_ans = answers.get(f"{key}_novel", {})

            if "choice" in subsystem_ans:
                group.subsystem = subsystem_ans["choice"]
                group.subsystem_confidence = subsystem_ans.get("confidence")
            else:
                group.subsystem = heuristic_subsystem(group)

            if "choice" in severity_ans:
                group.severity = severity_ans["choice"]
                group.severity_confidence = severity_ans.get("confidence")

            if "noul" in novel_ans:
                group.novel = novel_ans["noul"]

            group.classification_source = "typesafe"

    # Anything past max_classify, or left over after a failed chunk, still
    # gets a free heuristic subsystem guess so the summary is never empty.
    for group in groups:
        if group.subsystem is None:
            group.subsystem = heuristic_subsystem(group)

    return stats


def _project_root() -> str:
    # tools/triage_log.py -> repo root is its parent directory.
    return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# --------------------------------------------------------------------------
# Ranking + rendering
# --------------------------------------------------------------------------

_SEVERITY_RANK = {
    "likely-bug": 0,
    None: 1,  # unclassified -- treat as "needs a human look" too
    "benign-noise": 2,
    "known-limitation": 3,
}


def rank_key(group: Group) -> Tuple[int, float, int]:
    severity_rank = _SEVERITY_RANK.get(group.severity, 1)
    novel_rank = -(group.novel or 0.0)
    return (severity_rank, novel_rank, -group.count)


def confidence_note(confidence: Optional[float]) -> str:
    if confidence is None:
        return ""
    if confidence < 0.5:
        return " (low confidence -- verify manually)"
    return ""


def render_text(groups: Sequence[Group], stats: ClassifyStats, total_records: int, source_desc: str) -> str:
    out: List[str] = []
    out.append("=== Stackfall log triage ===")
    out.append(f"source: {source_desc}")
    out.append(f"error/warning records matched: {total_records}  distinct signatures: {len(groups)}")
    if stats.skipped_reason:
        out.append(f"classification: SKIPPED ({stats.skipped_reason}) -- deterministic grouping only below")
    elif stats.calls == 0:
        out.append("classification: nothing to classify (no new signatures, or all matched known limitations)")
    else:
        cost = (stats.input_tokens + stats.output_tokens) / 1_000_000 * TYPESAFE_PRICE_PER_MTOK_USD
        out.append(
            f"classification: TypeSafe ({TYPESAFE_MODEL}), {stats.calls} call(s), "
            f"{stats.input_tokens} in / {stats.output_tokens} out tokens (~${cost:.4f})"
        )
    out.append("")

    ranked = sorted(groups, key=rank_key)
    for i, g in enumerate(ranked, start=1):
        severity = g.severity or "unclassified"
        tag = severity.upper()
        novel_tag = ""
        if g.novel is not None and g.novel >= 0.7:
            novel_tag = "  NOVEL"
        subsystem_str = g.subsystem or "?"
        subsystem_conf = confidence_note(g.subsystem_confidence)
        severity_conf = confidence_note(g.severity_confidence)
        out.append(
            f"#{i}  [{tag}]{novel_tag}  subsystem={subsystem_str}{subsystem_conf}  "
            f"count={g.count}  first_line={g.first_line_no}  source={g.classification_source}"
        )
        if severity_conf:
            out.append(f"    severity confidence note:{severity_conf}")
        if g.matched_limitation:
            out.append(f"    matches known limitation: {g.matched_limitation[:160]}...")
        out.append(f"    {g.marker}: {g.representative.message}")
        for bt in g.representative.backtrace[:3]:
            out.append(f"      {bt}")
        if len(g.representative.backtrace) > 3:
            out.append(f"      ... ({len(g.representative.backtrace) - 3} more backtrace line(s))")
        out.append("")

    if not ranked:
        out.append("No ERROR/WARNING/SCRIPT ERROR records found. Clean run.")

    return "\n".join(out)


def to_jsonable(groups: Sequence[Group], stats: ClassifyStats, total_records: int, source_desc: str) -> Dict[str, Any]:
    ranked = sorted(groups, key=rank_key)
    return {
        "source": source_desc,
        "total_error_records": total_records,
        "distinct_signatures": len(groups),
        "classification": {
            "skipped_reason": stats.skipped_reason,
            "calls": stats.calls,
            "input_tokens": stats.input_tokens,
            "output_tokens": stats.output_tokens,
        },
        "groups": [
            {
                "rank": i,
                "marker": g.marker,
                "count": g.count,
                "first_line": g.first_line_no,
                "subsystem": g.subsystem,
                "subsystem_confidence": g.subsystem_confidence,
                "severity": g.severity,
                "severity_confidence": g.severity_confidence,
                "novel_probability": g.novel,
                "classification_source": g.classification_source,
                "matched_known_limitation": g.matched_limitation,
                "representative_message": g.representative.message,
                "backtrace": g.representative.backtrace,
            }
            for i, g in enumerate(ranked, start=1)
        ],
    }


# --------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Deduplicate and (optionally) classify errors/warnings in a Godot headless run log.",
    )
    parser.add_argument(
        "log_path",
        nargs="?",
        default=None,
        help="Path to a log file. Reads stdin if omitted.",
    )
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of text.")
    parser.add_argument(
        "--limitations-doc",
        default=os.path.join("docs", "M2_PLAN.md"),
        help="Milestone plan doc to read the 'Known limitations' section from (default: docs/M2_PLAN.md).",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=DEFAULT_CHUNK_SIZE,
        help=f"Groups per TypeSafe request (default: {DEFAULT_CHUNK_SIZE}).",
    )
    parser.add_argument(
        "--max-classify",
        type=int,
        default=DEFAULT_MAX_CLASSIFY,
        help=f"Max distinct signatures to send to TypeSafe (default: {DEFAULT_MAX_CLASSIFY}); "
        "the rest still appear in the summary, just unclassified.",
    )
    parser.add_argument("--model", default=TYPESAFE_MODEL, help=f"TypeSafe model (default: {TYPESAFE_MODEL}).")
    parser.add_argument(
        "--timeout", type=float, default=TYPESAFE_TIMEOUT_S, help="Per-request timeout in seconds."
    )
    parser.add_argument(
        "--no-classify", action="store_true", help="Skip TypeSafe entirely; deterministic grouping only."
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)

    if args.log_path:
        source_desc = args.log_path
        try:
            with open(args.log_path, "r", encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            print(f"triage_log: could not read {args.log_path}: {e}", file=sys.stderr)
            return 2
    else:
        source_desc = "<stdin>"
        text = sys.stdin.read()

    records = extract_records(text)
    groups = group_records(records)

    limitations_path = args.limitations_doc
    if not os.path.isabs(limitations_path):
        limitations_path = os.path.join(_project_root(), limitations_path)
    limitations = load_known_limitations(limitations_path)

    api_key = None if args.no_classify else os.environ.get("TYPESAFE_API_KEY")
    stats = classify_groups(
        groups,
        limitations,
        api_key,
        chunk_size=max(1, args.chunk_size),
        max_classify=max(0, args.max_classify),
        model=args.model,
        timeout=args.timeout,
    )
    if args.no_classify and stats.skipped_reason is None:
        stats.skipped_reason = "--no-classify was passed"

    if args.json:
        print(json.dumps(to_jsonable(groups, stats, len(records), source_desc), indent=2))
    else:
        print(render_text(groups, stats, len(records), source_desc))

    any_likely_bug = any(g.severity == "likely-bug" for g in groups)
    return 1 if any_likely_bug else 0


if __name__ == "__main__":
    sys.exit(main())
