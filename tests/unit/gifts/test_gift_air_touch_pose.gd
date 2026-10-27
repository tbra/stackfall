extends GutTest
## A held block touching a falling gift crate in the air claims it (MatchGifts.tick_host). The local
## seat's pose is the LocalHeldView read through MatchContext.local_held(); a remote seat's pose is
## the replicator cursor. Everything is observed through Match.gift_state, pending_special_count
## and Events.gift_claimed. Local-seat claim cases are red until the view replaces the ghost group read.

class CursorProvider:
	extends RefCounted
	var poses: Dictionary = {}
	func cursor_for_slot(slot_id: int) -> Dictionary:
		return poses.get(slot_id, {})

const CRATE_POINT: Vector2 = Vector2(0.0, 15.0)
const TOUCH_DROP_M: float = 0.5
const FAR_M: float = 6.0
const TICK_S: float = 0.01
const LOCAL: int = 0
const OTHER: int = 1

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef
var _cube: BlockShape


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_cube = load("res://config/blocks/cube.tres") as BlockShape
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match._net_provider = null
	Match.set_replicator(null)
	MatchContext.current().local_held().clear()
	Match._gifts._gift_config = load("res://config/gifts/gift_config.tres") as GiftConfig
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _start(turn_based: bool = false) -> void:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.rng_seed = 4242
	config.sandbox = true
	config.gifts_enabled = true
	config.special_frequency = 0
	config.turn_based = turn_based
	Match.start_match(config)
	for index: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._gifts._gift_config = Match._gifts._gift_config.duplicate() as GiftConfig
	for slot: int in range(2):
		Match._feed.debug_force_next_shape(slot, _cube.id)


func _spawn() -> int:
	var gift_id: int = Match._gifts._next_gift_id
	Match._gifts._spawn_crate_at(CRATE_POINT)
	return gift_id


func _crate(gift_id: int) -> Vector3:
	return Match.gift_state(gift_id)["origin"]


func _touch_pose(crate: Vector3) -> Vector3:
	return crate - Vector3.UP * TOUCH_DROP_M


func _publish(slot: int, shape: BlockShape, origin: Vector3) -> void:
	MatchContext.current().local_held().publish(slot, shape, origin, 0, Quaternion.IDENTITY, true, 0.0, 0)


func _claimed(gift_id: int) -> bool:
	return Match.gift_state(gift_id).is_empty()


func test_view_of_the_held_shape_touching_the_crate_claims_it() -> void:
	_start()
	var gift_id: int = _spawn()
	assert_eq(Match.held_shape(LOCAL), _cube, "fixture: the held piece is the cube")
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)))
	watch_signals(Events)
	Match._gifts.tick_host(TICK_S)
	assert_true(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), 1)
	assert_signal_emit_count(Events, "gift_claimed", 1)


func test_view_far_from_the_crate_does_not_claim() -> void:
	_start()
	var gift_id: int = _spawn()
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)) + Vector3.RIGHT * FAR_M)
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), 0)


func test_view_of_a_previous_piece_does_not_claim() -> void:
	_start()
	var gift_id: int = _spawn()
	var previous: BlockShape = load("res://config/blocks/domino.tres") as BlockShape
	assert_ne(previous, Match.held_shape(LOCAL), "fixture: the view's piece is not the one in hand")
	_publish(LOCAL, previous, _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), 0)


func test_null_view_does_not_claim() -> void:
	_start()
	var gift_id: int = _spawn()
	_publish(LOCAL, null, _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id))


func test_view_cleared_after_release_does_not_claim() -> void:
	_start()
	var gift_id: int = _spawn()
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)))
	MatchContext.current().local_held().clear()
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id), "a released block leaves no phantom claim")
	assert_eq(Match.pending_special_count(LOCAL), 0)


func test_eliminated_seat_does_not_claim() -> void:
	_start()
	var gift_id: int = _spawn()
	Match.slot(LOCAL).home_flag_alive = false
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id))


func test_view_published_for_another_seat_is_not_the_local_pose() -> void:
	_start()
	var gift_id: int = _spawn()
	_publish(OTHER, Match.held_shape(OTHER), _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id), "the view stands for the local seat only")
	assert_eq(Match.pending_special_count(OTHER), 0)


func test_turn_based_active_seat_claims_with_its_view() -> void:
	_start(true)
	var gift_id: int = _spawn()
	assert_eq(Match.active_slot(), LOCAL)
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_true(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), 1)


