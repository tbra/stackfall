# CLAUDE.md

## Project
A remake of Bontãgo (2003): a physics-based, competitive block-stacking territory game built in Godot 4.6+ with Jolt physics. It supports 2–8 players, online over Steam and on LAN. Working title: **Stackfall**.
**The full spec is `docs/SPEC.md`. Read the relevant sections before starting any milestone.** Where this file and the spec disagree, the spec wins.

## How the work is organised
The build runs as an **orchestrator plus reusable project workers**. The top-level Claude session owns sequencing, Beads, worktree assignments, and acceptance decisions; workers implement and validate bounded packages. Start a replacement session with `claude --agent stackfall-orchestrator` from this repository and use `.claude/skills/stackfall-session-resume/SKILL.md`. `docs/CLAUDE_HANDOFF.md` is historical context, not a startup read; live task state remains in Beads.

Read `docs/AGENT_WORKFLOW.md` for the worker roster, dispatch contract, checkpoints, and recovery protocol. The orchestrator may inspect files, run diagnostics, edit coordination documents, and manage authorized worktrees directly. Delegate substantial game code and independent reviews. Milestones (spec Part 4) continue once their acceptance criteria and review pass, subject to the pause points and Git authority below.

**Git authority (owner decision 2026-09-24):** the active profile is team-maintainer. After reviewing and validating a worker candidate, the orchestrator commits only owned changes and integrates them. After integrated checks pass, it pushes code immediately and verifies the remote revision; then it records evidence and closes the package issue. Run the full GUT suite once per integrated *game-code* batch before pushing; tooling and documentation changes get relevant focused checks. Beads has no configured remote (owner clarification 2026-09-25): keep issue writes local and do not attempt `bd dolt push` or `bd dolt pull` unless the owner explicitly configures and requests Beads remote sync. Workers do not commit, merge, push or sync by default. Never force-push, rewrite shared history, discard work, or include unrelated dirty files. A current explicit user stop or no-push instruction wins.

**Beads ownership:** the orchestrator owns claims, assignments, dependencies, acceptance and closure; workers may append detailed checkpoint and finding comments to their assigned issue only (owner clarification 2026-09-25). Every agent Beads write passes `--actor <agent-name>` (the orchestrator uses `--actor stackfall-orchestrator`); without it `bd` stamps the git user and the owner cannot tell agent writes from their own. At dispatch the orchestrator sets `--assignee "<worker profile> (<model>)"` (e.g. `stackfall-implementer (sonnet)`), or `stackfall-orchestrator` for work it does itself; unstarted issues stay unassigned (no placeholders), and an issue is never closed without an assignee. Workers return compact JSON pointing to their Beads comments, not the full findings. This project-specific rule takes precedence over generic skill, `bd prime`, and generated-block instructions telling workers to close their own issues.

**Model routing:** retain the user's chosen orchestrator model (currently Fable). Use Haiku for mechanical edits, triage, running known checks and the Codex bridge; Sonnet for normal planning, implementation, netcode and review. Reserve explicit Opus overrides for bounded genuinely hard reasoning, justify the escalation in the brief, then return routine work to its normal model. Do not propagate the orchestrator's model to every worker. Consult Jev first: `python tools/route_model.py` (see `docs/AGENT_WORKFLOW.md`) returns the tier, whether a review is needed and whether to split; override only with a stated reason.

Pause points — the only times the pipeline stops for the owner:
- **Any change to a rule tagged [ORIGINAL]** in the spec.
- **Major ambiguity:** anything that changes rules, game feel, scope, or player-facing behaviour in a way the spec doesn't settle. Describe the options and ask **through Beads**: a `decision` issue with `--label human --assignee Tony` (the owner answers with `bd human respond <id>`), and `bd gate create --type human --blocks <work-id>` or a dependency when the work must wait. Do not guess; do not use interactive prompts.
- **M7 art direction:** propose it and wait for approval before writing code.

