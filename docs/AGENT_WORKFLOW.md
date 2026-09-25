# Stackfall worker protocol

## Entry point and roles

Launch `claude --agent stackfall-orchestrator` from `M:/Bontago`, or tell a normal Claude session to follow that profile. Start with `.claude/skills/stackfall-session-resume/SKILL.md`, `CLAUDE.md`, and `AGENTS.md`; read only the relevant spec and design contract. `docs/CLAUDE_HANDOFF.md` is historical and should be opened only when a live bead points to it. Use the installed CLI's actual tool names. Existing Claude permissions still govern execution.

| Profile | Responsibility | Outputs |
| --- | --- | --- |
| `stackfall-orchestrator` | Recover state, sequence packages, assign workers, review evidence | Beads assignments/checkpoints, acceptance decisions |
| `stackfall-triage` | Mechanical edits, file searches, log grouping and initial diagnostics | Verified small edits or evidence for an implementation worker |
| `stackfall-planner` | Inspect code and design bounded work packages | Milestone design contract with ownership, interfaces and test criteria |
| `stackfall-implementer` | Write game code, resources and meaningful tests; reproduce and fix bugs | Runnable changes and validation evidence |
| `stackfall-netcode` | Implement host authority, transport, replication and hostile-input fixes | Network changes and regression cases |
| `stackfall-integrator` | Verify the combined candidate, diagnose integration failures, run acceptance and benchmarks | Exact commands/results/log locations; scoped fixes |
| `stackfall-reviewer` | Independently inspect source and supplied diff/test evidence | Actionable findings with file/line, trigger and consequence |
| `codex` | Relay a bounded task to the installed Codex CLI | Actual result, session ID and checkout state |

Workers have implementation tools where needed. The reviewer has file-reading/search tools plus a Bash hook that permits only a Beads comment on its assigned issue; the orchestrator supplies diff and validation evidence or asks the integrator to produce it. Workers return to the orchestrator rather than recursively creating more workers.

## Model routing

| Task | Default model / role |
| --- | --- |
| Main orchestration | User-selected model, currently Fable; only the orchestrator uses `inherit` |
| Mechanical edits, searches, log triage | Haiku / `stackfall-triage` |
| Run known gates, summarize results, small known integration fixes | Haiku / `stackfall-integrator` |
| Relay work to Codex and preserve its output | Haiku / `codex`; this controls the bridge, not Codex's own model |
| Normal implementation, netcode, planning and independent review | Sonnet / the corresponding specialist |
| Genuinely hard architecture, invariants, root-cause or security reasoning | Explicit per-invocation Opus override on the relevant specialist |

Choose by task complexity, not role prestige. A networking log summary belongs on
Haiku; an ordinary RPC fix belongs on Sonnet. Escalate only the difficult reasoning
slice, with its uncertainty, evidence and expected deliverable in the brief; return
routine implementation/testing to the default model afterward. Do not use Fable for
workers by default or automatically upgrade every review. Hard problems may justify
up-front escalation; repeated low-cost failures are not a prerequisite.

Honor profile defaults rather than always passing the orchestrator's model in the
Agent call. A per-invocation override can persist when resuming a worker: explicitly
reset to its normal model or start a fresh default-model invocation after escalation.
If a requested model is unavailable, report the substitution and choose another
available model of suitable weight instead of silently accepting expensive inheritance.
Use `/tasks` to inspect actual running models. A forced
`CLAUDE_CODE_SUBAGENT_MODEL_FORCE` setting can override this routing; inspect it if
all workers still use Fable. Do not change global/account settings without scope.
Already-running workers keep their invocation; these defaults guide new delegations.

## Dispatch contract

Every assignment must include:

- Beads issue ID, objective and acceptance criteria; existing owner/claim if any.
- Exact absolute checkout path, branch, base commit and required interface revisions.
- Owned files/directories and exclusions; required spec sections and design plan.
- Relevant commands, expected outcomes and where to retain logs.
- Git authority for this assignment (workers default to no commits, merges, pushes or remote sync; the orchestrator owns verified delivery). Name the shared Beads checkout for worker comments; workers may not change issue status.
- Exact verification budget: named targeted tests, maximum runs and duration, whether a visual probe is justified, and the stop condition.
- Expected Beads comment: files changed, tests actually run, findings, decisions, unresolved work and next action. Expected handback: the self-contained compact result below, with a Bead record pointer for later recovery.

