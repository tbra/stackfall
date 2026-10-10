class_name Main
extends Node3D
## The game's entry point: a router, not a match (spec Part 4 M3a;
## docs/archive/M3a_PLAN.md integration order step 4).
##
## This is the one file nobody but the integrator owns (as in M2), and it
## stays deliberately thin: every system self-wires through the Events bus or
## a `Variant` provider seam, so Main only ever hands pieces to each other
## once, in the right order, and reacts to the handful of signals that mark a
## state change.
##
## **Two paths.**
##   - `--hot-seat` reaches exactly what M2 built: register_world() ->
##     start_match() -> place_flags() -> set_overlay_source(), with one
##     HotSeat.tscn whose PlayerController follows Events.turn_changed. No
##     menu, no lobby, no networking autoload is touched — test_hot_seat.gd
##     and every M2 match-flow test still pin this path byte-identical.
##   - Everything else shows ui/MainMenu.tscn, then ui/Lobby.tscn once Net
##     enters HOST or CLIENT (Events.net_mode_changed — apply_command_line()'s
##     --host/--join/--headless-host fire it exactly the same as the menu's
##     own buttons do), then builds the match world when Match's state machine
##     crosses LOBBY -> LOADING: on the host that follows a direct
##     Match.start_match() call from the Lobby's start_requested signal; on a
##     client it follows net/MatchNet.gd's net_match_start RPC calling that
##     same Match.start_match() locally. Reacting to the state change instead
##     of branching on host/client here is what lets one code path build the
##     world identically on every instance. The world comes down again
##     whenever Match returns to LOBBY -- Match.abort_match(), which
##     start_match() itself runs first when a match is restarted from any
##     later state -- and when Net drops to OFFLINE, which also aborts the
##     stale Match so it stops ticking and the next host/join starts from a
##     clean LOBBY (Beads Bontago-mv0.1.9).
##
## **Wiring order matters**, same reason as M2: Match.register_world() must
## happen before start_match() (it configures BlockRegistry's host authority
## from Net's *current* mode, so it cannot run before Net has actually joined
## or hosted); Field.place_flags() and Field.set_overlay_source() must happen
## after start_match(), because only then do Match.config (sanitized) and
## Match.raster() exist. SnapshotSync.begin_match() needs the same registry
## and the config's MapDef, so it rides along with those two.
##
## **Ticks** SnapshotSync.host_tick()/client_tick() run every physics frame,
## unconditionally: both no-op unless the role and running state match
## (net/SnapshotSync.gd), so Main never has to branch on is_host()/is_client()
## itself. client_tick() writes global_transform and must run from
## _physics_process, never _process (docs/archive/M3a_PLAN.md "Frozen bodies").
##
## M2's other ticks (10 Hz solve, 5 Hz overlay upload, the hole backlog and
## the settled rule) are unchanged and still live inside Match, TerritoryOverlay
## and Field/BlockRegistry themselves — see the M2 doc this file used to carry.

## Default lobby settings for the hot-seat build. start_match() duplicates and
## sanitizes it, so the resource on disk is never mutated.
@export var match_config: MatchConfig = preload("res://config/match_defaults.tres")
## Spec Part 4 M2 accepts on "two players take turns on one PC", so
## `--hot-seat` starts a two-player hot-seat match. Both live in MatchConfig
## rather than as literals here (CLAUDE.md: no magic numbers).
@export var player_count: int = 2
## Bontago-mv0.8: tunables for the unlisted `--sandbox` debug entry point
## below (CLAUDE.md: no magic numbers — see config/SandboxConfig.gd).
@export var sandbox_config: SandboxConfig = preload("res://config/sandbox.tres")

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/MainMenu.tscn")
const MENU_PREWARM_CONFIG_PATH: String = "res://config/menu_prewarm.tres"
const HEADLESS_BOTS_FLOW_SCRIPT_PATH: String = "res://game/MainHeadlessBotsFlow.gd"
const SANDBOX_FLOW_SCRIPT_PATH: String = "res://game/MainSandboxFlow.gd"
const MATCH_FLOW_SCRIPT_PATH: String = "res://game/MainMatchFlow.gd"
const LOBBY_SCENE_PATH: String = "res://ui/Lobby.tscn"
const HOT_SEAT_SCENE_PATH: String = "res://game/HotSeat.tscn"
const SANDBOX_SCENE_PATH: String = "res://game/Sandbox.tscn"
const GIFT_DEMO_PRESET_PATH: String = "res://config/sandbox_gift_demo.tres"
const TOWER_TOPPLE_PRESET_PATH: String = "res://config/sandbox_tower_topple.tres"
## docs/archive/M6_PLAN.md package B3 (spec 2.7 "Tutorial").
const TUTORIAL_SCENE_PATH: String = "res://ui/Tutorial.tscn"
const REMOTE_CURSORS_SCENE_PATH: String = "res://game/RemoteCursors.tscn"
const NET_DEBUG_OVERLAY_SCENE_PATH: String = "res://ui/NetDebugOverlay.tscn"
## Bontago-xtq.42 (M7 P42, owner playtest: "there's no pause menu, I can't
## abandon a game and go back to the main menu or quit the game").
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/PauseMenu.tscn")
## Bontago-1pi.6 (owner playtest: "the win screen always says 'Team x wins!'
## even when not playing in teams"). Self-contained the same way
## ui/PauseMenu.gd is (see its own header) -- it self-wires to
## Events.match_results_ready/match_state_changed, so this is only an
## instantiate-and-hide, no further wiring in this file.
const RESULTS_SCREEN_SCENE: PackedScene = preload("res://ui/ResultsScreen.tscn")
## Bontago-1pi.69: hold-to-show live scoreboard (action show_scores).
const SCOREBOARD_SCENE: PackedScene = preload("res://ui/ScoreboardOverlay.tscn")
## Bontago-1pi.8 (owner playtest 2026-09-27): covers the LOBBY -> LOADING ->
## COUNTDOWN window instead of leaving the idle centre-beacon camera shot on
## screen -- see ui/LoadingScreen.gd's own header doc.
const LOADING_SCREEN_SCENE: PackedScene = preload("res://ui/LoadingScreen.tscn")

