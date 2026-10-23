extends GutTest
## Main's match lifecycle over a real (peerless) ENet host session: start, leave mid-match, rehost (spec 2.4).

const MAIN_SCENE: PackedScene = preload("res://game/main/Main.tscn")

## Well away from test_net_session.gd's 47800+ range and the harness's
## 47778, incrementing per test so a port the OS has not released yet can
## never collide with the next one.
static var _next_port: int = 47900

## game/main/Main.gd has no class_name (it is a scene root, not a type other code
## names), so the instance is held through a Variant-typed reference and
## its members resolved at runtime, as test_net_session.gd does for Net.
var _main: Variant = null

## DECISION: see test_match_flow.gd's own `_tiny_map` comment
## for the full story. Here Main.tscn's own persistent `$Field` child (not a
## Field this file builds itself) is the one paying round_medium.tres's
## ~6300-cell collision build on every _host()+_start() in every test's
## before_each; overridden the same way, before Main ever enters the tree (so
## before Field's _ready() runs), and handed to every MatchConfig through the
## same TinyMapMatchConfig seam so Match's own geometry still agrees with it.
var _tiny_map: MapDef

## .20a: start_match() writes the lobby's gravity_multiplier
## straight into the shared config/physics/physics_tuning.tres *instance* (see
## MatchLifecycle.gd's matching DECISION) -- the same process-wide singleton
## test_tuning_panel.gd's own before_each/after_each comment documents, so
## this file restores it exactly the same way.
var _saved_gravity_multiplier: float


