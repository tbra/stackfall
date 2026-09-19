extends GutTest
## autoload/Match.gd: the host state machine, the feed timer/auto-drop, and
## request_place's accept/reject/burn decision (spec 2.4, 2.5, 3.7).
##
## PlacementRules.validate()/closest_valid_origin() are P1-owned and still
## stubs at the time this package was built (docs/M2_PLAN.md: packages build
## in parallel off the stub commit). The accept/reject/burn *decision* is
## exercised directly against Match._resolve_outcome() with manufactured
## PlacementRules.Result values instead of a working raster — the "use
## fakes/stubs for territory results" the P2 brief calls for. The state
## machine, turn order and feed timer tests below don't touch PlacementRules
## at all, so they exercise real behavior end to end.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry


func before_each() -> void:
	# Match is a live autoload the engine ticks every real frame. These tests
	# drive it by calling _process() directly instead, so its automatic
	# processing is turned off for the duration — otherwise a real frame
	# advancing between statements (e.g. inside add_child_autofree) would
	# double-count delta against the manual calls below.
	Match.set_process(false)
	Match.abort_match()
	_field = autofree(Field.new())
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)


func _hotseat_config(player_count: int = 2, block_timer: float = 6.0) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.player_count = player_count
	config.hot_seat = true
	config.block_timer = block_timer
	config.rng_seed = 12345
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


## World position right on `slot_id`'s own home flag. Placement tests that
## exercise the real PlacementRules path (not the manufactured-Result tests
## further down) drop here rather than at an arbitrary point, so they stay
## meaningful once P1's validate() is more than a stub: a single cube on your
## own home flag should read VALID under any reasonable territory rule.
func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


# --- State machine (spec 3.7) ------------------------------------------------

func test_start_match_runs_lobby_to_playing_with_countdown_ticks() -> void:
	# assert_signal_emitted_with_parameters only checks the LATEST emission,
	# so the exact 3, 2, 1, 0 sequence (spec 3.7) is collected by hand instead.
	var ticks: Array[int] = []
	var collect: Callable = func(seconds_left: int) -> void: ticks.append(seconds_left)
	Events.countdown_tick.connect(collect)

	Match.start_match(_hotseat_config())
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(ticks, [3] as Array[int])

	_run_countdown()

	Events.countdown_tick.disconnect(collect)
	assert_eq(Match.state(), Match.State.PLAYING)
	assert_eq(ticks, [3, 2, 1, 0] as Array[int])


func test_start_match_builds_slots_and_issues_first_blocks() -> void:
	watch_signals(Events)
	Match.start_match(_hotseat_config(2))
	_run_countdown()

	assert_eq(Match.slot_count(), 2)
	assert_not_null(Match.held_shape(0))
	assert_not_null(Match.held_shape(1))
	assert_signal_emitted(Events, "feed_block_issued")
	assert_signal_emitted_with_parameters(Events, "turn_changed", [0])
	assert_eq(Match.active_slot(), 0)


func test_abort_match_returns_to_lobby() -> void:
	Match.start_match(_hotseat_config())
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)

	Match.abort_match()

	assert_eq(Match.state(), Match.State.LOBBY)
	assert_eq(Match.slot_count(), 0)


# --- Restart and teardown ordering (spec 3.7; Beads Bontago-mv0.1.9) --------
# game/Main.gd builds the match world synchronously inside the LOADING emit
# and reads Match.raster()/slot()/registry() right there, so the world model
# must be complete by then; and a start from a stale PLAYING/END (rehost
# after the host quit, a future rematch) must go back through LOBBY so every
# consumer tears the previous match down before the new one is built.

## Every transition Match emits, in order, as [from, to] pairs.
func _record_transitions(into: Array[Array]) -> Callable:
	var recorder: Callable = func(from_state: int, to_state: int) -> void:
		into.append([from_state, to_state])
	Events.match_state_changed.connect(recorder)
	return recorder


func test_loading_is_emitted_only_once_the_world_model_is_built() -> void:
	var seen_at_loading: Dictionary = {}
	var probe: Callable = func(_from_state: int, to_state: int) -> void:
		if to_state == Match.State.LOADING:
			seen_at_loading["raster"] = Match.raster()
			seen_at_loading["slots"] = Match.slot_count()
			seen_at_loading["config"] = Match.config
			seen_at_loading["cell_grid"] = Match.cell_grid()
	Events.match_state_changed.connect(probe)

	Match.start_match(_hotseat_config(3))
	Events.match_state_changed.disconnect(probe)

	assert_true(seen_at_loading.has("raster"), "LOADING must be emitted")
	assert_not_null(seen_at_loading.get("raster"), "The raster must exist when LOADING fires (Main binds the overlay to it).")
	assert_eq(seen_at_loading.get("raster"), Match.raster(), "and be the one the match then plays on")
	assert_not_null(seen_at_loading.get("cell_grid"))
	assert_eq(seen_at_loading.get("slots"), 3, "The slots must exist when LOADING fires (Main places the flags from them).")
	assert_not_null(seen_at_loading.get("config"), "The sanitized config must exist when LOADING fires.")


