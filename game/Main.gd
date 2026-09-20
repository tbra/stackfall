extends Node3D
## The game's entry point: a router, not a match (spec Part 4 M3a;
## docs/M3a_PLAN.md integration order step 4).
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
## _physics_process, never _process (docs/M3a_PLAN.md "Frozen bodies").
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
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const HOT_SEAT_SCENE: PackedScene = preload("res://game/HotSeat.tscn")
const SANDBOX_SCENE: PackedScene = preload("res://game/Sandbox.tscn")
const REMOTE_CURSORS_SCENE: PackedScene = preload("res://game/RemoteCursors.tscn")
const NET_DEBUG_OVERLAY_SCENE: PackedScene = preload("res://ui/NetDebugOverlay.tscn")

@onready var _field: Field = $Field
@onready var _blocks_container: Node3D = $BlocksContainer
@onready var _registry: BlockRegistry = $BlockRegistry
@onready var _camera_rig: CameraRig = $CameraRig

var _main_menu: MainMenu = null
var _lobby: Lobby = null
var _hot_seat: HotSeat = null
var _sandbox: Sandbox = null
var _remote_cursors: RemoteCursors = null
var _debug_overlay: NetDebugOverlay = null

## True once _build_match_world() has run for the match currently in
## progress, so a repeated match_state_changed(LOBBY, LOADING) firing twice
## (should not happen, but a state machine is exactly the place to be
## defensive about it) cannot double-instance HotSeat/RemoteCursors, and
## _end_match_world() is a no-op when there is nothing to tear down.
var _world_built: bool = false


func _ready() -> void:
	print(_boot_line())

	if _has_cmdline_flag("hot-seat"):
		_start_hot_seat_match()
		return

	if _has_cmdline_flag("sandbox"):
		_start_sandbox_match()
		return

	Events.match_state_changed.connect(_on_match_state_changed)
	Events.net_mode_changed.connect(_on_net_mode_changed)

	# docs/M3b_PLAN.md integration order step 4: Steam init is synchronous by
	# this point, so MainMenu._ready() can immediately read steam_available().
	Net.init_steam()
	_show_main_menu()

	# apply_command_line() calls host_game()/join_game() synchronously when
	# --host, --headless-host or --join is present, which emits
	# Events.net_mode_changed before this call returns -- _on_net_mode_changed
	# has already swapped the menu for the lobby by the time we get here.
	Net.apply_command_line()


func _physics_process(delta: float) -> void:
	SnapshotSync.host_tick(delta)
	SnapshotSync.client_tick(delta)


# --- Hot-seat: byte-identical to M2 ------------------------------------------

func _start_hot_seat_match() -> void:
	_hot_seat = HOT_SEAT_SCENE.instantiate() as HotSeat
	add_child(_hot_seat)
	_hot_seat.set_camera_rig(_camera_rig)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_hot_seat_config())

	var config: MatchConfig = Match.config
	_field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
	_field.set_overlay_source(Match.raster(), config.player_colors)


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
	_sandbox = SANDBOX_SCENE.instantiate() as Sandbox
	add_child(_sandbox)
	_sandbox.set_camera_rig(_camera_rig)
	_sandbox.set_field(_field)
	Match.register_world(_field, _registry, _blocks_container)
	Match.start_match(_build_sandbox_config(_sandbox_player_count(args)))

	var config: MatchConfig = Match.config
	_field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
	_field.set_overlay_source(Match.raster(), config.player_colors)

	# F3's overlay works offline too (Net.stats() reports Offline/0 peers,
	# which is still useful context while sandbox-testing); it costs nothing
	# unopened, exactly as in the networked path below.
	_debug_overlay = NET_DEBUG_OVERLAY_SCENE.instantiate() as NetDebugOverlay
	add_child(_debug_overlay)


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
	return sandbox_config.default_player_count


# --- Menu / lobby routing -----------------------------------------------------

func _show_main_menu() -> void:
	_clear_menu_and_lobby()
	_main_menu = MAIN_MENU_SCENE.instantiate() as MainMenu
	add_child(_main_menu)


func _show_lobby() -> void:
	_clear_menu_and_lobby()
	_lobby = LOBBY_SCENE.instantiate() as Lobby
	add_child(_lobby)
	_lobby.start_requested.connect(_on_lobby_start_requested)
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
		# emits this): never a half-dead match (docs/M3a_PLAN.md
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


func _on_lobby_start_requested(config: MatchConfig) -> void:
	if not Net.is_host():
		return
	Match.start_match(config)


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
	# Spec 3.4: joining is lobby-only in M3a. Net must not name Match, so the
	# match flow flips Net's gate here, where every state change is routed: a
	# handshake arriving while the match is past LOBBY is refused with
	# JoinError.MATCH_IN_PROGRESS, and abort_match()'s (old -> LOBBY) emit
	# reopens it (Net.leave() also resets it itself). On a client this is a
	# harmless flag write; _rpc_handshake is host-gated (Beads Bontago-mv0.1.8).
	Net.set_accepting_joins(to_state == Match.State.LOBBY)
	if to_state == Match.State.LOBBY:
		_end_match_world()
	elif from_state == Match.State.LOBBY and to_state == Match.State.LOADING:
		_build_match_world()


func _build_match_world() -> void:
	if _world_built:
		return
	_world_built = true
	_clear_menu_and_lobby()

	var config: MatchConfig = Match.config
	_field.place_flags(config.player_count, config.player_colors, config.goal_flag_count)
	_field.set_overlay_source(Match.raster(), config.player_colors)

	SnapshotSync.set_disk(_field)
	SnapshotSync.begin_match(Match.registry(), config.map_def())

	_remote_cursors = REMOTE_CURSORS_SCENE.instantiate() as RemoteCursors
	add_child(_remote_cursors)

	_hot_seat = HOT_SEAT_SCENE.instantiate() as HotSeat
	add_child(_hot_seat)
	_hot_seat.set_camera_rig(_camera_rig)
	_hot_seat.bind_local_slot(Net.local_slot())

	_debug_overlay = NET_DEBUG_OVERLAY_SCENE.instantiate() as NetDebugOverlay
	add_child(_debug_overlay)


func _end_match_world() -> void:
	if not _world_built:
		return
	_world_built = false
	SnapshotSync.end_match()
	# Field is persistent (unlike everything else torn down below) and Match's
	# own teardown never touches it, so its flags, overlay raster reference
	# and open holes would otherwise still belong to the match that just ended
	# (Beads Bontago-mv0.1.9).
	_field.clear_match_state()
	if _remote_cursors != null and is_instance_valid(_remote_cursors):
		_remote_cursors.queue_free()
	_remote_cursors = null
	if _hot_seat != null and is_instance_valid(_hot_seat):
		_hot_seat.queue_free()
	_hot_seat = null
	if _debug_overlay != null and is_instance_valid(_debug_overlay):
		_debug_overlay.queue_free()
	_debug_overlay = null


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