Everything else is decided in place: for **minor ambiguity** (implementation detail with no gameplay impact) pick the simplest reasonable option, write a `# DECISION:` comment at that spot in the code, and list it in the summary.

Each milestone runs as a pipeline of agents, as parallel as the work allows:
1. **Plan** — `stackfall-planner` writes the milestone design contract: file ownership, interfaces, dependency order, and acceptance checks. Beads owns status. Have an implementation worker establish typed interface stubs before consumers; verify that each consumer's base actually contains them.
2. **Implement** — `stackfall-implementer` or `stackfall-netcode` edits and tests its assigned package. Parallel writers use separate explicitly assigned worktrees and disjoint ownership. If required shared contracts are still uncommitted, serialize dependent work in one checkout or wait at the Git gate; a new worktree cannot see uncommitted changes.
3. **Integrate and validate** — `stackfall-integrator` verifies the changed area and fixes only assigned integration defects. The orchestrator commits and integrates accepted work, runs the full suite once per game-code batch and other relevant gates, then pushes and verifies the remote revision. Run timing benchmarks on an otherwise idle machine.
4. **Review** — `stackfall-reviewer` examines the candidate and evidence without editing; an implementation worker reproduces and fixes findings. The orchestrator closes an issue only when its acceptance evidence is recorded, and closes the milestone only after integration and review pass.

## How to work (every agent)
- Work in small steps that each leave the game runnable. Return checkpoint evidence to the orchestrator after each working step; it records that evidence in Beads and owns commits.
- **Read before writing:** `CLAUDE.md`, the spec sections for the milestone, `README.md`, and the existing code the step touches.
- Never rewrite something the previous step got right; extend it.
- Hardware you can't use (a real gamepad, two PCs over Steam, a mid-range GPU for fps targets): verify what you can headlessly — synthetic `InputEventJoypad*` events through `Input.parse_input_event` in tests, ENet-only multiplayer, headless physics timing — then write **manual test steps** for the owner and continue.
- End every task with a summary covering what changed, how to test it by hand, every `DECISION`, and any open issues or questions.

## Tech rules
- Godot **4.6+** (developed on **4.7.2**), Forward+ renderer, `physics/3d/physics_engine = Jolt Physics`, 60 physics ticks per second, physics interpolation on.
- GDScript with **static typing everywhere** (typed variables, parameters, and return values). Untyped declarations are **compile errors** in this project (`debug/gdscript/warnings/untyped_declaration = 2`); `res://addons` is exempt.
- **No magic numbers.** Every tunable value belongs in a `Resource` under `res://config/`: `MatchConfig`, `PhysicsTuning`, `BlockShape`, `SpecialDef`, `MapDef`.
- Keep pure rule logic (territory, connectivity, win check, block bag) in `res://core/` with no dependence on the scene tree, and cover it with unit tests.
- Use a global signal bus (`Events` autoload) to decouple systems. Don't have deep node paths like `get_node("../../..")`.
- **All input goes through the Input Map.** Every action needs both a keyboard/mouse binding and a gamepad binding. Never check raw keycodes in code. The Input Map is generated by `tools/bootstrap_project.gd` — add actions there and re-run it; don't hand-edit the `[input]` section of `project.godot`. Mouse motion (`InputEventMouseMotion`) can't be an action and is read directly; that's allowed.
- **Multiplayer:**
  - The host is authoritative, and only the host runs physics.
  - Clients send intents. The host checks every intent before acting on it.
  - Gameplay code uses only `MultiplayerAPI` and must never assume a transport. Use ENet for LAN, direct IP, and tests, and Steam (GodotSteam, app ID 480 during development) for online play.
- Don't add third-party addons without asking. GodotSteam and GUT are already approved.

