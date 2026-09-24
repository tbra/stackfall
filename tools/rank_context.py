#!/usr/bin/env python3
"""Rank a small Beads issue or memory shortlist against a new task.

Input JSON on stdin: {"query":"...","candidates":[{"id":"...","text":"..."}]}.
The caller retrieves candidates with bd search / bd memories; this tool never
reads or mutates the board. It returns one candidate or no_match as JSON.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, List

API_URL = "https://api.typesafe.ai/v1/systemone"
MAX_CANDIDATES = 10


def rank(query: str, candidates: List[Dict[str, str]]) -> Dict[str, Any]:
    if not query.strip() or not candidates:
        return {"choice": "no_match", "source": "empty-shortlist"}
    shortlist = candidates[:MAX_CANDIDATES]
    ids = [str(item["id"]) for item in shortlist]
    if len(set(ids)) != len(ids) or "no_match" in ids:
        raise ValueError("Candidate IDs must be unique and cannot be no_match")
    terms = set(query.lower().split())
    fallback = max(shortlist, key=lambda item: len(terms & set(str(item["text"]).lower().split())))
    fallback_score = len(terms & set(str(fallback["text"]).lower().split()))
    fallback_choice = str(fallback["id"]) if fallback_score else "no_match"
    key = os.environ.get("TYPESAFE_API_KEY", "")
    if not key:
        return {"choice": fallback_choice, "source": "keyword-fallback"}
    state = {
        "task": query[:1500],
        "candidates": [{"id": str(item["id"]), "text": str(item["text"])[:500]} for item in shortlist],
    }
    criteria = {str(item["id"]): str(item["text"])[:500] for item in shortlist}
    criteria["no_match"] = "None of these candidates is relevant enough to reuse or treat as a duplicate."
    payload = {
        "model": "jev-latest",
        "state": state,
        "questions": {
            "best": {
                "type": "choice",
                "instructions": (
                    "Which candidate in `candidates` is most relevant to `task`? "
                    "For issues, choose a genuine duplicate or related existing task; "
                    "for memories, choose a lesson that helps avoid repeating work. "
                    "Choose no_match when the shortlist does not support a useful match."
                ),
                "criteria": criteria,
            }
        },
    }
    request = urllib.request.Request(
        API_URL,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            answer = json.load(response).get("answers", {}).get("best", {})
        choice = str(answer.get("choice", "no_match"))
        if choice not in criteria:
            raise ValueError("Unknown TypeSafe candidate")
        return {"choice": choice, "confidence": answer.get("confidence"), "source": "jev-latest"}
    except (urllib.error.URLError, TimeoutError, OSError, ValueError, json.JSONDecodeError):
        return {"choice": fallback_choice, "source": "keyword-fallback"}


def main() -> int:
    try:
        data = json.load(sys.stdin)
        result = rank(str(data["query"]), list(data["candidates"]))
    except (KeyError, TypeError, ValueError) as error:
        print(f"rank_context: {error}", file=sys.stderr)
        return 2
    print(json.dumps(result))
    return 0


if __name__ == "__main__":
    sys.exit(main())
