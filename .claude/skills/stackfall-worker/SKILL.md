---
name: stackfall-worker
description: Stackfall worker protocol (brief, ownership, budgets, Beads checkpoints, handback). Preloaded into every project worker; the orchestrator writes each dispatch brief from its "Your brief" section.
---

# Stackfall worker protocol

This protocol applies to every Stackfall worker; your role file adds what is specific to your role, and CLAUDE.md holds the project rules. You do not inherit the orchestrator's conversation: work from your brief.

## Your brief

Every dispatch brief gives you:
- the Bead ID, objective and acceptance criteria;
- the exact absolute checkout path, branch, base commit and any required interface revisions;
- owned files/directories and exclusions, and the spec sections and plan to read;
- commands, expected outcomes and the scratchpad for logs (`python tools/scratch.py path <bead-id> [slug]`);
- your Git authority (default none: no commits, merges, pushes, stash or sync; the guard refuses `git stash`, so copy files to the scratchpad) and the Beads checkout for comments (the main checkout unless named);
- the verification budget: named checks, maximum runs and time, whether a visual probe is justified, the stop condition and, for work over 30 min, a check-in time. A phased brief names only the current phase's checks; a phase before the last hands back verdict partial.

If something you need is missing or conflicts (ownership, an absent interface, a spec ambiguity that changes rules or feel), report it instead of guessing or touching another worker's files.

## Packages and ownership

- One outcome per package, at most about 10 owned files and 30 minutes. Ownership is by file, not function: a shared file is split before two writers touch it (`autoload/Match.gd` is a thin autoload over `autoload/match/MatchFeed.gd`, `MatchPlacement.gd`, `MatchTerritory.gd` and `MatchLifecycle.gd`).
- Check `git status --short` before you start and before you report; if files outside your ownership changed, stop and report. Two writers never share a checkout. Preserve unrelated changes; if stopped, leave the tree compiling and say exactly where you stopped.
- Parallel packages that need tests in the same test file add a new test file instead.

## Budgets and stopping

- Default budgets (the brief may narrow them or justify more): docs/mechanical: one inspection or quick check, no game launch, 10 min; small fix: one named targeted run and one retry after a fix, 20 min; visual: code first, then off-screen probes as needed and a final screenshot; network/physics: named targeted tests plus one relevant harness or isolated benchmark; complex package: 30 min.
- Never choose an open-ended test sweep. If two focused attempts do not settle a failure, return the reproduction and blocker; the orchestrator may authorize a further bounded pass.
- Stop at the time budget with recoverable files and the exact next step. That is a stopping rule, not success. One slow-run retry (below) may extend it; checkpoint on the Bead when it does.
- **Time limits on long runs:** run every harness, multiplayer, bot-match or other long command under a wall-clock limit that kills the whole process tree. Set it from the brief's expected duration with generous headroom (15 min when the brief names none). If a run hits the limit, check its log: if output was still advancing, it was slow, so rerun once with a longer limit and note that in `checks`; if output had stopped, report the hang with its last output as a finding instead of waiting on it.
- Work expected to take more than 30 min: a short Bead checkpoint about every 30 min.

## Evidence

- Implementation roles implement; they do not return advice only. Report failure honestly, separate verified results from untested assumptions, and treat pending tests as limitations, not passes.
- Keep full logs in your scratchpad; report exit status, totals, decisive errors and the path, not log contents. Never report a `head`/`tail`/`grep` exit code as the test's.

## Beads checkpoints

- Comment only on your assigned bead: `bd -C <Beads checkout> comments add <id> --actor <your profile> "<text>"`. No status, assignee, dependency or close changes, and no private Beads database in a worktree. Keep writes brief (embedded Dolt).
- Checkpoint at each meaningful implementation/test boundary and before returning:

```text
Role / session ID:
Checkout / branch / base / candidate revision (or uncommitted):
Owned and changed files:
Completed work and reproduction evidence:
Commands run, exit results and log paths:
Decisions and remaining risks:
Next exact action / blocked authority or prerequisite:
```

- If a comment fails, retry once; then keep the full evidence in your scratchpad and hand back with `verdict` blocked and `record` `comment-failed:<error>` so the orchestrator persists it.

## Handback

Your last action is one SubagentHandback call whose whole text is one JSON object: no prose before or after it. `tools/validate_worker_handback.py` checks it. Post your checkpoint first, stop every background shell, wait and Monitor you started (a live one wakes you after handback and you would send it again; the hook refuses the handback and names it), then hand back. Wait for a Godot slot in the foreground (`tools/run_gut.ps1` and `tools/godot_slots.py run` already block until one frees), never with a Monitor or a polling loop:

`{"bead":"Bontago-<id>","verdict":"done","candidate":"<checkout>@<rev or uncommitted>","files":"a.gd;b.gd","checks":"test_x: 12/12 PASS; lint_all: GREEN","finding":"decisive result, risk or blocker","next":"exact next action","record":"bd:Bontago-<id>"}`

- Use all eight keys, spelled exactly so (not `status`, `summary`, `findings` or `next_action`); `files`, `checks` and `finding` may be short lists.
- `verdict` is one of done | review | partial | blocked | failed. Reviewers use `review` and start `finding` with APPROVE or CHANGES.
- `checks` lists every check the brief named as PASS, FAIL or NOT RUN; a named check that did not run makes the verdict partial, never done, unless the brief marks it optional (write `NOT RUN (optional)`). Leave out checks the brief forbids or never named.
- `files` names changed or inspected paths, or `none`; `next` is an exact action; `record` is `bd:<same id>` after the checkpoint.
- Limits: 1800 characters for done/review, 2400 for partial/blocked/failed, at most 8 lines; after a failed comment, up to 3200 characters. These limits override the SubagentHandback tool text about putting everything in one report: full detail goes in the bead comment and the handback points to it. No markdown fence, large logs or repeated report.
- A brief naming several beads: `bead` may list the ids joined with `,` `;` `+` `&` or `and`, and `record` is `bd:<one of them>` optionally followed by more `bd:` ids; comment on each assigned bead.
