extends "res://tests/unit/match/match_world_test.gd"
## Match.request_place / request_throw: the shared release head (pose gate, down-ray, hole
## column, territory waiver) and the tail (feed consumed and refed, turn settle when turn-based),
## characterized through the public entry points only.

const AIM: Vector3 = Vector3(0.6, 0.0, 0.8)
const HOLE_REACH_M: float = 1.5
const HOLE_OPEN_S: float = 100.0


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	# Spawned bodies are freed synchronously so GUT's orphan check sees none.
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config(player_count: int = 2, turn_based: bool = false, sandbox: bool = false) -> MatchConfig:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = player_count
	config.block_timer = 6.0
	config.rng_seed = 97531
	config.turn_based = turn_based
	config.sandbox = sandbox
	# Old gift rule (a claim replaces the next piece).
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	return config


func _start(config: MatchConfig) -> void:
	Match.start_match(config)
	_run_countdown()


## Makes `slot_id` hold a throwable gift: queues it (sandbox-only API) and places one ordinary
## piece so the feed hands the gift over.
func _hold_gift(slot_id: int, gift_id: StringName = &"bomb") -> void:
	var was_sandbox: bool = Match.config.sandbox
	Match.config.sandbox = true
	assert_true(Match.debug_queue_special(slot_id, gift_id), "fixture: gift queued")
	Match.config.sandbox = was_sandbox
	assert_eq(
		Match.request_place(slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false),
		PlacementRules.REASON_OK, "fixture: ordinary piece placed so the gift is fed"
	)
	assert_eq(Match.held_special(slot_id), gift_id, "fixture: the gift is held")


func _off_disk_world() -> Vector3:
	return _field.to_global(Vector3(999.0, 5.0, 999.0))


func _centre_world() -> Vector3:
	return _field.to_global(Vector3(0.0, 5.0, 0.0))


## Opens a permanent raster hole under `local_xz` (disk-local), as an overlap hole would.
func _open_hole_at(local_xz: Vector2) -> void:
	var grid: CellGrid = Match.cell_grid()
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			if grid.is_in_disk(cx, cy) and grid.cell_center(cx, cy).distance_to(local_xz) <= HOLE_REACH_M:
				Match.raster().force_hole_cell(cx, cy, HOLE_OPEN_S, true)


func _hole_world(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _tick_match(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _settle_ticks() -> int:
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	return int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5


# --- Head: request_place refusals ---------------------------------------------------

func test_place_out_of_territory_is_refused_with_event_and_nothing_consumed() -> void:
	_start(_config())
	var seq: int = Match.feed_seq(0)
	var held: BlockShape = Match.held_shape(0)
	watch_signals(Events)

	var reason: StringName = Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)
	assert_eq(Match.held_shape(0), held)
	assert_eq(get_signal_emit_count(Events, "placement_rejected"), 1)
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [0, PlacementRules.REASON_OUTSIDE_TERRITORY])


func test_place_off_disk_is_refused_off_disk() -> void:
	_start(_config())
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _off_disk_world(), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OFF_DISK)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)


func test_place_plain_block_over_a_hole_is_refused_as_hole() -> void:
	_start(_config())
	var home: Vector2 = Match.slot(0).home_position
	_open_hole_at(home)
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _hole_world(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_HOLE)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)


func test_place_malformed_pose_is_refused_before_any_event() -> void:
	_start(_config())
	var seq: int = Match.feed_seq(0)
	watch_signals(Events)

	assert_eq(Match.request_place(0, Vector3(NAN, 0.0, 0.0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.request_place(0, _home_world_position(0), 999, Quaternion.IDENTITY, false), PlacementRules.REASON_NO_BLOCK)

	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)
	assert_signal_not_emitted(Events, "placement_rejected")


func test_place_goal_zone_is_refused_even_in_sandbox() -> void:
	_start(_config(2, false, true))
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _centre_world(), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_GOAL_ZONE, "sandbox waives territory only, not the goal zone")
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq)


# --- Head: waivers ----------------------------------------------------------------

