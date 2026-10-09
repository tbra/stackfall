#!/usr/bin/env python3
"""Ask TypeSafe/Jev which Claude model a Stackfall work package should run on.

Owner decision 2026-09-22: consult Jev before every dispatch instead of guessing.
Jev is a System One model: it returns a typed Choice with a probability per
option and a confidence, not prose. Code owns the policy (thresholds below);
Jev supplies the judgement about the brief.

Usage (the brief comes from stdin so long text is safe):

    python tools/route_model.py --title "Fix X" --files autoload/Match.gd,tests/... \\
        --kind bugfix < brief.txt
    cat brief.txt | python tools/route_model.py --title "..." --json

Prints a one-line verdict (or JSON with --json): model, review, split and
verification tier, with a bounded visual-probe recommendation. Code keeps
hard review and probe policy. Obvious mechanical and known-gate work uses
rules without a network call. Other work falls back to rules when needed.

Requires TYPESAFE_API_KEY (user environment). Same HTTP contract as
tools/triage_log.py (POST https://api.typesafe.ai/v1/systemone).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional

TYPESAFE_API_URL = "https://api.typesafe.ai/v1/systemone"
TYPESAFE_MODEL = "jev-latest"
TIMEOUT_S = 8.0

MODELS: Dict[str, str] = {
    "haiku": (
        "Mechanical, fully specified work with a known recipe and a checkable result: "
        "running named commands and reporting output, ranking or grouping logs, "
        "one-line wiring whose exact location and content are given, renaming, "
        "regenerating generated files. No design judgement, no debugging."
    ),
    "sonnet": (
        "Normal implementation, netcode, UI, tests and review: a bounded package with "
        "clear ownership where the worker reads existing code, writes typed GDScript "
        "and tests, reproduces a bug, or reviews a diff. Includes multi-file features "
        "and refactors with unchanged behaviour."
    ),
    "opus": (
        "Genuinely hard, bounded reasoning where several invariants interact and a "
        "plausible-looking implementation would be subtly wrong: new core rule "
        "algorithms whose output must stay byte-identical on another path, wire-format "
        "or replication changes with backward compatibility, physics/collision "
        "geometry redesigns, or a bug that already defeated a Sonnet attempt."
    ),
}

CORE_PATH_PREFIXES = ("core/", "net/", "autoload/", "shaders/")
SPECIALIZED_PATH_PREFIXES = ("net/", "autoload/", "core/territory", "tests/bench/")
VERIFICATION_TIERS = {
    "quick": "Documentation, generated files or mechanical edits: inspect the diff or run one quick check; no game launch.",
    "targeted": "Local behavior or UI change: run only the named affected tests, at most one retry after a fix.",
    "specialized": "Network, physics, territory or wire behavior: named targeted tests plus one relevant harness or isolated benchmark.",
}


MEMORY_MAX_KEYWORDS = 4
MEMORY_MIN_WORD_LEN = 5
MEMORY_MAX_KEYS = 5
MEMORY_CALL_TIMEOUT_S = 5.0
MEMORY_TOTAL_TIMEOUT_S = 15.0
# Session-note memories that match nearly every query; never informative.
MEMORY_EXCLUDED_KEYS = ("stackfall-handoff", "stackfall-debrief")
MEMORY_STOPWORDS = frozenset(
    "about after again before being could every first fixesharden other should "
    "their there these those through under until using where which while without would "
    "should update README tools tests there".split()
)
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def extract_keywords(title: str, limit: int = MEMORY_MAX_KEYWORDS) -> List[str]:
    """Salient lowercase words from a title: long, non-numeric, not stopwords, not bead ids."""
    seen: List[str] = []
    candidates: List[str] = []
    for word in re.findall(r"[A-Za-z0-9][A-Za-z0-9_-]*", title):
        candidates.append(word)
        # DECISION: also try CamelCase parts (StartupPump -> Startup) since memories use prose.
        candidates.extend(re.findall(r"[A-Z][a-z]+", word) if re.search(r"[a-z][A-Z]", word) else [])
    for word in candidates:
        w = word.lower()
        if len(w) < MEMORY_MIN_WORD_LEN or w in MEMORY_STOPWORDS or w in seen:
            continue
        if w.isdigit() or re.fullmatch(r"bontago-[a-z0-9.]+", w):
            continue
        seen.append(w)
    # Prefer longer (rarer) words; stable for ties so title order breaks them.
    seen.sort(key=lambda w: -len(w))
    return seen[:limit]


def parse_memory_keys(output: str) -> List[str]:
    """Keys from `bd memories` output: indented key lines followed by a deeper summary line."""
    keys: List[str] = []
    expect_key = True
    for line in output.splitlines():
        if line.startswith("Memories matching"):
            continue
        if not line.strip():
            expect_key = True
            continue
        if expect_key:
            key = line.strip()
            # A key line is indented and a single token; anything else (e.g. the
            # 'No memories matching "x"' notice) is not a key.
            if line[:1].isspace() and not any(ch.isspace() for ch in key):
                keys.append(key)
            expect_key = False
    return keys


def _run_bd_memories(keyword: str, timeout: float) -> str:
    exe = shutil.which("bd")  # resolves npm .cmd shims on Windows
    if not exe:
        return ""
    proc = subprocess.run(
        [exe, "memories", keyword], cwd=REPO_ROOT, capture_output=True, text=True, timeout=timeout, check=False
    )
    return proc.stdout if proc.returncode == 0 else ""


def find_memories(title: str, runner: Any = None) -> List[str]:
    """Memory keys matching the title's keywords. Never raises; failures mean no hits."""
    run = runner or _run_bd_memories
    keys: List[str] = []
    deadline = time.monotonic() + MEMORY_TOTAL_TIMEOUT_S
    for kw in extract_keywords(title):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            out = run(kw, min(MEMORY_CALL_TIMEOUT_S, remaining))
        except Exception:  # missing bd, timeout, OS error: advisory only
            continue
        for key in parse_memory_keys(out or ""):
            if key not in MEMORY_EXCLUDED_KEYS and key not in keys:
                keys.append(key)
    return keys[:MEMORY_MAX_KEYS]