@onready var _field: Field = $Field
@onready var _blocks_container: Node3D = $BlocksContainer
@onready var _registry: BlockRegistry = $BlockRegistry
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _skybox: Skybox = $Skybox
## Bontago-mp0.123: cosmetic horizon island ring, rebuilt wherever the sky set loads.
@onready var _horizon_islands: HorizonIslands = $HorizonIslands
## Bontago-xtq.26 (M7 P1): the one WorldEnvironment in game/Main.tscn --
## _apply_graphics_preset() below forwards ssr_enabled/volumetric_fog_enabled
## to its Environment resource. Null-checked rather than assumed non-null so a
## stripped-down test fixture without this node stays a safe no-op.
@onready var _world_environment: WorldEnvironment = $WorldEnvironment

## Bontago-1pi.11.84: serial prewarm queue and the on-demand sandbox flow (typed to the light ports).
var _prewarm_queue: MenuPrewarmQueue = null
var _sandbox_flow: MainSandboxFlowPort = null
var _headless_bots_flow: MainHeadlessBotsFlowPort = null
var _match_flow: MainMatchFlowPort = null
var _main_menu: MainMenu = null
var _lobby: Node = null
var _hot_seat: Node = null
var _sandbox: Node = null
## Bontago-1pi.70: set only by start_gift_demo_from_menu().
var _sandbox_preset: SandboxConfig = null
## docs/archive/M6_PLAN.md package B3: built/freed only by start_tutorial_from_menu()/
## _on_tutorial_finished() below -- never touched by _build_match_world()/
## _end_match_world() (this package does not own those functions).
var _tutorial: Node = null
var _remote_cursors: Node = null
var _debug_overlay: Node = null
## Bontago-xtq.42: built once below, right where Events.match_state_changed/
## net_mode_changed are connected -- kept alive for every menu/lobby/match
## screen that follows (main menu, lobby, sandbox-from-menu, tutorial-from-
## menu, a real online host/client match), the same "instantiate once, self-
## wire through Events" contract this file's own header describes. Never
## built for --hot-seat/the CLI-only --sandbox debug entry point above (both
## `return` out of _ready() before reaching this): this file's own header
## requires --hot-seat stay byte-identical to M2, and --sandbox is explicitly
## "not player-facing" (see _start_sandbox_match()'s own doc) -- the owner
## playtest finding this package answers was about the ordinary menu-driven
## game, which start_sandbox_from_menu()/start_tutorial_from_menu() below
## already cover.
var _pause_menu: PauseMenu = null
## Bontago-1pi.6: built once alongside _pause_menu above, for the same reason
## (self-wired via Events, inert until it has something to show). Unlike
## _pause_menu it needs no `suppressed` gate: it only ever appears in
## response to Events.match_results_ready (never a raw key press), so there
## is no toggle input to suppress during Tutorial/hot-seat/sandbox.
var _results_screen: ResultsScreen = null
var _scoreboard: ScoreboardOverlay = null
## Bontago-1pi.8: built once, right alongside _pause_menu above (same
## "instantiate once, self-wire" contract this file's own header describes),
## never for --hot-seat/the CLI-only --sandbox debug entry point (both return
## out of _ready() before Events.match_state_changed is even connected below,
## same reason _debug_overlay is skipped there too).
var _loading_screen: LoadingScreen = null
var _start_pending: bool = false
## Bontago-d5c.6 (M5 P5): one instance per bot slot in the match currently
## built, built in _build_match_world() (or _start_headless_bot_match_with_
## args()'s own reuse of it) and freed in _end_match_world() -- see
## _spawn_bot_controllers()'s own doc for why this lives here rather than in
## a P4 lobby append.
var _bot_controllers: Array[Node] = []

## M8 P5 (spec 3.5 "Stable-block optimization"): one instance for the match
## currently built, same build/teardown lifecycle as _bot_controllers above
## (built in _build_match_world(), freed in _end_match_world()) -- see
## _build_match_world()'s own single wiring-point comment. Host-gated inside
## the manager itself (game/StableBlockManager.gd's own `Net.is_host()`
## check), so building one on a client too costs nothing and stays inert,
## exactly the reasoning _spawn_bot_controllers()'s own doc comment already
## gives for BotController.
var _stable_block_manager: Node = null

## Bontago-d5c.6 review finding 2: diagnostics-only cadence for the
## `HEADLESS_BOTS` progress line printed by _on_headless_bots_report_tick()
## below, while a `--headless-host --bots=<n>` match is running. Not a
## gameplay tunable (CLAUDE.md's "no magic numbers" targets values that affect
## rules or feel; this only affects how chatty a CI log is), so it stays a
## const here rather than moving to a config/*.tres resource.
const HEADLESS_BOTS_REPORT_INTERVAL_S: float = 5.0

## Diagnostics-only state for the `HEADLESS_BOTS` progress line: see
## _start_headless_bots_diagnostics()'s own doc below. Null/0 whenever no
## headless bot match is running (every other entry point never touches
## these three).
var _headless_bots_report_timer: Timer = null
var _headless_bots_start_msec: int = 0
var _headless_bots_placements: int = 0
## Bontago-8or.21: `--loop-matches` state. Index 0 = no bot match started yet;
## _headless_loop_args is the command line the loop restarts from. Only ever
## armed by _start_headless_bot_match_with_args() with the flag present.
var _headless_loop_enabled: bool = false
var _headless_loop_index: int = 0
var _headless_loop_args: PackedStringArray = PackedStringArray()
var _headless_loop_seed: int = -1
var _headless_loop_restart_pending: bool = false

## True once _build_match_world() has run for the match currently in
## progress, so a repeated match_state_changed(LOBBY, LOADING) firing twice
## (should not happen, but a state machine is exactly the place to be
## defensive about it) cannot double-instance HotSeat/RemoteCursors, and
## _end_match_world() is a no-op when there is nothing to tear down.
var _world_built: bool = false
var _first_territory_ready: bool = false
var _loading_generation: int = 0
var _world_building: bool = false
var _controller_was_processing: bool = false
var _controller_was_handling_input: bool = false


