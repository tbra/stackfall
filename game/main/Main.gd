class_name Main
extends Node3D
## The game's entry point: a router, not a match.
##
## It stays deliberately thin: every system self-wires through the Events bus or
## a `Variant` provider seam, so Main only ever hands pieces to each other
## once, in the right order, and reacts to the handful of signals that mark a
## state change.
##
## Main shows ui/menus/MainMenu.tscn, then ui/lobby/Lobby.tscn once Net
## enters HOST or CLIENT (Events.net_mode_changed — apply_command_line()'s
## --host/--join/--headless-host fire it exactly the same as the menu's
## own buttons do), then builds the match world when Match's state machine
## crosses LOBBY -> LOADING: on the host that follows a direct
## Match.start_match() call from the Lobby's start_requested signal; on a
## client it follows net/MatchNet.gd's net_match_start RPC calling that
## same Match.start_match() locally. Reacting to the state change instead
## of branching on host/client here is what lets one code path build the
## world identically on every instance. The world comes down again
## whenever Match returns to LOBBY -- Match.abort_match(), which
## start_match() itself runs first when a match is restarted from any
## later state -- and when Net drops to OFFLINE, which also aborts the
## stale Match so it stops ticking and the next host/join starts from a
## clean LOBBY.
##
## **Wiring order matters**: Match.register_world() must
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
## _physics_process, never _process (frozen bodies are driven from the physics step).

## Default lobby settings. start_match() duplicates and
## sanitizes it, so the resource on disk is never mutated.
@export var match_config: MatchConfig = preload("res://config/match/match_defaults.tres")
## Tunables for the unlisted `--sandbox` debug entry point (config/match/SandboxConfig.gd).
@export var sandbox_config: SandboxConfig = preload("res://config/match/sandbox.tres")

const MAIN_MENU_SCENE: PackedScene = preload("res://ui/menus/MainMenu.tscn")
const BOT_COST_OVERLAY_PATH: String = "res://ui/debug/PerfBotCostOverlay.gd"
const SOAK_MONITOR_PATH: String = "res://game/debug/SoakMonitor.gd"
const SOAK_FUZZER_PATH: String = "res://game/debug/SoakIntentFuzzer.gd"
const SOAK_CONFIG_PATH: String = "res://config/soak/soak_config.tres"
## DECISION: Field, CameraRig and BlockRegistry are NOT dormant: they settle reset state (Field
## tilt basis, camera follow/origin/target) that a results->lobby leave starts, and pausing them
## left the next match differing from a fresh launch (test_match_reset_fingerprint). Only the
## purely visual sky roots go dormant.
const MENU_DORMANT_WORLD_NODES: PackedStringArray = [
	"Skybox", "AmbientLife", "CloudShadows",
]
const MENU_PREWARM_CONFIG_PATH: String = "res://config/match/menu_prewarm.tres"
const HEADLESS_BOTS_FLOW_SCRIPT_PATH: String = "res://game/main/MainHeadlessBotsFlow.gd"
const SANDBOX_FLOW_SCRIPT_PATH: String = "res://game/main/MainSandboxFlow.gd"
const MATCH_FLOW_SCRIPT_PATH: String = "res://game/main/MainMatchFlow.gd"
const LOBBY_SCENE_PATH: String = "res://ui/lobby/Lobby.tscn"
const LOCAL_PLAYER_SCENE_PATH: String = "res://game/main/LocalPlayer.tscn"
const WATCH_BOTS_OPTIONS_PATH: String = "res://game/main/WatchBotsOptions.gd"
const SANDBOX_SCENE_PATH: String = "res://game/sandbox/Sandbox.tscn"
const GIFT_DEMO_PRESET_PATH: String = "res://config/match/sandbox_gift_demo.tres"
const TOWER_TOPPLE_PRESET_PATH: String = "res://config/match/sandbox_tower_topple.tres"
## Spec 1.2 "Tutorial".
const TUTORIAL_SCENE_PATH: String = "res://ui/menus/Tutorial.tscn"
const REMOTE_CURSORS_SCENE_PATH: String = "res://game/player/RemoteCursors.tscn"
const NET_DEBUG_OVERLAY_SCENE_PATH: String = "res://ui/debug/NetDebugOverlay.tscn"
## In-match pause menu: abandon a game and go back to the main menu, or quit.
const PAUSE_MENU_SCENE_PATH: String = "res://ui/menus/PauseMenu.tscn"
## Self-wires to Events.match_results_ready/match_state_changed (like PauseMenu),
## so this is only an instantiate-and-hide.
const RESULTS_SCREEN_SCENE_PATH: String = "res://ui/menus/ResultsScreen.tscn"
## hold-to-show live scoreboard (action show_scores).
const SCOREBOARD_SCENE_PATH: String = "res://ui/hud/ScoreboardOverlay.tscn"
## Covers the LOBBY -> LOADING -> COUNTDOWN window; see ui/menus/LoadingScreen.gd.
const LOADING_SCREEN_SCENE_PATH: String = "res://ui/menus/LoadingScreen.tscn"

