# Menu-first plan: Main.tscn compiles the menu path only; match flows load on demand

Design contract for Bontago-1pi.11.84 (planner, 2026-10-10). Base `main@24a11d49`. Measurement only; no game code
changed. Scratch: `M:/Bontago-tools/scratch/menu-first/` (`closure.py`, `lite.py`, `menu2.py`, `timeload.gd`, `par.gd`,
`mix.gd`, logs `timing1.log`, `timing2.log`; dep_graph output in `dg/`). Related: docs/AUTOLOAD_DECOUPLING_PLAN.md
(autoload closure, landed), docs/STARTUP_COMPILE_PLAN.md (method), Bontago-1pi.11.85 (prewarm behind the menu).
No [ORIGINAL] rule is touched. One player-facing latency question is flagged in section 7 (no owner decision needed to start).

## 1. Where the 6.2 s goes (evidence)

`Boot.gd` threads `res://game/Main.tscn`; the worker compiles Main.tscn's whole script closure
(`Boot._ready`, `_process`; `MAIN_SCENE_PATH`). Static closure (dep_graph on this base, compile edges class/extends/
preload/ext_resource/autoload_use, excluding the 68-file / 21.0k-line autoload closure that is already compiled by the
first frame): **Main.tscn marginal = 221 .gd, 59.2k lines.** `game/Main.gd` (1838 lines) names, by `class_name` type
or `preload`, nearly every screen and match system, so loading Main compiles all of it although the first screen is the menu.

Headless sync `ResourceLoader.load` timings (`timeload.gd`, each group a fresh process, 3 runs, ms; the machine was
otherwise idle; windowed threaded Main load is ~13% slower, see Main alone):

| Group (ordered marginal, fresh process) | Runs (ms) | Median | Lines (.gd) |
| --- | --- | ---: | ---: |
| `game/Main.tscn` alone (the status quo) | 6125 / 5452 / 4870 (threaded probe: 7281) | 5450 | 59.2k |
| `game/Main.gd` alone | 4751 / 5578 (2 runs; the 3rd was lost) | ~5200 | - |
| `ui/MainMenu.tscn` (includes MenuArena -> Block/BlockFactory/Field) | 1551 / 1483 / 1569 | 1550 | 20.7k |
| then `ui/Lobby.tscn` | 551 / 525 / 621 | 551 | 6.5k |
| then PauseMenu + ResultsScreen + ScoreboardOverlay + LoadingScreen | 610 / 690 / 590 (sum of 4) | 610 | 5.1k |
| then Skybox + CameraRig + CloudShadows + HorizonIslands (rest of Main.tscn world) | 697 / 782 / 778 | 778 | 8.6k |
| then `game/HotSeat.tscn` (PlayerController, HUD, Minimap, ...) | 1119 / 990 / 1280 | 1119 | ~14k |
| then `game/Main.tscn` (Main.gd, Sandbox, Tutorial, bots, TuningPanel, debug, ...) | 1077 / 1059 / 1577 | 1077 | rest |
| HotSeat.tscn alone / MatchScenes (HotSeat+RemoteCursors+NetDebug) | 2887 / 3078 / 2908 | 2908 | 42k |

Order-independent summary (sums to the 5.5 s of Main alone): menu 1.55, lobby 0.55, overlays 0.60, world nodes
Main.tscn instances (Skybox etc.) 0.78, HotSeat chain 1.1, Main.gd + Sandbox/Tutorial/bots/TuningPanel/debug ~1.1-1.9.
Menu + world + a slim Main.gd is the only part the first screen needs.

