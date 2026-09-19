extends GutTest
## game/Main.gd's match lifecycle over a real (peerless) ENet host session:
## first network start, a repeated start, leaving mid-match and rehosting
## afterwards (spec 3.7 `End -> Lobby`, docs/M3a_PLAN.md "Disconnects";
## Beads Bontago-mv0.1.9).
##
## These drive the **real** Main scene, the real Net autoload and the real
## Match/SnapshotSync/MatchNet autoloads, because the two defects this pins
## were ordering bugs *between* them that no single-system test could see:
## Main bound the territory overlay to Match.raster() inside the LOADING emit
## before Match had built it, and Net.leave() left Match PLAYING so the next
## host's start_match() arrived as PLAYING -> LOADING and Main never rebuilt
## the world. Net.host_game() opens a listen server with no clients; every
## send path (MatchNet.replicate_*, SnapshotSync.host_tick) is a no-op with
## an empty peer list, so nothing here touches the network beyond binding a
## port. The client role cannot be driven in-process (the Net autoload owns
## the tree's default MultiplayerAPI, and a second scoped session's RPC
## paths do not resolve against it), so a client whose host quit is covered
## by the manual steps in the task report; Main's OFFLINE route is the same
## code for both roles (autoload/Net.gd's _on_server_disconnected() calls
## the same leave()).

const MAIN_SCENE: PackedScene = preload("res://game/Main.tscn")

## Well away from test_net_session.gd's 47800+ range and the harness's
## 47778, incrementing per test so a port the OS has not released yet can
## never collide with the next one.
static var _next_port: int = 47900

## game/Main.gd has no class_name (it is a scene root, not a type other code
## names), so the instance is held through a Variant-typed reference and
## its members resolved at runtime, as test_net_session.gd does for Net.
var _main: Variant = null


func before_each() -> void:
	# Match ticks on real frames; these tests drive _process() by hand where
	# a state must advance, so automatic processing is off for the duration.
	Match.set_process(false)
	Match.abort_match()
	SnapshotSync.end_match()
	assert_true(Net.is_offline(), "fixture: the real Net must start offline")
	_main = MAIN_SCENE.instantiate()
	add_child_autofree(_main)
	assert_not_null(_main._main_menu, "fixture: Main boots to the main menu with no command-line flags")


func after_each() -> void:
	Net.leave()
	Match.abort_match()
	SnapshotSync.end_match()
	Match.set_process(true)
	# Let queue_free()d world nodes actually go before autofree takes Main.
	await get_tree().process_frame
	await get_tree().process_frame


func _take_port() -> int:
	var port: int = _next_port
	_next_port += 1
	return port


func _host() -> void:
	assert_eq(Net.host_game(_take_port(), "Hostie"), OK)
	assert_true(Net.is_host())
	assert_not_null(_main._lobby, "hosting swaps the menu for the lobby synchronously")


