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

var _main_menu: MainMenu = null
var _lobby: Lobby = null
var _hot_seat: HotSeat = null
var _sandbox: Sandbox = null
## Bontago-1pi.70: set only by start_gift_demo_from_menu().
var _sandbox_preset: SandboxConfig = null
## docs/archive/M6_PLAN.md package B3: built/freed only by start_tutorial_from_menu()/
## _on_tutorial_finished() below -- never touched by _build_match_world()/
## _end_match_world() (this package does not own those functions).
var _tutorial: Tutorial = null
var _remote_cursors: RemoteCursors = null
var _debug_overlay: NetDebugOverlay = null
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
var _bot_controllers: Array[BotController] = []

## M8 P5 (spec 3.5 "Stable-block optimization"): one instance for the match
## currently built, same build/teardown lifecycle as _bot_controllers above
## (built in _build_match_world(), freed in _end_match_world()) -- see
## _build_match_world()'s own single wiring-point comment. Host-gated inside
## the manager itself (game/StableBlockManager.gd's own `Net.is_host()`
## check), so building one on a client too costs nothing and stays inert,
## exactly the reasoning _spawn_bot_controllers()'s own doc comment already
## gives for BotController.
var _stable_block_manager: StableBlockManager = null

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
		environment.volumetric_fog_enabled = preset.volumetric_fog_enabled


# --- Hot-seat: byte-identical to M2 ------------------------------------------

func _start_hot_seat_match() -> void:
	Sfx.set_music_context(&"gameplay")
	_hot_seat = _load_scene(HOT_SEAT_SCENE_PATH).instantiate() as HotSeat
	add_child(_hot_seat)
	_hot_seat.set_camera_rig(_camera_rig)
	_hot_seat.set_field(_field)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_hot_seat_config())

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	_apply_match_sky(config)
	_horizon_islands.rebuild_for_map(config.map_def(), _world_environment.environment if _world_environment != null else null)


## Bontago-1pi.108: every mode that builds a world (match, hot-seat, sandbox, tutorial)
## gets the same sky: the map's textured set plus the config's theme / cycle.
func _apply_match_sky(config: MatchConfig) -> void:
	_skybox.load_set(config.map_def().skybox_set)
	_skybox.configure_match_sky(config)


## The lobby settings a real lobby screen collects, for the one path that
## skips it. Hot-seat and the player count are the only overrides; everything
## else is whatever config/match_defaults.tres says.
func _build_hot_seat_config() -> MatchConfig:
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = true
	return config


# --- Sandbox: unlisted debug entry point (Bontago-mv0.8) ---------------------
#
# `godot --path . -- --sandbox [--players=N]` starts an *offline* match, same
# shape as _start_hot_seat_match() above (register_world() -> start_match()
# -> place_flags()/set_overlay_source()), but with every slot locally
# controllable, no feed timer, and unlimited blocks (config/MatchConfig.gd's
# `sandbox` flag; autoload/Match.gd's `_feed_timer_enabled`). Never reached by
# the menu/lobby, so it changes nothing about --hot-seat or the networked
# path above.

func _start_sandbox_match() -> void:
	_start_sandbox_match_with_args(OS.get_cmdline_user_args())


## Split from _start_sandbox_match() so a test can drive both the --players=
## parsing and the resulting world build with a manufactured argument list —
## the same seam autoload/Net.gd's _apply_command_line_args() uses, since
## there is no OS.set_cmdline_user_args() to fake the real one with.
func _start_sandbox_match_with_args(args: PackedStringArray) -> void:
	Sfx.set_music_context(&"gameplay")
	_sandbox = _load_scene(SANDBOX_SCENE_PATH).instantiate() as Sandbox
	add_child(_sandbox)
	# DECISION (Bontago-1pi.69): no scoreboard in the sandbox; Tab stays sandbox_next_slot.
	if _scoreboard != null:
		_scoreboard.suppressed = true
	_sandbox.set_camera_rig(_camera_rig)
	_sandbox.set_field(_field)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_sandbox_config(_sandbox_player_count(args)))

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	_apply_match_sky(config)
	_horizon_islands.rebuild_for_map(config.map_def(), _world_environment.environment if _world_environment != null else null)

	# F3's overlay works offline too (Net.stats() reports Offline/0 peers,
	# which is still useful context while sandbox-testing); it costs nothing
	# unopened, exactly as in the networked path below.
	_debug_overlay = _load_scene(NET_DEBUG_OVERLAY_SCENE_PATH).instantiate() as NetDebugOverlay
	add_child(_debug_overlay)

	# Bontago-1en.24: `--force-special=<id>` sets the same state F9
	# (sandbox_force_special) toggles at runtime, so a scripted sandbox launch
	# can start already forcing one special. _sandbox is already _ready()
	# (add_child() above runs it synchronously -- Main is already inside the
	# tree by the time _start_sandbox_match_with_args() runs from its own
	# _ready()), so its roster cache exists by the time this reaches it.
	var forced: String = _sandbox_force_special_arg(args)
	# Bontago-470.8: --force-special is a debug tool; ignored unless debug mode.
	if forced != "" and DebugMode.is_enabled():
		_sandbox.force_special_by_id(StringName(forced))


## The Main Menu's own entry point (docs/archive/M6_PLAN.md package B1; ui/MainMenu.
## gd's %SandboxButton, wired to this signal in _show_main_menu() below),
## unlike _start_sandbox_match()'s CLI-only one above: reachable only once
## the ordinary menu/lobby path in _ready() has already connected Events.
## match_state_changed, so Match.start_match()'s own (LOBBY -> LOADING) emit
## inside _start_sandbox_match_with_args() below would otherwise also run
## _build_match_world() -- which builds a *HotSeat*-driven world, not this
## function's own Sandbox one, and duplicates the field rebuild/overlay/
## debug-overlay work _start_sandbox_match_with_args() already does.
##
## _world_built = true here is now belt-and-braces rather than the only
## guard: _on_match_state_changed() itself diverts every state change away
## from _build_match_world()/_end_match_world() while _sandbox is a live
## instance (Bontago-xtq.43 round 2 -- see that handler's own DECISION), which
## is also what makes a later sandbox_reset_field (F5, game/Sandbox.gd's
## _reset_field()) safe: round 1 found that this line alone only suppressed
## the duplicate build on this *first* start, not on a later reset, because
## nothing re-armed it once _end_match_world() ran and cleared it back to
## false. _start_sandbox_match_with_args([]) below still runs byte-identical
## to the CLI path: default player count, no forced special.
func start_sandbox_from_menu() -> void:
	_sandbox_preset = null
	_launch_sandbox_from_menu()