@onready var _field: Field = $Field
@onready var _blocks_container: Node3D = $BlocksContainer
@onready var _registry: BlockRegistry = $BlockRegistry
@onready var _camera_rig: CameraRig = $CameraRig
@onready var _skybox: Skybox = $Skybox
## The one WorldEnvironment in game/main/Main.tscn: _apply_graphics_preset()
## forwards ssr_enabled/volumetric_fog_enabled to its Environment. Null-checked
## so a stripped-down test fixture without this node stays a no-op.
@onready var _world_environment: WorldEnvironment = $WorldEnvironment
var _graphics_applier: GraphicsApplier = null

## Background prewarm, late activation and scene loading (game/main/AppLoader.gd).
var _loader: AppLoader = null
## The one context all flows share, so cross-flow state (sandbox, tutorial, mode extras) has
## one owner. Built on the first flow request, which is after _ready set the members below.
var _world: MainWorld = null
## The on-demand flows (typed to the light ports).
var _sandbox_flow: MainSandboxFlowPort = null
var _headless_bots_flow: MainHeadlessBotsFlowPort = null
var _match_flow: MainMatchFlowPort = null
var _main_menu: MainMenu = null
var _lobby: Node = null
var _local_player: Node = null
## debug Watch bots: true from start_watch_bots() until the session ends or returns to
## the menu; the match flow then builds a SpectatorController instead of a LocalPlayer.
var _watch_bots_active: bool = false
var _spectator: Node = null
var _remote_cursors: Node = null
var _debug_overlay: Node = null
## The four overlays (pause menu, results screen, scoreboard, loading screen) are
## created on first need (ensure), not in _ready(). `_pause_menu` & co. are lazy
## accessors (the flows and tests read them and always get an instance); the
## `*_node` fields are the raw slots, null until created, for the paths that must
## NOT create one (main-menu entry, territory callbacks).
var _pause_menu_node: PauseMenu = null
var _pause_menu: PauseMenu:
	get:
		return _ensure_pause_menu()
## Built alongside _pause_menu and self-wired via Events. Needs no `suppressed`
## gate: it only appears in response to Events.match_results_ready, never a raw
## key press.
var _results_screen_node: ResultsScreen = null
var _results_screen: ResultsScreen:
	get:
		return _ensure_results_screen()
var _scoreboard_node: ScoreboardOverlay = null
var _scoreboard: ScoreboardOverlay:
	get:
		return _ensure_scoreboard()
var _loading_screen_node: LoadingScreen = null
var _loading_screen: LoadingScreen:
	get:
		return _ensure_loading_screen()
var _start_pending: bool = false
## One instance per bot slot in the match currently built; freed in
## _end_match_world(). See _spawn_bot_controllers().
var _bot_controllers: Array[Node] = []

## One instance for the match currently built, same lifecycle as _bot_controllers.
## Host-gated inside the manager (Net.is_host()), so building one on a client costs
## nothing and stays inert.
var _stable_block_manager: Node = null

## True once _build_match_world() has run for the match currently in
## progress, so a repeated match_state_changed(LOBBY, LOADING) firing twice
## (should not happen, but a state machine is exactly the place to be
## defensive about it) cannot double-instance LocalPlayer/RemoteCursors, and
## _end_match_world() is a no-op when there is nothing to tear down.
var _world_built: bool = false
var _first_territory_ready: bool = false
var _loading_generation: int = 0
var _world_building: bool = false
var _controller_was_processing: bool = false
var _controller_was_handling_input: bool = false


## the process-wide caches are released as the game scene leaves the tree.
func _exit_tree() -> void:
	ExitRelease.release_if_quitting()


## the world roots that stop processing while a menu/lobby holds the render
## budget (ui/menus/MenuBackdrop.gd). Overlays, perf tools and net/match nodes are not among them.
func _register_menu_dormant_world() -> void:
	var roots: Array[Node] = []
	for node_name: String in MENU_DORMANT_WORLD_NODES:
		var node: Node = get_node_or_null(node_name)
		if node != null:
			roots.append(node)
	MenuBackdrop.set_dormant_world(roots, _menu_world_is_live)


