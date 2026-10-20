---
name: stackfall-session-close
description: Close a Stackfall orchestration session with verified Git and Beads state, a compact next-bead handoff, and recoverable worker checkouts.
---

# Close a Stackfall session

Version: 1.2.1

Before acting, run `python tools/skill_versions.py --check stackfall-session-close <the Version line above>` and report its `Using ... (disk verified)` line to the user. If it reports `STALE`, re-invoke the on-disk skill once; if the mismatch persists, stop using this loaded copy and request a fresh Claude session.

Run on the main orchestrator thread. Do not turn close into another full project audit or load old handoff history.

1. Check `git status --short`, current revision, worktrees and active workers. Identify only session-owned deliverables. Never stage unrelated files or remove a dirty worktree. Finish accepted deliveries per `CLAUDE.md` and the orchestrator's Integration and delivery section. Record any incomplete step exactly.
2. Reconcile Beads using `python tools/board_brief.py` and targeted `bd show <id> --json --brief-deps` reads. Close actually delivered issues; checkpoint interrupted work with worker/session ID, checkout, base, changed files, results, blockers and next action. Release every claim whose worker is not live (including the `stale in progress` block of `board_brief.py`): unassign it and set it `open`, or `blocked` with a comment naming what it waits on; stale in_progress beads at close should be 0. Then run `python tools/archive_beads.py --apply` to archive beads closed for 7+ days.
3. Update a single short `stackfall-handoff` memory with the next work target: a ready bead, or a blocked bead and the exact prerequisite that must be resolved. Include why it is next, checkout/revision and anything a replacement must not undo or rediscover. Use other `bd remember` keys for reusable lessons only; do not make another task ledger. If there is no clear target, say why.
4. Debrief from measurements, not memory. Run `python tools/session_metrics.py --since <rev> --since-time <time>` with the revision and time from `bd kv get stackfall-session-start` (add `--mutate` when `core/` changed and the machine is idle). The debrief looks for gaps in the workflow loop, both in how it ran (gate REDs and their causes, denied or partial handbacks, review CHANGES, routing and handoff friction, avoidable test/probe loops, waste) and in what it produced (guard entries added, which should be 0; SHORTCUTs; tests that assert behaviour; mutation scores; review findings by severity). Time and token figures only identify waste: never propose a cheaper or thinner option to stretch usage (memory `owner-usage-principle`). Do not reread whole logs or transcripts to produce it.
   - Never propose loosening a lint, guard, hook, review, test or acceptance requirement to cut friction. Fix the friction by making the correct path easier, or make it a user decision.
   - Before proposing an item, search `bd list --all --label debrief --json --brief` for the same symptom. A recurrence goes on that Bead (why the earlier fix did not hold, then the new proposal) instead of a fresh patch.
   - Each item gives the symptom, the evidence (a metrics line or an observed event), the proposed change, the metric it should move, and a recommendation: _apply now_, _verify first (n/3)_ or _user decision_. An item stays in verify first for at most three sessions; at 3/3 it is applied, declined or made a user decision.
   - Suggest up to five items; if nothing material surfaced, say "none". Record a genuinely actionable follow-up as a Bead, not a pile of speculative issues.
   Hand the debrief to the next session by overwriting the single `stackfall-debrief` memory (`bd remember --key stackfall-debrief "..."`) with the numbered items. Carry forward each item still open with this session's evidence and its verify count; drop items that were applied or disproved. Keep it under about 2 KB. If the debrief is "none" and nothing carries forward, write "none" so the next session does not act on stale items.
5. Report in a few lines: delivered revision, gates, local Beads status, next bead, user action, the concise debrief suggestions and the **process changes** this session: one line per commit in the metrics' process-change list, flagging any that changed a guard or project policy (those should have been user decisions). Preserve partial work and its checkout. Do not clear while a worker handoff or unrecorded acceptance decision is pending. The next session uses `stackfall-session-resume`, not the old transcript.