Simulated closure with Main.gd's edges to the match/lobby/sandbox classes cut (`lite.py`): HotSeat, Sandbox, Tutorial, Lobby,
BotController, StableBlockManager, RemoteCursors, NetDebugOverlay, TuningPanel, PerfOverlay/Sampler/Logger, WinChecker,
SandboxConfig, RainPuddles, QualityGovernorDriver cut: **148 files / 37.0k lines**; additionally cutting the four overlay scenes:
**135 files / 34.1k lines** (58% of today's 59.2k). HUD, PlayerController, HotSeat, Sandbox, Lobby and TuningPanel drop out entirely.

Findings that shape the design (both measured, scratch `par.gd`, `mix.gd`):

- **F1 (blocking).** Issuing several `load_threaded_request`s at once for scenes with overlapping script closures
  (Main + MainMenu + Lobby + HotSeat + Skybox + PauseMenu + Sandbox + Tutorial) never finished within 110 s in 3/3 runs (a hang,
  the script cache is shared and cyclic). Never run two overlapping threaded loads at once. Boot's one-at-a-time sequence
  is the safe pattern; "parallel prefetch" is rejected.
- **F2 (blocking).** A synchronous main-thread `load()` of a scene whose scripts overlap an in-flight threaded load
  does not hang but **blocks until the worker finishes** (Lobby sync load with HotSeat in flight: returned at 4261 / 4893 / 4868 ms,
  the same instant the threaded load completed). So background prewarm behind the menu must be chunked into short serial
  requests (longest chunk ~1.1 s), and every on-demand load must go through one `ensure()` that knows what is in flight.
- **F3.** `Main.tscn` node names (`Field`, `CameraRig`, `Skybox`, `BlockRegistry`, ...) are read by 104 tests/tools
  (`get_node("Field")` before `_ready`, `_main._field`, ...; `tests/unit/test_main_lazy_loads.gd:27` etc.). Moving
  the world nodes out of Main.tscn is not worth it: Field is already in the menu closure through MenuArena -> Block -> Field
  (`Block.gd:324` `Field.BEACON_COLLISION_LAYER`), and Skybox+CameraRig+Cloud cost 0.75 s. They stay.
- **F4 (optional, not recommended now).** Trimming the menu closure itself: cutting BlockFactory.gd:187 (`GhostPreview`)
  and :213 (`GiftFxPresenter`) plus Block.gd:324 (`Field`) shrinks the MainMenu closure from 88 files / 20.7k to 40 / 10.7k
  lines, but Main.tscn still instances Field.tscn, so it saves nothing at startup until the world nodes also leave Main.tscn.

## 2. Closure inventory (what the first menu screen needs)

| Group | Files (representative) | Needed for first menu? | Plan |
| --- | --- | --- | --- |
| Menu | `ui/MainMenu.tscn`, `MainMenu.gd`, `MenuArena.gd`, `OptionsMenu`, `InputGlyph`, `KeyRebindRow`, `MenuBackdrop`, `SplashScreen`, tuning configs | yes | stays eager |
| World nodes in Main.tscn | `Field`, `CameraRig`, `Skybox`, `HorizonIslands`, `BlockRegistry`, `CloudShadows`, `SunFlare` | not drawn (menu holds the render budget, `MenuBackdrop` budget), but part of the scene tree contract (F3) | stays eager |
| Lobby | `ui/Lobby.tscn`, `Lobby.gd` (1799), lobby widgets | no; needed on first host/join click | prewarm behind menu |
| Overlays | `PauseMenu`, `ResultsScreen`, `ScoreboardOverlay`, `LoadingScreen` | no, but must exist before first `match_state_changed(LOBBY, LOADING)`; instantiated in `Main._ready` today | package MF5 (lazy), else eager |
| Match world / HUD | `HotSeat` + `PlayerController` (2023) + `HUD` (1699) + `Minimap`, `RemoteCursors`, `NetDebugOverlay`, `StableBlockManager`, `BotController` + `core/ai/*`, `ThrowArcPreview` | no | on demand, prewarmed |
| Sandbox / tutorial | `Sandbox`, `SandboxPanel`, `SandboxConePanel`, `Tutorial`, `SandboxConfig` presets | no (menu buttons) | on demand, prewarmed |
| Dev tools | `TuningPanel` (1966), `PerfOverlay`, `PerfSampler`, `PerfLogger`, `QualityGovernorDriver`, `DebugMode` | no (`TuningPanel.apply_saved_overrides()` at `Main._ready` line ~199 and `_build_debug_tools` 1795) | move behind port; QualityGovernorDriver stays tiny (66 lines) |
| Match flow code in Main.gd | hot-seat/sandbox/tutorial (416-717), headless bots (718-1110), world build/end/loading (1415-1790) | no | move to `Main*Flow.gd` impl files (below) |

## 3. Design

Goal: `Main.tscn` + `Main.gd` compile only menu + world nodes + router. Everything else is reached through a
typed port and loaded by path. Preserve the public/private surface the 59 test files use (`_main._sandbox`, `_main._field`,
`_main._start_headless_bot_match_with_args`, `_main._build_match_world`, `_main._on_lobby_start_requested`, ...). Tests type
`_main` as `Variant`, so Main keeps those names (fields and forwarders) and only their declared types change.

### 3.1 Typed interfaces (stub package MF0 creates them; Main is untouched by MF0)

```gdscript
# res://game/MainFlowPort.gd  -- tiny base: names no heavy class_name, no autoload facade types
class_name MainFlowPort
extends RefCounted
## Implementations live in game/MainSandboxFlow.gd, MainHeadlessBotsFlow.gd, MainMatchFlow.gd (extends this
## class, `main: Main`). Main only ever holds a MainFlowPort and obtains it via MenuPrewarmQueue.ensure_script().
var main: Node3D = null  # the Main node; impls re-type it locally as `main_node: Main`
func bind(main_node: Node3D) -> void:
	main = main_node
func release() -> void:  # drop state held for a torn-down world
	pass
```

Each impl adds only the methods its slice needs, declared on a small per-flow port when Main must call them without
naming the impl (virtuals with typed signatures and empty bodies), for example:

```gdscript
class_name MainMatchFlowPort extends MainFlowPort
func build_match_world(force_staging_for_test: bool = false) -> void: pass   # awaits internally; Main forwards without await
func end_match_world() -> void: pass
func spawn_bot_controllers(config: MatchConfig) -> void: pass
func on_match_state_changed(from_state: int, to_state: int) -> void: pass
```
(`MatchConfig` is already in the autoload closure.) `MainSandboxFlowPort` exposes `start_hot_seat_match()`,
`start_sandbox_match()`, `start_sandbox_match_with_args(args: PackedStringArray)`, `start_sandbox_from_menu()`,
`start_gift_demo_from_menu()`, `start_tower_topple_from_menu()`, `start_tutorial_from_menu()`, `on_tutorial_finished()`;
`MainHeadlessBotsFlowPort` exposes `start_match_with_args(args: PackedStringArray)` and the report-tick entry points.

```gdscript
# res://game/MenuPrewarmQueue.gd  (RefCounted; owned by Main)
class_name MenuPrewarmQueue
extends RefCounted
signal path_ready(path: String)
signal drained()
var config: MenuPrewarmConfig                      # ordered path chunks (no magic numbers)
func start(tree: SceneTree) -> void                # interactive only; headless/flags call ensure() synchronously
func poll() -> void                                # one in-flight threaded request at a time (F1), Main._process drives it
func ensure(path: String) -> Resource              # loaded resource: collects the in-flight request if it is `path`
                                                   # (load_threaded_get), else removes it from the queue and load()s it
func ensure_script(path: String) -> GDScript       # same, typed
func is_ready(path: String) -> bool
func has_in_flight() -> bool
func collect_in_flight() -> void                   # _exit_tree / close request (Bontago-1pi.11.80): never cancel
static func run_blocking(tree: SceneTree, cfg: MenuPrewarmConfig) -> void  # headless/test/CLI: load everything now

# res://config/MenuPrewarmConfig.gd (+ res://config/menu_prewarm.tres)
class_name MenuPrewarmConfig
extends Resource
@export var chunks: Array[PackedStringArray]       # serial order, each chunk <= ~1.1 s (F2); every path is requested
                                                   # one at a time, chunk boundaries are where Main may idle
@export var eager_flags: PackedStringArray         # CLI flags that force run_blocking: hot-seat, sandbox, headless-host, join, host
```
Default chunk order in the .tres (lobby first because Host/Join is the likeliest click): `[Lobby.tscn]`,
`[MainSandboxFlow.gd, HotSeat.tscn]`, `[MainMatchFlow.gd, RemoteCursors.tscn, NetDebugOverlay.tscn]`,
`[PauseMenu.tscn, ResultsScreen.tscn, ScoreboardOverlay.tscn, LoadingScreen.tscn]` (only after MF5), `[Sandbox.tscn, Tutorial.tscn,
config presets]`, `[MainHeadlessBotsFlow.gd, TuningPanel.gd]`.

### 3.2 Main changes (serialised, one owner at a time)

- `Main.gd` stays the router: `_ready`, `_physics_process`, frame cap and graphics preset (lines 194-415), `_show_main_menu`,
  `_show_lobby`, `_clear_menu_and_lobby`, `_on_net_mode_changed`, `_has_cmdline_flag`, `_boot_line`. It gains `class_name Main`
  so impl files can type `main_node: Main`; the lint (section 5) forbids any non-impl file from depending on impl files.
- Fields tests read stay on Main (`_hot_seat`, `_sandbox`, `_tutorial`, `_remote_cursors`, `_debug_overlay`, `_bot_controllers`,
  `_stable_block_manager`, `_lobby`, `_pause_menu`, `_world_built`, ...), re-typed to `Node`/`Node3D` (never `HotSeat` etc.);
  impls cast back (`main_node._hot_seat as HotSeat`). Forwarders keep every `_main._xxx(...)` name that tests/tools call
  (`_start_headless_bot_match_with_args`, `_build_match_world`, `_end_match_world`, `_spawn_bot_controllers`, `_on_lobby_start_requested`,
  `_on_pause_*`, `_finish_loading_when_ready`, `_start_sandbox_match_with_args`, `_start_hot_seat_match`, ...): one line each, calling
  the loaded flow via `_queue.ensure_script(path)` cached in a typed `MainFlowPort` field.
- DECISION: impl files read Main's underscore-prefixed state through `main_node` (they are the same module split in two; tests
  already do). No new public API unless a call crosses to another system.