func test_start_match_from_playing_returns_through_lobby_with_a_fresh_world() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	assert_eq(Match.state(), Match.State.PLAYING)
	var old_raster: TerritoryRaster = Match.raster()
	var old_slot: PlayerSlot = Match.slot(0)
	# Spend some of slot 0's timer so a stale value would be visible.
	for _i: int in range(60):
		Match._process(1.0 / 60.0)
	assert_eq(Match.active_slot(), 0)

	var transitions: Array[Array] = []
	var recorder: Callable = _record_transitions(transitions)
	Match.start_match(_hotseat_config(3))
	Events.match_state_changed.disconnect(recorder)

	assert_eq(
		transitions,
		[
			[Match.State.PLAYING, Match.State.LOBBY],
			[Match.State.LOBBY, Match.State.LOADING],
			[Match.State.LOADING, Match.State.COUNTDOWN],
		] as Array[Array],
		"A restart goes back through LOBBY so consumers see exactly one LOBBY -> LOADING per match."
	)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(Match.slot_count(), 3, "The new config, not the old one")
	assert_ne(Match.raster(), old_raster, "A fresh raster")
	assert_ne(Match.slot(0), old_slot, "Fresh slots")
	assert_eq(Match.active_slot(), -1, "No turn is active before play begins")
	assert_null(Match.held_shape(0), "No held block carries over")
	assert_eq(Match.blocks_spawned(), 0)


func test_start_match_from_end_returns_through_lobby() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	Match._finish_match(0)
	assert_eq(Match.state(), Match.State.END)

	var transitions: Array[Array] = []
	var recorder: Callable = _record_transitions(transitions)
	Match.start_match(_hotseat_config(2))
	Events.match_state_changed.disconnect(recorder)

	assert_eq(transitions[0], [Match.State.END, Match.State.LOBBY] as Array)
	assert_eq(transitions[1], [Match.State.LOBBY, Match.State.LOADING] as Array)
	assert_eq(Match.state(), Match.State.COUNTDOWN)
	assert_eq(Match.winner_team(), -1, "The previous winner does not carry over")


func test_start_match_from_lobby_emits_no_lobby_transition() -> void:
	var transitions: Array[Array] = []
	var recorder: Callable = _record_transitions(transitions)
	Match.start_match(_hotseat_config(2))
	Events.match_state_changed.disconnect(recorder)

	assert_eq(
		transitions,
		[
			[Match.State.LOBBY, Match.State.LOADING],
			[Match.State.LOADING, Match.State.COUNTDOWN],
		] as Array[Array],
		"M2's first-start sequence is unchanged."
	)


func test_abort_match_stops_the_host_ticking() -> void:
	watch_signals(Events)
	Match.start_match(_hotseat_config(2, MatchConfig.BLOCK_TIMER_MIN))
	_run_countdown()

	Match.abort_match()
	for _i: int in range(int(MatchConfig.BLOCK_TIMER_MIN * 60.0) * 2):
		Match._process(1.0 / 60.0)

	assert_eq(Match.state(), Match.State.LOBBY)
	assert_signal_not_emitted(Events, "feed_timer_expired", "An aborted match must not keep running its feed.")
	assert_signal_not_emitted(Events, "match_won")
	assert_null(Match.config)
	assert_null(Match.raster())
	assert_eq(Match.countdown_remaining(), 0.0)


# --- Hot-seat turn order and feed timer (spec 2.2, 2.4, 2.7) ----------------

func test_only_the_active_slot_timer_runs_in_hot_seat() -> void:
	Match.start_match(_hotseat_config(2, 6.0))
	_run_countdown()

	var full: float = Match.feed_time_left(0)
	for _i: int in range(60):  # 1 second at 60 Hz
		Match._process(1.0 / 60.0)

	assert_lt(Match.feed_time_left(0), full, "The active slot's timer should have ticked down.")
	assert_almost_eq(Match.feed_time_left(1), 6.0, 0.001, "The inactive slot's timer must not move.")


func test_feed_timer_expires_exactly_at_block_timer() -> void:
	# spec 2.8's block_timer range is 3-12 s; sanitize() (called by
	# start_match) clamps to that, so the test uses the minimum rather than an
	# arbitrary short value.
	var block_timer: float = MatchConfig.BLOCK_TIMER_MIN
	watch_signals(Events)
	Match.start_match(_hotseat_config(2, block_timer))
	_run_countdown()

	var frames_just_under: int = int(block_timer * 60.0) - 1
	for _i: int in range(frames_just_under):
		Match._process(1.0 / 60.0)
	assert_signal_not_emitted(Events, "feed_timer_expired")

	for _i: int in range(5):
		Match._process(1.0 / 60.0)
	assert_signal_emitted_with_parameters(Events, "feed_timer_expired", [0])


