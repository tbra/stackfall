# Agent Instructions

## Project orchestration and handoff

For Stackfall architecture and game rules, read `CLAUDE.md` and the relevant sections of `docs/SPEC.md`. For worker assignments, recovery and validation, read `docs/AGENT_WORKFLOW.md`. `docs/CLAUDE_HANDOFF.md` is a dated restart brief; inspect live Beads and Git state before using it.

The active Git profile is **team-maintainer** (owner decision 2026-09-24): after a package is verified and accepted, the orchestrator commits and integrates it, runs proportionate integrated gates, pushes code, verifies the remote revision, and closes its issue. **Beads has no configured remote (owner clarification 2026-09-25): keep issue writes local and do not attempt `bd dolt push` or `bd dolt pull` unless the owner explicitly configures and requests Beads remote sync.** Workers do not commit, merge, push or sync unless an assignment explicitly grants that responsibility. Never force-push, rebase shared history, discard work or include unrelated changes. Parallel implementation uses disjoint file ownership and explicitly assigned worktrees with a verified base; serialize dependent work if shared changes are uncommitted. Run performance benchmarks without competing workloads. This project-specific profile supersedes generic conservative defaults in managed Beads blocks below.

Reusable Claude roles live in `.claude/agents/`. Their durable task checkpoints and project knowledge live in Beads; do not create separate MEMORY.md files. Record assignment, checkout/branch/base, changed files, validation, blockers and next action so a replacement worker can recover without the previous conversation. Only the orchestrator closes milestone issues after integrated validation and independent review.

The orchestrator uses `.claude/skills/stackfall-auto-run`, `stackfall-session-close`, and `stackfall-session-resume` for continued work and handoff. Keep bulky logs and iterative probes in worker context; dispatches name exact checks, time and screenshot budgets. Workers return compact evidence and stop when their budget is exhausted. The full GUT suite runs once per integrated game-code batch, never per package.

The three project Claude skills carry `Version:` lines; bump a skill's version whenever its behavior changes. At session start, list on-disk versions with `python tools/skill_versions.py`; before each skill use, verify and announce the loaded version. A stale mismatch requires re-invocation or a fresh session. Unattended auto-run continues across task batches and native compaction; it has no fixed task-count cutoff. Keep orchestrator tool output bounded and checkpoint before compaction.

The orchestrator owns Beads claims, assignments, status and closure. Workers may comment on **their assigned issue only** with `--actor <worker-profile>`; they never close or reassign it. Their compact handback carries candidate, files, named checks, decisive finding and next action; the Bead comment is for recovery, not routine rereading. Use comment-free `bd show <id> --json --brief-deps` for ordinary issue reads. If a comment fails after one retry, return its error and scratchpad path. At delivered batch boundaries, checkpoint in Beads and refresh Claude context when stale transcript content accumulates. See `docs/AGENT_WORKFLOW.md`.

Claude model routing follows `docs/AGENT_WORKFLOW.md`: user-selected orchestrator (currently Fable), Haiku for mechanical/triage/known validation/CLI relay work, Sonnet for normal implementation/planning/review, and explicit Opus overrides only for genuinely hard reasoning. Worker models must not all inherit the orchestrator's model.

This project uses **bd** (beads) for issue tracking. Use `bd prime --no-memories` when Beads workflow context is missing or stale and retrieve relevant memories by key; normal session recovery uses the compact resume skill and targeted Beads queries.

> **Architecture in one line:** Issues live in a local Dolt database
> (`.beads/embeddeddolt/` in this checkout; verify with `bd info`); cross-machine sync uses `bd dolt push/pull` (a
> git-compatible protocol), stored under `refs/dolt/data` on your git
> remote — separate from `refs/heads/*` where your code lives.
> `.beads/issues.jsonl` is a passive export, not the wire protocol.
>
> See [sync-concepts](https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md)
> for the one-screen overview and anti-patterns (don't treat JSONL as the
> source of truth; don't `bd import` during normal operation; don't
> reach for third-party Dolt hosting before trying the default).

## Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work atomically
bd close <id>         # Complete work
```

## Non-Interactive Shell Commands

**ALWAYS use non-interactive flags** with file operations to avoid hanging on confirmation prompts.

Shell commands like `cp`, `mv`, and `rm` may be aliased to include `-i` (interactive) mode on some systems, causing the agent to hang indefinitely waiting for y/n input.

**Use these forms instead:**
```bash
# Force overwrite without prompting
cp -f source dest           # NOT: cp source dest
mv -f source dest           # NOT: mv source dest
rm -f file                  # NOT: rm file

# For recursive operations
rm -rf directory            # NOT: rm -r directory
cp -rf source dest          # NOT: cp -r source dest
```

**Other commands that may prompt:**
- `scp` - use `-o BatchMode=yes` for non-interactive
- `ssh` - use `-o BatchMode=yes` to fail instead of prompting
- `apt-get` - use `-y` flag
- `brew` - use `HOMEBREW_NO_AUTO_UPDATE=1` env var

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:46cd31e7 -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.

## Agent Context Profiles

The managed Beads block is task-tracking guidance, not permission to override repository, user, or orchestrator instructions.

- **Conservative (default)**: Use `bd` for task tracking. Do not run git commits, git pushes, or Dolt remote sync unless explicitly asked. At handoff, report changed files, validation, and suggested next commands.
- **Minimal**: Keep tool instruction files as pointers to `bd prime`; use the same conservative git policy unless active instructions say otherwise.
- **Team-maintainer**: Only when the repository explicitly opts in, agents may close beads, run quality gates, commit, and push as part of session close. A current "do not commit" or "do not push" instruction still wins.

## Session Completion

This protocol applies when ending a Beads implementation workflow. It is subordinate to explicit user, repository, and orchestrator instructions.

1. **File issues for remaining work** - Create beads for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Handle git/sync by active profile**:
   ```bash
   # Conservative/minimal/default: report status and proposed commands; wait for approval.
   git status

   # Team-maintainer opt-in only, unless current instructions forbid it:
   git pull --rebase
   git push
   git status
   ```
5. **Hand off** - Summarize changes, validation, issue status, and any blocked sync/commit/push step

**Critical rules:**
- Explicit user or orchestrator instructions override this Beads block.
- Do not commit or push without clear authority from the active profile or the current user request.
- If a required sync or push is blocked, stop and report the exact command and error.
<!-- END BEADS INTEGRATION -->

<!-- BEGIN BEADS CODEX SETUP: generated by bd setup codex -->
## Beads Issue Tracker

Use Beads (`bd`) for durable task tracking in repositories that include it. Use the `beads` skill at `.agents/skills/beads/SKILL.md` (project install) or `~/.agents/skills/beads/SKILL.md` (global install) for Beads workflow guidance, then use the `bd` CLI for issue operations.

### Quick Reference

```bash
bd ready                # Find available work
bd show <id>            # View issue details
bd update <id> --claim  # Claim work
bd close <id>           # Complete work
bd prime                # Refresh Beads context
```

### Rules

- Use `bd` for all task tracking; do not create markdown TODO lists.
- Run `bd prime` when Beads context is missing or stale. Codex 0.129.0+ can load Beads context automatically through native hooks; use `/hooks` to inspect or toggle them.
- Keep persistent project memory in Beads via `bd remember`; do not create ad hoc memory files.

**Architecture in one line:** issues live in a local Dolt DB; sync uses `refs/dolt/data` on your git remote; `.beads/issues.jsonl` is a passive export. See https://github.com/gastownhall/beads/blob/main/docs/core-concepts/sync-concepts.md for details and anti-patterns.
<!-- END BEADS CODEX SETUP -->