func _launch_sandbox_from_menu() -> void:
	_clear_menu_and_lobby()
	# Bontago-1pi.46 (G5): this path bypasses _build_match_world(), so it needs
	# its own new-match reset -- before Sandbox.set_camera_rig() below, which
	# re-sets CameraRig.suppress_pad_home_focus that reset_view() clears.
	_reset_match_scope()
	_world_built = true
	# Bontago-xtq.42 fix round 2: _build_match_world() (which owns this same
	# line for every other match-start path) never runs for sandbox-from-menu
	# -- see the `_world_built = true` line right above -- so this path needs
	# its own explicit unsuppress.
	_pause_menu.suppressed = false
	_start_sandbox_match_with_args(PackedStringArray())


## Bontago-1pi.70: the Debug page's Gift demo. The ordinary sandbox launched
## with config/sandbox_gift_demo.tres: pre-placed opponent towers, gifts on at
## high frequency. Leaving goes through the sandbox pause menu like any sandbox.
func start_gift_demo_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	_sandbox_preset = load(GIFT_DEMO_PRESET_PATH) as SandboxConfig
	_launch_sandbox_from_menu()
	_sandbox.apply_preset(_sandbox_preset)


## Bontago-1pi.102: the Debug page's Tower topple. Same sandbox path with
## config/sandbox_tower_topple.tres: a row of settled towers (the tower tests'
## heights, up to the 30/40-block acceptance towers) to knock down with blocks
## and gifts.
func start_tower_topple_from_menu() -> void:
	if not DebugMode.is_enabled():
		return
	_sandbox_preset = load(TOWER_TOPPLE_PRESET_PATH) as SandboxConfig
	_launch_sandbox_from_menu()
	_sandbox.apply_preset(_sandbox_preset)


## Same lobby-settings-minus-a-few-overrides shape as _build_hot_seat_config().
## config.sandbox is what lets MatchConfig.sanitize() allow `player_count`
## below spec 2.8's normal floor of 2, and tells Match to start with its feed
## timer paused (autoload/Match.gd's start_match()).
func _build_sandbox_config(requested_player_count: int) -> MatchConfig:
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = requested_player_count
	config.hot_seat = false
	config.ai_count = 0
	config.sandbox = true
	if _sandbox_preset != null:
		if _sandbox_preset.special_frequency_override >= 0:
			config.gifts_enabled = true
			config.special_frequency = _sandbox_preset.special_frequency_override
	return config


## `--players=<n>`, parsed with the same "-"-stripping loop
## _has_cmdline_flag() and autoload/Net.gd's _apply_command_line_args() both
## use. Takes the argument list explicitly rather than reading
## OS.get_cmdline_user_args() itself (see _start_sandbox_match_with_args()),
## so a test can drive it with a manufactured list. Out-of-range values are
## not clamped here — MatchConfig.sanitize() (Match.start_match()) already
## does that against this config's own `sandbox` flag.
func _sandbox_player_count(args: PackedStringArray) -> int:
	const PREFIX: String = "players="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	if _sandbox_preset != null:
		return _sandbox_preset.default_player_count
	return sandbox_config.default_player_count


## `--force-special=<id>`, same "-"-stripping loop and same "takes the
## argument list explicitly" seam as _sandbox_player_count() right above (so a
## test can drive it with a manufactured list) -- validation of `<id>` against
## the real roster is game/Sandbox.gd's force_special_by_id()'s job, not this
## file's; an unrecognized id there warns and leaves forcing off rather than
## this parser guessing at the roster itself.
func _sandbox_force_special_arg(args: PackedStringArray) -> String:
	const PREFIX: String = "force-special="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return text.substr(PREFIX.length())
	return ""


# --- Tutorial: single-player onboarding (docs/archive/M6_PLAN.md package B3) --------
#
# Reachable only from the Main Menu's own %TutorialButton (ui/MainMenu.gd's
# tutorial_requested signal, the same direct child-signal convention
# start_sandbox_from_menu() above uses for sandbox_requested): a one-player,
# offline match built exactly like start_sandbox_from_menu()'s own
# register_world() -> start_match() -> place_flags()/set_overlay_source(),
# with config.sandbox = true (so ui/Tutorial.gd's own Match.debug_queue_
# special() call is allowed through MatchGifts.debug_queue_special()'s own
# host/config.sandbox gate) and config.player_count = 1 (there is only ever
# one tutorial participant). Never reached from --hot-seat/--sandbox or the
# real lobby/net path, so it changes nothing about either.

func start_tutorial_from_menu() -> void:
	_clear_menu_and_lobby()
	# Bontago-1pi.46 (G5): same bypass of _build_match_world() as the sandbox
	# start above, so the same new-match reset.
	_reset_match_scope()
	_world_built = true
	# Bontago-xtq.42: see ui/PauseMenu.gd's own `suppressed` doc comment --
	# Tutorial already owns ui_cancel/Escape for its own quit gesture, and the
	# two scenes' _unhandled_input() dispatch order relative to each other
	# (unrelated siblings under this node) is not a documented guarantee.
	_pause_menu.suppressed = true
	_tutorial = _load_scene(TUTORIAL_SCENE_PATH).instantiate() as Tutorial
	add_child(_tutorial)
	_tutorial.set_camera_rig(_camera_rig)
	_tutorial.finished.connect(_on_tutorial_finished)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_tutorial_config())

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	_apply_match_sky(config)
	_horizon_islands.rebuild_for_map(config.map_def(), _world_environment.environment if _world_environment != null else null)


## Same lobby-settings-minus-a-few-overrides shape as _build_sandbox_config()
## above: always exactly one player, config.sandbox = true so ui/Tutorial.gd's
## forced special (Match.debug_queue_special()) is let through.
func _build_tutorial_config() -> MatchConfig:
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = 1
	config.hot_seat = false
	config.ai_count = 0
	config.sandbox = true
	return config


