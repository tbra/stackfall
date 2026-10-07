---
name: stackfall-session-close
description: Close a Stackfall orchestration session with verified Git and Beads state, a compact next-bead handoff, and recoverable worker checkouts.
---

# Close a Stackfall session

Version: 1.1.0

Before acting, run `python tools/skill_versions.py --check stackfall-session-close 1.1.0` and report its `Using ... (disk verified)` line to the owner. If it reports `STALE`, re-invoke the on-disk skill once; if the mismatch persists, stop using this loaded copy and request a fresh Claude session.

Run on the main orchestrator thread. Do not turn close into another full project audit or load old handoff history.

1. Check `git status --short`, current revision, worktrees and active workers. Identify only session-owned deliverables. Never stage unrelated files or remove a dirty worktree. Finish accepted deliveries per `CLAUDE.md`: commit, integrate, run integrated gates, push and verify remote revision. Record any incomplete step exactly.
2. Reconcile Beads using `python tools/board_brief.py` and targeted `bd show <id> --json --brief-deps` reads, which omit comment bodies. Read a full comment only when recovering interrupted work, investigating a failed gate or auditing a disputed finding. Do not print whole-board JSON into the main chat. Close actually delivered issues; checkpoint interrupted work with worker/session ID, checkout, base, changed files, results, blockers and next action. All orchestrator writes use `--actor stackfall-orchestrator`.
3. Keep Beads changes local. No Beads remote is configured; do not attempt `bd dolt push`/`pull` unless the owner explicitly sets one up and requests sync. Code push is separate from local Beads state.
4. Update a single short `stackfall-handoff` memory with the next work target: a ready bead, or a blocked bead and the exact prerequisite that must be resolved. Include why it is next, checkout/revision and anything a replacement must not undo or rediscover. Use other `bd remember` keys for reusable lessons only; do not make another task ledger or append session history to `docs/CLAUDE_HANDOFF.md`. If there is no clear target, say why.
5. Debrief this session from evidence already seen: where time or tokens went, avoidable test/probe loops, handoff or model-routing friction, and any skill, hook, agent, context, or general setup change that would help. Suggest up to five concrete improvements, each with the observed symptom and its expected benefit. Do not pad the list; if nothing material surfaced, say "none". Do not reread logs or the whole transcript just to produce a debrief, and do not silently change project policy during close. Record only a genuinely actionable follow-up as a Bead, not a pile of speculative issues.
   Hand the debrief to the next session by overwriting the single `stackfall-debrief` memory (`bd remember --key stackfall-debrief "..."`). Number the items; for each give the symptom, your reasoning (the evidence and why it matters), the proposed change, and a recommendation: *apply now*, *verify first* (the next session should watch for the symptom) or *owner decision*. Carry forward any item from the previous debrief that is still open, adding this session's evidence for or against it; drop items that were applied or disproved. Keep the memory under about 2 KB. If the debrief is "none" and nothing carries forward, write "none" so the next session does not act on stale items.
6. Report in a few lines: delivered revision, gates, local Beads status, next bead, owner action and the concise debrief suggestions. Preserve partial work and its checkout. At a completed integration-batch boundary, invite the owner to use `/context` and `/usage`; if stale context has accumulated, recommend `/clear` or a fresh `claude --agent stackfall-orchestrator` session. Do not clear while a worker handoff or unrecorded acceptance decision is pending. The next session uses `stackfall-session-resume`, not the old transcript.
