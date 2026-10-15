extends GutTest
## Glue fusion: the FusedBody carrier itself.
## Real Jolt physics on a tiny disc; the carrier is built through GlueFusion.fuse().

const CUBE_SIDE_M: float = 1.2
const SETTLE_FRAMES: int = 20
const MOVE_FRAMES: int = 25
const POSE_TOLERANCE: float = 0.0001
const COM_TOLERANCE: float = 0.01
const IMPACT_SPEED_MPS: float = 8.0
const OBSERVE_FRAMES: int = 60
const TILT_CYCLE_S: float = 2.0
const TILT_KICK: float = 0.35
const ANCHOR_DRIFT_M: float = 0.02
const FALL_MIN_M: float = 0.5

var _field: Field
var _root: Node3D
var _tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")
var _next_net_id: int = 100


func before_each() -> void:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_root = autofree(Node3D.new())
	add_child_autofree(_root)


func _block(shape_id: String, slot: int, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, slot)
	block.net_id = _next_net_id
	_next_net_id += 1
	_root.add_child(block)
	block.global_position = at
	return block


func _shape_count(body: Node) -> int:
	var count: int = 0
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			count += 1
	return count


func _shapes_of(block: Block) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			shapes.append(child as CollisionShape3D)
	return shapes


func _basis_error(a: Basis, b: Basis) -> float:
	var worst: float = 0.0
	for axis: Vector3 in [a.x - b.x, a.y - b.y, a.z - b.z]:
		worst = maxf(worst, maxf(absf(axis.x), maxf(absf(axis.y), absf(axis.z))))
	return worst


func _frames(count: int) -> void:
	for _i: int in range(count):
		await get_tree().physics_frame