## ui/Tutorial.gd's own `finished` signal (step 5 completing, or ui_cancel at
## any step -- see its own doc comment): frees the Tutorial subtree
## start_tutorial_from_menu() above built and returns to the Main Menu.
## ui/Tutorial.gd already called Match.abort_match() itself before emitting
## (consuming Match's own public API, not this package's -- Events.
## match_state_changed's own (-> LOBBY) emit has already run
## _on_match_state_changed()'s existing _end_match_world() call by the time
## this handler runs, the same way start_sandbox_from_menu()'s own
## _world_built guard above does), so this only has to clean up the one node
## this package added.
func _on_tutorial_finished() -> void:
	if _tutorial != null and is_instance_valid(_tutorial):
		_tutorial.queue_free()
	_tutorial = null
	# Bontago-xtq.42 fix round 2: _show_main_menu() below now owns re-
	# suppressing/force-closing this menu for every "no match world" screen,
	# so no explicit `= false` write belongs here -- see its own doc comment.
	_show_main_menu()


# --- Headless bot match: `--bots=<n>` (Bontago-d5c.6, M5 P5) -----------------
#
# `godot --headless --path . -- --headless-host --bots=<n> [--players=<n2>]
# [--seconds=<n3>]` starts a **real** networked match (config.sandbox = false,
# config.hot_seat = false -- the real feed/territory/win loop, unlike
# --sandbox above) with `n` bot-driven seats and no human required to click
# the Lobby's Start button. Unlike --hot-seat/--sandbox this does NOT return
# early out of _ready(): Events.match_state_changed/net_mode_changed are
# already connected and Net.apply_command_line() has already run host_game()
# for --headless-host by the time _ready() reaches this call, so
# Match.start_match() below's own (LOBBY -> LOADING) emit runs the normal
# _build_match_world() exactly as a lobby-started match would -- only the
# "wait for a human to press Start" step is skipped. This is deliberate: it
# is what lets _build_match_world()'s own bot-controller wiring (below) serve
# both this entry point and an ordinary mixed human+bot lobby match with one
# piece of code (docs/archive/M5_PLAN.md P5 item 3), rather than a second, divergent
# world-build path. host_game() can still fail (its port already bound, say)
# and leave Net at OFFLINE despite --headless-host being present on the
# command line; _net_is_hosting()'s guard below refuses to build a match in
# that case rather than silently running every bot against a session nothing
# can ever join.

func _start_headless_bot_match_with_args(args: PackedStringArray) -> void:
	var bots: int = _bots_arg(args)
	if bots <= 0:
		# Feature off by default: every existing `--headless-host`-only
		# command line (no `--bots=`) falls straight through to the normal
		# Lobby wait-for-Start path, unaffected.
		return
	if not _net_is_hosting():
		# Bontago-d5c.6 review finding 1: --headless-host's own host_game()
		# call (Net.apply_command_line(), already run by the time _ready()
		# reaches this branch -- see this function's own doc above) can fail
		# to bind its port and leave Net at OFFLINE. Net.is_host() cannot see
		# that failure (autoload/Net.gd's own doc: "True on the host **and
		# offline**" -- offline is the normal, successful state for
		# --sandbox/--hot-seat and every existing unit test's own fixture),
		# so _net_is_hosting() below checks Net.mode() directly instead.
		# Building a bot match with nobody actually hosting would run every
		# bot and the whole feed/territory/win loop against a session no
		# client, and no acceptance harness, could ever reach.
		push_error(
			"--headless-host --bots=%d: Net never became the host (host_game() likely failed to bind its port) -- refusing to start a bot match with no host." % bots
		)
		return
	Match.register_world(_field, _registry, _blocks_container)
	_headless_loop_enabled = _has_loop_matches_arg(args)
	_headless_loop_args = args
	_headless_loop_index = 0
	if _headless_loop_enabled:
		Events.match_state_changed.connect(_on_headless_loop_state_changed)
	_start_headless_loop_match(bots, args)

	# `--seconds=<n>` bounds the run with a hard wall-clock quit: the
	# acceptance command has no real win condition to end on within a CI
	# harness's own patience (docs/archive/M5_PLAN.md P5).
	var seconds: float = _seconds_arg(args)
	if seconds > 0.0:
		get_tree().create_timer(seconds).timeout.connect(_on_headless_bots_seconds_elapsed)


## Builds and starts one headless bot match. Without --loop-matches this is
## exactly the previous Match.start_match + diagnostics pair; with it, each
## match after the first gets a fresh rng_seed.
func _start_headless_loop_match(bots: int, args: PackedStringArray) -> void:
	var config: MatchConfig = _build_headless_bot_config(bots, args)
	_headless_loop_index += 1
	if _headless_loop_enabled:
		# DECISION (Bontago-8or.21): match 1 keeps the configured seed when one is
		# set; every later match draws a fresh positive seed so repeats differ.
		if _headless_loop_index > 1 or config.rng_seed < 0:
			config.rng_seed = randi_range(1, 2147483647)
		_headless_loop_seed = config.rng_seed
	Match.start_match(config)
	_start_headless_bots_diagnostics()


## `--loop-matches`, same "-"-stripping convention as the other flags.
func _has_loop_matches_arg(args: PackedStringArray) -> bool:
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == "loop-matches":
			return true
	return false


## Bontago-8or.21: on END print one compact `HEADLESS_MATCH` summary line and
## restart on the next frame (deferred, so the END emit finishes first; the
## restart goes END -> LOBBY -> LOADING, which tears the old world down).
func _on_headless_loop_state_changed(_from_state: int, to_state: int) -> void:
	if to_state != Match.State.END or _headless_loop_restart_pending:
		return
	print(_headless_match_summary_line())
	_headless_loop_restart_pending = true
	_restart_headless_loop_match.call_deferred()


func _restart_headless_loop_match() -> void:
	_headless_loop_restart_pending = false
	if not _headless_loop_enabled or not _net_is_hosting() or Match.state() != Match.State.END:
		return
	_start_headless_loop_match(_bots_arg(_headless_loop_args), _headless_loop_args)


func _headless_match_summary_line() -> String:
	return "HEADLESS_MATCH index=%d mode=%d seed=%d duration=%.1f winner_team=%d placements=%d homes_alive=%d" % [
		_headless_loop_index,
		Match.config.game_mode if Match.config != null else 0,
		_headless_loop_seed, _headless_bots_elapsed_s(), Match.winner_team(),
		_headless_bots_placements, _headless_bots_homes_alive(),
	]


