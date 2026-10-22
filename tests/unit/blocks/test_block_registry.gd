extends GutTest
## game/blocks/BlockRegistry.gd: tracks live blocks, the settled rule (spec 1.5), and
## net_id <-> Block.

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")

## DECISION: a duplicate of round_medium.tres shrunk to a 20 m
## disk (~1250 cells, vs. round_medium's own ~6300), not the shared resource
## itself -- Field.new() defaults its own map_def export to that exact shared,
## cached round_medium.tres, and every test below built one, so the fixture
## alone cost ~11 s per test (measured; nothing here asserts on absolute map
## scale). _make_field() below points every Field it builds at this same
## instance, and it stands in for the real map_def in every direct call below
## too (registry.configure(), influence_circles(), CellGrid.new()), so the
## registry, the grid and the physical field all agree with each other.
var _map_def: MapDef


func before_each() -> void:
	_map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map_def.field_radius = 20.0


func _make_field() -> Field:
	var field: Field = autofree(Field.new())
	field.map_def = _map_def
	add_child_autofree(field)
	return field


func _make_registry(field: Field) -> BlockRegistry:
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	registry.configure(field, _map_def)
	return registry


func _slots(count: int) -> Array[PlayerSlot]:
	var slots: Array[PlayerSlot] = []
	for i: int in range(count):
		slots.append(PlayerSlot.new(i, i, "P%d" % i, Color.WHITE, Vector2.ZERO))
	return slots


func test_block_placed_assigns_increasing_net_ids() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block_a: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block_a)
	Events.block_placed.emit(block_a, shape.id)

	var block_b: Block = BlockFactory.build(shape, _tuning, 1)
	field.add_child(block_b)
	Events.block_placed.emit(block_b, shape.id)

	assert_gt(block_a.net_id, 0)
	assert_gt(block_b.net_id, block_a.net_id)
	assert_eq(registry.block_for_net_id(block_a.net_id), block_a)
	assert_eq(registry.tracked_block_count(), 2)


func test_block_removed_untracks_and_frees_its_net_id() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	var net_id: int = block.net_id

	Events.block_removed.emit(block, "kill_plane")

	assert_eq(registry.tracked_block_count(), 0)
	assert_null(registry.block_for_net_id(net_id))


func _place(field: Field, shape: BlockShape, slot: int) -> Block:
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	return block


func test_owner_conversion_updates_territory_and_only_target_material() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var target: Block = _place(field, shape, 1)
	var other: Block = _place(field, shape, 1)
	var target_mesh: MeshInstance3D = target.get_node("BlockMesh")
	var other_mesh: MeshInstance3D = other.get_node("BlockMesh")
	var old_material: Material = target_mesh.material_override
	var other_material: Material = other_mesh.material_override
	var paint_color: Color = Color.RED
	# One production tick whose delta alone spans the settle time.
	registry._physics_process(_tuning.sleep_settle_time + 1.0)
	assert_true(registry.convert_owner(target, 0, paint_color))
	assert_eq(target.owner_slot, 0)
	var by_body: Dictionary = {}
	for circle: InfluenceCircle in registry.influence_circles(_slots(2), _territory_tuning, _map_def):
		by_body[circle.body_id] = circle
	assert_eq((by_body[target.get_instance_id()] as InfluenceCircle).slot_id, 0, "territory follows the new owner")
	assert_eq((by_body[other.get_instance_id()] as InfluenceCircle).slot_id, 1, "the other block keeps its owner")
	assert_ne(target_mesh.material_override, old_material)
	assert_eq((target_mesh.material_override as ShaderMaterial).get_shader_parameter(&"albedo_color"), paint_color)
	assert_eq(((target_mesh.material_override as ShaderMaterial).next_pass as ShaderMaterial).get_shader_parameter(&"tint_color"), paint_color)
	assert_eq(other_mesh.material_override, other_material)
	assert_false(registry.convert_owner(target, 0, paint_color), "repeat conversion does nothing")
	var untracked: Block = autofree(Block.new())
	assert_false(registry.convert_owner(untracked, 0, paint_color), "untracked bodies are refused")


func test_client_owner_mirror_uses_net_id_and_refuses_unknown_or_duplicate() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	registry.set_host_authority(false)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = _place(field, shape, 1)
	registry.bind_net_id(block, 81)
	assert_false(registry.apply_replicated_owner(82, 0, Color.RED))
	assert_true(registry.apply_replicated_owner(81, 0, Color.RED))
	assert_eq(block.owner_slot, 0)
	assert_false(registry.apply_replicated_owner(81, 0, Color.RED))
	assert_false(registry.convert_owner(block, 1, Color.BLUE), "client cannot author conversion")