## Bontago-xtq.44: the process-wide caches are released as the game scene leaves the tree.
func _exit_tree() -> void:
	ExitRelease.release_all()


func _ready() -> void:
	print(_boot_line())

	# Bontago-mv0.18: load any saved tuning-panel overrides onto the shared
	# tuning singletons before anything else in the tree reads them (nothing
	# does yet at this point -- see ui/TuningPanel.gd's own doc comment on why
	# that ordering doesn't matter either way).
	TuningPanel.apply_saved_overrides()

	# Bontago-xtq.26 (M7 P1): connected before the hot-seat/sandbox early
	# returns below so those offline entry points get the current graphics
	# preset applied too, even though they skip ui/MainMenu.tscn/ui/Lobby.tscn
	# entirely. current_graphics_preset() never returns null (Settings loads
	# a default at its own _ready()), so the initial call always has a preset
	# to apply.
	Settings.graphics_preset_changed.connect(_apply_graphics_preset)
	Settings.window_mode_changed.connect(_on_window_mode_changed)
	_apply_graphics_preset(Settings.current_graphics_preset())
	# Bontago-1pi.11.37: opt-in adaptive quality (idle unless the Options toggle is on).
	add_child(QualityGovernorDriver.new())

	# Bontago-xtq.45 (M7 P4): applies the persisted window mode (borderless
	# fullscreen by default) over whatever project.godot's own boot-time
	# window settings produced. Settings.apply_window_mode()'s own guards
	# already skip headless/editor/--position runs, so this is a no-op for
	# the test suite and off-screen probe tools.
	Settings.apply_window_mode()

	_build_debug_tools()

	if _has_cmdline_flag("hot-seat"):
		_start_hot_seat_match()
		return

	if _has_cmdline_flag("sandbox"):
		_start_sandbox_match()
		return

	Events.match_state_changed.connect(_on_match_state_changed)
	Events.net_mode_changed.connect(_on_net_mode_changed)
	# Bontago-8or.11: the gameplay half of mid-match admission. Net must not
	# name Match, so MatchNet (the membrane that reads both) answers which seat
	# a late joiner may take and whether a returning peer's slot is still its.
	Net.set_seat_policy(MatchNet.pick_open_seat, MatchNet.seat_reclaimable)

	_pause_menu = PAUSE_MENU_SCENE.instantiate() as PauseMenu
	add_child(_pause_menu)
	_pause_menu.leave_match_requested.connect(_on_pause_leave_requested)
	# Bontago-1pi.50: Return to lobby (host ends the match for everyone).
	_pause_menu.return_to_lobby_requested.connect(_on_pause_return_to_lobby_requested)
	_pause_menu.context_provider = _pause_menu_context
	# Bontago-xtq.42 fix round 2 (orchestrator review): inert until a match/
	# sandbox world actually exists -- _show_main_menu() below sets this too,
	# but set it explicitly here as well so it's never even momentarily false
	# before that first call.
	_pause_menu.suppressed = true

	_results_screen = RESULTS_SCREEN_SCENE.instantiate() as ResultsScreen
	add_child(_results_screen)
	_scoreboard = SCOREBOARD_SCENE.instantiate() as ScoreboardOverlay
	add_child(_scoreboard)
	# Bontago-1pi.8: built before Net.init_steam()/_show_main_menu() below,
	# same reasoning as _pause_menu just above -- it must already exist the
	# first time _on_match_state_changed() below can possibly fire.
	_loading_screen = LOADING_SCREEN_SCENE.instantiate() as LoadingScreen
	add_child(_loading_screen)
	Events.match_loading_announced.connect(_on_match_loading_announced)
	_loading_screen.readiness_timed_out.connect(_on_loading_readiness_timed_out)
	Events.territory_updated.connect(_on_loading_territory_updated)
	Events.territory_replicated.connect(_on_loading_territory_replicated)

	# docs/archive/M3b_PLAN.md integration order step 4: Steam init is synchronous by
	# this point, so MainMenu._ready() can immediately read steam_available().
	# Spacewar (480) is only our development Steam AppID. On Windows, its
	# Steam Input configuration intercepts physical pad events from Godot as
	# soon as steamInitEx runs, even though the pad still appears connected.
	# Keep local play/controller navigation functional by opting into Steam
	# explicitly while using that test ID. A real AppID restores auto-init.
	if Net.STEAM_APP_ID_EXPECTED != 480 or _has_cmdline_flag("steam-online") or _has_cmdline_flag("host-online"):
		Net.init_steam()
	# Bontago-59o.1: interactive launches show the SlopShop splash (with its
	# jingle) first; headless/CLI entry points go straight to the menu.
	if SplashScreen.should_show_now():
		var splash: SplashScreen = SplashScreen.new()
		add_child(splash)
		splash.finished.connect(_show_main_menu)
	else:
		_show_main_menu()

	# apply_command_line() calls host_game()/join_game() synchronously when
	# --host, --headless-host or --join is present, which emits
	# Events.net_mode_changed before this call returns -- _on_net_mode_changed
	# has already swapped the menu for the lobby by the time we get here.
	Net.apply_command_line()

	# Bontago-d5c.6 (M5 P5): a headless host has no human to click the
	# Lobby's own Start button, so `--headless-host --bots=<n>` (n > 0) skips
	# straight past that wait -- see _start_headless_bot_match_with_args()'s
	# own doc. A no-op (and so byte-identical to today) for every other
	# --headless-host command line: the function itself gates on --bots=<n>
	# being present and > 0.
	if _has_cmdline_flag("headless-host"):
		_start_headless_bot_match_with_args(OS.get_cmdline_user_args())


func _physics_process(delta: float) -> void:
	var probe_snapshot: int = PerfProbe.start()
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)
	PerfProbe.stop(&"snapshot", probe_snapshot)


## Bontago-1pi.11.49: the single place that decides the in-match frame cap (default =
## display refresh, see GraphicsPreset.FrameCap); ui/MenuBackdrop.gd arbitrates it
## against the menu cap. Headless and agent-probe runs keep the engine default.
## Tests set frame_cap_in_headless and refresh_rate_provider.
var frame_cap_in_headless: bool = false
var refresh_rate_provider: Callable = Callable()