def _request(payload: Dict[str, Any], api_key: str) -> Dict[str, Any]:
    body = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        TYPESAFE_API_URL,
        data=body,
        method="POST",
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _fallback(files: List[str], kind: str, brief: str) -> Dict[str, Any]:
    touches_core = any(f.startswith(CORE_PATH_PREFIXES) for f in files)
    mechanical = kind in ("gate", "triage", "mechanical", "docs", "documentation")
    hard_words = ("wire", "replicat", "byte-identical", "argmax", "invariant", "collision", "trimesh")
    hard = touches_core and any(w in brief.lower() for w in hard_words)
    model = "haiku" if mechanical else ("opus" if hard else "sonnet")
    specialized = any(f.startswith(SPECIALIZED_PATH_PREFIXES) for f in files)
    tier = "quick" if mechanical or kind in ("docs", "documentation") else ("specialized" if specialized else "targeted")
    visual = tier != "quick" and any(f.startswith(("ui/", "scenes/", "shaders/")) for f in files)
    return {
        "source": "fallback-rules",
        "model": model,
        "probabilities": {model: 1.0},
        "confidence": None,
        "needs_review": touches_core,
        "split_first": len(files) > 10,
        "verification_tier": tier,
        "visual_probe_recommended": visual,
        "max_targeted_runs": 0 if tier == "quick" else 2,
        "max_windowed_probes": None,  # owner 2026-10-07: no fixed probe cap
        "reason": "TYPESAFE_API_KEY missing or API unreachable; deterministic rules applied",
    }