func test_allocation_refuses_past_the_wire_ceiling_instead_of_aliasing() -> void:
	# Unreachable in play (Quantize's DECISION: 72 days at the fastest feed),
	# but the behaviour at the ceiling must be "no id" — never a wrapped or
	# truncated one that a snapshot would deliver to some other body.
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	# Boundary (reported): the allocator cannot be started near the ceiling through the public API (16.7M placements otherwise), so the counter is seeded directly.
	registry._next_net_id = Quantize.NET_ID_MAX

	var last: Block = _place(field, shape, 0)
	var over: Block = _place(field, shape, 1)
	assert_push_error("net_id space exhausted")

	assert_eq(last.net_id, Quantize.NET_ID_MAX, "the last representable id is handed out")
	assert_eq(over.net_id, -1, "past it no id is handed out at all")
	assert_eq(registry.block_for_net_id(Quantize.NET_ID_MAX), last, "the last id still names its own body")
	assert_null(registry.block_for_net_id(0), "nothing answers to 'no body'")
	assert_null(registry.block_for_net_id(1), "and nothing answers to a wrapped id")
	assert_eq(registry.tracked_block_count(), 2, "the host still tracks the body for territory")

	# A second refusal is reported too; the counter stays put and nothing
	# from the earlier body is disturbed.
	var another: Block = _place(field, shape, 0)
	assert_push_error("net_id space exhausted")
	assert_eq(another.net_id, -1)
	assert_eq(registry.block_for_net_id(Quantize.NET_ID_MAX), last)


func test_unsettled_block_contributes_no_influence_circle() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	block.global_position = Vector3(2.0, 5.0, 0.0)
	block.linear_velocity = Vector3(10.0, 0.0, 0.0)  # far above sleep_linear_threshold
	Events.block_placed.emit(block, shape.id)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var circles: Array[InfluenceCircle] = registry.influence_circles(_slots(1), _territory_tuning, _map_def)
	assert_eq(circles.size(), 0, "A moving block should not produce influence yet.")


func test_settled_block_produces_a_circle_after_settle_time() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	block.freeze = true  # keep it perfectly still so the settle timer accumulates cleanly
	block.global_position = Vector3(3.0, 0.5, -1.0)
	Events.block_placed.emit(block, shape.id)

	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame

	var circles: Array[InfluenceCircle] = registry.influence_circles(_slots(1), _territory_tuning, _map_def)
	assert_eq(circles.size(), 1, "A block settled for sleep_settle_time should produce one circle.")
	assert_almost_eq(circles[0].center.x, 3.0, 0.05)
	assert_almost_eq(circles[0].center.y, -1.0, 0.05)
	assert_eq(circles[0].team_id, 0)
	assert_eq(circles[0].slot_id, 0)
	assert_false(circles[0].is_home)


func test_all_settled_is_false_while_one_tracked_block_still_moves() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var settled_block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(settled_block)
	settled_block.freeze = true
	settled_block.global_position = Vector3(2.0, 0.5, 0.0)
	Events.block_placed.emit(settled_block, shape.id)

	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame
	assert_true(registry.all_settled(), "sanity check: the lone settled block reads as settled")

	var moving_block: Block = BlockFactory.build(shape, _tuning, 1)
	field.add_child(moving_block)
	moving_block.global_position = Vector3(-2.0, 5.0, 0.0)
	moving_block.linear_velocity = Vector3(10.0, 0.0, 0.0)  # far above sleep_linear_threshold
	Events.block_placed.emit(moving_block, shape.id)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_false(registry.all_settled(), "one still-moving block keeps the whole registry unsettled")


# --- physics-driven territory_revision bumps ---------------


func test_physics_settle_flip_bumps_territory_revision() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	block.freeze = true
	block.global_position = Vector3(3.0, 0.5, -1.0)
	Events.block_placed.emit(block, shape.id)
	var placed_revision: int = registry.territory_revision()
	await get_tree().physics_frame
	assert_eq(registry.territory_revision(), placed_revision, "No flip yet: still inside the settle window.")
	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame
	assert_eq(registry.territory_revision(), placed_revision + 1, "Unsettled -> settled bumps exactly once.")
	for _i: int in range(5):
		await get_tree().physics_frame
	assert_eq(registry.territory_revision(), placed_revision + 1, "A still settled block stays clean.")


## A frozen block settled at the placed pose, with the registry's settled flag
## already set.
func _settled_frozen_block(field: Field, registry: BlockRegistry, shape: BlockShape) -> Block:
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	block.freeze = true
	block.global_position = Vector3(3.0, 0.5, -1.0)
	Events.block_placed.emit(block, shape.id)
	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame
	assert_true(registry.all_settled(), "fixture: block settled")
	return block