## True while a match, sandbox or tutorial world is built or building: a menu backdrop still in
## the tree must not freeze it.
func _menu_world_is_live() -> bool:
	return _world_built or _world_building


## Menu hand-off (after the splash, or at once without one); the loader collects the Lobby chunk first.
func _show_main_menu_after_splash() -> void:
	if _loader.menu_shown(LOBBY_SCENE_PATH):
		_show_main_menu()


## A menu activation can ask for the "Loading..." status while its target prewarms.
func _show_loading_status(text: String) -> void:
	if _main_menu != null:
		_main_menu.show_status(text)


func _ready() -> void:
	print(_boot_line())

	_loader = _build_app_loader()

	# Load any saved tuning-panel overrides onto the shared tuning singletons before
	# anything else in the tree reads them.
	TuningOverrides.apply_saved()

	# The game's global wiring: SnapshotSync's session and Net's chat bus / real UPnP.
	SnapshotSync.bind_session(SessionPort.new(Net))
	Net.attach_global_wiring()

	# The ambient life subscribes to the sky's Events, so it exists before the preset below is
	# applied; the sky booted before this node, so it re-publishes what it already knows.
	add_child(AmbientLife.build(_field, _registry))
	_skybox.republish_ambient()

	# synchronous runs (headless, CLI flags, probes) build the autoloads' late
	# state now; the interactive path does it behind the menu (AppLoader._process).
	if not _loader.wants_background():
		_loader.ensure_late_active()

	# current_graphics_preset() never returns null.
	# The applier listens to Settings itself; the first apply is explicit.
	_graphics_applier = GraphicsApplier.new()
	_graphics_applier.sun = get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	_graphics_applier.skybox = _skybox
	add_child(_graphics_applier)
	_graphics_applier.apply(Settings.current_graphics_preset())
	# opt-in adaptive quality (idle unless the Options toggle is on).
	add_child(QualityGovernorDriver.new())

	# Applies the persisted window mode over project.godot's boot-time window
	# settings; apply_window_mode() skips headless/editor/--position runs, so tests
	# and off-screen probes are unaffected.
	Settings.apply_window_mode()

	_build_debug_tools()
	_register_menu_dormant_world()

	Events.match_state_changed.connect(_on_match_state_changed)
	Events.net_mode_changed.connect(_on_net_mode_changed)
	# Mid-match admission, gameplay half. Net must not name Match, so MatchNet (which
	# reads both) answers which seat a late joiner may take and whether a returning
	# peer's slot is still its.
	Net.set_seat_policy(MatchNet.pick_open_seat, MatchNet.seat_reclaimable)

	# The overlays are built by _ensure_overlays() (lobby entry / loading announced / first
	# use), never here; Events wiring that must exist before then stays below.
	Events.match_loading_announced.connect(_on_match_loading_announced)
	Events.territory_updated.connect(_on_loading_territory_updated)
	Events.territory_replicated.connect(_on_loading_territory_replicated)

	# Steam init is synchronous by this point, so MainMenu._ready() can immediately read steam_available().
	# Spacewar (480) is only our development Steam AppID. On Windows, its
	# Steam Input configuration intercepts physical pad events from Godot as
	# soon as steamInitEx runs, even though the pad still appears connected.
	# Keep local play/controller navigation functional by opting into Steam
	# explicitly while using that test ID. A real AppID restores auto-init.
	if Net.STEAM_APP_ID_EXPECTED != 480 or _has_cmdline_flag("steam-online") or _has_cmdline_flag("host-online"):
		Net.init_steam()
	# interactive launches show the SlopShop splash (with its
	# jingle) first; headless/CLI entry points go straight to the menu.
	if _loader.wants_background():
		_loader.begin(LOBBY_SCENE_PATH)
	if SplashScreen.should_show_now():
		var splash: SplashScreen = SplashScreen.new()
		add_child(splash)
		splash.finished.connect(_show_main_menu_after_splash)
	else:
		_show_main_menu_after_splash()

	# apply_command_line() calls host_game()/join_game() synchronously when
	# --host, --headless-host or --join is present, which emits
	# Events.net_mode_changed before this call returns -- _on_net_mode_changed
	# has already swapped the menu for the lobby by the time we get here.
	Net.apply_command_line()

	# A headless host has no human to click Start, so `--headless-host --bots=<n>`
	# (n > 0) skips the lobby wait; the function gates on --bots=<n> itself, so other
	# --headless-host command lines are unaffected.
	if _has_cmdline_flag("headless-host"):
		_start_headless_bot_match_with_args(OS.get_cmdline_user_args())
	# `-- --sandbox [--players=N]` runs the menu sandbox's path once the ordinary wiring above exists.
	if _has_cmdline_flag("sandbox"):
		_start_sandbox_match.call_deferred()
	# `-- --watch-bots=<n> [--mode=<id>] [--difficulty=<level>]` starts the same debug
	# all-bot watch match the Debug page's picker does (debug mode only).
	# Loaded by path so the watch-bots rules stay out of Main's compile closure (tools/lint_layers.py L4).
	var watch_options: GDScript = load(WATCH_BOTS_OPTIONS_PATH) as GDScript
	if bool(watch_options.call(&"has_cli", OS.get_cmdline_user_args())):
		start_watch_bots.call_deferred(watch_options.call(&"from_args", OS.get_cmdline_user_args(), watch_options.call(&"load_saved")) as RefCounted)