## Bontago-d5c.6 review finding 1: true only when Net actually became the
## HOST, unlike Net.is_host() (autoload/Net.gd: "True on the host **and
## offline**"), which cannot tell a genuine offline mode apart from
## --headless-host's own host_game() call having failed to bind. A private
## helper rather than inlining `Net.mode() == Net.Mode.HOST` at the one call
## site above, so a test that needs to force either outcome has exactly one
## seam to reach for.
func _net_is_hosting() -> bool:
	return Net.mode() == Net.Mode.HOST


## `--bots=<n>`, same "-"-stripping/PREFIX convention as _sandbox_player_
## count()/_sandbox_force_special_arg() above. 0 when absent -- see
## _start_headless_bot_match_with_args()'s own "feature off by default" doc.
func _bots_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "bots="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## `--seconds=<n>`, same convention. 0.0 (unbounded -- the match runs until a
## real win condition or the process is killed) when absent.
func _seconds_arg(args: PackedStringArray) -> float:
	const PREFIX: String = "seconds="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return float(text.substr(PREFIX.length()))
	return 0.0


## Same "players="-reading loop as _sandbox_player_count(), with a different
## absent-flag default (0, so `maxi(bots, ...)` below reduces to exactly
## `bots` with no --players given -- docs/archive/M5_PLAN.md P5: "every seat a bot"
## is the literal acceptance command's own shape) -- kept separate from
## _sandbox_player_count() rather than reused, since that function's own
## absent-flag default (sandbox_config.default_player_count) is wrong here.
func _headless_bot_players_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "players="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## Same lobby-settings-minus-a-few-overrides shape as _build_hot_seat_config()/
## _build_sandbox_config() above: `config.player_count` may be raised past
## `bots` by `--players=<n2>` to leave human seats idle (docs/archive/M5_PLAN.md P5:
## "matching --sandbox's own --players= precedent, but is not required for
## the acceptance criterion"); `config.sandbox` stays false (unlike
## --sandbox's own config) -- this is a real match, real timers/cadence, the
## whole point being that the real feed/territory/win loop survives N
## concurrent bots, not sandbox's relaxed rules.
func _build_headless_bot_config(bots: int, args: PackedStringArray) -> MatchConfig:
	# DECISION (game/Main.gd, Bontago-3k0, deferred from Bontago-keo.19):
	# Net.match_config_override() (set by --match-config=<path>, parsed inside
	# Net's own host branch -- autoload/Net.gd's _apply_command_line_args())
	# takes over `match_config`'s usual role as the duplication source here,
	# extending this function's existing duplicate-then-override shape rather
	# than adding a second, parallel config path. Null (no flag, or a
	# rejected path/type) leaves this exactly as it was before the flag
	# existed.
	var base_config: MatchConfig = match_config
	if Net.match_config_override() != null:
		base_config = Net.match_config_override()
	var config: MatchConfig = base_config.duplicate(true) as MatchConfig
	config.ai_count = bots
	config.player_count = maxi(bots, _headless_bot_players_arg(args))
	config.hot_seat = false
	config.sandbox = false
	# DECISION (Bontago-mp0.27): headless bot matches have no human to wait for,
	# so they skip the 3-2-1 countdown (harnesses and loops stay fast).
	config.countdown_seconds = 0.0
	# DECISION (Bontago-1t5.3): `--mode=<classic|ctf|elimination|sky>` (or the
	# GameMode integer) picks the headless bot match's mode; absent keeps the
	# config's own mode. resolve_game_mode() still falls back for unselectable ids.
	# DECISION (Bontago-1t5.1): `--goals=<1..5>` overrides goal_flag_count for headless bot matches.
	# Bontago-1pi.107: `--disc-size=<step>` picks the disc-size slider step (0 tiny .. 5 enormous).
	var disc_step: int = _disc_size_arg(args)
	if disc_step >= 0:
		config.disc_size_step = DiscSizeTuning.shared().clamp_step(disc_step)

	var goals_override: int = _goals_arg(args)
	if goals_override > 0:
		config.goal_flag_count = clampi(goals_override, MatchConfig.GOAL_FLAG_MIN, MatchConfig.GOAL_FLAG_MAX)
	var mode_override: int = _mode_arg(args)
	if mode_override >= 0:
		config.game_mode = MatchConfig.resolve_game_mode(mode_override)
		config.round_timer_minutes = MatchConfig.clamp_round_timer(config.round_timer_minutes, config.game_mode)
	return config


## `--disc-size=<step>`, -1 when absent.
func _disc_size_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "disc-size="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return -1


## `--goals=<n>`, 0 when absent.
func _goals_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "goals="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text.begins_with(PREFIX):
			return int(text.substr(PREFIX.length()))
	return 0


## Bontago-1t5.1 diagnostics: per team, the most goals it holds in one group, "tN:k/total".
func _headless_bots_goal_coverage() -> String:
	var raster: TerritoryRaster = Match.raster()
	if raster == null or Match.config == null:
		return "n/a"
	var goals: PackedVector2Array = PlayerSlot.goal_positions_for(Match.config.effective_goal_flag_count(), Match.config.map_def())
	var by_group: Dictionary = {}
	for point: Vector2 in goals:
		var team: int = WinChecker.goal_holder(raster, point, Match._territory._claim_radius())
		if team < 0:
			continue
		var key: String = "%d/%d" % [team, raster.group_at_point(point)]
		by_group[key] = int(by_group.get(key, 0)) + 1
	var best_per_team: Dictionary = {}
	for key: String in by_group:
		var team_id: int = int(key.split("/")[0])
		best_per_team[team_id] = maxi(int(best_per_team.get(team_id, 0)), int(by_group[key]))
	var parts: PackedStringArray = PackedStringArray()
	for team_id: int in best_per_team:
		parts.append("t%d:%d/%d" % [team_id, int(best_per_team[team_id]), goals.size()])
	return "[%s]" % ",".join(parts)


## `--mode=<name|id>`, -1 when absent or unrecognised.
func _mode_arg(args: PackedStringArray) -> int:
	const PREFIX: String = "mode="
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if not text.begins_with(PREFIX):
			continue
		var value: String = text.substr(PREFIX.length()).to_lower()
		match value:
			"classic":
				return MatchConfig.GameMode.CLASSIC
			"ctf", "capture_the_flag":
				return MatchConfig.GameMode.CAPTURE_THE_FLAG
			"elimination":
				return MatchConfig.GameMode.ELIMINATION
			"sky", "reach_the_sky":
				return MatchConfig.GameMode.REACH_THE_SKY
			"domination":
				return MatchConfig.GameMode.DOMINATION
		if value.is_valid_int():
			var id: int = int(value)
			if MatchConfig.resolve_game_mode(id) != id:
				push_warning("--mode=%s is reserved or unselectable; falling back to %d" % [value, MatchConfig.resolve_game_mode(id)])
			return id
		push_warning("--mode=%s is not a known mode id; keeping the configured mode" % value)
		return -1
	return -1


