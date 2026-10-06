extends GutTest
## Bontago-1pi.85.32: a released gift swaps to its SpecialDef.activation_scale model (collider,
## visual, mass); the held preview is untouched; the host lift check uses the scaled extent.

const SCALES: Dictionary = {
	&"anvil": 5.0, &"bomb": 3.0, &"propeller": 5.0, &"rocket": 2.0, &"magnet": 2.0, &"jumping_bean": 2.0,
}
const REST_FRAMES: int = 240
const DROP_HEIGHT: float = 6.0
## A neighbour may be pushed by the landing, but not flung: at most one cube width.
const MAX_NEIGHBOUR_SHIFT_CUBES: float = 1.0

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")
var _special_tuning: SpecialTuning = load("res://config/special_tuning.tres") as SpecialTuning


func _shape() -> BlockShape:
	return BlockShape.load_all_shapes()[0]


func _gift(id: StringName) -> Block:
	var shape: BlockShape = _shape()
	var block: Block = BlockFactory.build(shape, _tuning, 0)
	BlockFactory.apply_gift_visual(block, shape, _tuning, id)
	return block


func _collider(block: Block) -> CollisionShape3D:
	for child: Node in block.get_children():
		if child is CollisionShape3D:
			return child as CollisionShape3D
	return null


func test_configured_scales_match_the_owner_list() -> void:
	for id: StringName in SCALES:
		assert_eq(SpecialDef.find_by_id(id).activation_scale, SCALES[id], str(id))


func test_collider_visual_and_mass_follow_the_scale() -> void:
	for id: StringName in SCALES:
		var s: float = SCALES[id]
		var block: Block = _gift(id)
		add_child_autofree(block)
		var box: BoxShape3D = _collider(block).shape as BoxShape3D
		assert_almost_eq(box.size.x, (_tuning.cube_size - _tuning.cube_margin) * s, 0.001, "%s collider" % id)
		var visual: Node3D = block.get_node(NodePath(BlockFactory.GIFT_VISUAL_NODE)) as Node3D
		assert_almost_eq(visual.scale.x, s, 0.001, "%s visual scale" % id)
		assert_almost_eq(block.mass, _tuning.cube_mass * pow(s, _special_tuning.activation_mass_exponent), 0.001, "%s mass" % id)
		# Bottom face stays where the 1x cell's bottom face was.
		var bottom: float = _collider(block).position.y - box.size.y * 0.5
		var centre_1x: float = BlockFactory.gift_cell_center(_shape(), _tuning).y
		assert_almost_eq(bottom, centre_1x - (_tuning.cube_size - _tuning.cube_margin) * 0.5, 0.001, "%s grows about the bottom" % id)


func test_mass_exponent_is_honoured() -> void:
	var saved: float = _special_tuning.activation_mass_exponent
	_special_tuning.activation_mass_exponent = 3.0
	var block: Block = _gift(&"bomb")
	_special_tuning.activation_mass_exponent = saved
	add_child_autofree(block)
	assert_almost_eq(block.mass, _tuning.cube_mass * 27.0, 0.001)


func test_unscaled_gift_and_preview_stay_one_x() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"cat")
	if def != null:
		assert_eq(BlockFactory.activation_scale_for(&"cat"), 1.0)
	assert_eq(BlockFactory.activation_scale_for(&"no_such_gift"), 1.0)
	# The held preview (GhostPreview) is built by build_fallback_gift_visual/build_visual_only and never
	# goes through apply_gift_visual, so it carries no activation scale.
	var preview: Node3D = GhostPreview.build_fallback_gift_visual(_tuning.cube_size)
	autofree(preview)
	assert_eq(preview.scale, Vector3.ONE)


func test_host_lift_uses_the_scaled_extent() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	var field: Field = autofree(Field.new())
	field.map_def = map
	add_child_autofree(field)
	var root: Node3D = autofree(Node3D.new())
	add_child_autofree(root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, root)
	var shape: BlockShape = _shape()
	# A resting cube whose top is 1.5 m up; a 1x gift at +1.7 m clears, a 5x one centred there does not.
	var wall: Block = BlockFactory.build(shape, _tuning, 0)
	root.add_child(wall)
	wall.global_position = Vector3(0.0, 1.0, 0.0)
	wall.freeze = true
	await wait_physics_frames(2)
	var origin: Vector3 = Vector3(2.5, 0.0, 0.0)  # 1x cube at x in [2,3] clears x in [0.5,1.5]
	var plain: Variant = Match._placement._lift_pose_clear(shape, origin, Basis.IDENTITY, false, &"")
	assert_eq(plain, origin, "1x pose clears")
	var big: Variant = Match._placement._lift_pose_clear(shape, origin, Basis.IDENTITY, false, &"anvil")
	assert_ne(big, null)
	assert_gt((big as Vector3).y, origin.y, "5x extent overlaps the wall, so the host lifts it")
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


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