func test_feed_timer_expiry_fires_only_once_until_the_turn_advances() -> void:
	watch_signals(Events)
	Match.start_match(_hotseat_config(2, MatchConfig.BLOCK_TIMER_MIN))
	_run_countdown()

	for _i: int in range(int(MatchConfig.BLOCK_TIMER_MIN * 60.0) * 2):  # well past the timer; turn never advances
		Match._process(1.0 / 60.0)

	assert_signal_emit_count(
		Events, "feed_timer_expired", 1,
		"feed_timer_expired should not re-fire every frame once it has fired."
	)


func test_turn_advances_on_placement_and_wraps_around() -> void:
	Match.start_match(_hotseat_config(2, 6.0))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	var shape0: BlockShape = Match.held_shape(0)
	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)
	assert_ne(shape0, null)
	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(Match.active_slot(), 1, "Turn should pass to slot 1 after slot 0 places.")

	Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false)
	assert_eq(Match.active_slot(), 0, "Turn should wrap back to slot 0.")


func test_request_place_rejects_the_slot_whose_turn_it_isnt() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	assert_eq(Match.active_slot(), 0)

	var reason: StringName = Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_NOT_YOUR_TURN)
	assert_eq(_blocks_root.get_child_count(), 0, "A not-your-turn request must not spawn anything.")


func test_request_place_before_playing_returns_no_block() -> void:
	Match.start_match(_hotseat_config(2))
	# Still in COUNTDOWN.
	var reason: StringName = Match.request_place(0, Vector3.ZERO, 0, Quaternion.IDENTITY, false)
	assert_eq(reason, PlacementRules.REASON_NO_BLOCK)


func test_request_place_consumes_the_block_and_feeds_the_next_one() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var held_before: BlockShape = Match.held_shape(0)
	Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)

	assert_ne(Match.held_shape(0), null, "A new block should be waiting for slot 0's next turn.")
	assert_eq(_blocks_root.get_child_count(), 1)
	var spawned: Node = _blocks_root.get_child(0)
	assert_signal_emitted_with_parameters(Events, "block_placed", [spawned, held_before.id])


# --- The authority's own guard against a pose it cannot evaluate -----------
# net/MatchNet.gd refuses these at the wire (tests/unit/
# test_remote_intent_validation.gd); Match refuses them too, from any caller,
# so a bad index can never reach BlockOrientations.get_basis() and a NaN
# origin can never reach the raster (Beads Bontago-mv0.1.5, .6).

func test_request_place_refuses_a_malformed_pose_without_spending_the_block() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	var seq: int = Match.feed_seq(0)
	var home: Vector3 = _home_world_position(0)

	var bad_poses: Array[Array] = [
		[home, -1, Quaternion.IDENTITY],
		[home, BlockOrientations.ORIENTATION_COUNT, Quaternion.IDENTITY],
		[home, 1 << 40, Quaternion.IDENTITY],
		[Vector3(NAN, home.y, home.z), 0, Quaternion.IDENTITY],
		[Vector3(home.x, INF, home.z), 0, Quaternion.IDENTITY],
		[home, 0, Quaternion(0.0, 0.0, 0.0, 0.0)],
		[home, 0, Quaternion(0.0, 0.0, 0.0, 2.0)],
		[home, 0, Quaternion(NAN, 0.0, 0.0, 1.0)],
	]
	for pose: Array in bad_poses:
		var reason: StringName = Match.request_place(0, pose[0], int(pose[1]), pose[2], false)
		assert_eq(reason, PlacementRules.REASON_NO_BLOCK, "Pose %s must be refused." % [pose])

	assert_eq(_blocks_root.get_child_count(), 0, "A malformed pose spawns nothing, not even a burned block.")
	assert_eq(Match.feed_seq(0), seq, "and consumes nothing")
	assert_eq(Match.active_slot(), 0, "and the hot-seat turn does not pass")


func test_preview_placement_reports_empty_for_a_malformed_pose() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	var home: Vector3 = _home_world_position(0)

	assert_eq(Match.preview_placement(0, home, BlockOrientations.ORIENTATION_COUNT, Quaternion.IDENTITY), PlacementRules.Result.EMPTY)
	assert_eq(Match.preview_placement(0, Vector3(NAN, 0.0, 0.0), 0, Quaternion.IDENTITY), PlacementRules.Result.EMPTY)
	assert_eq(Match.preview_placement(0, home, 0, Quaternion(0.0, 0.0, 0.0, 0.0)), PlacementRules.Result.EMPTY)
	assert_ne(
		Match.preview_placement(0, home, 0, Quaternion.IDENTITY),
		PlacementRules.Result.EMPTY,
		"A well-formed pose is still previewed for real."
	)