# --- Headless bot match diagnostics (Bontago-d5c.6 review finding 2) ---------
#
# The literal acceptance command (`--headless-host --bots=8 --seconds=60`) has
# no console to watch, so this prints one `HEADLESS_BOTS` line every
# HEADLESS_BOTS_REPORT_INTERVAL_S and a final one right before the --seconds
# quit, each carrying the wall-clock time since the match began, Match's own
# state name and how many blocks have been placed so far (Events.block_placed
# -- autoload/Events.gd: "a block became a live physics body, either placed by
# a player or auto-dropped when its feed timer ran out", exactly what a bot's
# own placements are). Diagnostics only: nothing here feeds a rule or a test
# assertion about gameplay, only a human (or tools/triage_log.py) reading the
# log. `bots_active` from the brief is omitted -- BotController's own _state
# (game/BotController.gd) has no public accessor and this file does not own
# that script, so reading it here is not "cheaply readable" without editing a
# file outside this package's ownership.

func _start_headless_bots_diagnostics() -> void:
	# Idempotent (Bontago-8or.21): a --loop-matches restart must not double-connect
	# block_placed or leak a second report Timer.
	_stop_headless_bots_diagnostics()
	_headless_bots_start_msec = Time.get_ticks_msec()
	_headless_bots_placements = 0
	Events.block_placed.connect(_on_headless_bots_block_placed)
	_headless_bots_report_timer = Timer.new()
	_headless_bots_report_timer.wait_time = HEADLESS_BOTS_REPORT_INTERVAL_S
	_headless_bots_report_timer.autostart = true
	_headless_bots_report_timer.timeout.connect(_on_headless_bots_report_tick)
	add_child(_headless_bots_report_timer)


## Torn down from _end_match_world() (idempotent: a no-op for every match
## world that never called _start_headless_bots_diagnostics() above, since
## _headless_bots_report_timer stays null and Events.block_placed was never
## connected by this instance).
func _stop_headless_bots_diagnostics() -> void:
	if Events.block_placed.is_connected(_on_headless_bots_block_placed):
		Events.block_placed.disconnect(_on_headless_bots_block_placed)
	if _headless_bots_report_timer != null and is_instance_valid(_headless_bots_report_timer):
		_headless_bots_report_timer.queue_free()
	_headless_bots_report_timer = null


func _on_headless_bots_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	_headless_bots_placements += 1


func _on_headless_bots_report_tick() -> void:
	print(_headless_bots_periodic_line())


## _start_headless_bot_match_with_args()'s own `--seconds=<n>` quit timer,
## above: prints one last line (with the same counters the periodic line
## used) so the acceptance command's log always ends with a placements total,
## even when the process quits between two HEADLESS_BOTS_REPORT_INTERVAL_S
## ticks.
func _on_headless_bots_seconds_elapsed() -> void:
	print(_headless_bots_done_line())
	await Sfx.drain_for_quit()
	get_tree().quit(0)


func _headless_bots_periodic_line() -> String:
	return "HEADLESS_BOTS t=%.1f state=%s placements=%d mode=%d homes_alive=%d frontier_gap=%.2f goals=%s" % [
		_headless_bots_elapsed_s(), _headless_bots_state_name(), _headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
		_headless_bots_frontier_gap(), _headless_bots_goal_coverage(),
	]


func _headless_bots_done_line() -> String:
	return "HEADLESS_BOTS done t=%.1f placements=%d mode=%d homes_alive=%d" % [
		_headless_bots_elapsed_s(), _headless_bots_placements,
		Match.config.game_mode if Match.config != null else 0, _headless_bots_homes_alive(),
	]


## Bontago-1t5.4 diagnostics: smallest (distance to a living enemy home minus
## the circle's radius) over every circle, i.e. how close any team's influence
## frontier is to an enemy home (<= 0 means a circle covers one). -1 when n/a.
func _headless_bots_frontier_gap() -> float:
	var arrays: Dictionary = Match.circle_render_arrays()
	var xs: PackedFloat32Array = arrays.get("xs", PackedFloat32Array()) as PackedFloat32Array
	var zs: PackedFloat32Array = arrays.get("zs", PackedFloat32Array()) as PackedFloat32Array
	var radii: PackedFloat32Array = arrays.get("radii", PackedFloat32Array()) as PackedFloat32Array
	var teams: PackedInt32Array = arrays.get("teams", PackedInt32Array()) as PackedInt32Array
	var best: float = INF
	for i: int in range(mini(teams.size(), radii.size())):
		for slot_index: int in range(Match.slot_count()):
			var slot: PlayerSlot = Match.slot(slot_index)
			if slot == null or not slot.home_flag_alive or Match.team_of(slot_index) == teams[i]:
				continue
			best = minf(best, Vector2(xs[i], zs[i]).distance_to(slot.home_position) - radii[i])
	return best if best != INF else -1.0


## Living home flags (diagnostics: shows whether an Elimination bot match
## eliminated anyone).
func _headless_bots_homes_alive() -> int:
	var alive: int = 0
	for i: int in range(Match.slot_count()):
		var slot: PlayerSlot = Match.slot(i)
		if slot != null and slot.home_flag_alive:
			alive += 1
	return alive


func _headless_bots_elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _headless_bots_start_msec) / 1000.0


## Match.State's own name for Match.state() (e.g. "PLAYING"), read the same
## way an enum-to-string helper would if Match exported one: Dictionary.
## find_key() on the enum itself, since GDScript enums are plain Dictionaries
## under the hood. "UNKNOWN" only if Match.state() is ever a value the enum
## does not declare, which should not be possible.
func _headless_bots_state_name() -> String:
	var key: Variant = Match.State.find_key(Match.state())
	return str(key) if key != null else "UNKNOWN"


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
	_lobby = _load_scene(LOBBY_SCENE_PATH).instantiate() as Lobby
	add_child(_lobby)
	_lobby.start_requested.connect(_on_lobby_start_pressed)
	_lobby.back_requested.connect(_on_lobby_back_requested)
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