## Bontago-1pi.11.51: the cap also follows the window: re-applied after a window-mode
## change and when a low-frequency check (GraphicsPreset.screen_check_interval_s) sees the
## window on another screen or the screen's refresh rate changed. Tests set screen_provider.
var screen_provider: Callable = Callable()
var _cap_display_key: Vector2 = Vector2.INF
var _screen_check_timer: Timer = null


func _frame_cap_skipped() -> bool:
	return not frame_cap_in_headless and (DisplayServer.get_name() == "headless" or AgentProbe.is_active())


func _current_screen() -> int:
	if screen_provider.is_valid():
		return int(screen_provider.call())
	return DisplayServer.window_get_current_screen()


func _current_refresh_hz() -> float:
	if refresh_rate_provider.is_valid():
		return float(refresh_rate_provider.call())
	return DisplayServer.screen_get_refresh_rate(_current_screen())


func _apply_frame_cap(preset: GraphicsPreset) -> void:
	if _frame_cap_skipped():
		return
	var refresh_hz: float = _current_refresh_hz()
	_cap_display_key = Vector2(float(_current_screen()), refresh_hz)
	MenuBackdrop.set_match_cap(FrameCapRule.resolve_for_preset(preset, refresh_hz))
	if _screen_check_timer == null and not _frame_cap_skipped() and DisplayServer.get_name() != "headless":
		_screen_check_timer = Timer.new()
		_screen_check_timer.wait_time = preset.screen_check_interval_s
		_screen_check_timer.timeout.connect(_recheck_frame_cap)
		add_child(_screen_check_timer)
		_screen_check_timer.start()


## Re-applies the cap only when the window's screen or that screen's refresh changed.
func _recheck_frame_cap() -> void:
	if _frame_cap_skipped():
		return
	var key: Vector2 = Vector2(float(_current_screen()), _current_refresh_hz())
	if key != _cap_display_key:
		_apply_frame_cap(Settings.current_graphics_preset())


func _on_window_mode_changed(_id: StringName) -> void:
	# The OS moves/resizes the window after apply_window_mode(); read the screen next frame.
	_apply_frame_cap.call_deferred(Settings.current_graphics_preset())


## Bontago-xtq.26 (M7 P1): applies every field GraphicsPreset (config/
## GraphicsPreset.gd) currently declares. Connected to
## Settings.graphics_preset_changed and also called once at startup above, so
## a mid-match preset change (Options screen, not built yet) and the initial
## boot value both reach the same place.
func _apply_graphics_preset(preset: GraphicsPreset) -> void:
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = preset.msaa_3d
		# Bontago-1pi.11.37: only written on change; 1.0 on every shipped preset.
		if not is_equal_approx(viewport.scaling_3d_scale, preset.render_scale_3d):
			viewport.scaling_3d_scale = preset.render_scale_3d
		# DECISION (Bontago-1pi.11.67): the upscaler is a preset field (Low: FSR 1.0).
		var mode: Viewport.Scaling3DMode = preset.render_scale_3d_mode as Viewport.Scaling3DMode
		if viewport.scaling_3d_mode != mode:
			viewport.scaling_3d_mode = mode

	# DECISION (Bontago-xtq.26): Godot 4 has no per-Viewport or per-light
	# directional-shadow-atlas size -- RenderingServer.
	# directional_shadow_atlas_set_size() is the only API surface (confirmed
	# via ClassDB.class_get_method_list(&"RenderingServer"); Viewport only
	# exposes positional_shadow_atlas_size, for OmniLight3D/SpotLight3D). It's
	# a global, write-only call (no getter to assert against in a test), so it
	# applies to every DirectionalLight3D in the process, which is correct
	# here (game/Main.tscn has exactly one). `is_16bits = true` is the mandatory
	# second argument, passed as the engine's own unmodified default
	# (project.godot has no rendering/lights_and_shadows/directional_shadow/
	# 16_bits override) -- not a preset-tunable value, so it isn't a
	# GraphicsPreset field.
	RenderingServer.directional_shadow_atlas_set_size(preset.shadow_atlas_size, true)

	# Bontago-1pi.11.49: frame cap per preset (the headless server/tests keep the engine
	# default so bot matches and test waits are not throttled).
	_apply_frame_cap(preset)

	# Bontago-1pi.11.2: cascade count / range of the sun's shadow pass.
	var sun: DirectionalLight3D = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun != null:
		sun.directional_shadow_mode = preset.sun_shadow_mode as DirectionalLight3D.ShadowMode
		sun.directional_shadow_max_distance = preset.sun_shadow_max_distance

	if _world_environment != null and _world_environment.environment != null:
		var environment: Environment = _world_environment.environment
		environment.ssr_enabled = preset.ssr_enabled
		environment.glow_enabled = preset.glow_enabled  # Bontago-1pi.11.67
		environment.volumetric_fog_enabled = preset.volumetric_fog_enabled


# --- Hot-seat / sandbox / tutorial: forwarders (Bontago-1pi.11.84 MF1) -------
#
# The bodies live in game/MainSandboxFlow.gd, loaded on demand through the prewarm queue
# (docs/MENU_FIRST_PLAN.md 3.2). Every old member name stays here for tests and tools.

func _start_hot_seat_match() -> void:
	_sandbox_flow_port().start_hot_seat_match()


func _start_sandbox_match() -> void:
	_sandbox_flow_port().start_sandbox_match()


func _start_sandbox_match_with_args(args: PackedStringArray) -> void:
	_sandbox_flow_port().start_sandbox_match_with_args(args)


func start_sandbox_from_menu() -> void:
	_sandbox_flow_port().start_sandbox_from_menu()


func start_gift_demo_from_menu() -> void:
	_sandbox_flow_port().start_gift_demo_from_menu()


func start_tower_topple_from_menu() -> void:
	_sandbox_flow_port().start_tower_topple_from_menu()


func start_tutorial_from_menu() -> void:
	_sandbox_flow_port().start_tutorial_from_menu()


