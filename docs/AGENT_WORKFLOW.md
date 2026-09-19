# Stackfall worker protocol

## Entry point and roles

Launch `claude --agent stackfall-orchestrator` from `M:/Bontago`, or tell a normal Claude session to follow that profile. Read `CLAUDE.md`, `AGENTS.md`, `docs/CLAUDE_HANDOFF.md`, then the relevant spec and design contract. Use the installed CLI's actual tool names. Existing Claude permissions still govern execution.

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

Workers have implementation tools where needed. The reviewer has only file-reading/search tools; the orchestrator supplies diff and validation evidence or asks the integrator to produce it. Workers return to the orchestrator rather than recursively creating more workers.

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
- Git authority for this assignment (default: no commits, merges/rebases, pushes or remote sync).
- Expected report: files changed, tests actually run, findings, decisions, unresolved work, next action, and checkpoint location.

Use role names as subagent types when dispatching. Workers first read the supplied context and inspect checkout identity/status. Do not assume they inherit the conversation. Reassign overlapping ownership or establish a missing interface before dependent implementation; report substantial spec ambiguity to the orchestrator.

Parallelism is bounded by independent packages and machine capacity. Start with at most two implementation workers. Do not benchmark alongside game instances, test suites or other benchmarks. Never launch multiple writers in the same checkout. Automatic worktree isolation is intentionally not set in the profiles: the orchestrator assigns and verifies an explicit checkout and base so a worker cannot silently start from an older default branch. If the base lacks uncommitted contracts/configuration, serialize the work or wait for the relevant Git operation to be authorized. Preserve patches and worktrees until their contents are integrated and verified.

## Persistence and recovery

The agent definitions survive chat changes. A worker process or its conversational context is not guaranteed to survive a rate limit, crash or new chat. Task state lives in the shared Beads database, and reusable project knowledge uses `bd remember`. Native Claude `memory:` is deliberately omitted: it would create a second MEMORY.md store contrary to this project's Beads convention.

The orchestrator runs `bd prime`, examines `bd ready` and `bd list --status=in_progress`, and reads each assigned issue with `bd show <id>`. It claims the issue once, records the assigned worker, and serializes Beads writes (this project uses embedded Dolt). Workers report checkpoints to the orchestrator; they do not initialize private Beads databases inside worktrees. A replacement session reads the existing records before reclaiming anything, and verifies that the old worker is no longer active.

At each meaningful implementation/test boundary and before a worker returns, persist a checkpoint using `bd comments add <id> "..."`. Retain history rather than overwriting unrelated notes. Include:

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
./tools/run_m3a_local.ps1 -Peers 4 -SimLag 100 -SimLoss 0.02
godot --headless --path . res://tests/bench/bench_snapshot.tscn
```

Run the multiplayer checks for network changes and the relevant physics/territory benchmarks when those systems change. Existing pending tests are limitations, not passes. For real hardware, record explicit owner steps and what remains unverified. Do not label frame-rate acceptance verified by a headless run alone. Review the exact candidate that was tested; changes after review need proportionate revalidation.

The orchestrator closes package issues only after their acceptance evidence is recorded; milestone issues need integrated validation and independent review. Follow the active Git policy in `AGENTS.md` and `CLAUDE.md`. A permission failure is a blocked operation to report, not authority to bypass the sandbox. Do not stop or delete unrelated processes/worktrees; re-check process identity before any authorized cleanup.

## Skills and references

Use `.agents/skills/beads/SKILL.md` for task tracking. For TypeSafe/Jev features or log-triage changes, read `.agents/skills/typesafe-ai/SKILL.md` and its current live API/SDK guidance. Keep credentials in environment variables and out of logs, issue bodies and commits. TypeSafe is not required for ordinary deterministic GDScript changes.

Agent file format and lifecycle: [Claude Code custom subagents](https://code.claude.com/docs/en/sub-agents). Locally checked against Claude Code 2.1.276 on 2026-09-18. Profiles inherit permission settings; they do not enable bypass modes or an experimental team service.