## The world exists exactly while Match is past the lobby. Match guarantees
## that a genuine start always arrives as LOBBY -> LOADING (start_match()
## goes back through abort_match() first from any later state), with the
## raster, slots and registry already built when the signal fires, so this
## binds them synchronously. The from_state guard is deliberate, not
## belt-and-braces: a client's mirror re-emits the host's replicated LOADING
## as (COUNTDOWN -> LOADING) after net_match_start already ran its own start
## (Match.apply_replicated_state_change), and that must not rebuild anything.
func _on_match_state_changed(from_state: int, to_state: int) -> void:
	if to_state == Match.State.LOADING:
		Sfx.set_music_context(&"gameplay")
	# Spec 3.4: joining is lobby-only in M3a. Net must not name Match, so the
	# match flow flips Net's gate here, where every state change is routed: a
	# handshake arriving while the match is past LOBBY is refused with
	# JoinError.MATCH_IN_PROGRESS, and abort_match()'s (old -> LOBBY) emit
	# reopens it (Net.leave() also resets it itself). On a client this is a
	# harmless flag write; _rpc_handshake is host-gated (Beads Bontago-mv0.1.8).
	#
	# Bontago-8or.11 (spec 3.4 "Mid-match joins can be enabled in settings"):
	# a live match also admits new joiners when its config allows it. LOADING
	# (synchronous on the host) and END stay closed; MatchNet replays the
	# world to whoever is admitted. Net is told when a match world starts and
	# when the session really returns to the lobby -- not the transient LOBBY
	# a replay/restart passes through inside start_match() -- so it can keep
	# and drop rejoin reservations and reseat spectators.
	if to_state == Match.State.LOADING:
		Net.set_match_in_progress(true)
	elif to_state == Match.State.LOBBY and not Match._lifecycle.is_starting_match():
		Net.set_match_in_progress(false)
	var live_state: bool = Match.is_replicating(to_state)
	var mid_match_join: bool = live_state and Match.config != null and Match.config.allow_mid_match_join
	Net.set_accepting_joins(to_state == Match.State.LOBBY or mid_match_join)

	# DECISION (game/Main.gd, Bontago-xtq.43 round 2): a sandbox reset
	# (sandbox_reset_field, F5 -- game/Sandbox.gd's _reset_field()) re-runs
	# Match.start_match() with its own current config, which always goes back
	# through abort_match() first (MatchLifecycle.start_match()'s own doc: "A
	# start from anything but LOBBY first goes back through the lobby"), so a
	# reset fires this handler twice in a row, synchronously: (X -> LOBBY)
	# then (LOBBY -> LOADING). game/Sandbox.gd already owns the whole world
	# for every slot in a sandbox match (its own PlayerController/GhostPreview
	# subtree -- never Main's _hot_seat) and already replays Field.
	# place_flags()/set_overlay_source() itself right after start_match()
	# returns (see _reset_field()'s own doc) -- so routing this pair through
	# the ordinary _end_match_world()/_build_match_world() below tore down and
	# then rebuilt a *second*, independent HotSeat (_build_match_world() has
	# no way to know a Sandbox is already serving every slot) bound to the
	# same local slot Sandbox's own controller already drives, both then
	# reading input for it (round 1's reproduction: LOCAL_HELD_GROUP count
	# growing 2 -> 3 -> 4 -> 5 across resets).
	#
	# Checked against the live _sandbox instance rather than Match.config.
	# sandbox: Tutorial also sets that flag on its own config (start_tutorial_
	# from_menu()'s _build_tutorial_config()), and its _on_tutorial_finished()
	# teardown still needs the ordinary _end_match_world() reaction to
	# (-> LOBBY) to run -- unlike Sandbox, Tutorial has a real "return to
	# menu" exit and never mid-session-resets. _sandbox is non-null for
	# exactly the lifetime of a sandbox match on this Main instance (no
	# "return to menu" path out of sandbox exists today), so this only ever
	# diverts the reaction while a sandbox match is actually live.
	#
	# _field.clear_match_state() is still run directly on the (X -> LOBBY)
	# half, so a reset still actually clears holes/tilt/physical-balance state
	# the same way it visibly did before this fix (the previous, buggy
	# _end_match_world() call happened to do that too, as a side effect of
	# also building the duplicate world) -- everything else _end_match_world()/
	# _build_match_world() would otherwise touch (SnapshotSync, _remote_
	# cursors, bot controllers, the debug overlay Sandbox already built itself
	# in _start_sandbox_match_with_args()) is correctly left alone; Sandbox's
	# own place_flags()/set_overlay_source() calls right after start_match()
	# returns pick the field back up from there.
	if _sandbox != null and is_instance_valid(_sandbox):
		if to_state == Match.State.LOBBY:
			_field.clear_match_state()
			# Bontago-1pi.46: a sandbox reset is a new match too -- dry arena;
			# the camera stays where the player put it, and so does the sandbox's
			# own CameraRig.suppress_pad_home_focus (only a camera reset clears it).
			_reset_match_scope(false)
		elif Match.is_start_transition(from_state, to_state) and Match.config != null:
			# Bontago-1pi.127 (owner screenshot: the sandbox showed the painted sunset after
			# F5): the scope reset on the (X -> LOBBY) half returns the Skybox to its launch
			# sky (the static painted-panorama sunset), so the restart sets the sandbox's sky
			# up again like at entry.
			_apply_match_sky(Match.config)
		return

	if to_state == Match.State.LOBBY:
		_loading_generation += 1
		_end_match_world()
		# Bontago-1pi.8: safety net for a match aborted mid-load -- see
		# LoadingScreen.cancel()'s own doc.
		_loading_screen.cancel()
		# A results-screen return ends the match without changing Net's mode,
		# so _on_net_mode_changed() cannot rebuild the lobby for us. A replay
		# briefly passes through LOBBY inside start_match(); keep that transition
		# out of the UI route so the new match builds directly.
		if not Match._lifecycle.is_starting_match() and not Net.is_offline():
			_show_lobby()
	elif Match.is_start_transition(from_state, to_state):
		_loading_generation += 1
		_first_territory_ready = false
		# Bontago-1pi.8: shown before _build_match_world() below runs, so the
		# overlay is already queued to composite over this same frame's draw
		# pass -- see ui/LoadingScreen.gd's own header doc.
		_loading_screen.show_for_match(Match.config, _loading_screen_slots())
		# Bontago-mp0.27. # DECISION: the 3-2-1 must start once the loading screen
		# is gone, not run down behind it. Held from here until
		# _finish_loading_when_ready() releases it (a reset/abort also clears it).
		# Skipped headless: no loading screen is ever rendered there, and tests
		# and bot harnesses drive Match by hand.
		if DisplayServer.get_name() != "headless":
			Match.set_countdown_held(true)
		_build_match_world()
	elif to_state == Match.State.COUNTDOWN:
		_finish_loading_when_ready(_loading_generation)