func test_is_pose_well_formed_accepts_every_table_index_and_any_unit_rotation() -> void:
	for index: int in range(BlockOrientations.ORIENTATION_COUNT):
		assert_true(Match.is_pose_well_formed(Vector3.ZERO, index, Quaternion.IDENTITY))
	assert_true(Match.is_pose_well_formed(Vector3(1.0e6, -1.0e6, 3.0), 5, Quaternion(Vector3(1.0, 1.0, 0.0).normalized(), 2.0)))
	assert_false(Match.is_pose_well_formed(Vector3.ZERO, -1, Quaternion.IDENTITY))
	assert_false(Match.is_pose_well_formed(Vector3(0.0, 0.0, -INF), 0, Quaternion.IDENTITY))
	assert_false(Match.is_pose_well_formed(Vector3.ZERO, 0, Quaternion(1.0, 1.0, 1.0, 1.0)))


# --- request_place's accept/reject/burn decision (spec 2.2, 2.5) -----------
# Match._resolve_outcome() is the pure seam: given a PlacementRules.Result
# (what a working raster would have produced) and, for auto-drop, a
# relocation result, it decides the reason and whether to relocate. Testing
# it directly does not require PlacementRules' still-stubbed validate()/
# closest_valid_origin() to do anything real yet.

func test_resolve_outcome_valid_is_accepted_without_relocation() -> void:
	var outcome: Dictionary = Match._resolve_outcome(PlacementRules.Result.VALID, false, PlacementRules.NO_ORIGIN)
	assert_eq(outcome["reason"], PlacementRules.REASON_OK)
	assert_false(outcome["use_relocation"])


func test_resolve_outcome_deliberate_invalid_burns_with_its_reason() -> void:
	var invalid_results: Array[PlacementRules.Result] = [
		PlacementRules.Result.OUTSIDE_TERRITORY,
		PlacementRules.Result.CONTESTED,
		PlacementRules.Result.HOLE,
		PlacementRules.Result.OFF_DISK,
	]
	for result: PlacementRules.Result in invalid_results:
		var outcome: Dictionary = Match._resolve_outcome(result, false, PlacementRules.NO_ORIGIN)
		# reason_for() itself is still a P1 stub (always REASON_OK) at the time
		# this package was built; what this test owns is that _resolve_outcome
		# defers to it verbatim rather than inventing its own mapping.
		assert_eq(outcome["reason"], PlacementRules.reason_for(result))
		assert_false(outcome["use_relocation"], "A deliberate release never relocates (docs/M2_PLAN.md).")


func test_resolve_outcome_auto_drop_relocates_when_a_valid_spot_was_found() -> void:
	var relocated: Vector2 = Vector2(4.0, -2.0)
	var outcome: Dictionary = Match._resolve_outcome(PlacementRules.Result.CONTESTED, true, relocated)
	assert_eq(outcome["reason"], PlacementRules.REASON_OK)
	assert_true(outcome["use_relocation"])


func test_resolve_outcome_auto_drop_burns_when_no_relocation_exists() -> void:
	var outcome: Dictionary = Match._resolve_outcome(
		PlacementRules.Result.HOLE, true, PlacementRules.NO_ORIGIN
	)
	assert_eq(outcome["reason"], PlacementRules.reason_for(PlacementRules.Result.HOLE))
	assert_false(outcome["use_relocation"])


# --- Owner decision: home flag lost to a hole eliminates the slot ----------

func test_player_eliminated_when_holes_open_under_their_home_flag() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var home_cell: Vector2i = Match.cell_grid().world_to_cell(Match.slot(0).home_position)
	var index: int = Match.cell_grid().cell_index(home_cell.x, home_cell.y)
	Match._check_home_flags(PackedInt32Array([index]))

	assert_false(Match.slot(0).home_flag_alive)
	assert_signal_emitted_with_parameters(Events, "player_eliminated", [0, 0])


func test_match_ends_when_only_one_team_remains() -> void:
	Match.start_match(_hotseat_config(2))
	_run_countdown()
	watch_signals(Events)

	var home_cell: Vector2i = Match.cell_grid().world_to_cell(Match.slot(0).home_position)
	var index: int = Match.cell_grid().cell_index(home_cell.x, home_cell.y)
	Match._check_home_flags(PackedInt32Array([index]))

	assert_eq(Match.state(), Match.State.END)
	assert_signal_emitted_with_parameters(Events, "match_won", [1])