func _physics_process(delta: float) -> void:
	var probe_snapshot: int = PerfProbe.start()
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)
	PerfProbe.stop(&"snapshot", probe_snapshot)


# SHORTCUT: forwarder for MainMatchFlow.gd's re-apply after the world is built, removed with P7-Inav when the flow owns its own call.
func _apply_graphics_preset(preset: GraphicsPreset) -> void:
	_graphics_applier.apply(preset)


# --- Hot-seat / sandbox / tutorial: forwarders -------
#
# The bodies live in game/main/MainSandboxFlow.gd, loaded on demand through the prewarm queue.

func _start_sandbox_match() -> void:
	var sandbox_flow: MainSandboxFlowPort = _sandbox_flow_port()
	sandbox_flow.start_sandbox_match()


func start_sandbox_from_menu() -> void:
	if not await _loader.await_prewarmed(PackedStringArray([SANDBOX_FLOW_SCRIPT_PATH, SANDBOX_SCENE_PATH])):
		return
	var sandbox_flow: MainSandboxFlowPort = _sandbox_flow_port()
	sandbox_flow.start_sandbox_from_menu()


func start_gift_demo_from_menu() -> void:
	if not await _loader.await_prewarmed(PackedStringArray([SANDBOX_FLOW_SCRIPT_PATH, SANDBOX_SCENE_PATH])):
		return
	var sandbox_flow: MainSandboxFlowPort = _sandbox_flow_port()
	sandbox_flow.start_gift_demo_from_menu()


func start_tower_topple_from_menu() -> void:
	if not await _loader.await_prewarmed(PackedStringArray([SANDBOX_FLOW_SCRIPT_PATH, SANDBOX_SCENE_PATH])):
		return
	var sandbox_flow: MainSandboxFlowPort = _sandbox_flow_port()
	sandbox_flow.start_tower_topple_from_menu()


func start_tutorial_from_menu() -> void:
	if not await _loader.await_prewarmed(PackedStringArray([SANDBOX_FLOW_SCRIPT_PATH, TUTORIAL_SCENE_PATH])):
		return
	var sandbox_flow: MainSandboxFlowPort = _sandbox_flow_port()
	sandbox_flow.start_tutorial_from_menu()


## The sandbox flow, loaded through the serial prewarm queue on first use. DECISION: the queue
## is built lazily here (synchronous path); AppLoader.begin() owns the background start.
func _sandbox_flow_port() -> MainSandboxFlowPort:
	if _sandbox_flow == null:
		var flow_script: GDScript = _loader.ensure_script(SANDBOX_FLOW_SCRIPT_PATH)
		_sandbox_flow = flow_script.new() as MainSandboxFlowPort
		_sandbox_flow.bind(self)
		_sandbox_flow.bind_world(_main_world())
	return _sandbox_flow


## every mode that builds a world (match, sandbox, tutorial)
## gets the same sky: the config's theme / cycle.
func _apply_match_sky(config: MatchConfig) -> void:
	_skybox.configure_match_sky(config)


# --- Headless bot match ------------------
#
# The state and handlers live in game/main/MainHeadlessBotsFlow.gd, loaded on demand through the prewarm queue;
# the headless/CLI path stays synchronous.

func _start_headless_bot_match_with_args(args: PackedStringArray) -> void:
	_headless_bots_flow_port().start_match_with_args(args)


# SHORTCUT: forwarder for the headless bots flow, removed by P7-Inav
## Only a loaded flow can have started diagnostics, so teardown never loads it.
func _stop_headless_bots_diagnostics() -> void:
	if _headless_bots_flow != null:
		_headless_bots_flow.stop_diagnostics()