func test_turn_based_off_turn_seat_does_not_claim() -> void:
	_start(true)
	var gift_id: int = _spawn()
	Match.advance_turn()
	assert_eq(Match.active_slot(), OTHER, "fixture: the turn moved on")
	_publish(LOCAL, Match.held_shape(LOCAL), _touch_pose(_crate(gift_id)))
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), 0)


func test_cursor_touching_claims_without_any_view() -> void:
	_start()
	var gift_id: int = _spawn()
	var provider: CursorProvider = CursorProvider.new()
	provider.poses[OTHER] = {"origin": _touch_pose(_crate(gift_id)), "orientation_index": 0,
		"free_quat": Quaternion.IDENTITY, "age": 0.0}
	Match.set_replicator(provider)
	Match._gifts.tick_host(TICK_S)
	assert_true(_claimed(gift_id))
	assert_eq(Match.pending_special_count(OTHER), 1)


func test_fresh_cursor_wins_over_the_view() -> void:
	_start()
	var gift_id: int = _spawn()
	var touching: Vector3 = _touch_pose(_crate(gift_id))
	var provider: CursorProvider = CursorProvider.new()
	provider.poses[LOCAL] = {"origin": touching + Vector3.RIGHT * FAR_M, "orientation_index": 0,
		"free_quat": Quaternion.IDENTITY, "age": 0.0}
	Match.set_replicator(provider)
	_publish(LOCAL, Match.held_shape(LOCAL), touching)
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id), "the accepted cursor decides, not the view")


func test_cursor_exactly_at_max_age_still_counts_and_older_falls_back_to_the_view() -> void:
	_start()
	var gift_id: int = _spawn()
	var touching: Vector3 = _touch_pose(_crate(gift_id))
	var max_age: float = Match._gifts._gift_config.cursor_max_age_s
	var provider: CursorProvider = CursorProvider.new()
	provider.poses[LOCAL] = {"origin": touching + Vector3.RIGHT * FAR_M, "orientation_index": 0,
		"free_quat": Quaternion.IDENTITY, "age": max_age}
	Match.set_replicator(provider)
	_publish(LOCAL, Match.held_shape(LOCAL), touching)
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id), "age == cursor_max_age_s is still accepted")
	provider.poses[LOCAL]["age"] = max_age + 0.01
	Match._gifts.tick_host(TICK_S)
	assert_true(_claimed(gift_id), "a stale cursor is ignored and the view is read")


func _held_gift_setup() -> BlockShape:
	assert_true(Match.debug_queue_special(LOCAL, &"earthquake"))
	var home: Vector2 = Match.slot(LOCAL).home_position
	var at: Vector3 = _field.to_global(Vector3(home.x, 5.0, home.y))
	assert_eq(Match.request_place(LOCAL, at, 0, Quaternion.IDENTITY, false, Match.feed_seq(LOCAL)),
		PlacementRules.REASON_OK)
	assert_eq(Match.held_special(LOCAL), &"earthquake", "fixture: the gift carrier is in hand")
	return Match.held_shape(LOCAL)


func test_held_gift_claims_where_its_one_cell_sits() -> void:
	_start()
	var shape: BlockShape = _held_gift_setup()
	var gift_id: int = _spawn()
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	_publish(LOCAL, shape, _crate(gift_id) - BlockFactory.gift_cell_center(shape, tuning))
	var queued_before: int = Match.pending_special_count(LOCAL)
	Match._gifts.tick_host(TICK_S)
	assert_true(_claimed(gift_id))
	assert_eq(Match.pending_special_count(LOCAL), queued_before + 1, "the claim queues one special")


func test_held_gift_ignores_the_carrier_cells_outside_its_one_cell() -> void:
	_start()
	var shape: BlockShape = _held_gift_setup()
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres") as PhysicsTuning
	var gift_center: Vector3 = BlockFactory.gift_cell_center(shape, tuning)
	var pivot: Vector3 = shape.bottom_center()
	var other_center: Vector3 = Vector3.ZERO
	var found: bool = false
	for cell: Vector3i in shape.cells:
		var center: Vector3 = (Vector3(cell) - pivot) * tuning.cube_size
		if center.distance_to(gift_center) > tuning.cube_size * 0.9:
			other_center = center
			found = true
			break
	if not found:
		pending("the carrier is a single cell here; no second cell to tell apart")
		return
	var gift_id: int = _spawn()
	_publish(LOCAL, shape, _crate(gift_id) - other_center)
	Match._gifts.tick_host(TICK_S)
	assert_false(_claimed(gift_id), "only the gift's own cell can touch")