func _finish_loading_when_ready(generation: int) -> void:
	while not _world_built:
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	if not _loading_screen.visible:
		_release_countdown_hold(generation)
		return
	_loading_screen.set_stage("Solving territory", _loading_screen.tuning.solve_progress)
	while not _first_territory_ready:
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
	_loading_screen.set_stage("Warming materials", _loading_screen.tuning.materials_progress)
	_loading_screen.warm_common_materials()
	for frame: int in range(_loading_screen.tuning.stable_frames):
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_release_countdown_hold(generation)
			return
		_loading_screen.set_stage("Stabilizing view", lerpf(_loading_screen.tuning.stabilize_start_progress, _loading_screen.tuning.stabilize_end_progress, float(frame + 1) / maxf(float(_loading_screen.tuning.stable_frames), 1.0)))
	_loading_screen.set_stage("Ready", _loading_screen.tuning.complete_progress)
	# Bontago-mp0.27: the camera starts at the local player's own beacon, looking
	# at the centre, whatever the loading frames did to it.
	if _hot_seat != null and _camera_rig != null:
		_camera_rig.begin_start_framing(Net.local_slot())
	if _hot_seat != null:
		_hot_seat.controller().set_process(_controller_was_processing)
		_hot_seat.controller().set_process_unhandled_input(_controller_was_handling_input)
	await _loading_screen.fade_out()
	# Bontago-mp0.27: the screen is gone; now the 3-2-1 starts running down.
	_release_countdown_hold(generation)


## Bontago-mp0.27 review: every exit of the loading hand-off (overlay already
## hidden, cancelled, timed out, superseded) must free the countdown hold, or a
## match could sit held. A stale generation belongs to a newer load, which owns
## the hold now, so only the current generation releases.
func _release_countdown_hold(generation: int) -> void:
	if generation == _loading_generation:
		Match.set_countdown_held(false)


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


func _build_match_world(force_staging_for_test: bool = false) -> void:
	if _world_built or _world_building:
		return
	_world_building = true
	var generation: int = _loading_generation
	# Bontago-1pi.46: the single new-match entry (host, client and headless
	# alike) -- starts from the launch camera and a dry arena whatever the
	# previous match left behind, and tells the persistent owners (Events.
	# match_scope_reset) to do the same. Runs before configure_match_sky() below.
	_reset_match_scope()
	# DECISION: only a visible interactive overlay needs frame-separated stages.
	# Headless hosts and test/probe runs retain the synchronous start contract.
	var stage_build: bool = force_staging_for_test or (_loading_screen != null and _loading_screen.visible and DisplayServer.get_name() != "headless" and not AgentProbe.is_active())
	_clear_menu_and_lobby()
	# Bontago-xtq.42 fix round 2: every real (host/client/headless-bot) match
	# reaches this one guarded builder -- start_sandbox_from_menu() above is
	# the only match-start path that bypasses it (see its own doc comment),
	# so it needs its own copy of this line.
	_pause_menu.suppressed = false

	var config: MatchConfig = Match.config
	_field.rebuild_for_map(config.map_def())
	_camera_rig.set_map_def(config.map_def())
	_loading_screen.set_stage("Placing flags", _loading_screen.tuning.flags_progress)
	if stage_build:
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return
	_field.place_flags(config.player_count, config.player_colors, config.effective_goal_flag_count())
	_loading_screen.set_stage("Preparing territory", _loading_screen.tuning.territory_progress)
	if stage_build:
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return
	_field.set_overlay_source(Match.raster(), config.territory_colors())
	_apply_match_sky(config)
	_horizon_islands.rebuild_for_map(config.map_def(), _world_environment.environment if _world_environment != null else null)
	# Bontago-470.4: the lobby's Day/Night/Random, resolved by the host and
	# replicated; the F4 Theme dropdown still overrides live afterwards.

	SnapshotSync.set_disk(_field)
	SnapshotSync.begin_match(Match.registry(), config.map_def())
	_loading_screen.set_stage("Preparing players", _loading_screen.tuning.players_progress)
	if stage_build:
		await get_tree().process_frame
		if generation != _loading_generation or not _loading_screen.visible:
			_world_building = false
			return

	_remote_cursors = _load_scene(REMOTE_CURSORS_SCENE_PATH).instantiate() as RemoteCursors
	add_child(_remote_cursors)

	# Bontago-d5c.6 (M5 P5): a HotSeat instance always binds Net.local_slot()
	# (0 on the host, whether online, offline or the headless-bots path
	# above), so it must not be built when that slot itself is a bot -- the
	# all-bot `--bots=<n>` acceptance command (config.player_count ==
	# config.ai_count, no `--players=` override) leaves no human slot at all.
	# A mixed lobby match (some humans, some bots) still gets it exactly as
	# before: humans always fill the lowest slot ids first (MatchLifecycle.
	# _build_slots()'s `is_bot = i >= player_count - ai_count`), so
	# Net.local_slot() is never a bot slot on any path but this one.
	# Bontago-8or.11: a mid-match spectator (Net.local_slot() == -1) gets no
	# controller at all.
	# DECISION (Bontago-8or.11): it watches through the default camera rig
	# with no HotSeat -- there is no slot for one to drive.
	if config.ai_count < config.player_count and Net.local_slot() >= 0:
		_hot_seat = _load_scene(HOT_SEAT_SCENE_PATH).instantiate() as HotSeat
		add_child(_hot_seat)
		_hot_seat.set_camera_rig(_camera_rig)
		_hot_seat.set_field(_field)
		_hot_seat.bind_local_slot(Net.local_slot())
		# Bontago-mv0.26 (owner test 2026-09-22, "the original lets me keep moving
		# once I hit the edge of the screen"): HotSeat.gd's own _ready() already
		# calls this unconditionally (this scene is the exact same HOT_SEAT_SCENE_PATH scene
		# --hot-seat uses), so it should already be captured by the time
		# add_child() above returns. Called again here, explicitly, the same way
		# HotSeat.gd/Sandbox.gd each call it for their own subtree: this world
		# build is the one place that wires a controller into a match Main itself
		# owns, so it gets its own direct call rather than depending solely on a
		# child scene's _ready() timing -- idempotent (enable_mouse_capture() just
		# re-sets Input.mouse_mode) and a no-op headless, so it changes nothing
		# for --headless-host or the test suite.
		_hot_seat.controller().enable_mouse_capture()
		_controller_was_processing = _hot_seat.controller().is_processing()
		_controller_was_handling_input = _hot_seat.controller().is_processing_unhandled_input()
		if stage_build:
			_hot_seat.controller().set_process(false)
			_hot_seat.controller().set_process_unhandled_input(false)

	_spawn_bot_controllers(config)

	# M8 P5's single wiring point (docs/M8_PLAN.md P5): built here, right
	# alongside _spawn_bot_controllers() above, for the same reason every
	# other host-only match manager already lives in this function --
	# BlockRegistry.all_blocks() only has anything to scan once _registry
	# itself is populated, which SnapshotSync.begin_match(Match.registry(),
	# ...) above has already done by this point.
	_stable_block_manager = StableBlockManager.new()
	add_child(_stable_block_manager)
	_stable_block_manager.setup(_registry)

	_debug_overlay = _load_scene(NET_DEBUG_OVERLAY_SCENE_PATH).instantiate() as NetDebugOverlay
	add_child(_debug_overlay)

	# Bontago-xtq.26 (M7 P1): re-applies the current preset once the match
	# world exists. _world_environment is a static child of Main today, so
	# this is a no-op repeat of the _ready()-time call -- kept here anyway
	# because this is the one shared scene-load path (lobby-driven and
	# headless-bot matches alike), so a later package that adds a
	# WorldEnvironment under the field rebuilt above (P3's FogVolume) picks up
	# the current preset without this package having to guess at that
	# not-yet-built structure.
	_apply_graphics_preset(Settings.current_graphics_preset())
	_world_built = true
	_world_building = false