func _config(player_count: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = false
	config.rng_seed = 777
	return config


## What ui/Lobby.gd's start_requested does on the host.
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


func _hot_seats() -> int:
	return _count(func(node: Node) -> bool: return node is HotSeat)


func _remote_cursors() -> int:
	return _count(func(node: Node) -> bool: return node is RemoteCursors)


func _debug_overlays() -> int:
	return _count(func(node: Node) -> bool: return node is NetDebugOverlay)


func _overlay_raster() -> TerritoryRaster:
	return _main._field.overlay()._raster


func _home_flag_count() -> int:
	return _main._field._home_flags.size()


## How many listeners hang on the bus. Compared across a full
## build/teardown/build so a leaked HotSeat, RemoteCursors or debug overlay
## (or a SnapshotSync connection never dropped) shows up as growth.
func _bus_connection_count() -> int:
	var total: int = 0
	for signal_info: Dictionary in Events.get_signal_list():
		total += Events.get_signal_connection_list(StringName(signal_info["name"])).size()
	return total


func _assert_one_fresh_world(player_count: int, context: String) -> void:
	assert_true(_main._world_built, "%s: the world is built" % context)
	assert_null(_main._lobby, "%s: the lobby is gone" % context)
	assert_eq(_hot_seats(), 1, "%s: exactly one HotSeat" % context)
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

func test_a_repeated_start_rebuilds_exactly_one_fresh_world() -> void:
	_host()
	_start(2)
	var old_raster: TerritoryRaster = Match.raster()
	var old_hot_seat: Node = _main._hot_seat
	var old_cursors: Node = _main._remote_cursors
	await _settle()
	var connections_after_first: int = _bus_connection_count()

	_start(3)
	await _settle()

	_assert_one_fresh_world(3, "second start")
	assert_ne(Match.raster(), old_raster, "a fresh raster, not the first match's")
	assert_ne(_main._hot_seat, old_hot_seat, "a fresh HotSeat")
	assert_false(is_instance_valid(old_hot_seat), "the first HotSeat is freed")
	assert_false(is_instance_valid(old_cursors), "the first RemoteCursors is freed")
	assert_eq(_bus_connection_count(), connections_after_first, "no listener leaks across the rebuild")


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
	assert_null(_main._hot_seat)
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
	assert_eq(_hot_seats(), 0, "the HotSeat is gone")
	assert_eq(_remote_cursors(), 0, "the RemoteCursors is gone")
	assert_eq(_debug_overlays(), 0, "the debug overlay is gone")


# --- (d) Rehost after END / leave ---------------------------------------------

func test_rehost_after_the_match_ended_and_the_session_closed_builds_a_fresh_world() -> void:
	_host()
	_start(2)
	_run_countdown()
	Match._finish_match(0)
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


func test_a_host_that_quits_before_starting_returns_to_the_menu_without_a_lobby_to_lobby_emit() -> void:
	_host()
	watch_signals(Events)

	Net.leave()

	assert_signal_not_emitted(Events, "match_state_changed", "Match was already in the lobby; nothing to abort")
	assert_eq(Match.state(), Match.State.LOBBY)
	assert_not_null(_main._main_menu)
	assert_null(_main._lobby)


# --- (e) Lobby-only joining (Bontago-mv0.1.8) ---------------------------------
#
# autoload/Net.gd's _accepting_joins gate is inert until the match flow flips
# it; game/Main.gd's _on_match_state_changed() is where that happens (Net must
# not name Match). These pin the gate to Match's state machine through the real
# Main: closed from the first step out of LOBBY until the match is aborted or
# the session left. A refused late joiner over ENet is covered by
# test_net_session.gd (flag flipped directly) and by the owner's manual step;
# the client role cannot be driven in-process against the Net autoload (see the
# header).

func test_joins_close_when_the_match_leaves_the_lobby_and_reopen_on_abort() -> void:
	_host()
	assert_true(Net.accepting_joins(), "a fresh lobby accepts joins")

	_start(2)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_false(Net.accepting_joins(), "COUNTDOWN: joins are closed")
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_false(Net.accepting_joins(), "PLAYING: joins stay closed")
	Match._finish_match(0)
	assert_eq(Match.state(), Match.State.END)
	assert_false(Net.accepting_joins(), "END: still closed; End -> Lobby is the only way back")

	Match.abort_match()
	assert_eq(Match.state(), Match.State.LOBBY)
	assert_true(Net.is_host(), "aborting the match does not end the session")
	assert_true(Net.accepting_joins(), "back in the lobby, joins reopen")


func test_a_repeated_start_leaves_joins_closed_and_leaving_reopens_them() -> void:
	_host()
	_start(2)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture reaches PLAYING")

	# start_match() from PLAYING goes back through abort_match() (PLAYING ->
	# LOBBY, which momentarily reopens joins) and on to LOBBY -> LOADING ->
	# COUNTDOWN, all synchronously: what must hold once it returns is closed.
	_start(3)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_false(Net.accepting_joins(), "a restarted match closes joins again")

	Net.leave()
	assert_true(Net.is_offline())
	assert_eq(Match.state(), Match.State.LOBBY)
	assert_true(Net.accepting_joins(), "leaving resets the gate for the next session")

	_host()
	assert_true(Net.accepting_joins(), "a rehosted lobby accepts joins")


# --- (f) Field state does not survive the match that opened it ---------------
#
# game/Field.gd is persistent (Main never frees or rebuilds it, unlike
# HotSeat/RemoteCursors/NetDebugOverlay), and Match's own teardown
# (_reset_match_state()) never touches it, so leaving mid-match used to leave
# its flags, its overlay's raster reference and every hole it had opened
# behind on the field the main menu sits over (Beads Bontago-mv0.1.9).

func test_leaving_mid_match_clears_the_fields_flags_overlay_and_holes() -> void:
	_host()
	_start(2)
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING, "fixture reaches PLAYING")

	# grid.cell_index(1, 1) and (2, 2) are near the (0, 0) corner of the square
	# CellGrid wraps around the disk (core/territory/CellGrid.gd) -- outside the
	# actual round map for any field_radius bigger than a couple of cells, so
	# Field._enqueue_toggle() (game/Field.gd) silently drops them
	# (_cell_owner_ids[cell] < 0 for a cell with no shape owner) and the fixture
	# assertion below never sees them applied. The disk centre and its neighbor
	# are always in-disk by construction (CellGrid's central cell), so use those.
	var grid: CellGrid = _main._field.grid()
	var mid: int = grid.res / 2
	var opened: PackedInt32Array = PackedInt32Array([
		grid.cell_index(mid, mid), grid.cell_index(mid + 1, mid),
	])
	Events.hole_cells_changed.emit(opened, PackedInt32Array())
	for _i: int in range(5):
		await get_tree().physics_frame
	for cell: int in opened:
		assert_true(_main._field.is_hole_cell(cell), "fixture: the hole is actually applied before we leave")

	Net.leave()
	await _settle()

	assert_true(_main._field.home_flags().is_empty(), "no stale home flags behind the menu")
	assert_true(_main._field.goal_flags().is_empty(), "no stale goal flags behind the menu")
	assert_null(_overlay_raster(), "the overlay keeps no reference to the ended match's raster")
	for cell: int in opened:
		assert_false(_main._field.is_hole_cell(cell), "every hole this match opened is closed")
	assert_eq(_main._field.pending_toggle_count(), 0, "no queued toggle survives the teardown")

	# A rehost still places the right number of flags for the next match
	# (existing coverage: test_rehost_after_the_match_ended_and_the_session_closed_builds_a_fresh_world;
	# this only pins that the fresh flag count is not an accident of a field
	# that was never actually cleared).
	_host()
	_start(3)
	await _settle()
	assert_eq(_home_flag_count(), 3, "a rehosted match still places the right number of flags")