func _on_tutorial_finished() -> void:
	_sandbox_flow_port().on_tutorial_finished()


## The sandbox flow, loaded through the serial prewarm queue on first use. DECISION: the queue
## is built lazily here (synchronous path); MF4 owns the background start and eager flags.
func _sandbox_flow_port() -> MainSandboxFlowPort:
	if _sandbox_flow == null:
		var flow_script: GDScript = _menu_prewarm_queue().ensure_script(SANDBOX_FLOW_SCRIPT_PATH)
		_sandbox_flow = flow_script.new() as MainSandboxFlowPort
		_sandbox_flow.bind(self)
	return _sandbox_flow


## Bontago-1pi.108: every mode that builds a world (match, hot-seat, sandbox, tutorial)
## gets the same sky: the map's textured set plus the config's theme / cycle.
func _apply_match_sky(config: MatchConfig) -> void:
	_skybox.load_set(config.map_def().skybox_set)
	_skybox.configure_match_sky(config)


# --- Headless bot match: forwarders (Bontago-1pi.11.84 MF2) ------------------
#
# The bodies live in game/MainHeadlessBotsFlow.gd, loaded on demand through the prewarm queue;
# the headless/CLI path stays synchronous. State fields (_headless_*) stay here.

func _start_headless_bot_match_with_args(args: PackedStringArray) -> void:
	_headless_bots_flow_port().start_match_with_args(args)


func _start_headless_loop_match(bots: int, args: PackedStringArray) -> void:
	_headless_bots_flow_port().call(&"_start_headless_loop_match", bots, args)


func _has_loop_matches_arg(args: PackedStringArray) -> bool:
	return _headless_bots_flow_port().call(&"_has_loop_matches_arg", args) as bool


func _on_headless_loop_state_changed(_from_state: int, to_state: int) -> void:
	_headless_bots_flow_port().call(&"_on_headless_loop_state_changed", _from_state, to_state)


func _restart_headless_loop_match() -> void:
	_headless_bots_flow_port().call(&"_restart_headless_loop_match")


func _headless_match_summary_line() -> String:
	return _headless_bots_flow_port().call(&"_headless_match_summary_line") as String


func _net_is_hosting() -> bool:
	return _headless_bots_flow_port().call(&"_net_is_hosting") as bool


func _bots_arg(args: PackedStringArray) -> int:
	return _headless_bots_flow_port().call(&"_bots_arg", args) as int


func _seconds_arg(args: PackedStringArray) -> float:
	return _headless_bots_flow_port().call(&"_seconds_arg", args) as float


func _headless_bot_players_arg(args: PackedStringArray) -> int:
	return _headless_bots_flow_port().call(&"_headless_bot_players_arg", args) as int


func _build_headless_bot_config(bots: int, args: PackedStringArray) -> MatchConfig:
	return _headless_bots_flow_port().call(&"_build_headless_bot_config", bots, args) as MatchConfig


func _disc_size_arg(args: PackedStringArray) -> int:
	return _headless_bots_flow_port().call(&"_disc_size_arg", args) as int


func _goals_arg(args: PackedStringArray) -> int:
	return _headless_bots_flow_port().call(&"_goals_arg", args) as int


func _headless_bots_goal_coverage() -> String:
	return _headless_bots_flow_port().call(&"_headless_bots_goal_coverage") as String


func _mode_arg(args: PackedStringArray) -> int:
	return _headless_bots_flow_port().call(&"_mode_arg", args) as int


func _start_headless_bots_diagnostics() -> void:
	_headless_bots_flow_port().call(&"_start_headless_bots_diagnostics")


## Only a loaded flow can have started diagnostics, so teardown never loads it.
func _stop_headless_bots_diagnostics() -> void:
	if _headless_bots_flow != null:
		_headless_bots_flow.call(&"_stop_headless_bots_diagnostics")


func _on_headless_bots_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_headless_bots_flow_port().call(&"_on_headless_bots_block_placed", _block, _shape_id)


func _on_headless_bots_report_tick() -> void:
	_headless_bots_flow_port().call(&"_on_headless_bots_report_tick")


func _on_headless_bots_seconds_elapsed() -> void:
	_headless_bots_flow_port().call(&"_on_headless_bots_seconds_elapsed")


func _headless_bots_periodic_line() -> String:
	return _headless_bots_flow_port().call(&"_headless_bots_periodic_line") as String


func _headless_bots_done_line() -> String:
	return _headless_bots_flow_port().call(&"_headless_bots_done_line") as String


func _headless_bots_frontier_gap() -> float:
	return _headless_bots_flow_port().call(&"_headless_bots_frontier_gap") as float


func _headless_bots_homes_alive() -> int:
	return _headless_bots_flow_port().call(&"_headless_bots_homes_alive") as int


func _headless_bots_elapsed_s() -> float:
	return _headless_bots_flow_port().call(&"_headless_bots_elapsed_s") as float


func _headless_bots_state_name() -> String:
	return _headless_bots_flow_port().call(&"_headless_bots_state_name") as String


## The headless bots flow, loaded through the serial prewarm queue on first use.
func _headless_bots_flow_port() -> MainHeadlessBotsFlowPort:
	if _headless_bots_flow == null:
		var flow_script: GDScript = _menu_prewarm_queue().ensure_script(HEADLESS_BOTS_FLOW_SCRIPT_PATH)
		_headless_bots_flow = flow_script.new() as MainHeadlessBotsFlowPort
		_headless_bots_flow.bind(self)
	return _headless_bots_flow


func _menu_prewarm_queue() -> MenuPrewarmQueue:
	if _prewarm_queue == null:
		_prewarm_queue = MenuPrewarmQueue.new()
		_prewarm_queue.config = load(MENU_PREWARM_CONFIG_PATH) as MenuPrewarmConfig
	return _prewarm_queue



# --- Menu / lobby routing -----------------------------------------------------