## The headless bots flow, loaded through the serial prewarm queue on first use.
func _headless_bots_flow_port() -> MainHeadlessBotsFlowPort:
	if _headless_bots_flow == null:
		var flow_script: GDScript = _loader.ensure_script(HEADLESS_BOTS_FLOW_SCRIPT_PATH)
		_headless_bots_flow = flow_script.new() as MainHeadlessBotsFlowPort
		_headless_bots_flow.bind(self)
		_headless_bots_flow.bind_world(_main_world())
	return _headless_bots_flow


func _main_world() -> MainWorld:
	if _world == null:
		_world = MainWorld.new()
		_world.parent = self
		_world.field = _field
		_world.registry = _registry
		_world.blocks_container = _blocks_container
		_world.camera_rig = _camera_rig
		_world.world_environment = _world_environment
		_world.skybox = _skybox
		_world.loader = _loader
		_world.graphics = _graphics_applier
	return _world


func _build_app_loader() -> AppLoader:
	var loader: AppLoader = AppLoader.new()
	loader.queue = MenuPrewarmQueue.new()
	loader.queue.config = load(MENU_PREWARM_CONFIG_PATH) as MenuPrewarmConfig
	loader.quit = DeferredQuit.new()
	loader.loading_status_requested.connect(_show_loading_status)
	add_child(loader)
	return loader



# --- Menu / lobby routing -----------------------------------------------------

## Instantiates one overlay through the prewarm queue (blocks only for the remaining chunk
## when it is still prewarming, plain load() otherwise). Each _ensure_* creates once.
func _ensure_pause_menu() -> PauseMenu:
	if _pause_menu_node == null:
		var menu: PauseMenu = _load_scene(PAUSE_MENU_SCENE_PATH).instantiate() as PauseMenu
		add_child(menu)
		menu.leave_match_requested.connect(_on_pause_leave_requested)
		# Return to lobby (host ends the match for everyone).
		menu.return_to_lobby_requested.connect(_on_pause_return_to_lobby_requested)
		menu.context_provider = _pause_menu_context
		# inert until a match/sandbox world exists (flows clear it).
		menu.suppressed = true
		_pause_menu_node = menu
	return _pause_menu_node


func _ensure_results_screen() -> ResultsScreen:
	if _results_screen_node == null:
		_results_screen_node = _load_scene(RESULTS_SCREEN_SCENE_PATH).instantiate() as ResultsScreen
		add_child(_results_screen_node)
	return _results_screen_node


func _ensure_scoreboard() -> ScoreboardOverlay:
	if _scoreboard_node == null:
		_scoreboard_node = _load_scene(SCOREBOARD_SCENE_PATH).instantiate() as ScoreboardOverlay
		add_child(_scoreboard_node)
		# Created while a sandbox is live (the sandbox flow only suppresses an existing one).
		_scoreboard_node.suppressed = _main_world().sandbox != null and is_instance_valid(_main_world().sandbox)
	return _scoreboard_node


func _ensure_loading_screen() -> LoadingScreen:
	if _loading_screen_node == null:
		var screen: LoadingScreen = _load_scene(LOADING_SCREEN_SCENE_PATH).instantiate() as LoadingScreen
		add_child(screen)
		screen.readiness_timed_out.connect(_on_loading_readiness_timed_out)
		_loading_screen_node = screen
	return _loading_screen_node


## Creates all four (lobby entry, match loading announced, world build): they must exist before
## the first match_state_changed(LOBBY, LOADING) because they self-wire through Events.
func _ensure_overlays() -> void:
	_ensure_pause_menu()
	_ensure_results_screen()
	_ensure_scoreboard()
	_ensure_loading_screen()


func _show_main_menu() -> void:
	# stats() is null until late_activate(); a fresh session has no wins to reset.
	var session_stats: RefCounted = Match.stats()
	if session_stats != null:
		session_stats.reset_session_wins()  # a fresh local session
	Sfx.set_music_context(&"menu")
	# DECISION: Main owns the splash -> menu hand-off, so it starts the
	# menu music here (after the splash `finished`, or immediately with no splash).
	# play_music() is idempotent: a later return to the menu keeps the running music.
	Sfx.play_music()
	_clear_menu_and_lobby()
	# The main menu is a "no match world" screen: force_close() covers a match that ended
	# by another route (e.g. a host disconnect on a client, via _on_net_mode_changed())
	# while the overlay was open; `suppressed` keeps it inert here.
	if _pause_menu_node != null:
		_pause_menu_node.force_close()
		_pause_menu_node.suppressed = true
	_main_menu = MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child(_main_menu)
	_main_menu.sandbox_requested.connect(start_sandbox_from_menu)
	_main_menu.tutorial_requested.connect(start_tutorial_from_menu)
	_main_menu.bots_requested.connect(start_bots_from_menu)
	_main_menu.gift_demo_requested.connect(start_gift_demo_from_menu)
	_main_menu.tower_topple_requested.connect(start_tower_topple_from_menu)
	_main_menu.watch_bots_requested.connect(start_watch_bots)


