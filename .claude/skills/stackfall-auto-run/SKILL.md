---
name: stackfall-auto-run
description: Continue Stackfall's ready Beads work through bounded workers, integrated verification, and delivery when the owner asks to keep working or auto-run.
---

# Auto-run Stackfall

Use on the main orchestrator thread only after the owner activates continued work. The project's Git authority and pause points in `CLAUDE.md` still apply. Keep the orchestrator's context small: delegate implementation and long diagnostic loops; read brief results and decisive evidence, not whole logs.

1. Run `python tools/board_brief.py` for the bounded ready/in-progress overview; query individual beads only as needed. Do not print whole-board JSON into the main chat. Reconcile existing worker/checkpoint state before taking new work. Prefer a ready package that unblocks dependent work; keep the owner's current priority above stale handoff suggestions.
2. Inspect only the bead, relevant source slices, and required spec/plan. Search `bd memories <topic>` before repeating an unfamiliar investigation; use `bd search <topic>` to check whether feedback already has a bead. A triage worker may pass up to ten plausible results to `tools/rank_context.py` for a Jev relevance judgment; the board and source evidence still decide whether two issues are duplicates. Keep shortlists out of the main thread. Assign one outcome, exact checkout/base and disjoint files. Run `tools/route_model.py` for the dispatch verdict, then give the worker named checks, a time limit, run count, and visual-probe limit from `docs/AGENT_WORKFLOW.md`. The orchestrator logs the brief and verdict in Beads with `--actor stackfall-orchestrator`.
3. Have workers iterate within their budget and return a final handback of at most 900 characters on success or 1500 on failure; detailed findings/logs go in the assigned scratchpad. A budget expiry returns a recoverable checkpoint; it never counts as acceptance. Verify candidate identity, diff, test totals, and any required independent review. Inspect `git diff --stat`, `git diff --check` and scoped hunks first; give large diffs to the reviewer instead of dumping them into the main chat. Avoid duplicate worker and integrator test runs unless a concrete integration risk warrants them.
4. Commit only accepted, owned files; integrate them without overwriting unrelated state. Run the full GUT suite once per integrated game-code batch and any required specialized gate on the integrated revision. For tooling/docs, use focused checks. When green, push code immediately, verify the remote revision, record commit and gate evidence in local Beads, and close accepted package issues. Do not attempt Beads remote sync; no remote is configured.
5. Repeat while actionable work remains. Stop for `[ORIGINAL]` rule changes, owner decisions, art direction, exhausted quota, conflicting ownership, or an unresolved failed gate. Continue unrelated safe packages where possible. Do not endlessly retry a failed command.

Routine user updates are one useful line: bead, result/count, next action. Expand only for a decision, failed gate, or material risk. Use `stackfall-session-close` before ending a long run.