- Synchronous eager path: when `DisplayServer.get_name() == "headless"`, `AgentProbe.is_active()`, or a CLI flag in
  `MenuPrewarmConfig.eager_flags` is present, `Main._ready` calls `MenuPrewarmQueue.run_blocking` first, so tests, dedicated hosts,
  `--hot-seat`, `--sandbox` and bot matches keep today's startup order byte for byte.
- Interactive path: `Main._ready` builds the queue after `_show_main_menu()` (or after `SplashScreen.finished`),
  `_process` polls it (one request in flight), Main keeps `auto_accept_quit=false` while a request is in flight and quits at the
  next chunk boundary on `NOTIFICATION_WM_CLOSE_REQUEST` (Boot's 1pi.11.53/1pi.11.80 rule moves to the queue; Boot frees itself at
  hand-over, so Boot's own copy is untouched).
- On-demand: every code path that needs a flow, scene or script calls `_queue.ensure*()`, not bare `load()`: this is the
  single place that avoids F2 (it waits through `load_threaded_get` when the target is in flight, and removes a queued
  target so the sync load does not wait behind a different chunk). If the user clicks before the target is ready the call blocks
  at most one chunk (<= ~1.1 s); `MainMenu.show_status("Loading...")` is set first (existing method, `Main.start_bots_from_menu`).

### 3.3 Preserved behaviours and rules

- Static typing and no magic numbers: chunk lists and eager flags are a Resource; the impl files move code verbatim, so existing
  `# DECISION:` comments travel with it.
- Events bus decoupling and no deep node paths: unchanged; the queue is a plain RefCounted owned by Main, signals only for tests.
- Host-authority netcode: `_on_match_state_changed` body (Net.set_match_in_progress, set_accepting_joins) moves unchanged into
  `MainMatchFlow.on_match_state_changed`; `Main._ready` still connects the Events signals and forwards. The match-start path must be
  loaded before any `Events.match_state_changed(LOBBY, LOADING)`: `Main._on_match_state_changed` forwarder calls `ensure_script`
  first (client RPC path included). ENet harnesses guard this.
- Autoload-closure lint (`tools/lint_layers.py` L1-L3): untouched; new L4 (section 5) guards Main's own closure.
- Boot (1pi.11.53/1pi.11.80): no change to Boot in this plan. Boot still loads a (now smaller) Main.tscn, then prewarms `LateScripts`
  (~1.1 s) before handing over; that stage is Bontago-1pi.11.85's.
- 1pi.11.85 fit: it lands after MF4 and appends LateScripts.paths() as the first chunks of the same `MenuPrewarmQueue` (so there is
  still exactly one serial background loader, F1/F2) plus its facade-safety work (`Match`/`MatchNet` getters before `late_activate`).
  Its gate is `ensure_ready(&"late")` in `Main._show_lobby`/`_on_net_mode_changed`; MF4 leaves a typed hook `MenuPrewarmQueue.is_group_ready(group: StringName)`.

## 4. Packages (disjoint ownership; Main.gd is serialised)

Size note: each package is <= ~10 files, one outcome, ~30 min. Because MF1-MF4 all edit `game/Main.gd`, they run in ONE chain in ONE
worktree, each branch based on the previous accepted commit (a new worktree cannot see uncommitted changes). After MF0 lands, MF1 and MF2
touch disjoint line ranges and could run in two worktrees if the orchestrator prechecks with `integrate_batch.py --merge-only`; default: serial.

| Pkg | Outcome | Owned files | Depends | Worker |
| --- | --- | --- | --- | --- |
| **MF0 stubs** (first, interface stub package) | Typed ports + queue + config + unit tests; Main unchanged; both lints green | `game/MainFlowPort.gd`, `game/MainSandboxFlowPort.gd`, `game/MainHeadlessBotsFlowPort.gd`, `game/MainMatchFlowPort.gd`, `game/MenuPrewarmQueue.gd`, `config/MenuPrewarmConfig.gd`, `config/menu_prewarm.tres`, `tests/unit/test_menu_prewarm_queue.gd` (+ `.uid` sidecars) | none | stackfall-implementer |
| **MF1 sandbox flow** | Lines 416-717 (hot-seat, sandbox, tutorial) moved to `MainSandboxFlow.gd`; forwarders + re-typed fields | `game/Main.gd`, `game/MainSandboxFlow.gd`, `tests/unit/test_main_lazy_loads.gd` (add deferred paths) | MF0 | stackfall-implementer |
| **MF2 headless bots flow** | Lines 718-1110 moved to `MainHeadlessBotsFlow.gd`; forwarders keep every `_main._headless_*`/`_bots_arg` name | `game/Main.gd`, `game/MainHeadlessBotsFlow.gd` | MF1 | stackfall-implementer |
| **MF3 match flow** | `_build_match_world`, `_end_match_world`, `_spawn_bot_controllers`, `_reset_match_scope`, `_on_match_state_changed`, `_finish_loading_when_ready`, `_release_countdown_hold` moved to `MainMatchFlow.gd`; remaining Main fields re-typed; no match-only class_name left in Main.gd | `game/Main.gd`, `game/MainMatchFlow.gd`, `tests/unit/test_main_match_flow_split.gd` | MF2 | **stackfall-netcode** (match-start/clients path), then stackfall-reviewer |
| **MF4 wire queue + lint + measure** | Main builds `MenuPrewarmQueue` after the menu, eager path for headless/CLI; close-request deferral; L4 lint + baseline; startup measurement | `game/Main.gd`, `tools/lint_layers.py`, `tools/layer_baseline.json`, `tools/test_lint_layers.py`, `tests/unit/test_main_prewarm_wiring.gd` | MF3 | stackfall-implementer |
| **MF5 lazy overlays (optional, +0.6 s)** | PauseMenu/Results/Scoreboard/LoadingScreen instantiated by `ensure` at first lobby/match need (null-guarded in `_show_main_menu`, `_on_match_loading_announced`) | `game/Main.gd`, `config/menu_prewarm.tres`, `tests/unit/test_main_overlays_lazy.gd` | MF4 | stackfall-implementer, reviewer |
| **1pi.11.85** (existing issue) | LateScripts prewarm behind the menu | Boot/Match facades/`MenuPrewarmQueue` chunk list | MF4 | stackfall-netcode |

Integration order: MF0 -> MF1 -> MF2 -> MF3 -> MF4 -> (review) -> MF5 -> 1pi.11.85. Orchestrator runs the full gate once after MF3 (game code
batch) and after MF4/MF5; each intermediate commit leaves the game fully working (every flow still reachable by its old name).

## 5. Acceptance checks per package

- **All packages:** `godot --headless --editor --path <checkout> --quit` prints no new error/warning; `python tools/lint_layers.py` GREEN
  (L1-L3 unchanged); `python tools/affected_tests.py` list run; no windowed run except the measure tool below; `git status` lists owned files only.
- **MF0:** `powershell -NoProfile -File tools/run_gut.ps1 test_menu_prewarm_queue -Path <checkout>`: serial order (never two in flight: assert via a
  fake loader callable), `ensure()` of an in-flight path collects it, `ensure()` of a queued path dequeues it, `run_blocking` loads all, `collect_in_flight()`
  returns only after completion, unknown path pushes one error and returns null.
- **MF1/MF2:** `run_gut.ps1 test_main,test_main_lazy_loads,test_sandbox,test_sandbox_placement,test_tutorial,test_gift_demo_preset,test_tower_topple_preset,test_black_hole_gift_demo_flow`
  (MF2: `test_headless_bot_match,test_headless_loop_matches,test_gift_claim_bot_match`). Tests that read `_main._sandbox`/`_main._headless_*` need no edits (Variant). New assert in
  `test_main_lazy_loads`: the moved script paths are not in Main.gd's `preload`s.
- **MF3:** `test_main,test_match_flow,test_match_restart,test_match_countdown,test_match_lifecycle,test_loading_screen,test_pause_menu,test_pause_return_lobby,test_start_camera_flow,
  test_start_framing,test_lobby,test_net_session,test_team_slots,test_hover_cap_real_match` + `test_main_match_flow_split` (the new test instantiates Main.tscn headless and asserts
  Main.gd's script `get_script_property_list()` types and `ResourceLoader.get_dependencies` contain none of HotSeat/Sandbox/Tutorial/Lobby/BotController/TuningPanel/HUD). **ENet harnesses
  (quote each final `ENET RESULT` line):** `tools/run_reset_enet.ps1`, plus the start-camera and return-to-lobby harnesses (`tests/bench/start_camera_enet.gd`, `return_lobby_enet.gd`,
  the matching `tools/run_*enet*.ps1`), and a headless bot match `godot --headless --path . -- --headless-host --bots=8` (15 min deadline, no SCRIPT ERROR; `tools/triage_log.py`).
  stackfall-reviewer pass on the client match-start ordering (flow loaded before the first LOADING state).
- **MF4 (the timing gate):** new lint rule **L4 in `tools/lint_layers.py`**: the compile closure of `game/Main.tscn`, computed from the dep_graph, may not contain the forbidden set
  {`game/HotSeat.gd`, `game/PlayerController.gd`, `ui/HUD.gd`, `game/Sandbox.gd`, `ui/Tutorial.gd`, `ui/Lobby.gd`, `game/BotController.gd`, `ui/TuningPanel.gd`,
  `game/MainSandboxFlow.gd`, `game/MainHeadlessBotsFlow.gd`, `game/MainMatchFlow.gd`} and may not grow (baseline count: expected <= 148 files / 37.0k lines; the closure file list
  goes into `layer_baseline.json`); `tools/test_lint_layers.py` covers pass/fail. Targeted GUT: `test_main_prewarm_wiring` (headless path = blocking, flags force blocking, interactive
  path queues without loading, window-close during a request waits for the chunk then quits via an injected `quit_callable`), `test_boot,test_agent_probe`.
  **`python tools/measure_startup.py --path <checkout> --runs 5`** (idle machine, before and after; record the baseline median first): target **menu_ready median <= 8.8 s** from 11.3 s
  (predicted 8.5 s), first_frame within +-0.3 s of baseline, 0 SCRIPT ERROR lines; after 1pi.11.85 the target drops to <= 7.7 s. Also a scratch check
  (`timeload.gd`: `godot --headless --path <checkout> -s <abs scratch>/timeload.gd -- res://game/Main.tscn`, 3 runs): median <= 3.4 s vs 5.45 s today.
  Manual owner step: launch, click Play -> Vs bots immediately after the menu appears and again after ~8 s; the lobby must appear without "Not responding".
- **MF5:** `test_pause_menu,test_loading_screen,test_main,test_pause_return_lobby`; measure_startup 5 runs: additional ~-0.5 s expected; ENet harness `run_reset_enet.ps1` again.

## 6. Predicted saving

Main.tscn threaded load 6.2 s -> ~3.4 s (menu 1.55 + world 0.75 + slim router 0.2-0.5, x1.13 threaded penalty) : **~2.8 s saved (range 2.3-3.3)**;
menu_ready 11.3 s -> ~8.5 s. MF5 adds ~0.6 s (to ~7.9 s); 1pi.11.85 moves the 1.1 s LateScripts prewarm behind the menu (-> ~6.8 s).
Residual floor: first frame 3.0-3.6 s + menu compile 1.55 s + world 0.75 s + `Main._ready` ~0.4 s.

## 7. Owner-facing changes and risks

Owner-facing (no [ORIGINAL] rule, no gameplay change; informational):
1. **Latency window.** A click on Host/Join/Play/Sandbox/Tutorial during the first few seconds after the menu appears can wait up to ~1.1 s (one prewarm
   chunk) plus up to ~1.5 s of compile if the target is not loaded yet; later clicks have no wait. Status text "Loading..." is shown on the menu. Today there is no
   such wait because everything compiles before the menu. If this window is unacceptable, MF4 can preload the Lobby chunk before showing the menu (+0.6 s
   menu_ready); default is not to.
2. Nothing else changes for players; CLI/headless/test entry points keep a synchronous startup.

Risks and mitigations:
- R1 (F1) hang on concurrent threaded loads: queue is strictly serial; unit test asserts one in flight; never reuse for Boot's own request.
- R2 (F2) main-thread stall behind a worker compile: chunking + `ensure()`; the stall is bounded by the longest chunk. Measure the longest chunk after
  MF3 (`timeload.gd` on each chunk); split if > 1.2 s.
- R3 Test churn: 104 files reference Main.tscn; mitigation is "names stay, only declared types change" (tests use `Variant`); run `affected_tests.py`
  at every package. Any test that types `_main` as Main or assigns `Main._hot_seat` to a `HotSeat` var must cast (grep before MF1).
- R4 Client match-start ordering: the match flow must be loaded before the first `Events.match_state_changed(LOBBY, LOADING)` (client RPC `net_match_start`
  arrives with no Main involvement): forwarder `ensure_script` first. ENet harnesses (MF3 gate). Netcode owner + review.
- R5 Coroutine safety: `build_match_world` awaits frames; keep the `_loading_generation` guard in Main and re-check `is_instance_valid(main_node)` after each await.
- R6 `class_name Main`: new global name; verify no clash (`grep -rn "class_name Main\b"`) and keep it off the autoload closure (lint L1 already forbids autoload -> game/Main).
- R7 1pi.11.80: window close during an in-flight chunk must not cancel it (cancelled worker logs "Could not preload" and may hang): `collect_in_flight()` in `_exit_tree` and a
  deferred quit; reuse Boot's tests as a template (`test_boot.gd`).
- R8 Headless timing numbers here are sync loads with late scripts already activated (LateScripts loads happen in the autoload `_ready` headless), so they understate the
  windowed threaded load by ~13% and do not include the 1.1 s prewarm; the measure_startup acceptance is the authority.

## 8. Dispatch-ready briefs (one line each; the orchestrator adds the _common.md contract)

- **MF0** (implementer, Sonnet, no model override): create the typed ports, `MenuPrewarmQueue`, `MenuPrewarmConfig` + `.tres`, and `test_menu_prewarm_queue.gd` exactly per
  docs/MENU_FIRST_PLAN.md 3.1; do not touch Main.gd/Boot.gd; targeted GUT + lint_layers green; hand back the exact signatures.
- **MF1/MF2** (implementer): per 3.2, move the named line ranges verbatim into the impl file, keep every old name as a one-line forwarder, re-type fields to Node/Node3D; run the listed tests; no behaviour change.
- **MF3** (netcode, Sonnet; reviewer after): as MF1 for the match flow plus the ENet harness list in 5; quote ENET RESULT lines.
- **MF4** (implementer): wire the queue, eager/blocking path, close-request deferral, L4 lint + baseline, then run `measure_startup.py --runs 5` before and after and report medians.
- **MF5** (implementer, optional; run only if MF4's median meets target and the owner accepts the extra complexity).
