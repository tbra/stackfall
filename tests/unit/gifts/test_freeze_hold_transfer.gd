extends GutTest
## A Freeze hold follows its body through glue fusion (GlueFusion.fuse), a collapse back to a
## single Block (FusedBody.remove_member) and a hole dissolve (HoleDissolver.start_dissolve).
## Characterisation through the public API: the hold is read through Block.is_freeze_static(),
## Block.freeze, Block.is_frozen_visual(), Events.block_frozen_changed and the release Timer
## child (FreezeEffect.TIMER_NAME) that the 20 s expiry is driven through, as test_freeze_effect.gd does.

const MEMBER_GAP_M: float = 1.2
const AIR_Y_M: float = 4.0
const LONG_S: float = 20.0
const SHORT_S: float = 5.0
const TIME_TOLERANCE_S: float = 1.0
const SETTLE_FRAMES: int = 3
const DISSOLVE_FRAMES: int = 60

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _glue: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")
var _cube: BlockShape = load("res://config/blocks/cube.tres")

var _field: Field
var _registry: BlockRegistry
var _root: Node3D
var _removed_ids: Dictionary = {}
## net_id -> last frozen flag seen on Events.block_frozen_changed.
var _frozen_events: Dictionary = {}


func before_each() -> void:
	_removed_ids = {}
	_frozen_events = {}
	Events.block_removed.connect(_record_removed)
	Events.block_frozen_changed.connect(_record_frozen)
	var map: MapDef = MapDef.new()
	map.id = &"test_freeze_hold_transfer"
	map.field_radius = 6.0
	map.cell_size = 1.0
	map.disk_height = 1.0
	map.territory_res = 32
	_field = Field.new()
	_field.map_def = map
	add_child_autofree(_field)
	_root = Node3D.new()
	add_child_autofree(_root)
	_registry = BlockRegistry.new()
	add_child_autofree(_registry)
	_registry.set_host_authority(true)
	_registry.configure(_field, map)


func after_each() -> void:
	if Events.block_removed.is_connected(_record_removed):
		Events.block_removed.disconnect(_record_removed)
	if Events.block_frozen_changed.is_connected(_record_frozen):
		Events.block_frozen_changed.disconnect(_record_frozen)


func _record_frozen(net_id: int, frozen: bool) -> void:
	_frozen_events[net_id] = frozen


func _record_removed(block: RigidBody3D, _reason: String) -> void:
	_removed_ids[block.get_instance_id()] = true


## A registered cube hanging in the air (registered so it has a net_id and the dissolver sees it).
func _block(index: int) -> Block:
	var block: Block = BlockFactory.build(_cube, _tuning, 0)
	_root.add_child(block)
	block.global_position = _field.world_from_disk_local(Vector2(float(index) * MEMBER_GAP_M, 0.0), AIR_Y_M)
	Events.block_placed.emit(block, _cube.id)
	return block


func _frozen_block(index: int, duration_s: float) -> Block:
	var block: Block = _block(index)
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_duration_s = duration_s
	effect.freeze_block(block, _field)
	return block


func _timer(block: Block) -> Timer:
	return block.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)) as Timer


func _fuse(charged: Block, target: Block) -> FusedBody:
	var carrier: FusedBody = GlueFusion.fuse(charged, target, _glue)
	assert_not_null(carrier, "fixture: the pair fuses")
	return carrier


# --- fuse: the hold moves to the carrier ------------------------------------

func test_fusing_two_frozen_blocks_leaves_the_carrier_held_and_the_members_released_of_their_timers() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)

	assert_true(carrier.is_freeze_static(), "the carrier holds the group")
	assert_true(carrier.freeze, "the carrier body is frozen")
	assert_not_null(_timer(carrier), "the release timer lives on the carrier")
	assert_null(_timer(a), "a member keeps no timer of its own")
	assert_null(_timer(b), "a member keeps no timer of its own")


func test_the_longer_remaining_hold_wins_when_two_frozen_blocks_fuse() -> void:
	var short_block: Block = _frozen_block(0, SHORT_S)
	var long_block: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(short_block, long_block)
	await wait_physics_frames(SETTLE_FRAMES)

	var timer: Timer = _timer(carrier)
	assert_not_null(timer)
	assert_almost_eq(timer.time_left, LONG_S, TIME_TOLERANCE_S, "the longer remaining time is kept")


func test_the_longer_remaining_hold_wins_in_the_other_adoption_order() -> void:
	var long_block: Block = _frozen_block(0, LONG_S)
	var short_block: Block = _frozen_block(1, SHORT_S)
	var carrier: FusedBody = _fuse(long_block, short_block)
	await wait_physics_frames(SETTLE_FRAMES)

	assert_almost_eq(_timer(carrier).time_left, LONG_S, TIME_TOLERANCE_S)


func test_the_carrier_releases_when_the_transferred_timer_expires() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)
	_frozen_events.clear()
	_timer(carrier).timeout.emit()

	assert_false(carrier.is_freeze_static(), "the group is released after the timer")
	assert_false(carrier.freeze)
	assert_false(a.is_frozen_visual(), "a member's frozen overlay is cleared")
	assert_false(b.is_frozen_visual(), "a member's frozen overlay is cleared")
	assert_eq(_frozen_events.get(a.net_id), false, "clients are told a thawed")
	assert_eq(_frozen_events.get(b.net_id), false, "clients are told b thawed")


func test_fusing_a_frozen_block_with_a_plain_one_holds_the_whole_group() -> void:
	var frozen: Block = _frozen_block(0, LONG_S)
	var plain: Block = _block(1)
	var carrier: FusedBody = _fuse(plain, frozen)
	await wait_physics_frames(SETTLE_FRAMES)

	assert_true(carrier.is_freeze_static(), "one held member holds the group")
	assert_not_null(_timer(carrier))
	_timer(carrier).timeout.emit()
	assert_false(carrier.is_freeze_static())