func _show_main_menu() -> void:
	Match.stats().reset_session_wins()  # Bontago-1pi.72.3: a fresh local session
	Sfx.set_music_context(&"menu")
	_clear_menu_and_lobby()
	# Bontago-xtq.42 fix round 2 (orchestrator review): the main menu is a
	# "no match world" screen -- force_close() handles the case where the
	# match ended by some means other than PauseMenu's own Leave button (e.g.
	# a host disconnect on a client, reaching this via _on_net_mode_changed()
	# below) while the overlay happened to be open; `suppressed = true` then
	# keeps pause_menu inert here, same as start_tutorial_from_menu()'s own.
	_pause_menu.force_close()
	_pause_menu.suppressed = true
	_main_menu = MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child(_main_menu)
	_main_menu.sandbox_requested.connect(start_sandbox_from_menu)
	_main_menu.tutorial_requested.connect(start_tutorial_from_menu)
	_main_menu.bots_requested.connect(start_bots_from_menu)
	_main_menu.gift_demo_requested.connect(start_gift_demo_from_menu)
	_main_menu.tower_topple_requested.connect(start_tower_topple_from_menu)


## DECISION: Play local → Vs bots starts from the normal lobby with one human
## and one bot selected. The lobby remains editable before Start, while LAN
## discovery stays off for this local entry point.
func start_bots_from_menu(player_name: String) -> void:
	var err: Error = Net.host_game(0, player_name, false)
	if err != OK:
		if _main_menu != null:
			_main_menu.show_status("Could not start local game: %s" % error_string(err))
		return
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = 2
	config.ai_count = 1
	Net.set_lobby_data(config.to_dict())


func _show_lobby() -> void:
	_prefetch_match_scenes()
	# Menu and lobby share a playlist; navigation must not restart the song.
	Sfx.set_music_context(&"menu")
	_clear_menu_and_lobby()
	# Bontago-xtq.42 fix round 2: see _show_main_menu()'s own comment just
	# above -- the lobby is equally a "no match world" screen.
	_pause_menu.force_close()
	_pause_menu.suppressed = true
	_lobby = _load_scene(LOBBY_SCENE_PATH).instantiate()
	add_child(_lobby)
	_lobby.connect(&"start_requested", _on_lobby_start_pressed)
	_lobby.connect(&"back_requested", _on_lobby_back_requested)
	# Must happen only once Net.is_host()/is_client() reflects the real mode
	# (register_world() reads it immediately, to set BlockRegistry's host
	# authority), which is exactly what firing here, after net_mode_changed,
	# guarantees -- and must happen before start_match(), on every instance:
	# the host calls that directly from the lobby, but a client's copy runs
	# the moment net/MatchNet.gd's net_match_start RPC arrives, with no chance
	# for Main to get in ahead of it any other way.
	Match.register_world(_field, _registry, _blocks_container)


func _clear_menu_and_lobby() -> void:
	if _main_menu != null and is_instance_valid(_main_menu):
		_main_menu.queue_free()
	_main_menu = null
	if _lobby != null and is_instance_valid(_lobby):
		_lobby.queue_free()
	_lobby = null


func _on_net_mode_changed(mode: int) -> void:
	if mode == Net.Mode.OFFLINE:
		# Covers both a deliberate leave and the host disconnecting a client
		# (autoload/Net.gd's _on_server_disconnected() calls leave(), which
		# emits this): never a half-dead match (docs/archive/M3a_PLAN.md
		# "Disconnects").
		_end_match_world()
		# DECISION (game/Main.gd): Net.leave() does not know about Match, so
		# the match is aborted here, where the session's end is routed.
		# Without it Match stayed PLAYING/END on the main menu -- still
		# ticking feed timers and the territory solve against a world that
		# no longer exists -- and the next host/join's start_match() came
		# from that stale state (Beads Bontago-mv0.1.9). abort_match() emits
		# (old -> LOBBY), which _on_match_state_changed() below answers with
		# the same _end_match_world() (idempotent, so the order of these two
		# lines does not matter); it is skipped when Match is already in the
		# lobby so a client whose host quit before starting sees no
		# LOBBY -> LOBBY emit.
		if Match.state() != Match.State.LOBBY:
			Match.abort_match()
		_show_main_menu()
	else:
		_show_lobby()


## Bontago-t8x.4: Match.start_match() runs the whole world build synchronously
## in one frame, so an overlay shown inside it is never presented before the
## freeze. The Lobby's Start button therefore lands here first: the overlay (and
## the clients' net_match_loading) goes up, tuning.pre_start_frames rendered
## frames pass, and only then _on_lobby_start_requested() starts the match.
## There is no separate match scene to thread-load: Main already hosts the
## world, and the skybox jpgs are decoded from raw files, not ResourceLoader
## resources.
func _on_lobby_start_pressed(config: MatchConfig) -> void:
	if not Net.is_host() or _start_pending:
		return
	_start_pending = true
	_loading_screen.show_pending(config)
	MatchNet.replicate_match_loading()
	for _i: int in range(_loading_screen.tuning.pre_start_frames):
		await get_tree().process_frame
	_start_pending = false
	if not Net.is_host() or not _loading_screen.is_pending():
		return
	_on_lobby_start_requested(config)


func _on_lobby_start_requested(config: MatchConfig) -> void:
	if not Net.is_host():
		return
	Match.start_match(config)


## Client side of the above: raise the overlay as soon as the host announces.
## Bontago-1pi.11.62: rarely used scenes are loaded on first use instead of
## preloaded at parse time. No member keeps the PackedScene: the resource cache
## holds it while an instance is alive and releases it afterwards.
func _load_scene(path: String) -> PackedScene:
	return load(path) as PackedScene


## Bontago-1pi.11.62: threaded prefetch of the match-start scene set so the
## world build's _load_scene() calls do not hitch (called while the lobby /
## loading screen is up).
func _prefetch_match_scenes() -> void:
	for path: String in [HOT_SEAT_SCENE_PATH, REMOTE_CURSORS_SCENE_PATH, NET_DEBUG_OVERLAY_SCENE_PATH]:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


func _on_match_loading_announced() -> void:
	if Match.state() != Match.State.LOBBY:
		return
	_prefetch_match_scenes()
	_loading_screen.show_pending(null)