## SPEC 2.x: a settled block that moved less than TerritoryTuning.dirty_move_epsilon
## does not dirty the board; a larger move dirties it once, and the mark then
## follows the block so it is not counted again.
func test_physics_settled_move_beyond_epsilon_bumps_but_jitter_does_not() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = await _settled_frozen_block(field, registry, shape)
	var eps: float = _territory_tuning.dirty_move_epsilon
	registry.set_move_epsilon(eps)
	var before: int = registry.territory_revision()
	block.global_position += Vector3(eps * 0.25, 0.0, 0.0)
	await get_tree().physics_frame
	assert_eq(registry.territory_revision(), before, "Sub-epsilon jitter does not bump.")
	block.global_position += Vector3(eps * 4.0, 0.0, 0.0)
	await get_tree().physics_frame
	assert_eq(registry.territory_revision(), before + 1, "A move beyond epsilon bumps once.")
	await get_tree().physics_frame
	assert_eq(registry.territory_revision(), before + 1, "The mark follows the block: no repeat bump.")


func test_paintball_owner_conversion_bumps_revision_host_and_client() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = _place(field, shape, 1)
	var before: int = registry.territory_revision()
	assert_true(registry.convert_owner(block, 0, Color.RED))
	assert_eq(registry.territory_revision(), before + 1, "Host conversion bumps.")
	assert_false(registry.convert_owner(block, 0, Color.RED))
	assert_eq(registry.territory_revision(), before + 1, "A no-op conversion does not bump.")

	var client_registry: BlockRegistry = _make_registry(field)
	client_registry.set_host_authority(false)
	var mirrored: Block = _place(field, shape, 1)
	client_registry.bind_net_id(mirrored, 81)
	var client_before: int = client_registry.territory_revision()
	assert_true(client_registry.apply_replicated_owner(81, 0, Color.RED))
	assert_eq(client_registry.territory_revision(), client_before + 1, "Client mirror conversion bumps.")


