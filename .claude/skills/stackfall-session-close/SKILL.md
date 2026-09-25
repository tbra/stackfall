---
name: stackfall-session-close
description: Close a Stackfall orchestration session with verified Git and Beads state, a compact next-bead handoff, and recoverable worker checkouts.
---

# Close a Stackfall session

Run on the main orchestrator thread. Do not turn close into another full project audit or load old handoff history.

1. Check `git status --short`, current revision, worktrees and active workers. Identify only session-owned deliverables. Never stage unrelated files or remove a dirty worktree. Finish accepted deliveries per `CLAUDE.md`: commit, integrate, run integrated gates, push and verify remote revision. Record any incomplete step exactly.
2. Reconcile Beads using `python tools/board_brief.py` and only the relevant `bd show` records; do not print whole-board JSON into the main chat. Close actually delivered issues; checkpoint interrupted work with worker/session ID, checkout, base, changed files, results, blockers and next action. All orchestrator writes use `--actor stackfall-orchestrator`.
3. Keep Beads changes local. No Beads remote is configured; do not attempt `bd dolt push`/`pull` unless the owner explicitly sets one up and requests sync. Code push is separate from local Beads state.
4. Update a single short `stackfall-handoff` memory with the next work target: a ready bead, or a blocked bead and the exact prerequisite that must be resolved. Include why it is next, checkout/revision and anything a replacement must not undo or rediscover. Use other `bd remember` keys for reusable lessons only; do not make another task ledger or append session history to `docs/CLAUDE_HANDOFF.md`. If there is no clear target, say why.
5. Report in a few lines: delivered revision, gates, local Beads status, next bead and any owner action. Preserve partial work and its checkout.