## DECISION: Play local → Vs bots starts from the normal lobby with one human
## and no bot preloaded (ai_count 0, one open seat). The lobby remains editable
## before Start, while LAN discovery stays off for this local entry point.
func start_bots_from_menu(player_name: String) -> void:
	if not await _loader.await_prewarmed(PackedStringArray()):
		return
	var err: Error = Net.host_game(0, player_name, false)
	if err != OK:
		if _main_menu != null:
			_main_menu.show_status("Could not start local game: %s" % error_string(err))
		return
	var config: MatchConfig = match_config.duplicate(true) as MatchConfig
	config.player_count = 2
	config.ai_count = 0
	Net.set_lobby_data(config.to_dict())


## debug-only. A local host session with every seat a bot and no human seat, so the
## match flow builds a SpectatorController (watch, follow, speed) instead of a LocalPlayer. Back to menu and
## Play again on the results screen work as for any host match.
func start_watch_bots(options: RefCounted) -> void:
	if not DebugMode.is_enabled():
		return
	if not await _loader.await_prewarmed(PackedStringArray()):
		return
	var err: Error = Net.host_game(0, Settings.player_name(), false)
	if err != OK:
		if _main_menu != null:
			_main_menu.show_status("Could not start watch match: %s" % error_string(err))
		return
	_watch_bots_active = true
	Match.start_match(options.call(&"build_config", match_config) as MatchConfig)


func _show_lobby() -> void:
	_prefetch_match_scenes()
	# Menu and lobby share a playlist; navigation must not restart the song.
	Sfx.set_music_context(&"menu")
	_clear_menu_and_lobby()
	# Like _show_main_menu(): the lobby is equally a "no match world" screen.
	_ensure_overlays()
	_pause_menu_node.force_close()
	_pause_menu_node.suppressed = true
	_lobby = _load_scene(LOBBY_SCENE_PATH).instantiate()
	add_child(_lobby)
	_lobby.connect(&"start_requested", _on_lobby_start_pressed)
	_lobby.connect(&"back_requested", _on_lobby_back_requested)
	# Must run once Net.is_host()/is_client() reflects the real mode (register_world()
	# reads it to set BlockRegistry's host authority) and before start_match() on every
	# instance: a client's start_match() runs the moment MatchNet's net_match_start RPC
	# arrives, so Main cannot get in ahead of it any other way.
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
		# emits this): never a half-dead match.
		_end_match_world()
		_watch_bots_active = false
		# DECISION (game/main/Main.gd): Net.leave() does not know about Match, so
		# the match is aborted here, where the session's end is routed. Otherwise
		# Match stays PLAYING/END on the main menu, still ticking feed timers and
		# the territory solve, and the next start_match() starts from that stale
		# state. abort_match() emits (old -> LOBBY), which _on_match_state_changed()
		# answers with the same idempotent _end_match_world(); it is skipped when
		# Match is already in the lobby so no LOBBY -> LOBBY emit happens.
		if Match.state() != Match.State.LOBBY:
			Match.abort_match()
		_show_main_menu()
	else:
		# Host/Join/LAN/Steam-invite/CLI all land here before any peer packet is polled.
		_loader.ensure_late_active()
		_show_lobby()


## Match.start_match() runs the whole world build synchronously
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
	_ensure_overlays()
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


## Rarely used scenes load on first use instead of at parse time. No member keeps
## the PackedScene: the resource cache holds it while an instance is alive and
## releases it afterwards.
# SHORTCUT: forwarder for the flows that still call main_node._load_scene, removed by P7-Inav
func _load_scene(path: String) -> PackedScene:
	return _loader.load_scene(path)


## Threaded prefetch of the match-start scene set so the world build's
## _load_scene() calls do not hitch (called while the lobby / loading screen is up).
func _prefetch_match_scenes() -> void:
	if _loader.is_background():
		return  # the serial queue owns these (a second threaded request could hang)
	for path: String in [LOCAL_PLAYER_SCENE_PATH, REMOTE_CURSORS_SCENE_PATH, NET_DEBUG_OVERLAY_SCENE_PATH]:
		if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path)