func _air_pair() -> Array[Block]:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("L4", 1, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	return [a, b]


func _fuse(charged: Block, target: PhysicsBody3D) -> FusedBody:
	return GlueFusion.fuse(charged, target, _tuning)


func test_two_blocks_become_one_dynamic_body_keeping_identity_mass_and_shapes() -> void:
	var pair: Array[Block] = _air_pair()
	var a: Block = pair[0]
	var b: Block = pair[1]
	var mass_total: float = a.mass + b.mass
	var shapes_total: int = _shape_count(a) + _shape_count(b)
	var a_id: int = a.net_id
	var carrier: FusedBody = _fuse(a, b)
	assert_not_null(carrier, "fuse returns the carrier")
	assert_eq(carrier.members.size(), 2)
	assert_false(carrier.freeze, "free group is a dynamic body")
	assert_almost_eq(carrier.mass, mass_total, 0.0001, "mass is the sum of the members")
	assert_eq(_shape_count(carrier), shapes_total, "every shape moved to the carrier")
	assert_eq(_shape_count(a) + _shape_count(b), 0, "followers keep no shapes")
	assert_eq(a.net_id, a_id, "member keeps net_id")
	assert_eq(a.owner_slot, 0)
	assert_eq(b.owner_slot, 1)
	assert_eq(carrier.owner_slot, -1, "mixed-owner group has no single owner")
	assert_eq(carrier.net_id, -1, "carrier is never an identity block")
	assert_not_null(a.get_node_or_null(^"BlockMesh"), "follower keeps its mesh")
	assert_true(a.is_fused_member())
	assert_eq(a.fused_carrier(), carrier)
	assert_gt(a.mass, 0.0, "follower mass retained")
	assert_eq(a.collision_layer, 0)
	assert_true(a.freeze and a.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC)


func test_centre_of_mass_is_mass_weighted() -> void:
	var pair: Array[Block] = _air_pair()
	var world_sum: Vector3 = Vector3.ZERO
	var mass_total: float = 0.0
	for block: Block in pair:
		var com_local: Vector3 = FusedBody.shapes_center_of_mass(_shapes_of(block))
		world_sum += (block.global_transform * com_local) * block.mass
		mass_total += block.mass
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	var expected: Vector3 = world_sum / mass_total
	var mine: Vector3 = carrier.global_transform * carrier.local_center_of_mass()
	assert_lt(mine.distance_to(expected), COM_TOLERANCE, "carrier COM helper is mass-weighted")
	await _frames(2)
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(carrier.get_rid())
	var engine_com: Vector3 = carrier.global_transform * state.center_of_mass_local
	mine = carrier.global_transform * carrier.local_center_of_mass()
	assert_lt(engine_com.distance_to(mine), COM_TOLERANCE, "the engine's centre of mass matches")
	for member: Block in carrier.members:
		assert_eq(member.center_of_mass_mode, RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)


func test_pushing_the_carrier_keeps_followers_at_rigid_offsets() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	await _frames(3)
	carrier.linear_velocity = Vector3(3.0, 2.0, 0.0)
	carrier.angular_velocity = Vector3(0.0, 1.5, 2.0)
	for _i: int in range(MOVE_FRAMES):
		await get_tree().physics_frame
		for member: Block in carrier.members:
			var expected: Transform3D = carrier.global_transform * carrier.member_offset(member)
			assert_lt(member.global_position.distance_to(expected.origin), POSE_TOLERANCE, "follower origin rigid")
			var basis_error: float = _basis_error(member.global_transform.basis, expected.basis)
			assert_lt(basis_error, POSE_TOLERANCE, "follower basis rigid")
	assert_gt(carrier.linear_velocity.length(), 0.0)
	assert_lt(pair[0].linear_velocity.distance_to(carrier.linear_velocity), POSE_TOLERANCE, "follower mirrors carrier velocity")


func test_removing_a_middle_member_drops_mass_and_keeps_the_others() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var c: Block = _block("cube", 0, at + Vector3(2.0 * CUBE_SIDE_M, 0.0, 0.0))
	var carrier: FusedBody = _fuse(a, b)
	_fuse(c, b)
	assert_eq(carrier.members.size(), 3)
	var mass_before: float = carrier.mass
	var b_mass: float = b.mass
	var removed: Array = []
	var on_removed: Callable = func(block: RigidBody3D, _reason: String) -> void: removed.append(block)
	Events.block_removed.connect(on_removed)
	carrier.remove_member(b, &"hole")
	Events.block_removed.disconnect(on_removed)
	assert_eq(removed, [b], "block_removed for the removed member only")
	assert_almost_eq(carrier.mass, mass_before - b_mass, 0.0001)
	assert_eq(carrier.members.size(), 2)
	assert_eq(_shape_count(carrier), 2, "the removed member's shape left")
	assert_true(a.is_fused_member() and c.is_fused_member(), "others stay fused")
	assert_eq(a.fused_carrier(), c.fused_carrier())
	await _frames(2)
	assert_false(is_instance_valid(b), "removed member is freed")


func test_collapse_to_one_member_restores_a_normal_dynamic_block() -> void:
	var pair: Array[Block] = _air_pair()
	var a: Block = pair[0]
	var b: Block = pair[1]
	var b_shapes: int = _shape_count(b)
	var b_layer: int = b.collision_layer
	var released: Array = []
	var on_released: Callable = func(member: Node) -> void: released.append(member)
	Events.fused_member_released.connect(on_released)
	var carrier: FusedBody = _fuse(a, b)
	await _frames(3)
	carrier.remove_member(a, &"hole")
	Events.fused_member_released.disconnect(on_released)
	assert_eq(released, [b])
	assert_false(b.is_fused_member())
	assert_false(b.freeze, "survivor is dynamic again")
	assert_eq(b.center_of_mass_mode, RigidBody3D.CENTER_OF_MASS_MODE_AUTO)
	assert_eq(_shape_count(b), b_shapes, "survivor got its shapes back")
	assert_eq(b.collision_layer, b_layer)
	await _frames(2)
	assert_false(is_instance_valid(carrier), "carrier freed after the collapse")
	var y_before: float = b.global_position.y
	await _frames(10)
	assert_lt(b.global_position.y, y_before, "survivor falls under normal physics")


func test_impact_and_blast_do_not_split_a_fused_body() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	var released: Array = []
	var on_released: Callable = func(member: Node) -> void: released.append(member)
	Events.fused_member_released.connect(on_released)
	await _frames(SETTLE_FRAMES)
	var hit: Block = _block("cube", 2, carrier.global_position + Vector3(0.0, 4.0, 0.0))
	hit.linear_velocity = Vector3(0.0, -IMPACT_SPEED_MPS, 0.0)
	await _frames(OBSERVE_FRAMES)
	var space: PhysicsDirectSpaceState3D = carrier.get_world_3d().direct_space_state
	ExplosionFx.blast(space, carrier.global_position + Vector3(-2.0, 0.0, 0.0), ExplosionTuning.new(), [])
	await _frames(OBSERVE_FRAMES)
	Events.fused_member_released.disconnect(on_released)
	assert_true(released.is_empty(), "nothing was released")
	assert_eq(carrier.members.size(), 2, "still one body of two members")
	assert_true(pair[0].is_fused_member() and pair[1].is_fused_member())


func _anchored_stack(count: int) -> Dictionary:
	var rest_y: float = _field.surface_y() + CUBE_SIDE_M * 0.5
	var blocks: Array[Block] = []
	for i: int in range(count):
		blocks.append(_block("cube", 0, _field.to_global(Vector3(0.0, rest_y + float(i) * CUBE_SIDE_M, 0.0))))
	var carrier: FusedBody = _fuse(blocks[0], blocks[1])
	for i: int in range(2, count):
		_fuse(blocks[i], blocks[i - 1])
	_fuse(blocks[0], _field)
	return {"carrier": carrier, "blocks": blocks}


func test_disc_anchored_carrier_follows_a_tilting_field_and_stays() -> void:
	var setup: Dictionary = _anchored_stack(2)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	assert_true(carrier.is_disc_anchored())
	assert_true(carrier.freeze and carrier.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC, "kinematic, not STATIC")
	var local_start: Array[Vector3] = [_field.to_local(blocks[0].global_position), _field.to_local(blocks[1].global_position)]
	_field.set_tilt_enabled(true)
	var max_tilt: float = 0.0
	var frames: int = int(TILT_CYCLE_S * 60.0)
	for i: int in range(frames):
		if i == 0:
			_field.apply_tilt_impulse(Vector2(1.0, 0.0), TILT_KICK)
		await get_tree().physics_frame
		max_tilt = maxf(max_tilt, _field.tilt_vector().length())
	assert_gt(max_tilt, 0.0, "the disc really tilted")
	for i: int in range(blocks.size()):
		assert_lt(_field.to_local(blocks[i].global_position).distance_to(local_start[i]), ANCHOR_DRIFT_M, "member stays fixed to the disc")
	assert_true(carrier.is_disc_anchored())


func test_removing_the_anchor_member_makes_the_group_fall() -> void:
	var setup: Dictionary = _anchored_stack(3)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	await _frames(3)
	var upper_y: float = blocks[1].global_position.y
	carrier.remove_member(blocks[0], &"hole")
	assert_false(carrier.is_disc_anchored())
	assert_false(carrier.freeze, "group is dynamic once its anchor is gone")
	assert_eq(carrier.members.size(), 2)
	await _frames(40)
	assert_lt(blocks[1].global_position.y, upper_y - FALL_MIN_M, "the remainder fell")
	assert_true(blocks[1].is_fused_member(), "and stayed rigid")


func test_follower_forwards_freeze_wake_and_kick_to_the_carrier() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	pair[0].request_freeze_static(&"freeze")
	assert_true(carrier.is_freeze_static())
	assert_true(pair[1].is_freeze_static())
	pair[1].release_freeze_static(&"freeze")
	assert_false(carrier.is_freeze_static())
	pair[0].wake_for_impulse()
	pair[1].kick(Vector3(0.0, 0.0, 4.0))
	assert_eq(carrier.linear_velocity, Vector3(0.0, 0.0, 4.0))
	assert_true(carrier._script_kick_pending)
	assert_false(pair[0]._script_kick_pending)


const HEAVY_MASS_FACTOR: float = 6.0
const SPIN_EPSILON: float = 0.05


func _world_com(members: Array[Block]) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var total: float = 0.0
	for member: Block in members:
		sum += (member.global_transform * member.center_of_mass) * member.mass
		total += member.mass
	return sum / total


func test_centre_of_mass_uses_member_mass_not_shape_volume() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var c: Block = _block("cube", 0, at + Vector3(2.0 * CUBE_SIDE_M, 0.0, 0.0))
	a.mass *= HEAVY_MASS_FACTOR
	var carrier: FusedBody = _fuse(a, b)
	_fuse(c, b)
	var start_y: float = carrier.global_position.y
	await _frames(10)
	var state: PhysicsDirectBodyState3D = PhysicsServer3D.body_get_direct_state(carrier.get_rid())
	assert_eq(carrier.center_of_mass_mode, RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM)
	var members: Array[Block] = [a, b, c]
	var engine_com: Vector3 = carrier.global_transform * state.center_of_mass_local
	assert_lt(engine_com.distance_to(_world_com(members)), COM_TOLERANCE, "physics COM follows member mass")
	assert_lt(carrier.angular_velocity.length(), SPIN_EPSILON, "free fall does not spin the carrier")
	assert_lt(carrier.global_position.y, start_y, "carrier falls")
	var before: Vector3 = carrier.center_of_mass
	carrier.remove_member(c, &"hole")
	members = [a, b]
	var after_com: Vector3 = carrier.global_transform * carrier.center_of_mass
	assert_ne(carrier.center_of_mass, before, "COM updates when a member leaves")
	assert_lt(after_com.distance_to(_world_com(members)), COM_TOLERANCE, "updated COM is mass-weighted")


func test_externally_freed_member_is_removed_from_the_group() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var c: Block = _block("cube", 0, at + Vector3(2.0 * CUBE_SIDE_M, 0.0, 0.0))
	var carrier: FusedBody = _fuse(a, b)
	_fuse(c, b)
	var mass_before: float = carrier.mass
	var b_mass: float = b.mass
	b.queue_free()
	await _frames(3)
	assert_eq(carrier.members.size(), 2)
	assert_eq(_shape_count(carrier), 2, "orphan shape dropped")
	assert_almost_eq(carrier.mass, mass_before - b_mass, 0.0001)
	a.queue_free()
	await _frames(3)
	assert_true(c.is_inside_tree() and not c.is_fused_member(), "collapse rules still apply")
	assert_eq(_shape_count(c), 1)


func test_carrier_is_in_the_tuning_group() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	assert_true(carrier.is_in_group(Block.TUNING_GROUP))


# --- Composition review fixes ---

const FREEZE_TEST_S: float = 0.25
const FREEZE_WAIT_FRAMES: int = 40


func _freeze_effect() -> FreezeEffect:
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_duration_s = FREEZE_TEST_S
	return effect


func test_frozen_group_keeps_its_freeze_timer_when_merged_into_another() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var c: Block = _block("cube", 0, at + Vector3(0.0, 0.0, 4.0))
	var d: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 4.0))
	var first: FusedBody = _fuse(a, b)
	var second: FusedBody = _fuse(c, d)
	_freeze_effect().freeze_block(second)
	assert_true(second.is_freeze_static())
	var merged: FusedBody = _fuse(a, c)
	assert_eq(merged, first)
	assert_eq(merged.members.size(), 4)
	assert_true(merged.is_freeze_static(), "the Freeze hold follows the merged members")
	await _frames(FREEZE_WAIT_FRAMES)
	assert_false(merged.is_freeze_static(), "and releases on time instead of staying STATIC forever")