Use role names as subagent types when dispatching. Workers first read the supplied context and inspect checkout identity/status. Do not assume they inherit the conversation. Reassign overlapping ownership or establish a missing interface before dependent implementation; report substantial spec ambiguity to the orchestrator.

Parallelism is bounded by independent packages and machine capacity. The owner lifted the old two-writer default on 2026-09-23: run as many disjoint-ownership workers as the machine allows, but still serialize benchmarks, the full suite, and any two writers that share a file. Do not benchmark alongside game instances, test suites or other benchmarks. Never launch multiple writers in the same checkout. Automatic worktree isolation is intentionally not set in the profiles: the orchestrator assigns and verifies an explicit checkout and base so a worker cannot silently start from an older default branch. If the base lacks uncommitted contracts/configuration, serialize the work or wait for the relevant Git operation to be authorized. Preserve patches and worktrees until their contents are integrated and verified.

## Package size, reports and review scope (owner decisions 2026-09-22)

- **One outcome per package**, at most ~10 owned files and ~30 minutes of worker time. Split anything larger before dispatch; a stopped or rate-limited worker then loses little, and small packages merge without waiting on each other.
- **Proportional default budgets** (the brief may narrow these or justify an increase): docs/mechanical: one inspection or quick check, no game launch; small gameplay: one named targeted run and one retry after a fix; visual: code inspection, at most one reproduction and one final off-screen screenshot; network/physics: named targeted tests plus one relevant harness or isolated benchmark. A worker never chooses an open-ended test sweep. If two focused attempts do not settle a failure, return the reproduction and blocker for a new decision; do not keep probing. The orchestrator may authorize a further bounded diagnostic pass with a written reason.
- **Time budget:** the brief names a maximum; default 10 minutes for mechanical/triage, 20 minutes for a small fix, 30 minutes for a complex package. Stop at the budget with recoverable files and exact next step, even if unfinished. This is a stopping rule, not permission to claim success.
- **Durable report:** each worker adds a concise but complete comment to its assigned Bead with files, actual commands/results, findings, decisions, blockers and next action. Use `bd -C M:/Bontago comments add <id> --actor <worker-profile> "<comment>"` (or the assigned main-checkout path); no status/assignee/dependency/close changes. Retry a transient comment failure once, then keep the full evidence in the assigned scratchpad and report `comment-failed:<error>` so the orchestrator can persist it. Avoid concurrent comments when the orchestrator is changing board status.
- **Handback:** return one JSON object with nonempty string fields `bead`, `verdict`, `candidate`, `files`, `checks`, `finding`, `next`, `record`. `candidate` identifies checkout and revision (or says uncommitted); `files` names changed/inspected paths or `none`; `checks` names each actual check and result (or why none ran); `finding` states the decisive result, risk or blocker; `next` is an exact action. `record` is `bd:<same-id>` after the durable comment. This is enough for routine acceptance without reading that comment. Limit: 1100 characters for done/review, 1500 for partial/blocked/failed. If the comment fails after one retry, use `verdict=blocked`, `record=comment-failed:<error>`, and up to 3200 characters to preserve the finding. The worker-only hooks check this before `SubagentHandback` and once at `SubagentStop`. No markdown fence, large logs, or repeated report in main chat.

  Example: `{"bead":"Bontago-123","verdict":"done","candidate":"M:/wt/a@abc123","files":"core/rules.gd;tests/test_rules.gd","checks":"test_rules: 12/12 pass; import: pass","finding":"Overlap scoring fixed; no known risk","next":"integrate candidate","record":"bd:Bontago-123"}`
