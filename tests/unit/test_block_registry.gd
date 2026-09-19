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


func _place(field: Field, shape: BlockShape, slot: int) -> Block:
	var block: Block = BlockFactory.build(shape, _tuning, slot)
	field.add_child(block)
	Events.block_placed.emit(block, shape.id)
	return block


func test_net_ids_walk_past_the_u16_boundary_without_reuse() -> void:
	# Bontago-mv0.1.7: the counter is monotonic and never reused within a
	# match, so it *will* pass 65535 in a long enough match. Every id it hands
	# out past that point must still be its own body on the wire.
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	registry.debug_set_next_net_id(65535)

	var blocks: Array[Block] = [_place(field, shape, 0), _place(field, shape, 1), _place(field, shape, 0)]
	assert_eq(
		[blocks[0].net_id, blocks[1].net_id, blocks[2].net_id],
		[65535, 65536, 65537],
		"ids continue past the u16 boundary, none reused"
	)
	for block: Block in blocks:
		assert_true(Quantize.is_wire_id(block.net_id), "%d is representable on the wire" % block.net_id)
		assert_eq(registry.block_for_net_id(block.net_id), block, "%d names its own body" % block.net_id)
	assert_null(registry.block_for_net_id(0), "nothing answers to the 'no body' id")
	assert_null(registry.block_for_net_id(1), "and nothing answers to the id 65537 would alias")
	assert_eq(registry.debug_next_net_id(), 65538, "the counter keeps climbing")


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


func test_debug_set_next_net_id_never_reaches_the_reserved_zero() -> void:
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	registry.debug_set_next_net_id(0)
	assert_eq(registry.debug_next_net_id(), 1, "0 is 'no body' on the wire and is never allocated")
	registry.debug_set_next_net_id(-5)
	assert_eq(registry.debug_next_net_id(), 1)
	registry.debug_set_next_net_id(40)
	registry.reset()
	assert_eq(registry.debug_next_net_id(), 1, "reset() restarts the counter as before")


func test_bind_net_id_refuses_ids_the_wire_cannot_carry() -> void:
	# Bontago-mv0.1.7: bind_net_id() used to check only `net_id < 0`, so the
	# client's own boundary would happily track a body under net_id == 0 (the
	# wire's reserved "no body" id) or an id past Quantize.NET_ID_MAX -- either
	# aliases a real body or a legitimate "nothing here" answer.
	var field: Field = _make_field()
	var registry: BlockRegistry = _make_registry(field)
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning, 0))
	add_child_autofree(block)

	for bad_id: int in [-1, 0, Quantize.NET_ID_MAX + 1]:
		registry.bind_net_id(block, bad_id)
		assert_eq(block.net_id, -1, "an id the wire cannot carry (%d) is never bound" % bad_id)
		assert_null(registry.block_for_net_id(bad_id))

	registry.bind_net_id(block, 42)
	assert_eq(block.net_id, 42, "a real id still binds")
	assert_eq(registry.block_for_net_id(42), block)


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