func test_adopting_a_frozen_block_moves_the_hold_to_the_carrier() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var frozen: Block = _block("cube", 0, at)
	var charged: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	_freeze_effect().freeze_block(frozen)
	var carrier: FusedBody = _fuse(charged, frozen)
	assert_true(carrier.is_freeze_static())
	assert_null(frozen.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)), "the timer moved off the follower")
	assert_not_null(carrier.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)))
	await _frames(FREEZE_WAIT_FRAMES)
	assert_false(carrier.is_freeze_static(), "the group releases when the Freeze ends")


func test_collapse_keeps_the_freeze_hold_on_the_survivor() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var carrier: FusedBody = _fuse(a, b)
	_freeze_effect().freeze_block(carrier)
	carrier.remove_member(a, &"hole")
	assert_true(b.is_freeze_static())
	await _frames(FREEZE_WAIT_FRAMES)
	assert_false(b.is_freeze_static(), "the survivor is not STATIC forever")


func test_snow_lump_colliders_stay_on_their_block() -> void:
	var at: Vector3 = _field.to_global(Vector3(0.0, 6.0, 0.0))
	var a: Block = _block("cube", 0, at)
	var b: Block = _block("cube", 0, at + Vector3(CUBE_SIDE_M, 0.0, 0.0))
	var lump: CollisionShape3D = CollisionShape3D.new()
	lump.shape = BoxShape3D.new()
	lump.set_meta(SnowCaps.LUMP_META, true)
	a.add_child(lump)
	var carrier: FusedBody = _fuse(a, b)
	assert_eq(FusedBody.SNOW_LUMP_META, SnowCaps.LUMP_META)
	assert_eq(lump.get_parent(), a, "lump colliders are not adopted by the carrier")
	assert_eq(SnowCaps.lump_colliders(a).size(), 1, "SnowCaps can still melt it")
	assert_eq(_shape_count(carrier), 2)


