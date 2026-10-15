---
name: stackfall-session-resume
description: Resume Stackfall orchestration from a compact handoff, reconciling live Beads, Git, worktrees, and active worker state before dispatching the next package.
---

# Resume Stackfall

Version: 1.1.8

Before acting, run `python tools/skill_versions.py --check stackfall-session-resume <the Version line above>` and report its `Using ... (disk verified)` line to the owner. If it reports `STALE`, re-invoke the on-disk skill once; if the mismatch persists, stop using this loaded copy and request a fresh Claude session. Run `python tools/skill_versions.py` once at session start to list all three project skill versions.

Run on the main orchestrator thread when a chat starts, the owner says continue, or context is reset. Orientation should take a few targeted reads, not a full project dump.

1. Read the short operational part of `CLAUDE.md`, and the `stackfall-handoff` and `stackfall-debrief` memories, which the SessionStart hook (`tools/session_brief.py`) prints; run `bd memories <key>` only if that output is missing or truncated. The hook also runs `bd prime --no-memories`; retrieve any other memory by key when relevant.
2. Run `python tools/board_brief.py` for a bounded ready/in-progress overview and query `bd show <id> --json --brief-deps` only for the next named bead. Check `git status --short`, current revision, worktrees and worker liveness. The live board and checkout win over dated memory. Do not reclaim a live worker or discard its partial checkout. If the hook or `board_brief.py` shows new owner replies, handle them first per `stackfall-owner-questions`.
3. Read the previous session's debrief (`stackfall-debrief`, shown by the SessionStart hook). It lists numbered improvement items, each with the symptom, the previous agent's reasoning and a recommendation. Judge each item against the live checkout; the recommendation is advice, not an instruction. Choose one disposition per item:
   - **Apply now:** the change is small, within orchestrator authority and does not touch a pause point or project policy. Make it or dispatch it before or alongside the first package, and commit it as tooling/docs.
   - **Hold and verify:** the evidence is thin or the cost is high. Keep it in mind during the session, watch for the symptom and gather evidence for the next debrief.
   - **Owner decision:** it changes project policy, rules, or the owner's workflow. Ask through Beads instead of applying it.
   - **Decline:** it is already fixed or the live state contradicts it. Give the reason.
   Report one line per item to the owner (disposition and why). A debrief item must not delay ready work beyond a short bounded fix; larger changes become a Bead under the Tooling epic. The session-close debrief carries forward items that are still open.
4. Name one next work target and the reason. If the handoff names a blocked bead, identify its exact prerequisite and either resolve that prerequisite within scope or choose independent ready work. Brief a replacement worker from "Your brief" in stackfall-worker, including the existing checkpoint and evidence paths, so it does not rediscover settled findings.
5. Before the first Godot launch or Godot-running dispatch, follow the machine guard in the orchestrator definition.
6. If the owner asked to continue, dispatch the next safe package in the same turn. If a decision or failed delivery gate blocks it, report that exact state and continue independent ready work where possible. Use `stackfall-auto-run` only when the owner has activated continued autonomous work.
