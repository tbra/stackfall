extends GutTest
## autoload/match/MatchPlacement.gd's request_place(): a manual (auto_drop ==
## false) release outside the placing player's own territory (spec 2.5's
## contract; docs/AGENT_WORKFLOW.md Bontago-mv0.24, owner test 2026-09-22).
##
## The owner's test of the original found a refused drop is simply not a
## drop: nothing spawns, nothing is consumed, and the player keeps holding the
## same piece and may try again -- superseding spec 2.2's older "thrown off
## the map with a visible reject animation" line for this case (see
## Events.placement_rejected's own doc comment). An auto-drop still relocates
## to the closest valid point as before, and now also tells the owning client
## exactly where it landed via Events.placement_relocated, so
## game/PlayerController.gd can snap its cursor and camera there.
##
## Fixture mirrors tests/unit/test_match_flow.gd's own (tiny map, real Field/
## Match, no live peer) rather than reusing its private helpers across files.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	# Script swap first: Object.set_script() resets script-level state to the
	# new script's declared defaults (test_match_flow.gd's own
	# _tiny_map_config() DECISION has the full story).
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 24680
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


# --- Outcome 1: a manual out-of-zone drop is refused, not burned ------------

func test_manual_drop_outside_territory_is_refused_and_the_block_stays_held() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)
	watch_signals(Events)

	# Slot 1's home is outside slot 0's own territory.
	var reason: StringName = Match.request_place(
		slot_id, _home_world_position(1), 0, Quaternion.IDENTITY, false
	)

	assert_eq(reason, PlacementRules.REASON_OUTSIDE_TERRITORY)
	assert_eq(
		_blocks_root.get_child_count(), 0,
		"Owner test 2026-09-22: a refused manual drop must not spawn a block, burned or otherwise."
	)
	assert_eq(Match.feed_seq(slot_id), seq_before, "the piece must not be consumed")
	assert_eq(Match.held_shape(slot_id), shape_before, "the player must still be holding the exact same piece")
	assert_eq(get_signal_emit_count(Events, "placement_rejected"), 1)
	assert_signal_emitted_with_parameters(Events, "placement_rejected", [slot_id, PlacementRules.REASON_OUTSIDE_TERRITORY])

	# The refusal must not have jammed anything: a second, valid, drop still
	# works right afterwards.
	var second_reason: StringName = Match.request_place(
		slot_id, _home_world_position(slot_id), 0, Quaternion.IDENTITY, false
	)
	assert_eq(second_reason, PlacementRules.REASON_OK)
	assert_eq(_blocks_root.get_child_count(), 1)


func test_manual_drop_in_a_goal_flags_no_build_zone_is_refused_too() -> void:
	Match.start_match(_config())
	_run_countdown()
	var center_world: Vector3 = _field.to_global(Vector3(0.0, 5.0, 0.0))
	var seq_before: int = Match.feed_seq(0)

	var reason: StringName = Match.request_place(0, center_world, 0, Quaternion.IDENTITY, false)

	assert_eq(reason, PlacementRules.REASON_GOAL_ZONE)
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_eq(Match.feed_seq(0), seq_before, "the piece must not be consumed")


# --- Outcome 2: an auto-drop outside the zone relocates and says where ------

func test_auto_drop_outside_the_zone_relocates_and_emits_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var home: Vector2 = Match.slot(slot_id).home_position
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	# Just past the home circle's own radius, so validate_point() refuses the
	# raw point but a valid one sits only a couple of metres away -- well
	# inside auto_drop_search_max_radius (config/territory_tuning.tres: step
	# 1.0, max 12.0).
	var desired_local: Vector2 = home + Vector2(tuning.home_radius + 1.5, 0.0)
	var desired_world: Vector3 = _field.to_global(Vector3(desired_local.x, 5.0, desired_local.y))
	watch_signals(Events)

	var reason: StringName = Match.request_place(slot_id, desired_world, 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK, "a successfully relocated auto-drop still reports OK.")
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_signal_emitted(Events, "placement_relocated")
	var params: Array = get_signal_parameters(Events, "placement_relocated")
	assert_eq(int(params[0]), slot_id)
	var relocated_point: Vector2 = params[1]
	assert_ne(
		relocated_point, desired_local,
		"the reported point must be where the block actually landed, not the invalid spot it was asked for."
	)

	# The reported point must be exactly the spawned block's own disk-local
	# origin -- the same frame final_disk_origin already used to spawn it.
	var block: Node3D = _blocks_root.get_child(0) as Node3D
	var spawned_local: Vector3 = _field.to_local(block.global_position)
	assert_almost_eq(relocated_point.x, spawned_local.x, 0.01)
	assert_almost_eq(relocated_point.y, spawned_local.z, 0.01)


func test_auto_drop_inside_the_zone_never_emits_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()
	watch_signals(Events)

	var reason: StringName = Match.request_place(0, _home_world_position(0), 0, Quaternion.IDENTITY, true)

	assert_eq(reason, PlacementRules.REASON_OK)
	assert_signal_not_emitted(Events, "placement_relocated", "a valid auto-drop never relocates.")


# --- Outcome 3: PlayerController reacts only to its own slot's relocation ---

func test_playercontroller_moves_its_cursor_on_its_own_slots_placement_relocated() -> void:
	Match.start_match(_config())
	_run_countdown()

	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_acting_slot(0)

	var point: Vector2 = Match.slot(0).home_position + Vector2(2.0, 0.0)

	# A relocation for a different slot must be ignored entirely.
	Events.placement_relocated.emit(1, point)
	assert_eq(controller._cursor, Vector3.ZERO, "another slot's relocation must not move this controller's cursor.")

	Events.placement_relocated.emit(0, point)
	var expected_world: Vector3 = _field.to_global(Vector3(point.x, 0.0, point.y))
	assert_true(
		controller._cursor.is_equal_approx(expected_world),
		"the controller's own slot's relocation must move the cursor to the reported disk-local point."
	)