## docs/archive/M5_PLAN.md P5 item 3: one BotController per bot slot, for the
## headless-only-bots path above (_start_headless_bot_match_with_args()'s own
## Match.start_match() reaches this function too, via Events.match_state_
## changed -- see its own doc) and an ordinary mixed human+bot lobby match
## alike -- the trailing `config.ai_count` slots, exactly matching
## MatchLifecycle._build_slots()'s own `is_bot` assignment
## (`i >= player_count - ai_count`). Host-gated inside BotController itself
## (`game/BotController.gd`'s own `_is_host()` check), so building one on a
## client too costs nothing and stays inert.
##
## Lobby rework (Bontago-1pi.53): each bot gets its own seat's difficulty
## (MatchConfig.ai_difficulty_for_slot(): slot_ai_difficulties[slot] when the
## lobby set per-seat values, else the lobby-wide ai_difficulty -- so `--bots=N`,
## sandbox and every older config keep the single shared difficulty).
func _spawn_bot_controllers(config: MatchConfig) -> void:
	var first_bot_slot: int = config.player_count - config.ai_count
	for slot_id: int in range(first_bot_slot, config.player_count):
		var bot: BotController = BotController.new()
		add_child(bot)
		bot.setup(slot_id, config.ai_difficulty_for_slot(slot_id), _field, _registry)
		_bot_controllers.append(bot)


## Bontago-1pi.46 (owner playtest: "leaving match and starting a new match
## doesn't reset properly ... my camera and zoom level were the same as when i
## left the old match and the arena still had rain puddles"; owner requirement:
## after leaving a match and starting another, everything is as if freshly
## launched). ROOT CAUSE: the CameraRig, the Field's RainPuddles layer and a
## number of autoloads/presentation nodes are persistent, so they outlived every
## match; a match start re-aimed only the camera's yaw/target, and puddles dry
## over RainTuning.puddle_dry_time_s. This is the one presentation-reset entry
## (docs/MATCH_RESET_AUDIT.md section 4): Main resets the children it owns
## directly, then emits Events.match_scope_reset for every persistent owner it
## cannot name. Run when a match world is built, when one is torn down (also a
## cancelled staged build and a menu sandbox/tutorial) and on a sandbox reset;
## synchronous and idempotent, so the next match starts like a fresh launch.
## `reset_camera` is false only for a sandbox reset (F5), where the player keeps
## their view.
func _reset_match_scope(reset_camera: bool = true) -> void:
	RainPuddles.clear_on(_field)
	if reset_camera and _camera_rig != null:
		_camera_rig.reset_view()
	Events.match_scope_reset.emit()


func _end_match_world() -> void:
	# Bontago-1pi.46 (G5). DECISION: the scope reset runs before the _world_built
	# early return, so every (-> LOBBY) -- including a staged build that was
	# cancelled before it finished (_world_built still false), and a CLI
	# --sandbox, which never sets it -- leaves a launch-state camera, dry arena
	# and reset persistent owners. Such a half-built world still touched the
	# Field (flags, rebuild, overlay), so it is cleared here too. Idempotent: a
	# net leave reaches this twice (mode change, then the abort's -> LOBBY).
	if not _world_built:
		_field.clear_match_state()
		_reset_match_scope()
		return
	_world_built = false
	_stop_headless_bots_diagnostics()
	SnapshotSync.end_match()
	# Field is persistent (unlike everything else torn down below) and Match's
	# own teardown never touches it, so its flags, overlay raster reference
	# and open holes would otherwise still belong to the match that just ended
	# (Beads Bontago-mv0.1.9).
	_field.clear_match_state()
	# Bontago-1pi.46: and the menu/lobby behind it looks like a fresh launch too.
	_reset_match_scope()
	if _remote_cursors != null and is_instance_valid(_remote_cursors):
		_remote_cursors.queue_free()
	_remote_cursors = null
	if _hot_seat != null and is_instance_valid(_hot_seat):
		_hot_seat.queue_free()
	_hot_seat = null
	for bot: BotController in _bot_controllers:
		if bot != null and is_instance_valid(bot):
			bot.queue_free()
	_bot_controllers.clear()
	if _stable_block_manager != null and is_instance_valid(_stable_block_manager):
		_stable_block_manager.queue_free()
	_stable_block_manager = null
	if _debug_overlay != null and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
	_debug_overlay = null


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