## Delegating to OpenAI Codex
A second coding agent is available on PATH as `codex`. The `codex` bridge (`.claude/agents/codex.md`) runs the installed CLI in the exact assigned checkout. Use its configured model unless the user selects another. Check `codex exec --help` before changing invocation flags. Supply long prompts through stdin and retain its session ID and result in the Beads checkpoint. Do not assume authentication or quota is still available; report actual errors.

Use it for an independent review, a hard bug, or an isolated implementation package. Its brief must explicitly name `AGENTS.md`, this file, the relevant spec/plan, owned files, and acceptance checks. Review findings are evidence to verify, not permission to close a task or a substitute for reproduction.

## Log triage
`tools/triage_log.py` turns a long headless run into a ranked summary: it strips Godot boilerplate, normalises ids out of error lines, groups duplicates, then asks TypeSafe/Jev to classify only the distinct signatures by subsystem and severity. It needs `TYPESAFE_API_KEY` (user environment variable) and degrades to the deterministic grouping without one. Exits non-zero on a confident likely-bug, so it can gate CI. Use it on the M5 bot matches and the M8 soak.

## Environment
- Godot 4.7.2 standard build. `godot` is on PATH via a shim in `C:\Users\tonyf\bin` (works in Git Bash and cmd/PowerShell). Full binary: `%LOCALAPPDATA%\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe`.
- The repo root is this folder (`M:\Bontago`); `res://` is the repo root.
- Test framework: **GUT 9.6.1** in `addons/gut/`, config in `.gutconfig.json`. Tests live in `tests/unit/`, benchmarks in `tests/bench/`.
- A windowed run can save a screenshot for verification: `get_viewport().get_texture().get_image().save_png(...)` after a frame, with `--quit-after N`.

## Commands
- Run the editor: `godot --editor --path .`
- Run the game: `godot --path .`
- Headless unit tests: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Targeted unit tests while iterating (seconds, not 20 min; `.gutconfig.json` makes `-gselect` run everything): `powershell -NoProfile -File tools/run_gut.ps1 test_net_session,test_steam_client` (`-Unit <substring>` for one test, `-Path <checkout>` for a worktree). The full suite now takes ~2 min (fixtures use a tiny map); the orchestrator still runs it once per merged batch, workers use the targeted runner.
- Regenerate settings + Input Map: `godot --headless --path . -s tools/bootstrap_project.gd`
- Open-the-project check (must print no errors or warnings): `godot --headless --editor --path . --quit`
- Headless bot match (from M5 onward): `godot --headless --path . -- --headless-host --bots=8`
- Multiplayer testing: in the editor, Debug → Customize Run Instances → 2–4 instances.

## Folder layout
Follow spec §3.2. New scenes go next to their scripts, shaders go in `res://shaders/`, and build-time scripts that aren't part of the running game go in `tools/`.

## Definition of done (every task)
- [ ] `godot --headless --editor --path . --quit` prints no errors and no new warnings.
- [ ] Unit tests pass.
- [ ] The feature works with mouse and keyboard **and** with a gamepad, where relevant (synthetic events in tests; manual steps for the owner).
- [ ] From M3 onward, it works for a client over ENet with simulated lag.
- [ ] Beads records the candidate path/revision, completed work, validation and remaining risks; the orchestrator has committed and pushed accepted work, or recorded the exact failed delivery step.
- [ ] The summary includes steps to test it by hand.


<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:1105d646 -->
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

### Project convention: bd vs. the milestone plans

Milestone and task tracking for Stackfall lives in `bd` (epics M0–M8, specials, known
limitations, owner questions), not in markdown TODOs. `docs/M<N>_PLAN.md` files are **not**
replaced by bd — they remain the design contract for each milestone's work packages (file
ownership, interfaces, integration order) and stay the reference for *how* to build a step.
The orchestrator checks `bd ready`, assigns issues and closes accepted work. Workers
comment detailed checkpoints on their assigned issues and return compact pointers;
they do not close
their own issues or create separate trackers.
<!-- END BEADS INTEGRATION -->
