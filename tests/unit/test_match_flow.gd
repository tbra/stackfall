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
