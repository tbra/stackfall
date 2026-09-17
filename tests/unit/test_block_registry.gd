extends GutTest
## game/BlockRegistry.gd: tracks live blocks, the settled rule (spec 2.2), and
## net_id <-> Block.

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
var _territory_tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
var _map_def: MapDef = load("res://config/maps/round_medium.tres")


func _make_field() -> Field:
	var field: Field = autofree(Field.new())
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


func test_bodies_over_cells_finds_the_body_under_that_cell() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var grid: CellGrid = CellGrid.new(_map_def.field_radius, _map_def.cell_size)

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	field.add_child(block)
	block.freeze = true
	block.global_position = Vector3(5.0, 0.5, 5.0)
	Events.block_placed.emit(block, shape.id)

	await get_tree().physics_frame

	var coords: Vector2i = grid.world_to_cell(Vector2(5.0, 5.0))
	var index: int = grid.cell_index(coords.x, coords.y)
	var found: Array[RigidBody3D] = registry.bodies_over_cells(PackedInt32Array([index]))
	assert_eq(found.size(), 1)
	assert_eq(found[0], block)

	var elsewhere: Array[RigidBody3D] = registry.bodies_over_cells(PackedInt32Array([0]))
	assert_eq(elsewhere.size(), 0)