- **Tests:** targeted runner only (`tools/run_gut.ps1`, own + affected scripts). The full suite runs once per integrated game-code batch, in the background, by the orchestrator. ENet harness only for `net/`, `autoload/`, rules or lobby changes. Benchmarks only for physics, territory or wire changes, alone on the machine.
- **Integrator:** validates only the changed area (targeted set + the harness/bench that area needs) and the merge itself; no full-suite runs.
- **Reviewer:** required for `core/`, `net/`, `autoload/`, physics and rules changes; runs concurrently with integration. UI, tooling and docs packages skip independent review.
- **Windowed probes (owner, 2026-09-23):** agent-launched windowed Godot runs (screenshot probes, smoke runs) must start off-screen — always pass `--position 10000,10000`, never `--always-on-top`/`--maximized` — and quit as soon as the capture is saved; use `--headless` whenever no screenshot is needed. They were popping up on the owner's other monitor.
- **Godot processes (incident 2026-09-22):** `tasklist | findstr /i godot` is broken under Git Bash (always prints "Cannot open godot"). Check for running engines with `tasklist | grep -i godot` or `wmic process where "name like '%godot%'" get ProcessId,CommandLine`. Other agents run benchmarks in other worktrees at the same time: never `taskkill //IM Godot*`; kill only PIDs you started, by `taskkill //F //PID <n>`, and only after reading their CommandLine.
- **Owner questions (owner, 2026-09-22):** never interactive prompts. File a `decision` issue with `--label human --assignee Tony`, options plus the orchestrator's recommendation in the description; the owner answers with `bd human respond <id>` (see `bd human list`). Block dependent work with `bd gate create --type human --blocks <work-id> --reason ...` or a dependency. Where a tunable default can ship meanwhile, say so in the issue and proceed.
- **New tunables:** every new numeric/bool/Color `@export` on a tuning Resource the F4 panel shows (CameraTuning, GhostTuning, PhysicsTuning, TerritoryTuning, TerritoryVisuals, BlockFeedConfig) needs a one-sentence entry in `config/tuning_panel_hints.tres` `descriptions` (and a slider range if the default is ≤ 0 or the useful range is not ~[0, 4x default]); `test_tuning_panel` fails otherwise.
- **Tunable brief gate:** when an assignment adds a numeric/bool/Color `@export` to an F4 tuning Resource, the orchestrator explicitly names `test_tuning_panel` as a required targeted check. The implementer adds the hint and runs that test within the assigned budget; a missing hint or unrun test is not accepted.
- **Jev-assisted dispatch:** run `python tools/route_model.py --title "<title>" --files <owned,files> --kind <feature|bugfix|refactor|review|gate|triage|mechanical|plan> < brief.txt` for semantic packages. It returns model, review, split and verification tier/visual-need judgments in one request; deterministic policy sets hard limits and selects actual tests. Obvious mechanical/known-gate work uses the script's deterministic fast path. Record the verdict and any override in the dispatch comment. Do not let Jev waive a required gate or authorize additional probes.
- **File ownership over function ownership:** `autoload/Match.gd` is now a thin autoload over `autoload/match/MatchFeed.gd` (bags, intervals, locks, auto-drop), `MatchPlacement.gd` (request/preview/spawn/burn), `MatchTerritory.gd` (solve loop, raster, circles, elimination) and `MatchLifecycle.gd` (state machine, slots, grace, hot-seat turns). Assign those files, not functions; split any other shared file the same way before dispatching two writers.

## Persistence and recovery

The agent definitions survive chat changes. A worker process or its conversational context is not guaranteed to survive a rate limit, crash or new chat. Task state lives in the shared Beads database, and reusable project knowledge uses `bd remember`. Native Claude `memory:` is deliberately omitted: it would create a second MEMORY.md store contrary to this project's Beads convention.

The orchestrator uses `bd prime --no-memories` only when Beads workflow context is missing or stale, and reads individual memories by key. It runs `python tools/board_brief.py` for a bounded ready/in-progress overview; for the next assigned issue, `bd show <id> --json --brief-deps` gives issue fields without comment bodies on the installed Beads version. Use the worker's self-contained handback plus direct candidate/gate checks for routine acceptance. Open a full Bead comment only to recover interrupted work, investigate a failed gate or audit a disputed finding; the pointer alone is not a reason to read it. Do not echo full-board JSON or large diffs/logs into the main chat. The project SessionStart hook prints only a resume pointer, avoiding a full memory dump on every new chat. The orchestrator claims an issue once, records the assigned worker, and owns all status/assignee/dependency/closure writes. Every orchestrator write carries `--actor stackfall-orchestrator` (Codex uses `--actor codex`). Workers append comments to their assigned issue only, with their own profile as actor; keep writes brief because this project uses embedded Dolt. The dispatch write sets `--assignee "<worker profile> (<model>)"`; unstarted issues stay unassigned, and no issue is closed without an assignee. Workers do not initialize private Beads databases inside worktrees. A replacement session reads existing records before reclaiming work and verifies that the old worker is no longer active.