func before_each() -> void:
	# Match ticks on real frames; these tests drive _process() by hand where
	# a state must advance, so automatic processing is off for the duration.
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	(_main.get_node("Field") as Field).map_def = _tiny_map
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")
	_saved_gravity_multiplier = (load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	(load("res://config/physics/physics_tuning.tres") as PhysicsTuning).gravity_multiplier = _saved_gravity_multiplier
	# Let queue_free()d world nodes actually go before autofree takes Main.
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	# Parallel gate shards (tools/full_gate.py) run several Godot processes at
	# once; a fixed port sequence collided, so ask the OS for a free port.
	return AgentProbe.free_udp_port()


func _host() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(Net.is_host())
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")


func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults, so it must happen before any field is
	# set on `config` (test_match_flow.gd's own _tiny_map_config() reproduced
	# this the hard way -- see its doc comment).
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.rng_seed = 777
	return config


## What ui/lobby/Lobby.gd's start_requested does on the host.
func _start(player_count: int) -> void:
	_main._on_lobby_start_requested(_config(player_count))


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## Two frames, so every node queue_free()d by a swap (the menu or lobby the
## build replaced, the world a teardown removed) is actually gone. The bus
## connection count below is only meaningful once it is: a Lobby or MainMenu
## awaiting its free still holds its Events connections for that frame.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame


func _count(type_check: Callable) -> int:
	var total: int = 0
	for child: Node in _main.get_children():
		if bool(type_check.call(child)):
			total += 1
	return total


func _local_players() -> int:
	return _count(func(node: Node) -> bool: return node is LocalPlayer)


func _remote_cursors() -> int:
	return _count(func(node: Node) -> bool: return node is RemoteCursors)


func _debug_overlays() -> int:
	return _count(func(node: Node) -> bool: return node is NetDebugOverlay)


func _overlay_raster() -> TerritoryRaster:
	return _main._field.overlay()._raster


func _home_flag_count() -> int:
	return _main._field.home_flags().size()


## How many listeners hang on the bus. Compared across a full
## build/teardown/build so a leaked LocalPlayer, RemoteCursors or debug overlay
## (or a SnapshotSync connection never dropped) shows up as growth.
func _bus_connection_count() -> int:
	var total: int = 0
	for signal_info: Dictionary in Events.get_signal_list():
		total += Events.get_signal_connection_list(StringName(signal_info["name"])).size()
	return total


func _assert_one_fresh_world(player_count: int, context: String) -> void:
	assert_true(_main._world_built, "%s: the world is built" % context)
	assert_null(_main._lobby, "%s: the lobby is gone" % context)
	assert_eq(_local_players(), 1, "%s: exactly one LocalPlayer" % context)
	assert_eq(_remote_cursors(), 1, "%s: exactly one RemoteCursors" % context)
	assert_eq(_debug_overlays(), 1, "%s: exactly one NetDebugOverlay" % context)
	assert_not_null(Match.raster(), "%s: the match has a raster" % context)
	assert_eq(_overlay_raster(), Match.raster(), "%s: the overlay draws this match's raster" % context)
	assert_eq(Match.slot_count(), player_count, "%s: the new config's slots" % context)
	assert_eq(_home_flag_count(), player_count, "%s: one home flag per slot of the new config" % context)
	assert_true(SnapshotSync.is_running(), "%s: SnapshotSync is running" % context)
	assert_eq(SnapshotSync._registry, _main._registry, "%s: SnapshotSync is bound to Main's registry" % context)


# --- (a) First network start --------------------------------------------------

func test_first_network_start_binds_the_overlay_and_snapshot_sync_to_the_new_match() -> void:
	_host()

	_start(2)

	assert_eq(Match.state(), Match.State.COUNTDOWN)
	_assert_one_fresh_world(2, "first start")


# --- (b) Repeated start -------------------------------------------------------

# --- (c) Leave during PLAYING -------------------------------------------------

func test_leaving_during_play_aborts_the_match_and_tears_the_world_down() -> void:
	_host()
	_start(2)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture reaches PLAYING")

	Net.leave()

	assert_true(Net.is_offline())
	assert_eq(Match.state(), Match.State.LOBBY, "leaving aborts the match")
	assert_eq(Match.slot_count(), 0)
	assert_null(Match.raster())
	assert_null(Match.config)
	assert_false(SnapshotSync.is_running())
	assert_false(_main._world_built)
	assert_null(_main._local_player)
	assert_null(_main._remote_cursors)
	assert_null(_main._debug_overlay)
	assert_not_null(_main._main_menu, "back on the main menu")
	assert_null(_main._lobby)

	# A stale match used to keep ticking on the menu; an aborted one decides
	# nothing.
	watch_signals(Events)
	for _i: int in range(int(MatchConfig.BLOCK_TIMER_MAX * Engine.physics_ticks_per_second)):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	assert_eq(Match.state(), Match.State.LOBBY)
	assert_signal_not_emitted(Events, "feed_timer_expired")
	assert_signal_not_emitted(Events, "match_state_changed")

	await _settle()
	assert_eq(_local_players(), 0, "the LocalPlayer is gone")
	assert_eq(_remote_cursors(), 0, "the RemoteCursors is gone")
	assert_eq(_debug_overlays(), 0, "the debug overlay is gone")


# --- (d) Rehost after END / leave ---------------------------------------------

func test_rehost_after_the_match_ended_and_the_session_closed_builds_a_fresh_world() -> void:
	_host()
	_start(2)
	_run_countdown()
	Match._lifecycle._finish_match(0)
	assert_eq(Match.state(), Match.State.END, "fixture reaches END")
	var old_raster: TerritoryRaster = Match.raster()
	await _settle()
	var connections_after_first: int = _bus_connection_count()

	Net.leave()
	await _settle()
	assert_eq(Match.state(), Match.State.LOBBY)
	assert_false(_main._world_built)

	_host()
	assert_eq(Match.state(), Match.State.LOBBY, "hosting again finds a clean lobby")
	var transitions: Array[Array] = []
	var recorder: Callable = func(from_state: int, to_state: int) -> void:
		transitions.append([from_state, to_state])
	Events.match_state_changed.connect(recorder)
	_start(3)
	Events.match_state_changed.disconnect(recorder)
	await _settle()

	assert_eq(
		transitions,
		[
			[Match.State.LOBBY, Match.State.LOADING],
			[Match.State.LOADING, Match.State.COUNTDOWN],
		] as Array[Array],
		"the second match starts from LOBBY exactly as the first did"
	)
	_assert_one_fresh_world(3, "rehost")
	assert_ne(Match.raster(), old_raster)
	assert_eq(Match.winner_team(), WinChecker.NO_TEAM, "no winner carries over")
	assert_eq(_bus_connection_count(), connections_after_first, "no listener leaks across leave and rehost")


# --- (e) Lobby-only joining ---------------------------------
#
# The roster's join gate (net_roster) is inert until the match flow flips
# it; game/main/Main.gd's _on_match_state_changed() is where that happens (Net must
# not name Match). These pin the gate to Match's state machine through the real
# Main: closed from the first step out of LOBBY until the match is aborted or
# the session left. A refused late joiner over ENet is covered by
# test_net_session.gd (flag flipped directly) and by the owner's manual step;
# the client role cannot be driven in-process against the Net autoload (see the
# header).

# --- (f) Field state does not survive the match that opened it ---------------
#
# game/field/Field.gd is persistent (Main never frees or rebuilds it, unlike
# LocalPlayer/RemoteCursors/NetDebugOverlay), and Match's own teardown
# (_reset_match_state()) never touches it, so leaving mid-match used to leave
# its flags, its overlay's raster reference and every hole it had opened
# behind on the field the main menu sits over (Beads).

# --- (g) Lobby gravity reaches physics at match start (.20a) ------

func test_start_match_writes_the_lobbys_gravity_into_the_shared_physics_tuning() -> void:
	_host()
	var config: MatchConfig = _config(2)
	config.gravity_multiplier = 1.2

	_main._on_lobby_start_requested(config)

	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	assert_almost_eq(tuning.gravity_multiplier, 1.75 * 1.2, 0.0001)


# --- (h) M5 P1: _build_slots() marks the trailing ai_count slots as bots ----

# --- (i) M6 A3 regression: match_timer_minutes == 0 (Off) never arms sudden
# death, no matter how it is toggled -----------------------------------------
#
# See tests/unit/match/test_sudden_death.gd for the full match-timer/sudden-death
# contract; this one lives here (not there) because it is the one case this
# package's own plan names as a test_match_lifecycle.gd append.