func _on_loading_territory_updated(_raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	# DECISION: an applied result can arrive while the staged world is building.
	if Net.is_host() and _loading_screen.visible and not _loading_screen.is_pending():
		_first_territory_ready = true


func _on_loading_territory_replicated(_raster: TerritoryRaster) -> void:
	if Net.is_client() and _loading_screen.visible and not _loading_screen.is_pending():
		_first_territory_ready = true


func _on_loading_readiness_timed_out() -> void:
	_release_countdown_hold(_loading_generation)
	_loading_generation += 1
	if Net.is_host():
		Match.abort_match()
	else:
		Net.leave()


## ui/Lobby.gd's %BackButton (Bontago-xtq.32 redo #3, review finding #1):
## _show_lobby() above is only ever entered from _on_net_mode_changed() once
## Net is already HOST or CLIENT, so this needs no host/client branch --
## Net.leave()'s own contract ("the host disconnects everyone ... first",
## autoload/Net.gd) stops LAN/Steam advertising and drops peers for a host,
## or simply disconnects for a client, either way emitting
## Events.net_mode_changed(OFFLINE). _on_net_mode_changed() answers that the
## same way it answers a mid-match disconnect: _end_match_world(), an
## abort_match() skipped here too (Match is still LOBBY, the match never
## started), then _show_main_menu() -- the exact online-branch behaviour
## _on_pause_leave_requested() below already relies on for the pause menu's
## own Leave button.
func _on_lobby_back_requested() -> void:
	Net.leave()


## ui/PauseMenu.gd's own leave_match_requested (Leave match, confirmed).
## DECISION (game/Main.gd, minor ambiguity): the online/offline split lives
## here, not in ui/PauseMenu.gd (which never touches Net/Match -- see its own
## doc comment on this signal), because this file already owns exactly this
## split for the symmetric case, Net dropping to OFFLINE
## (_on_net_mode_changed() above): online (host or client alike --
## autoload/Net.gd's own leave() doc: "Safe to call... The host disconnects
## everyone... first"), Net.leave() already tears the match world down and
## shows the main menu through that same handler; offline (sandbox), there is
## no Net transition to react to, so this aborts the match directly
## (idempotent from LOBBY, matching _on_net_mode_changed()'s own guard) and
## shows the menu itself. _sandbox is freed explicitly because it is this
## package's own node, outside _end_match_world()'s ownership (see its own var
## doc comment above). A tutorial session never reaches this handler:
## ui/PauseMenu.gd is suppressed for its whole duration (start_tutorial_from_
## menu()/_on_tutorial_finished() above) -- Tutorial keeps its own existing
## ui_cancel -> _end_tutorial() quit gesture unmodified.
##
## DECISION (game/Main.gd, Bontago-xtq.42 round 3): _sandbox is freed and
## nulled *before* Match.abort_match() below, not after. _on_match_state_
## changed()'s own Bontago-xtq.43 round 2 fix diverts every (-> LOBBY)
## reaction away from _end_match_world() while _sandbox is still a live
## instance (see that handler's own DECISION) -- freeing it first here means
## abort_match()'s (old -> LOBBY) emit instead takes the ordinary
## _end_match_world() path, which is the only place that clears _world_built
## back to false. The previous order (abort_match() first, free second) left
## _world_built stuck true for the rest of this Main instance's life: the
## *next* ordinary (non-sandbox) match's _build_match_world() call then hit
## its own `if _world_built: return` guard and silently built nothing at all
## (no HotSeat, RemoteCursors, bot controllers or debug overlay) -- not a
## duplicate build, since Main never built any of those for a sandbox match
## to begin with (_on_match_state_changed()'s own doc). _field.clear_match_
## state() still runs exactly once, now via _end_match_world() itself instead
## of the diverted branch's own direct call, so a reset's visible field-clear
## behavior is unchanged. The online path above needs no matching fix: Net.
## leave() reaches _end_match_world() through _on_net_mode_changed() (a
## different handler, never diverted by _sandbox -- sandbox matches are
## always offline, so _sandbox is never live while Net.mode() != OFFLINE).
## tests/unit/test_sandbox.gd covers this with a regression test.
func _on_pause_leave_requested() -> void:
	if Net.mode() != Net.Mode.OFFLINE:
		Net.leave()
		return
	if _sandbox != null and is_instance_valid(_sandbox):
		# Bontago-1pi.46 (G8). ROOT CAUSE: queue_free() only frees at the end of the
		# frame, so the sandbox's PlayerController still ran _process once more after
		# the abort below had reset the camera (-> _end_match_world() ->
		# _reset_match_scope() -> CameraRig.reset_view()) and wrote its follow position
		# (0, 0.3, 0) back over the launch view; the menu then showed a stale camera.
		# Disabling the subtree stops every _process/_input at once, so the reset
		# below is the last word.
		_sandbox.process_mode = Node.PROCESS_MODE_DISABLED
		_sandbox.queue_free()
		_sandbox = null
		if _scoreboard != null:
			_scoreboard.suppressed = false
	if Match.state() != Match.State.LOBBY:
		Match.abort_match()
	_show_main_menu()


## Bontago-1pi.50 (owner playtest 2026-10-03: "return to lobby option from pause
## menu"): what ui/PauseMenu.gd's Return to lobby entry shows, answered here
## because only Main may name Net and Match for it (the menu's own header).
## HOST: enabled -- every hosted session has a lobby to go back to, a local
## "Vs bots" game included (Net.host_game() without advertising). CLIENT: shown
## disabled (DECISION: only the host can end a match for everyone; a client's
## own exit stays Leave match). OFFLINE (sandbox, --hot-seat): hidden --
## DECISION: no lobby exists there, and Leave match already goes to the main
## menu, so a second button doing the same would only confuse. "In progress"
## is a match the host is about to throw away (loading, countdown, play, sudden
## death); on the results screen (END) the result is already shown, so no
## confirmation is asked.
func _pause_menu_context() -> Dictionary:
	var entry: int = PauseMenu.ReturnEntry.HIDDEN
	match Net.mode():
		Net.Mode.HOST:
			entry = PauseMenu.ReturnEntry.ENABLED
		Net.Mode.CLIENT:
			entry = PauseMenu.ReturnEntry.DISABLED
	var state: int = int(Match.state())
	var in_progress: bool = Match.is_in_progress(state)
	return {"return_entry": entry, "match_in_progress": in_progress}


## ui/PauseMenu.gd's return_to_lobby_requested (Return to lobby, confirmed).
## Host: ends the match for every peer and puts them back in the session lobby,
## through the same path the results screen's Back to lobby takes
## (MatchNet.request_return_to_lobby() -> Match.abort_match(); called directly
## because that request is only honoured on State.END, and this one also works
## mid-match, which is the point). abort_match() fires (old -> LOBBY), which
## _on_match_state_changed() answers on the host with the world teardown, the
## match scope reset (Events.match_scope_reset, once) and the lobby; MatchNet
## replicates that same LOBBY change to every client, whose Main does likewise.
## Lobby settings (Net's cached lobby data) and the seats (Net's peer slots) are
## never touched by a match, so they come back as they were; Net.
## set_match_in_progress(false) reseats spectators and drops rejoin reservations
## like any return. DECISION (stats/results): the match is abandoned, so there
## is no winner, no results screen and no stats row -- abort_match() resets the
## stats and never emits the match-finished event.
## A client (disabled entry, so this should never arrive) and a lobby already
## showing are ignored. OFFLINE has no lobby: DECISION, it is Leave match.
func _on_pause_return_to_lobby_requested() -> void:
	if Net.mode() == Net.Mode.OFFLINE:
		_on_pause_leave_requested()
		return
	if not Net.is_host() or Match.state() == Match.State.LOBBY:
		return
	Match.abort_match()


# --- Building the match world (host and client alike) ------------------------

## Bontago-1pi.8: MatchLifecycle._build_slots() (autoload/match/
## MatchLifecycle.gd's start_match()) already ran before the LOBBY -> LOADING
## emit this feeds, so every slot's display_name/is_bot is already final for
## the match that is about to build -- collected into a plain array so
## ui/LoadingScreen.gd never has to reach for the Match singleton itself
## (same dependency-injection shape as ui/HUD.gd's match_provider seam, for
## the same reason: a bare array of PlayerSlot.new(...) is trivial to test).
func _loading_screen_slots() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(Match.slot_count()):
		var slot_item: PlayerSlot = Match.slot(i)
		if slot_item != null:
			slots.append(slot_item)
	return slots


# --- Match world: forwarders (Bontago-1pi.11.84 MF3) --------------------------
#
# The bodies live in game/MainMatchFlow.gd. R4: `_on_match_state_changed` is connected in _ready()
# and also fires from a client's net_match_start RPC with no other Main involvement, so every
# forwarder resolves the flow through `_match_flow_port()` (ensure_script first, bound once)
# before the first LOBBY -> LOADING reaction. The coroutine bodies are awaited so a test or caller
# that awaits the old name still waits, while fire-and-forget callers behave as before (a
# coroutine that never suspends completes synchronously, e.g. headless).

## Bontago-1pi.11.84: the match-world rules (state routing, world build/teardown, loading hand-off).
func _on_match_state_changed(from_state: int, to_state: int) -> void:
	_match_flow_port().on_match_state_changed(from_state, to_state)


func _finish_loading_when_ready(generation: int) -> void:
	await _match_flow_port().call(&"_finish_loading_when_ready", generation)


func _release_countdown_hold(generation: int) -> void:
	_match_flow_port().call(&"_release_countdown_hold", generation)


func _build_match_world(force_staging_for_test: bool = false) -> void:
	await _match_flow_port().call(&"build_match_world", force_staging_for_test)


func _spawn_bot_controllers(config: MatchConfig) -> void:
	_match_flow_port().spawn_bot_controllers(config)


func _reset_match_scope(reset_camera: bool = true) -> void:
	_match_flow_port().call(&"_reset_match_scope", reset_camera)


func _end_match_world() -> void:
	_match_flow_port().end_match_world()


## The match flow, loaded through the serial prewarm queue on first use (synchronous path).
func _match_flow_port() -> MainMatchFlowPort:
	if _match_flow == null:
		var flow_script: GDScript = _menu_prewarm_queue().ensure_script(MATCH_FLOW_SCRIPT_PATH)
		_match_flow = flow_script.new() as MainMatchFlowPort
		_match_flow.bind(self)
	return _match_flow


# --- Debug tools (Bontago-470.8) ---------------------------------------------

## Debug mode only (game/DebugMode.gd): the F1 perf overlay, its sampler and
## the per-session CSV logger. Lives under Main for the whole session, so it
## covers menus, lobby, matches and the sandbox alike. Not built (and PerfProbe
## stays disabled) for players.
func _build_debug_tools() -> void:
	PerfProbe.enabled = DebugMode.is_enabled()
	if not DebugMode.is_enabled():
		return
	var debug_config: DebugConfig = DebugMode.config()
	var sampler: PerfSampler = PerfSampler.new()
	sampler.config = debug_config
	add_child(sampler)
	var overlay: PerfOverlay = PerfOverlay.new()
	overlay.config = debug_config
	overlay.sampler = sampler
	add_child(overlay)
	var logger: PerfLogger = PerfLogger.new()
	logger.config = debug_config
	logger.sampler = sampler
	add_child(logger)


# --- Helpers -----------------------------------------------------------------

## Same "-" stripping Net._apply_command_line_args() uses, so "--hot-seat" and
## "-hot-seat" are both recognised the same way the rest of the command line
## is. Net itself never sees this flag (autoload/Net.gd's docstring lists
## exactly the flags it parses, and hot-seat is not networking's concern).
func _has_cmdline_flag(flag: String) -> bool:
	for raw: String in OS.get_cmdline_user_args():
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == flag:
			return true
	return false


## One-line report of the settings M0 is required to get right (spec 3.1, 3.5).
func _boot_line() -> String:
	var version: String = str(Engine.get_version_info().get("string", "unknown"))
	var physics_engine: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var ticks: int = Engine.physics_ticks_per_second
	var interpolated: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	return "Stackfall boot | godot %s | renderer %s | physics %s | %d Hz | interpolation %s" % [
		version, renderer, physics_engine, ticks, interpolated,
	]