func test_tallest_settled_for_slot_returns_the_owners_highest_settled_block() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	assert_true(registry.tallest_settled_for_slot(0).is_empty(), "nothing tracked -> {}")
	var specs: Array = [[0, Vector3(2.0, 0.5, 0.0)], [0, Vector3(-3.0, 2.5, 1.0)], [1, Vector3(0.0, 6.5, 0.0)]]
	for spec: Array in specs:
		var block: Block = BlockFactory.build(shape, _tuning, int(spec[0]))
		field.add_child(block)
		block.freeze = true
		block.global_position = spec[1] as Vector3
		Events.block_placed.emit(block, shape.id)
	var ticks: int = int(ceil(_tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(ticks):
		await get_tree().physics_frame
	var tallest: Dictionary = registry.tallest_settled_for_slot(0)
	assert_false(tallest.is_empty())
	assert_almost_eq((tallest["xz"] as Vector2).x, -3.0, 0.05)
	assert_almost_eq((tallest["xz"] as Vector2).y, 1.0, 0.05)
	assert_gt(float(tallest["height"]), 2.5, "top of slot 0's high cube")
	assert_lt(float(tallest["height"]), 6.0, "not the other slot's cube")
	assert_true(registry.tallest_settled_for_slot(5).is_empty(), "no blocks for that slot")


# --- remove_block: the one edge-fall removal (spec 1.7) ---------------------

const REST_HEIGHT_M: float = 0.62
const CUBE_SIDE_M: float = 1.2

var _removed_ids: Array[int] = []
var _removed_reasons: Array[String] = []


func _record_removals() -> void:
	_removed_ids = []
	_removed_reasons = []
	Events.block_removed.connect(_on_removed_recorded)


func _on_removed_recorded(body: RigidBody3D, reason: String) -> void:
	_removed_ids.append(body.get_instance_id())
	_removed_reasons.append(reason)


func after_each() -> void:
	if Events.block_removed.is_connected(_on_removed_recorded):
		Events.block_removed.disconnect(_on_removed_recorded)


## A cube resting on the disc at disk-local `x`.
func _cube_at(field: Field, shape: BlockShape, slot: int, x: float) -> Block:
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	add_child_autofree(block)
	block.global_position = field.to_global(Vector3(x, REST_HEIGHT_M, 0.0))
	Events.block_placed.emit(block, shape.id)
	return block


func _fused_trio(field: Field, shape: BlockShape) -> Array:
	var glue: GlueDropTuning = load("res://config/gifts/glue_drop_tuning.tres")
	var a: Block = _cube_at(field, shape, 0, -CUBE_SIDE_M)
	var b: Block = _cube_at(field, shape, 1, 0.0)
	var c: Block = _cube_at(field, shape, 0, CUBE_SIDE_M)
	var carrier: FusedBody = GlueFusion.fuse(a, b, glue)
	assert_not_null(carrier, "fixture: first pair fused")
	assert_eq(GlueFusion.fuse(c, a, glue), carrier, "fixture: third cube joins the same group")
	assert_eq(carrier.members.size(), 3, "fixture: three members")
	return [carrier, a, b, c]


func test_remove_block_removes_a_plain_block_with_one_event() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = _cube_at(field, shape, 0, 0.0)
	var net_id: int = block.net_id
	_record_removals()

	registry.remove_block(block)

	assert_eq(_removed_ids, [block.get_instance_id()], "exactly one block_removed")
	assert_eq(_removed_reasons, [String(Events.REASON_KILL_PLANE)])
	assert_true(block.is_queued_for_deletion(), "the body is freed")
	assert_eq(registry.tracked_block_count(), 0, "the registry forgot it")
	assert_null(registry.block_for_net_id(net_id))


func test_remove_block_on_a_fused_carrier_removes_every_member_once_in_member_order() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var trio: Array = _fused_trio(field, shape)
	var carrier: FusedBody = trio[0]
	var expected: Array[int] = []
	for member: Block in carrier.members:
		expected.append(member.get_instance_id())
	var carrier_id: int = carrier.get_instance_id()
	_record_removals()

	registry.remove_block(carrier, Events.REASON_KILL_PLANE)

	assert_eq(_removed_ids, expected, "one block_removed per member, in member order")
	assert_false(_removed_ids.has(carrier_id), "never emitted for the carrier itself")
	assert_eq(_removed_reasons, ["kill_plane", "kill_plane", "kill_plane"])
	assert_eq(registry.tracked_block_count(), 0)
	await wait_physics_frames(2)
	assert_false(is_instance_valid(carrier), "the carrier ends with its members")


func test_remove_block_on_a_lone_follower_leaves_the_group_and_keeps_the_rest() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var trio: Array = _fused_trio(field, shape)
	var carrier: FusedBody = trio[0]
	var follower: Block = trio[1]
	var others: Array[Block] = [trio[2], trio[3]]
	_record_removals()

	registry.remove_block(follower)

	assert_eq(_removed_ids, [follower.get_instance_id()], "exactly one block_removed, for the follower")
	assert_true(follower.is_queued_for_deletion())
	assert_eq(registry.tracked_block_count(), 2)
	assert_true(is_instance_valid(carrier), "the group survives")
	assert_eq(carrier.members.size(), 2)
	for other: Block in others:
		assert_true(registry.is_tracked(other))
		assert_true(other.is_fused_member(), "the rest stay fused")


func test_remove_block_is_a_no_op_without_host_authority() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var plain: Block = _cube_at(field, shape, 0, 4.0)
	var trio: Array = _fused_trio(field, shape)
	var carrier: FusedBody = trio[0]
	registry.set_host_authority(false)
	_record_removals()

	registry.remove_block(plain)
	registry.remove_block(carrier)
	registry.remove_block(trio[1])

	assert_eq(_removed_ids, [], "a client never reports a removal")
	assert_false(plain.is_queued_for_deletion())
	assert_false(carrier.is_queued_for_deletion())
	assert_eq(carrier.members.size(), 3)
	assert_eq(registry.tracked_block_count(), 4)


func test_remove_block_ignores_null_and_already_dying_bodies() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = _cube_at(field, shape, 0, 0.0)
	_record_removals()

	registry.remove_block(null)
	block.queue_free()
	registry.remove_block(block)

	assert_eq(_removed_ids, [], "nothing to remove, no double report")


## Every start_match configures the registry again with the same Field; a fall
## through the kill plane must still report exactly one removal (spec 1.7).
func test_kill_plane_fall_reports_exactly_one_block_removed_after_repeated_configure() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	registry.configure(field, _map_def)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	add_child_autofree(block)
	block.global_position = field.to_global(Vector3(0.0, _tuning.kill_plane_y, 0.0))
	Events.block_placed.emit(block, shape.id)
	var id: int = block.get_instance_id()
	_record_removals()

	var frames: int = 0
	while frames < 60 and not _removed_ids.has(id):
		await wait_physics_frames(1)
		frames += 1
	await wait_physics_frames(5)

	assert_eq(_removed_ids.count(id), 1, "exactly one block_removed for the fallen block")
	assert_eq(registry.tracked_block_count(), 0)
