---
name: stackfall-session-resume
description: Resume Stackfall orchestration from a compact handoff, reconciling live Beads, Git, worktrees, and active worker state before dispatching the next package.
---

# Resume Stackfall

Run on the main orchestrator thread when a chat starts, the owner says continue, or context is reset. Orientation should take a few targeted reads, not a full project dump.

1. Read `AGENTS.md`, the short operational part of `CLAUDE.md`, and the handoff memory (`bd memories stackfall-handoff`). Run `bd prime` only when Beads context is absent or stale; avoid echoing the entire output into the main chat when a compact lookup suffices. `docs/CLAUDE_HANDOFF.md` is dated history, not the live task ledger.
2. Check `bd ready --json`, `bd list --status=in_progress --json`, the named bead and its comments. Check `git status --short`, current revision, worktrees and worker liveness. The live board and checkout win over dated memory. Do not reclaim a live worker or discard its partial checkout.
3. Name one next work target and the reason. If the handoff names a blocked bead, identify its exact prerequisite and either resolve that prerequisite within scope or choose independent ready work. Pass a replacement worker only the bead, relevant spec/plan slices, existing checkpoint, exact checkout/base, owned files, verification budget and evidence paths. Do not make them rediscover settled findings.
4. If the owner asked to continue, dispatch the next safe package in the same turn. If a decision or failed delivery gate blocks it, report that exact state and continue independent ready work where possible. Use `stackfall-auto-run` only when the owner has activated continued autonomous work.