func test_wake_on_a_disc_anchored_carrier_stays_out_of_the_awake_set() -> void:
	var setup: Dictionary = _anchored_stack(2)
	var carrier: FusedBody = setup["carrier"]
	carrier.wake()
	assert_false(Block.is_awake_registered(carrier), "a kinematic anchored carrier is never in the awake set")


func test_kill_plane_style_removal_keeps_shapes_until_the_body_is_freed() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	var shapes_before: int = _shape_count(carrier)
	carrier.remove_all_members(&"killed")
	assert_eq(_shape_count(carrier), shapes_before, "shapes are not removed inside the (area) callback")
	await _frames(3)
	assert_false(is_instance_valid(carrier))


# --- Carry fixes ---

func test_resting_anchored_group_reports_sleeping_and_a_tilt_wakes_it() -> void:
	var setup: Dictionary = _anchored_stack(2)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	assert_false(carrier.net_sleeping(), "just anchored: not yet at rest")
	await _frames(_tuning.anchor_rest_ticks + 3)
	assert_true(carrier.net_sleeping(), "a resting anchored group stops costing snapshot bandwidth")
	assert_true(blocks[1].net_sleeping(), "followers report the carrier's rest state")
	assert_true(blocks[1].is_contributing_visual(), "host glow follows the carrier, not the follower's own signal")
	_field.set_tilt_enabled(true)
	_field.apply_tilt_impulse(Vector2(1.0, 0.0), TILT_KICK)
	await _frames(3)
	assert_false(carrier.net_sleeping(), "disc tilt wakes the anchored group so clients follow")
	assert_false(blocks[1].is_contributing_visual())


