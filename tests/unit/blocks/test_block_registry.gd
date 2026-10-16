extends GutTest
## game/blocks/BlockRegistry.gd: tracks live blocks, the settled rule (spec 2.2), and
## net_id <-> Block.

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = load("res://config/territory/territory_tuning.tres")

## DECISION (Bontago-mv0.3): a duplicate of round_medium.tres shrunk to a 20 m
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
	assert_eq(registry.net_id_for_block(block_b), block_b.net_id)
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
	registry._entries[target.get_instance_id()].is_settled = true
	assert_true(registry.convert_owner(target, 0, paint_color))
	assert_eq(target.owner_slot, 0)
	assert_eq(registry.influence_circles(_slots(2), _territory_tuning, _map_def)[0].slot_id, 0)
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
	registry.debug_set_next_net_id(Quantize.NET_ID_MAX)

	var last: Block = _place(field, shape, 0)
	var over: Block = _place(field, shape, 1)
	assert_push_error("net_id space exhausted")

	assert_eq(last.net_id, Quantize.NET_ID_MAX, "the last representable id is handed out")
	assert_eq(over.net_id, -1, "past it no id is handed out at all")
	assert_eq(registry.debug_next_net_id(), Quantize.NET_ID_MAX + 1, "the counter never wraps")
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


# --- Bontago-1pi.11.14: physics-driven territory_revision bumps ---------------


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
