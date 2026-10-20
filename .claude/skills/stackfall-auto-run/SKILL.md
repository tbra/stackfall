---
name: stackfall-auto-run
description: Continue Stackfall's ready Beads work through bounded workers, integrated verification, and delivery when the user asks to keep working or auto-run.
---

# Auto-run Stackfall

Version: 1.1.18

Before acting, run `python tools/skill_versions.py --check stackfall-auto-run <the Version line above>` and report its `Using ... (disk verified)` line to the user. If it reports `STALE`, stop using this loaded copy, re-invoke the on-disk skill once, and start a fresh Claude session if the mismatch persists. List the versions of all three project skills with `python tools/skill_versions.py` at the start of an unattended run.

Use on the main orchestrator thread only after the user activates continued work. CLAUDE.md (Git authority, pause points) and the orchestrator definition (dispatch, model routing, acceptance, delivery, machine guard, context hygiene) still apply; this skill adds the unattended loop.

Unattended context guard: keep working through ready, authorized packages; task counts and delivered batches are **not** stop conditions. Native compaction is the context backstop. At each delivered batch, leave a compact Bead checkpoint with the next exact action and active checkout/worker state, then continue. A context/compaction warning is a checkpoint signal, not a reason to end the session: secure in-flight work, let native compaction occur, reconcile from the checkpoint and live Git/Beads state, and continue. Use `stackfall-session-close` only when work is actually done or a real stop condition below prevents safe continuation. Do not claim that this skill can reset Claude's transcript or avoid the account's usage limit.

Usage-window guard (the `5h: N%` notices): from 85% run one worker at a time and rewrite the `stackfall-handoff` memory after each delivered package; at the first notice of 95% or more (the 95% and 100% notices can arrive together) stop the active worker, checkpoint its checkout, close the session with `stackfall-session-close`, then run the owner's end-of-window action named in the handoff. The guard protects work at the hard limit only; it never justifies cheaper or thinner work (`owner-usage-principle`).

0. Handle any new user reply first, per `stackfall-user-questions` (it also says how to catch replies during long runs).
1. Run `python tools/board_brief.py` for the bounded ready/in-progress overview; query individual beads only as needed. Reconcile existing worker/checkpoint state before taking new work. Prefer a ready package that unblocks dependent work; keep the user's current priority above stale handoff suggestions.
2. Inspect `bd show <id> --json --brief-deps` for the next bead, plus relevant source slices and required spec/plan. Search `bd memories <topic>` before repeating an unfamiliar investigation; use `bd search <topic>` to check whether feedback already has a bead. A triage worker may pass up to ten plausible results to `tools/rank_context.py` for a Jev relevance judgment; the board and source evidence still decide whether two issues are duplicates. Keep shortlists out of the main thread. Then dispatch per the orchestrator's Dispatch and Model routing sections and log the brief and verdict in Beads.
3. Accept per the orchestrator's Acceptance section. Verify candidate identity, `git diff --stat`, `git diff --check`, scoped hunks, test totals and any required review; give large diffs to the reviewer instead of reading them in the main thread. Avoid duplicate worker and integrator runs unless a concrete integration risk warrants them.
4. Deliver per the orchestrator's Integration and delivery section. Game-code batches get the full gate (CLAUDE.md); tooling/docs batches get focused checks, including `python tools/lint_all.py`. Keep reviewing, dispatching and preparing the next batch while the gate runs in the background.
5. Before every new dispatch, reconcile the brief checkpoint and any context warning as above, then continue while actionable work remains. Stop for user decisions (player-facing rule, feel or scope changes the spec doesn't settle), art direction, exhausted quota, conflicting ownership, an unresolved failed gate, or failed context recovery that makes safe continuation impossible. Continue unrelated safe packages where possible. Do not endlessly retry a failed command.

Use `stackfall-session-close` before ending a long run.