func test_place_sandbox_waives_foreign_territory_and_consumes() -> void:
	_start(_config(2, false, true))
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_place_held_gift_waives_territory_and_goal_zone_but_not_off_disk() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)
	var blocks: int = _blocks_root.get_child_count()

	assert_eq(
		Match.request_place(0, _off_disk_world(), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OFF_DISK,
		"off disk still refused for a gift"
	)
	assert_eq(_blocks_root.get_child_count(), blocks)
	assert_eq(Match.feed_seq(0), seq)
	assert_eq(Match.held_special(0), &"bomb", "a refused gift release keeps the gift")

	assert_eq(Match.request_place(0, _centre_world(), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK, "goal zone waived for a gift")
	assert_eq(Match.feed_seq(0), seq + 1)
	assert_eq(Match.held_special(0), &"", "the gift is consumed by the release")


func test_place_held_gift_over_a_hole_lands() -> void:
	_start(_config())
	_hold_gift(0)
	_open_hole_at(Match.slot(0).home_position)
	var seq: int = Match.feed_seq(0)
	var blocks: int = _blocks_root.get_child_count()

	var reason: StringName = Match.request_place(0, _hole_world(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), blocks + 1)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_place_held_gift_past_the_rim_with_nothing_beneath_is_refused() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _off_disk_world(), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OFF_DISK)
	assert_eq(Match.feed_seq(0), seq)


# --- Tail: request_place ---------------------------------------------------------------

func test_place_accepted_consumes_the_piece_and_refeeds() -> void:
	_start(_config())
	var seq: int = Match.feed_seq(0)
	watch_signals(Events)

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq(Match.feed_seq(0), seq + 1)
	assert_not_null(Match.held_shape(0), "a new piece is fed")
	assert_signal_not_emitted(Events, "placement_rejected")


func test_place_auto_drop_out_of_territory_relocates_and_consumes() -> void:
	_start(_config())
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK, "a relocated auto-drop reports OK")
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_place_auto_drop_with_nowhere_valid_burns_and_still_consumes() -> void:
	_start(_config())
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(0))
	var seq: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, true)

	assert_ne(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1, "a burned auto-drop still spawns its block")
	assert_eq(Match.feed_seq(0), seq + 1, "and consumes the piece")


# --- Head: request_throw ------------------------------------------------------------------

func test_throw_with_a_plain_piece_is_not_a_special_before_any_point_test() -> void:
	_start(_config())
	watch_signals(Events)

	var reason: StringName = Match.request_throw(0, _off_disk_world(), 0, Quaternion.IDENTITY, AIM)

	assert_eq(reason, ThrowRules.REASON_NOT_A_SPECIAL)
	assert_signal_not_emitted(Events, "placement_rejected")


func test_throw_malformed_pose_or_aim_is_refused_before_any_event() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)
	var blocks: int = _blocks_root.get_child_count()
	watch_signals(Events)

	assert_eq(Match.request_throw(0, Vector3(NAN, 0.0, 0.0), 0, Quaternion.IDENTITY, AIM), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.request_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, Vector3.ZERO), PlacementRules.REASON_NO_BLOCK)

	assert_eq(_blocks_root.get_child_count(), blocks)
	assert_eq(Match.feed_seq(0), seq)
	assert_signal_not_emitted(Events, "placement_rejected")


func test_throw_off_disk_is_refused_with_event_and_keeps_the_gift() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)
	var blocks: int = _blocks_root.get_child_count()
	watch_signals(Events)

	var reason: StringName = Match.request_throw(0, _off_disk_world(), 0, Quaternion.IDENTITY, AIM)

	assert_eq(reason, ThrowRules.reason_for(PlacementRules.Result.OFF_DISK))
	assert_eq(_blocks_root.get_child_count(), blocks)
	assert_eq(Match.feed_seq(0), seq)
	assert_eq(Match.held_special(0), &"bomb")
	assert_eq(get_signal_emit_count(Events, "placement_rejected"), 1)
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [0, reason])


func test_throw_waives_foreign_territory_for_the_held_gift() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)

	assert_eq(Match.request_throw(0, _home_world_position(1), 0, Quaternion.IDENTITY, AIM), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_throw_waives_the_goal_zone_for_the_held_gift() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)

	assert_eq(Match.request_throw(0, _centre_world(), 0, Quaternion.IDENTITY, AIM), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), seq + 1)