func test_a_frozen_block_joining_an_existing_plain_group_holds_it() -> void:
	var a: Block = _block(0)
	var b: Block = _block(1)
	var group: FusedBody = _fuse(a, b)
	var frozen: Block = _frozen_block(2, LONG_S)
	var carrier: FusedBody = _fuse(frozen, a)
	await wait_physics_frames(SETTLE_FRAMES)

	assert_eq(carrier, group, "the block joins the existing body")
	assert_true(carrier.is_freeze_static())
	assert_not_null(_timer(carrier))
	assert_null(_timer(frozen))


func test_merging_two_frozen_groups_leaves_one_held_carrier_with_the_longer_timer() -> void:
	var a: Block = _frozen_block(0, SHORT_S)
	var b: Block = _frozen_block(1, SHORT_S)
	var c: Block = _frozen_block(2, LONG_S)
	var d: Block = _frozen_block(3, LONG_S)
	var left: FusedBody = _fuse(a, b)
	var right: FusedBody = _fuse(c, d)
	var carrier: FusedBody = _fuse(b, c)
	await wait_physics_frames(SETTLE_FRAMES)

	var gone: FusedBody = right if carrier == left else left
	assert_false(is_instance_valid(gone), "the absorbed carrier is freed")
	assert_true(carrier.is_freeze_static())
	assert_almost_eq(_timer(carrier).time_left, LONG_S, TIME_TOLERANCE_S)
	_timer(carrier).timeout.emit()
	assert_false(carrier.is_freeze_static(), "one expiry releases the merged group")


func test_a_group_held_by_another_reason_stays_held_after_the_freeze_ends() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _block(1)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)
	carrier.request_freeze_static(Block.FREEZE_REASON_STABLE)

	_timer(carrier).timeout.emit()

	# The stable hold is the carrier's own; Freeze ending must not drop it.
	assert_true(carrier.is_freeze_static(), "a separate freeze reason keeps the group held")


# --- collapse back to a Block: the survivor inherits the hold ---------------

func test_the_survivor_of_a_collapsed_group_keeps_the_hold_and_its_remaining_time() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)

	carrier.remove_member(b, &"test")
	await wait_physics_frames(SETTLE_FRAMES)

	assert_false(is_instance_valid(carrier), "the one-member body collapses")
	assert_false(a.is_fused_member(), "the survivor is a plain Block again")
	assert_true(a.is_freeze_static(), "the survivor is still held")
	var timer: Timer = _timer(a)
	assert_not_null(timer, "the release timer moved to the survivor")
	assert_almost_eq(timer.time_left, LONG_S, TIME_TOLERANCE_S)


func test_the_collapsed_survivor_releases_when_the_timer_expires() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)
	carrier.remove_member(b, &"test")
	await wait_physics_frames(SETTLE_FRAMES)
	_frozen_events.clear()

	_timer(a).timeout.emit()

	assert_false(a.is_freeze_static(), "the survivor is released")
	assert_false(a.freeze)
	assert_false(a.is_frozen_visual())
	assert_eq(_frozen_events.get(a.net_id), false, "clients are told a thawed")


func test_a_collapsed_survivor_of_a_group_that_was_never_frozen_stays_free() -> void:
	var a: Block = _block(0)
	var b: Block = _block(1)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)

	carrier.remove_member(b, &"test")
	await wait_physics_frames(SETTLE_FRAMES)

	assert_false(a.is_freeze_static())
	assert_null(_timer(a), "no hold, so no timer is invented")


# --- hole dissolve of a frozen fused group ----------------------------------

func test_a_dissolve_of_a_frozen_group_releases_the_hold_and_starts_each_member() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)
	watch_signals(Events)
	_frozen_events.clear()

	_registry.hole_dissolver().start_dissolve(carrier)

	assert_true(_registry.hole_dissolver().is_dissolving(a), "every member dissolves")
	assert_true(_registry.hole_dissolver().is_dissolving(b))
	assert_false(carrier.is_freeze_static(), "the dissolve overrides the Freeze hold on the carrier")
	assert_null(_timer(carrier), "the release timer is gone")
	assert_false(a.is_frozen_visual())
	assert_false(b.is_frozen_visual())
	assert_eq(_frozen_events.get(a.net_id), false, "clients are told a thawed")
	assert_eq(_frozen_events.get(b.net_id), false, "clients are told b thawed")
	assert_signal_emit_count(Events, "block_dissolve_started", 2)


func test_a_dissolve_of_one_frozen_member_releases_the_hold_via_its_carrier() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)

	_registry.hole_dissolver().start_dissolve(a)

	assert_true(_registry.hole_dissolver().is_dissolving(a))
	assert_false(carrier.is_freeze_static(), "the carrier's hold is what held the group, and it ends")
	assert_false(a.is_frozen_visual())


func test_a_dissolved_frozen_group_still_completes_and_removes_every_member() -> void:
	var a: Block = _frozen_block(0, LONG_S)
	var b: Block = _frozen_block(1, LONG_S)
	var carrier: FusedBody = _fuse(a, b)
	await wait_physics_frames(SETTLE_FRAMES)
	var a_id: int = a.get_instance_id()
	var b_id: int = b.get_instance_id()

	_registry.hole_dissolver().start_dissolve(carrier)
	var frames: int = 0
	while frames < DISSOLVE_FRAMES and not (_removed_ids.has(a_id) and _removed_ids.has(b_id)):
		await wait_physics_frames(1)
		frames += 1

	assert_true(_removed_ids.has(a_id), "the dissolve completes for member a")
	assert_true(_removed_ids.has(b_id), "the dissolve completes for member b")
