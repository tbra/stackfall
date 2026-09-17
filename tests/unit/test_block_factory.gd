extends GutTest
## Checks BlockFactory's output shape (mass, collision/mesh count) against
## the numbers in spec 2.4 and config/physics_tuning.tres.

var _tuning: PhysicsTuning = load("res://config/physics_tuning.tres")


func test_cube_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 1)
	assert_almost_eq(block.mass, _tuning.cube_mass * 1.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 1)
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 1)


func test_bar4_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/bar4.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 4)
	assert_almost_eq(block.mass, _tuning.cube_mass * 4.0, 0.0001)
	assert_eq(_count_children_of_type(block, "CollisionShape3D"), 4)
	assert_eq(_count_children_of_type(block, "MeshInstance3D"), 4)


func test_slab6_mass_and_shape_count() -> void:
	var shape: BlockShape = load("res://config/blocks/slab6.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_eq(block.cube_count, 6)
	assert_almost_eq(block.mass, _tuning.cube_mass * 6.0, 0.0001)


func test_boxes_are_shrunk_by_the_margin() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	var collision: CollisionShape3D = null
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			collision = child
			break
	assert_not_null(collision)
	var box: BoxShape3D = collision.shape as BoxShape3D
	assert_not_null(box, "cube.tres should collide with a BoxShape3D.")
	var expected_edge: float = _tuning.cube_size - _tuning.cube_margin
	assert_almost_eq(box.size.x, expected_edge, 0.0001)
	assert_almost_eq(box.size.y, expected_edge, 0.0001)
	assert_almost_eq(box.size.z, expected_edge, 0.0001)


func test_wedge_uses_a_convex_collision_shape() -> void:
	var shape: BlockShape = load("res://config/blocks/wedge.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	var collision: CollisionShape3D = null
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			collision = child
			break
	assert_not_null(collision)
	assert_true(collision.shape is ConvexPolygonShape3D, "wedge needs a sloped (convex) collision shape.")


func test_physics_material_matches_tuning() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = autofree(BlockFactory.build(shape, _tuning))
	assert_almost_eq(block.physics_material_override.friction, _tuning.block_friction, 0.0001)
	assert_almost_eq(block.physics_material_override.bounce, _tuning.block_bounce, 0.0001)


func _count_children_of_type(node: Node, type_name: String) -> int:
	var count: int = 0
	for child: Node in node.get_children():
		if child.get_class() == type_name:
			count += 1
	return count