At each delivered integration batch, use any available context indicator or ask the owner to inspect Claude's `/context` and `/usage` to see whether startup instructions, tool results or repeated handbacks are growing the main session. These are diagnostics, not automatic acceptance gates. There is no fixed package or batch count that ends unattended auto-run. Instead, checkpoint the next exact action and active worker/checkout state in Beads, keep the main thread's command outputs to about 100 lines / 4 KB by default, and continue through native compaction. Save complete logs in worker scratchpads; report exit status, totals, decisive errors and a path. Do not pipe a test into `head`/`tail`/`grep` and mistake the filter's exit code for the test's. The project sets Claude's native `autoCompactWindow` to 120000 tokens; a higher-precedence environment override can replace it. Claude's status-line context percentage still uses the model's full window, so it does not display this earlier compaction threshold. A context warning calls for a checkpoint and recovery, not automatic session close. If compaction cannot recover enough context to coordinate safely, use `stackfall-session-close` and hand off from live Beads/Git state. Do not claim that a project hook can reset Claude's conversation.

If `bd close` or reassignment refuses a finished worker's bead, inspect the stated gate/claim and live worker state once; do not retry unchanged. `--force` is only for an explicitly verified completed package or abandoned claim after resolving why the normal operation was refused, never to bypass an unmet acceptance gate.

Observed context cost (owner 2026-09-25): Bash results, not worker implementation, dominated a short auto-run session. Do not dump startup-injected `AGENTS.md` or whole skill files just to check versions; use `tools/skill_versions.py`. Do not reread full Bead comments without a recovery/failed-gate/dispute reason, paste the same plan section into both the orchestrator and worker brief, or print whole GUT logs and broad diff hunks. In the main thread, summarize repetitive `Orphans` lines as a count and one example, keep full logs on disk, and inspect `git diff --stat` before a decisive hunk. Bundle related small queries to reduce fixed tool-call overhead while keeping the result bounded.

At each meaningful implementation/test boundary and before returning, the assigned worker persists a checkpoint on its own issue using `bd -C M:/Bontago comments add <id> --actor <worker-profile> "..."`. Retain history rather than overwriting unrelated notes. Include:

```text
Role / worker or CLI session ID:
Checkout / branch / base / candidate revision (or uncommitted):
Owned and changed files:
Completed work and reproduction evidence:
Commands run, exit results and log paths:
Decisions and remaining risks:
Next exact action / blocked authority or prerequisite:
```

Use `bd remember --key <stable-project-key> "..."` only for reusable knowledge, not transient progress. A handoff document is a dated entry point and design context, not a second task-status ledger. No markdown TODO backlog or separate agent memory files.

When a worker hits a limit, retain its checkout and last checkpoint. Resume it if its session ID remains usable; otherwise dispatch the same role with the checkpoint and current diff. A new chat or subagent still uses the account's quota. Do not silently loop retries or repeatedly launch workers against a known limit.

## Completion and validation

Implementation workers must implement their assigned changes, not return only advice. They report failure honestly and preserve partial work. Use open-project import before tests in a fresh worktree; the generated `.godot/` cache is not shared. Relevant gates:

```powershell
godot --headless --editor --path . --quit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
powershell -NoProfile -File tools/run_gut.ps1 <test_script>[,<test_script>] [-Unit <substring>]   # targeted, seconds; use while iterating
./tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02
godot --headless --path . res://tests/bench/bench_snapshot.tscn
```

Iterate with only the targeted runner scripts and run count named in the brief. The full suite is NOT a per-package gate: the orchestrator runs it once per integrated game-code batch after the commit and before push, never concurrently with another Godot process. Tooling/documentation batches get focused checks only. Run multiplayer checks for network changes and relevant physics/territory benchmarks when those systems change, within the assigned budget. Existing pending tests are limitations, not passes. For real hardware, record explicit owner steps and what remains unverified. Do not label frame-rate acceptance verified by a headless run alone. Review the exact candidate that was tested; changes after review need proportionate revalidation.

The orchestrator commits and integrates accepted candidate files only after checking ownership, diff, targeted evidence and required review. It runs integrated gates, pushes `main` promptly when green, verifies the remote revision, records evidence and closes the package issue. Milestones need integrated validation and independent review. A push or permission failure leaves the issue open with the exact failed step; never bypass the sandbox. Do not stop or delete unrelated processes/worktrees; re-check process identity before any authorized cleanup.

## Skills and references

Use `.agents/skills/beads/SKILL.md` for task tracking. For TypeSafe/Jev features or log-triage changes, read `.agents/skills/typesafe-ai/SKILL.md` and its current live API/SDK guidance. Keep credentials in environment variables and out of logs, issue bodies and commits. TypeSafe is not required for ordinary deterministic GDScript changes.

Agent file format and lifecycle: [Claude Code custom subagents](https://code.claude.com/docs/en/sub-agents). Locally checked against Claude Code 2.1.276 on 2026-09-18. Profiles inherit permission settings; they do not enable bypass modes or an experimental team service.