func test_refresh_anchor_pose_poses_followers_from_the_disc_of_the_same_tick() -> void:
	var setup: Dictionary = _anchored_stack(2)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	await _frames(2)
	var local: Vector3 = _field.to_local(blocks[1].global_position)
	_field.set_tilt_enabled(true)
	_field.apply_tilt_impulse(Vector2(1.0, 0.0), TILT_KICK)
	await _frames(5)
	# Move the disc by hand: before the carrier's own (later) tick, refresh must catch up.
	_field.global_transform = _field.global_transform.rotated_local(Vector3.RIGHT, 0.05)
	carrier.refresh_anchor_pose()
	assert_lt(_field.to_local(blocks[1].global_position).distance_to(local), ANCHOR_DRIFT_M, "no one-tick lag behind the disc")


func test_release_hold_on_a_member_clears_the_carrier_timer_and_rider() -> void:
	var pair: Array[Block] = _air_pair()
	var carrier: FusedBody = _fuse(pair[0], pair[1])
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_block(carrier, _field)
	assert_not_null(carrier.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)))
	FreezeEffect.release_hold(pair[1])
	assert_null(carrier.get_node_or_null(NodePath(FreezeEffect.TIMER_NAME)), "no stale timer for the rest of the duration")
	assert_null(carrier.get_node_or_null(NodePath(FreezeEffect.RIDER_NAME)))
	assert_false(carrier.is_freeze_static())
	assert_false(pair[0].is_frozen_visual())


func test_leaving_the_anchor_keeps_a_riding_freeze_hold_kinematic() -> void:
	var setup: Dictionary = _anchored_stack(3)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	var effect: FreezeEffect = FreezeEffect.new()
	effect.freeze_block(carrier, _field)
	carrier.remove_member(blocks[0], &"hole")
	assert_false(carrier.is_disc_anchored())
	assert_true(carrier.freeze and carrier.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC, "a Freeze hold rides the disc kinematic")


func test_shape_edits_stamp_the_frame_so_contact_attribution_can_skip_it() -> void:
	var setup: Dictionary = _anchored_stack(3)
	var carrier: FusedBody = setup["carrier"]
	var blocks: Array[Block] = setup["blocks"]
	await _frames(2)
	assert_ne(carrier.shape_change_frame, Engine.get_physics_frames())
	carrier.remove_member(blocks[2], &"hole")
	assert_eq(carrier.shape_change_frame, Engine.get_physics_frames())