## Client side of _on_lobby_start_pressed(): raise the overlay as soon as the host announces.
func _on_match_loading_announced() -> void:
	if Match.state() != Match.State.LOBBY:
		return
	_prefetch_match_scenes()
	_ensure_overlays()  # a client may reach LOADING without ever having built the lobby overlays
	_loading_screen.show_pending(null)


func _on_loading_territory_updated(_raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	# DECISION: an applied result can arrive while the staged world is building.
	if Net.is_host() and _loading_screen_node != null and _loading_screen_node.visible and not _loading_screen_node.is_pending():
		_first_territory_ready = true


func _on_loading_territory_replicated(_raster: TerritoryRaster) -> void:
	if Net.is_client() and _loading_screen_node != null and _loading_screen_node.visible and not _loading_screen_node.is_pending():
		_first_territory_ready = true


func _on_loading_readiness_timed_out() -> void:
	_release_countdown_hold(_loading_generation)
	_loading_generation += 1
	if Net.is_host():
		Match.abort_match()
	else:
		Net.leave()


## ui/lobby/Lobby.gd's %BackButton. _show_lobby() is only entered once Net is HOST
## or CLIENT, so no host/client branch is needed: Net.leave() stops advertising and
## drops peers for a host, or disconnects for a client, emitting
## Events.net_mode_changed(OFFLINE). _on_net_mode_changed() then answers as for a
## mid-match disconnect (_end_match_world(), no abort_match() since Match is still
## LOBBY, then _show_main_menu()).
func _on_lobby_back_requested() -> void:
	Net.leave()


## ui/menus/PauseMenu.gd's own leave_match_requested (Leave match, confirmed).
## DECISION (game/main/Main.gd, minor ambiguity): the online/offline split lives
## here, not in ui/menus/PauseMenu.gd (which never touches Net/Match), because this
## file already owns the symmetric case, Net dropping to OFFLINE
## (_on_net_mode_changed() above). Online (host or client), Net.leave() tears the
## match world down and shows the main menu through that handler. Offline (sandbox)
## there is no Net transition, so this aborts the match directly (idempotent from
## LOBBY) and shows the menu itself; the abort's (X -> LOBBY) frees the mode's nodes with the
## world. A tutorial session never reaches this handler: PauseMenu is suppressed for its whole duration.
func _on_pause_leave_requested() -> void:
	if Net.mode() != Net.Mode.OFFLINE:
		Net.leave()
		return
	if Match.state() != Match.State.LOBBY:
		Match.abort_match()
	_show_main_menu()


## Called by the match flow once the local player is built; the sandbox flow port
## attaches the mode's node. Inert for a lobby match.
func _attach_mode_extras(local_player: Node) -> void:
	var extras: ModeExtras = _main_world().mode_extras
	if extras == null:
		return
	_sandbox_flow_port().attach_extras(extras, local_player)


## What ui/menus/PauseMenu.gd's Return to lobby entry shows, answered here because
## only Main may name Net and Match for it (the menu's own header).
## HOST: enabled -- every hosted session has a lobby to go back to, a local
## "Vs bots" game included (Net.host_game() without advertising). CLIENT: shown
## disabled (DECISION: only the host can end a match for everyone; a client's
## own exit stays Leave match). OFFLINE (sandbox): hidden --
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
	# PauseMenu freezes the tree only when no remote human is connected.
	return {"return_entry": entry, "match_in_progress": in_progress, "freeze_tree": Net.is_solo_session()}


## ui/menus/PauseMenu.gd's return_to_lobby_requested (Return to lobby, confirmed).
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

## Collected into a plain array so ui/menus/LoadingScreen.gd never reaches for the
## Match singleton (same injection shape as ui/hud/HUD.gd's match_provider seam).
## Every slot's display_name/is_bot is already final: MatchLifecycle's slot build
## ran before the LOBBY -> LOADING emit this feeds.
func _loading_screen_slots() -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(Match.slot_count()):
		var slot_item: PlayerSlot = Match.slot(i)
		if slot_item != null:
			slots.append(slot_item)
	return slots


# --- Match world: forwarders --------------------------
#
# The bodies live in game/main/MainMatchFlow.gd. `_on_match_state_changed` is connected in _ready()
# and also fires from a client's net_match_start RPC with no other Main involvement, so every
# forwarder resolves the flow through `_match_flow_port()` (ensure_script first, bound once)
# before the first LOBBY -> LOADING reaction. The coroutine bodies are awaited so a test or caller
# that awaits the old name still waits, while fire-and-forget callers behave as before (a
# coroutine that never suspends completes synchronously, e.g. headless).

## the match-world rules (state routing, world build/teardown, loading hand-off).
func _on_match_state_changed(from_state: int, to_state: int) -> void:
	if to_state == Match.State.LOADING:
		_ensure_overlays()  # sandbox/bots/test entries never pass the lobby
	var match_flow: MainMatchFlowPort = _match_flow_port()
	match_flow.on_match_state_changed(from_state, to_state)


func _release_countdown_hold(generation: int) -> void:
	_match_flow_port().call(&"_release_countdown_hold", generation)


func _end_match_world() -> void:
	var match_flow: MainMatchFlowPort = _match_flow_port()
	match_flow.end_match_world()


## The match flow, loaded through the serial prewarm queue on first use (synchronous path).
func _match_flow_port() -> MainMatchFlowPort:
	if _match_flow == null:
		var flow_script: GDScript = _loader.ensure_script(MATCH_FLOW_SCRIPT_PATH)
		_match_flow = flow_script.new() as MainMatchFlowPort
		_match_flow.bind(self)
		_match_flow.bind_world(_main_world())
	return _match_flow


# --- Debug tools ---------------------------------------------

## Debug mode only (game/debug/DebugMode.gd): the F1 perf overlay, its sampler and
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
	# Loaded on demand by path (debug builds only): the bot code behind it stays out of Main's compile closure.
	var bot_cost_script: GDScript = load(BOT_COST_OVERLAY_PATH) as GDScript
	var bot_cost: CanvasLayer = bot_cost_script.new() as CanvasLayer
	bot_cost.set(&"config", debug_config)
	add_child(bot_cost)
	var logger: PerfLogger = PerfLogger.new()
	logger.config = debug_config
	logger.sampler = sampler
	add_child(logger)
	if _has_cmdline_flag("soak"):
		# Loaded by path like the bot overlay: the soak code stays out of Main's compile closure.
		var soak_script: GDScript = load(SOAK_MONITOR_PATH) as GDScript
		var soak: Node = soak_script.new() as Node
		soak.set(&"config", load(SOAK_CONFIG_PATH))
		# DECISION: Net.apply_command_line() runs after this, so Net.is_host() would read the
		# offline default; the role comes from the same parser Net uses.
		var joining: bool = NetCommandLine.parse(OS.get_cmdline_user_args()).has_join
		soak.set(&"role", &"client" if joining else &"host")
		soak.set(&"sampler", sampler)
		add_child(soak)
		# DECISION: the plan does not say client-only; the launcher passes --soak-fuzz to the client
		# alone and the fuzzer does nothing without a seat, so no role check is added here.
		if _has_cmdline_flag("soak-fuzz"):
			var fuzzer_script: GDScript = load(SOAK_FUZZER_PATH) as GDScript
			var fuzzer: Node = fuzzer_script.new() as Node
			fuzzer.set(&"config", load(SOAK_CONFIG_PATH))
			var seams_script: GDScript = fuzzer_script.get_script_constant_map()[&"Seams"] as GDScript
			var seams: RefCounted = seams_script.new() as RefCounted
			seams.set(&"playing", func() -> bool: return Match.state() == Match.State.PLAYING)
			seams.set(&"local_slot", Net.local_slot)
			seams.set(&"feed_seq", Match.feed_seq)
			seams.set(&"field_radius", func() -> float: return Match.config.map_def().field_radius)
			seams.set(&"submit_place", MatchNet.submit_place)
			seams.set(&"line", func(text: String) -> void: print(text))
			fuzzer.set(&"seams", seams)
			add_child(fuzzer)


# --- Helpers -----------------------------------------------------------------

## Same "-" stripping Net._apply_command_line_args() uses, so "--sandbox" and
## "-sandbox" are both recognised the same way the rest of the command line
## is. Net itself never sees these flags (autoload/Net.gd's docstring lists
## exactly the flags it parses).
func _has_cmdline_flag(flag: String) -> bool:
	for raw: String in OS.get_cmdline_user_args():
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		if text == flag:
			return true
	return false


## One-line report of the settings the project must get right (spec 2.1, 2.7).
func _boot_line() -> String:
	var version: String = str(Engine.get_version_info().get("string", "unknown"))
	var physics_engine: String = str(ProjectSettings.get_setting("physics/3d/physics_engine", "?"))
	var ticks: int = Engine.physics_ticks_per_second
	var interpolated: bool = bool(ProjectSettings.get_setting("physics/common/physics_interpolation", false))
	var renderer: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	return "Stackfall boot | godot %s | renderer %s | physics %s | %d Hz | interpolation %s" % [
		version, renderer, physics_engine, ticks, interpolated,
	]