def route(title: str, brief: str, files: List[str], kind: str, prior_attempts: int) -> Dict[str, Any]:
    if kind in ("gate", "triage", "mechanical", "docs", "documentation") and prior_attempts == 0:
        result = _fallback(files, kind, brief)
        result["reason"] = "Deterministic fast path for known or mechanical work"
        return result
    api_key = os.environ.get("TYPESAFE_API_KEY", "")
    if not api_key:
        return _fallback(files, kind, brief)
    state = {
        "task": {
            "title": title,
            "kind": kind,
            "brief": brief[:12000],
            "owned_files": files,
            "owned_file_count": len(files),
            "touches_core_net_autoload_or_shaders": any(f.startswith(CORE_PATH_PREFIXES) for f in files),
            "prior_failed_attempts_on_a_cheaper_model": prior_attempts,
        },
        "project_rules": (
            "Stackfall is a Godot 4.7 GDScript game built by an orchestrator dispatching "
            "bounded packages to Claude workers. Sonnet is the default worker. Haiku is only "
            "for mechanical, fully specified work. Opus is reserved for bounded, genuinely "
            "hard reasoning with interacting invariants and must be justified. Packages "
            "should own at most about ten files and take about thirty minutes."
        ),
    }
    questions = {
        "model": {
            "type": "choice",
            "instructions": (
                "Which Claude model tier should implement `task` given `project_rules`? "
                "Judge the reasoning difficulty of the brief and the risk that a plausible "
                "implementation is subtly wrong, not the amount of typing. A prior failed "
                "attempt on a cheaper model argues for the next tier up."
            ),
            "criteria": MODELS,
        },
        "needs_review": {
            "type": "noul",
            "instructions": (
                "Does `task` warrant an independent read-only review after implementation? "
                "Yes when it changes rules, host authority, replication/wire formats, physics "
                "or anything under core/, net/, autoload/ or shaders/; no for UI, tooling, "
                "documentation and test-only changes."
            ),
        },
        "split_first": {
            "type": "noul",
            "instructions": (
                "Is `task` too large for one package (more than one distinct outcome, more "
                "than about ten owned files, or likely well over thirty minutes of work) so "
                "that it should be split before dispatch?"
            ),
        },
        "verification_tier": {
            "type": "choice",
            "instructions": (
                "Which bounded verification tier fits `task`? Choose by the behavior changed, "
                "not by the number of files. Actual test names, run limits and acceptance "
                "remain code and orchestrator policy."
            ),
            "criteria": VERIFICATION_TIERS,
        },
        "visual_probe": {
            "type": "noul",
            "instructions": (
                "Does verifying `task` require observing rendered or animated behavior "
                "that named headless tests and code inspection cannot establish? "
                "Do not recommend a screenshot merely because UI files are touched."
            ),
        },
    }
    payload = {"model": TYPESAFE_MODEL, "state": state, "questions": questions}
    try:
        response = _request(payload, api_key)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, OSError, json.JSONDecodeError) as e:
        result = _fallback(files, kind, brief)
        result["reason"] = f"TypeSafe unavailable ({e}); deterministic rules applied"
        return result
    answers = response.get("answers", {}) or {}
    model_ans = answers.get("model", {}) or {}
    chosen = str(model_ans.get("choice", "sonnet"))
    probabilities = model_ans.get("distribution") or model_ans.get("probabilities") or {}
    confidence = model_ans.get("confidence")
    # A Noul answer carries its probability of "yes" under the key "noul".
    review_p = float((answers.get("needs_review", {}) or {}).get("noul", 0.0) or 0.0)
    split_p = float((answers.get("split_first", {}) or {}).get("noul", 0.0) or 0.0)
    tier_ans = answers.get("verification_tier", {}) or {}
    tier = str(tier_ans.get("choice", "targeted"))
    if tier not in VERIFICATION_TIERS:
        tier = "targeted"
    if any(f.startswith(SPECIALIZED_PATH_PREFIXES) for f in files):
        tier = "specialized"
    visual_p = float((answers.get("visual_probe", {}) or {}).get("noul", 0.0) or 0.0)
    visual_scope = any(f.startswith(("ui/", "scenes/", "shaders/")) for f in files) or any(
        word in brief.lower() for word in ("visual", "animation", "screenshot", "hud")
    )
    visual = visual_p >= 0.7 and visual_scope and tier != "quick"
    # Policy lives here, not in the model: a low-confidence Opus pick costs real
    # money, so require confidence >= 0.6 to escalate; otherwise fall to Sonnet.
    if chosen == "opus" and (confidence is None or float(confidence) < 0.6):
        chosen = "sonnet"
    return {
        "source": response.get("model", TYPESAFE_MODEL),
        "model": chosen,
        "probabilities": probabilities,
        "confidence": confidence,
        "needs_review": review_p >= 0.5 or any(f.startswith(CORE_PATH_PREFIXES) for f in files),
        "needs_review_probability": review_p,
        "split_first": split_p >= 0.5,
        "split_first_probability": split_p,
        "verification_tier": tier,
        "visual_probe_recommended": visual,
        "visual_probe_probability": visual_p,
        "max_targeted_runs": 0 if tier == "quick" else 2,
        "max_windowed_probes": None,  # owner 2026-10-07: no fixed probe cap
        "usage": response.get("usage", {}),
        "reason": "Jev judgement; opus requires confidence >= 0.6",
    }


def main(argv: Optional[List[str]] = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--title", required=True)
    ap.add_argument("--files", default="", help="comma-separated owned files")
    ap.add_argument("--kind", default="feature", help="feature|bugfix|refactor|review|gate|triage|mechanical|plan")
    ap.add_argument("--prior-attempts", type=int, default=0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-memories", action="store_true", help="skip the bd memories lookup (offline/tests)")
    args = ap.parse_args(argv)
    brief = sys.stdin.read() if not sys.stdin.isatty() else ""
    files = [f.strip() for f in args.files.split(",") if f.strip()]
    result = route(args.title, brief, files, args.kind, args.prior_attempts)
    memories = [] if args.no_memories else find_memories(args.title)
    result["memories"] = memories
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        probs = result.get("probabilities") or {}
        prob_text = " ".join(f"{k}={float(v):.2f}" for k, v in sorted(probs.items())) if isinstance(probs, dict) else ""
        print(
            f"model={result['model']} confidence={result.get('confidence')} {prob_text} "
            f"review={'yes' if result['needs_review'] else 'no'} split={'yes' if result['split_first'] else 'no'} "
            f"verify={result['verification_tier']} visual={'yes' if result['visual_probe_recommended'] else 'no'} "
            f"source={result['source']}"
        )
        if not args.no_memories:
            if memories:
                print(f"memories: {', '.join(memories)} (bd memories <key> to read)")
            else:
                print("memories: none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
