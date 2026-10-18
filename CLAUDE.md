# CLAUDE.md

## Project
Stackfall: a physics-based, competitive block-stacking territory game built in Godot 4.7 with Jolt physics. It supports 1–8 players, online over Steam and on LAN.
**The design and technical spec is `docs/SPEC.md`: it describes Stackfall as built and intended. Read the relevant sections before starting a package.** Where this file and the spec disagree, the spec wins; the orchestrator keeps it current.

## How the work is organised
The build runs as an **orchestrator plus reusable project workers**. The top-level Claude session owns sequencing, Beads, worktree assignments, and acceptance decisions; workers implement and validate bounded packages. Start a replacement session with `claude --agent stackfall-orchestrator` from this repository and use `.claude/skills/stackfall-session-resume/SKILL.md`. Live task state remains in Beads.

Each rule has one home, and other files point to it instead of restating it (`tools/lint_instructions.py` fails when rule text spreads): rules for every agent live here; orchestrator procedures (dispatch, model routing, acceptance, integration, machine guard, board structure) in `.claude/agents/stackfall-orchestrator.md`; the worker protocol in the `stackfall-worker` and `stackfall-godot` skills, which workers preload; role scope in each `.claude/agents/<role>.md`; and anything a tool enforces in that tool. The orchestrator may inspect files, run diagnostics, edit coordination documents, and manage authorized worktrees directly. Delegate substantial game code and independent reviews. Work packages (Beads epics) continue once their acceptance criteria and review pass, subject to the pause points and Git authority below.

The three session skills (`stackfall-session-resume`, `stackfall-auto-run`, `stackfall-session-close`) are versioned: bump the `Version:` line for each behavior change.

**Git authority:** the active profile is team-maintainer. After reviewing and validating a worker candidate, the orchestrator commits only owned changes and integrates them. After integrated checks pass, it pushes code immediately and verifies the remote revision; then it records evidence and closes the package issue. Run the full GUT suite once per integrated *game-code* batch before pushing; tooling and documentation changes get relevant focused checks. Beads has no configured remote: keep issue writes local and do not attempt `bd dolt push` or `bd dolt pull` unless the user explicitly configures and requests Beads remote sync. Workers do not commit, merge, push or sync by default. Never force-push, rewrite shared history, discard work, or include unrelated dirty files. A current explicit user stop or no-push instruction wins.

**Beads:** the orchestrator owns claims, assignments, acceptance and closure; workers comment on their assigned issue only. Every Beads write passes `--actor <profile>`: `--actor stackfall-orchestrator` for the main session, the worker's own profile name for a worker (bd otherwise stamps the git user). Use `bd remember --key <stable-key>` only for reusable knowledge, not progress; no MEMORY.md files, native agent `memory:`, markdown TODO backlogs or second status ledgers. This project rule supersedes the generic `bd prime` and managed-block instructions below.

Pause points — the only times the pipeline stops for the user:
- **Major ambiguity:** anything that changes rules, game feel, scope, or player-facing behaviour in a way the spec doesn't settle. Describe the options and ask **through a Beads decision** (the `stackfall-user-questions` skill); workers report the ambiguity to the orchestrator. Do not guess; do not use interactive prompts.
- **Art direction:** propose it and wait for approval before writing code.

Everything else is decided in place: for **minor ambiguity** (implementation detail with no gameplay impact) pick the simplest reasonable option, write a `# DECISION:` comment at that spot in the code, and list it in the summary.

Each milestone runs as a pipeline of agents, as parallel as the work allows:
1. **Plan** — `stackfall-planner` writes the milestone design contract: file ownership, interfaces, dependency order, and acceptance checks. Beads owns status. Have an implementation worker establish typed interface stubs before consumers; verify that each consumer's base actually contains them.
2. **Implement** — `stackfall-implementer` or `stackfall-netcode` edits and tests its assigned package. Parallel writers use separate explicitly assigned worktrees and disjoint ownership. If required shared contracts are still uncommitted, serialize dependent work in one checkout or wait at the Git gate; a new worktree cannot see uncommitted changes.
3. **Integrate and validate** — `stackfall-integrator` verifies the changed area and fixes only assigned integration defects. The orchestrator commits, integrates, gates and delivers accepted work under the Git authority above.
4. **Review** — `stackfall-reviewer` examines the candidate and evidence without editing; an implementation worker reproduces and fixes findings. The orchestrator closes an issue only when its acceptance evidence is recorded, and closes the milestone only after integration and review pass.

## How to work (every agent)
- Work in small steps that each leave the game runnable.
- **Read before writing:** `CLAUDE.md`, the spec sections for the milestone, `README.md`, and the existing code the step touches.
- Never rewrite something the previous step got right; extend it.
- **Public repository:** tracked files carry no provenance (who-and-when tags, dates, Beads ids) and no machine-specific paths or names; keep the reason, drop the who and when. Machine facts live in the untracked `CLAUDE.local.md`; `tools/lint_public.py` enforces this.
- Hardware you can't use (a real gamepad, two PCs over Steam, a mid-range GPU for fps targets): verify what you can headlessly — synthetic `InputEventJoypad*` events through `Input.parse_input_event` in tests, ENet-only multiplayer, headless physics timing — then write **manual test steps** for the user and continue.
- End every task with a summary covering what changed, how to test it by hand, every `DECISION`, and any open issues or questions.