func test_throw_over_a_hole_lands() -> void:
	_start(_config())
	_hold_gift(0)
	_open_hole_at(Match.slot(0).home_position)
	var seq: int = Match.feed_seq(0)

	assert_eq(Match.request_throw(0, _hole_world(0), 0, Quaternion.IDENTITY, AIM), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), seq + 1)


# --- Tail: request_throw ----------------------------------------------------------------

func test_throw_accepted_spawns_moving_block_consumes_gift_and_refeeds() -> void:
	_start(_config())
	_hold_gift(0)
	var seq: int = Match.feed_seq(0)
	var blocks: int = _blocks_root.get_child_count()

	var reason: StringName = Match.request_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), blocks + 1)
	assert_eq(Match.feed_seq(0), seq + 1)
	assert_eq(Match.held_special(0), &"", "the thrown gift is no longer held")
	assert_not_null(Match.held_shape(0))


# --- Turn settle ---------------------------------------------------------------------------

func test_turn_based_accepted_place_hands_the_turn_over_once_settled() -> void:
	_start(_config(2, true))
	assert_eq(Match.active_slot(), 0)
	assert_eq(Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	(_blocks_root.get_child(0) as Block).freeze = true

	await _tick_match(_settle_ticks())

	assert_eq(Match.active_slot(), 1)


func test_turn_based_refused_place_keeps_the_turn() -> void:
	_start(_config(2, true))
	assert_eq(Match.request_place(0, _home_world_position(1), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OUTSIDE_TERRITORY)

	await _tick_match(_settle_ticks())

	assert_eq(Match.active_slot(), 0, "no settle wait is armed by a refusal")


func test_turn_based_off_turn_slot_is_refused_before_the_point_test() -> void:
	_start(_config(2, true))
	watch_signals(Events)

	var reason: StringName = Match.request_place(1, _off_disk_world(), 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_NOT_YOUR_TURN)
	assert_signal_not_emitted(Events, "placement_rejected")


func test_turn_based_accepted_throw_hands_the_turn_over_once_settled() -> void:
	_start(_config(2, true))
	_hold_gift(0)
	# The ordinary piece placed by the fixture passed the turn once it settles; settle it first.
	(_blocks_root.get_child(0) as Block).freeze = true
	await _tick_match(_settle_ticks())
	assert_eq(Match.active_slot(), 1, "fixture: turn moved on")
	# Slot 1 takes its turn, then slot 0 holds the gift again on its next turn.
	assert_eq(Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	(_blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block).freeze = true
	await _tick_match(_settle_ticks())
	assert_eq(Match.active_slot(), 0, "fixture: back to slot 0")
	assert_eq(Match.held_special(0), &"bomb", "fixture: the gift is still held")

	assert_eq(Match.request_throw(0, _home_world_position(0), 0, Quaternion.IDENTITY, AIM), PlacementRules.REASON_OK)
	for child: Node in _blocks_root.get_children():
		(child as Block).linear_velocity = Vector3.ZERO
		(child as Block).freeze = true
	await _tick_match(_settle_ticks())

	assert_eq(Match.active_slot(), 1)


func test_turn_based_refused_throw_keeps_the_turn() -> void:
	_start(_config(2, true))
	_hold_gift(0)
	(_blocks_root.get_child(0) as Block).freeze = true
	await _tick_match(_settle_ticks())
	await _tick_match(1)
	assert_eq(Match.request_place(1, _home_world_position(1), 0, Quaternion.IDENTITY, false), PlacementRules.REASON_OK)
	for child: Node in _blocks_root.get_children():
		(child as Block).freeze = true
	await _tick_match(_settle_ticks())
	assert_eq(Match.active_slot(), 0, "fixture: back to slot 0")

	var reason: StringName = Match.request_throw(0, _off_disk_world(), 0, Quaternion.IDENTITY, AIM)
	await _tick_match(_settle_ticks())

	assert_ne(reason, PlacementRules.REASON_OK)
	assert_eq(Match.active_slot(), 0)
