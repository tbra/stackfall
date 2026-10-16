extends GutTest
## a released gift swaps to its SpecialDef.activation_scale model (collider,
## visual, mass); the held preview is untouched; the host lift check uses the scaled extent.

const REST_FRAMES: int = 240
const DROP_HEIGHT: float = 6.0
## A neighbour may be pushed by the landing, but not flung: at most one cube width.
const MAX_NEIGHBOUR_SHIFT_CUBES: float = 1.0

var _tuning: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
func _shape() -> BlockShape:
	return BlockShape.load_all_shapes()[0]


func _gift(id: StringName) -> Block:
	var shape: BlockShape = _shape()
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	BlockFactory.apply_gift_visual(block, shape, _tuning, id)
	return block


func test_five_x_anvil_lands_without_exploding_the_stack() -> void:
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(60.0, 1.0, 60.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	root.add_child(floor_body)
	var shape: BlockShape = _shape()
	var neighbours: Array[Block] = []
	for i: int in range(3):
		var cube: Block = BlockFactory.build(shape, _tuning, 0)
		root.add_child(cube)
		cube.global_position = Vector3(4.0 + float(i) * 1.5, 0.0, 0.0)
		neighbours.append(cube)
	var anvil: Block = _gift(&"anvil")
	root.add_child(anvil)
	anvil.global_position = Vector3(0.0, DROP_HEIGHT, 0.0)
	anvil.continuous_cd = true
	await wait_physics_frames(30)
	var starts: Array[Vector3] = []
	for cube: Block in neighbours:
		starts.append(cube.global_position)
	await wait_physics_frames(REST_FRAMES)
	assert_true(anvil.global_position.is_finite(), "anvil finite")
	assert_lt(anvil.global_position.y, 3.0, "anvil came to rest low, not launched")
	assert_lt(anvil.linear_velocity.length(), 2.0, "anvil settled")
	for i: int in range(neighbours.size()):
		assert_lt(neighbours[i].global_position.distance_to(starts[i]), _tuning.cube_size * MAX_NEIGHBOUR_SHIFT_CUBES, "neighbour %d not ejected" % i)