## Tech rules
- Godot **4.7** (developed and tested on **4.7.2**; `project.godot` declares the 4.7 feature), Forward+ renderer, `physics/3d/physics_engine = Jolt Physics`, 60 physics ticks per second, physics interpolation on.
- GDScript with **static typing everywhere** (typed variables, parameters, and return values). Untyped declarations are **compile errors** in this project (`debug/gdscript/warnings/untyped_declaration = 2`); `res://addons` is exempt.
- **No magic numbers.** Every tunable value belongs in a `Resource` under `res://config/`: `MatchConfig`, `PhysicsTuning`, `BlockShape`, `SpecialDef`, `MapDef`.
- Keep pure rule logic (territory, connectivity, win check, block bag) in `res://core/` with no dependence on the scene tree, and cover it with unit tests.
- Use a global signal bus (`Events` autoload) to decouple systems. Don't have deep node paths like `get_node("../../..")`.
- **Follow Godot's best practices** (Godot docs `tutorials/best_practices` for 4.7; local copy path in `CLAUDE.local.md`). Every script and scene is a class with one responsibility. A scene is self-contained and gets its collaborators from its parent (call down, signal up): no reaching into parents, siblings, groups or global context for them in new code. Set a node's properties before `add_child`. Keep autoloads for truly global systems, data in `Resource`s and non-node logic in `RefCounted` or static classes. New and touched code follows these; planners design for them and reviewers check them.
- **All input goes through the Input Map.** Every action needs both a keyboard/mouse binding and a gamepad binding. Never check raw keycodes in code. The Input Map is generated by `tools/bootstrap_project.gd` — add actions there and re-run it; don't hand-edit the `[input]` section of `project.godot`. Mouse motion (`InputEventMouseMotion`) can't be an action and is read directly; that's allowed.
- **Multiplayer:**
  - The host is authoritative, and only the host runs physics.
  - Clients send intents. The host checks every intent before acting on it.
  - Gameplay code uses only `MultiplayerAPI` and must never assume a transport. Use ENet for LAN, direct IP, and tests, and Steam (GodotSteam, app ID 480 during development) for online play.
- Don't add third-party addons without asking. GodotSteam and GUT are already approved.

## Log triage
`tools/triage_log.py` turns a long headless run into a ranked summary: it strips Godot boilerplate, normalises ids out of error lines, groups duplicates, then asks TypeSafe/Jev to classify only the distinct signatures by subsystem and severity. It needs `TYPESAFE_API_KEY` (user environment variable) and degrades to the deterministic grouping without one. Exits non-zero on a confident likely-bug, so it can gate CI. Use it on the M5 bot matches and the M8 soak. For TypeSafe/Jev features or log-triage changes, use the `typesafe-ai` skill from the TypeSafe plugin and its live API guidance; keep credentials in environment variables, out of logs, issue bodies and commits.

## Environment
- Engine source (read-only): a checkout of the exact Godot version the project runs, at the path in `CLAUDE.local.md`. Grep it for engine behaviour (Jolt in `modules/jolt_physics/`, `scene/`, `servers/`) instead of guessing; never edit or build it.
- Godot 4.7.2 standard build; `godot` must be on PATH. Machine-specific setup (binary location, folders, the user's Beads name) is in the untracked `CLAUDE.local.md`.
- **Off-screen windowed runs:** every agent-launched windowed Godot run passes `--windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy` plus `-- --agent-probe` (and `--render-size=WxH` when it needs a real render resolution; AgentProbe renders into a SubViewport), never `--always-on-top`/`--maximized`/fullscreen, and quits right after its capture; use `--headless` when no screenshot is needed. Visible windows interrupt the user on another monitor; `tools/guard_shell.py` refuses a launch that is neither headless nor off-screen. Screenshots come from `tools/shot`.

## Commands
- Steam-online dev run: `godot --path . -- --steam-online` (test AppID 480's Steam Input intercepts controller events on this Windows setup, so the ordinary local run skips Steam init; `--host-online` also initializes Steam). A real AppID restores automatic Steam init.
- Full gate: `python tools/full_gate.py [--path <checkout>]` runs the whole GUT suite sharded across parallel headless Godot processes, re-runs failing scripts alone once (pass-alone = reported `parallel_flaky`, not a failure) and prints one `FULL GATE GREEN|RED` line (orchestrator only). Plain serial run: `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Targeted unit tests while iterating (seconds, not 20 min; `.gutconfig.json` makes `-gselect` run everything): `powershell -NoProfile -File tools/run_gut.ps1 test_net_session,test_steam_client` (`-Unit <substring>` for one test, `-Path <checkout>` for a worktree).
- Regenerate settings + Input Map: `godot --headless --path . -s tools/bootstrap_project.gd`
- Open-the-project check (must print no errors or warnings): `godot --headless --editor --path . --quit`
- Headless bot match: `godot --headless --path . -- --headless-host --bots=8`
- Multiplayer testing: in the editor, Debug → Customize Run Instances → 2–4 instances.

## Folder layout
Follow spec §2.2. New scenes go next to their scripts, shaders go in `res://shaders/`, and build-time scripts that aren't part of the running game go in `tools/`.
Layout: layers at the top (`core/` pure logic, `config/` Resources by feature, `game/` scene nodes by feature, `net/`, `ui/` components/theme/hud/menus/lobby/debug, `shaders/<feature>`, `assets/{audio,models,textures,ui}`, `tests/unit/<feature>`, flat `tools/`). `vfx/` and `sfx/` no longer exist: put new code in the feature folder.

## Definition of done (every task)
- [ ] `godot --headless --editor --path . --quit` prints no errors and no new warnings.
- [ ] Unit tests pass.
- [ ] The feature works with mouse and keyboard **and** with a gamepad, where relevant (synthetic events in tests; manual steps for the user).
- [ ] It works for a client over ENet with simulated lag.
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


<!-- END BEADS INTEGRATION -->
