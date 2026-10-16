extends GutTest
## Glue fusion WP1: GlueFusion.fuse() rules (docs/GLUE_FUSION_PLAN.md section 5).

const CUBE_SIDE_M: float = 1.2
const AIR_Y_M: float = 6.0

var _field: Field
var _root: Node3D
var _tuning: GlueDropTuning = preload("res://config/gifts/glue_drop_tuning.tres")


func before_each() -> void:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_root = autofree(Node3D.new())
	add_child_autofree(_root)


func _block(shape_id: String, slot: int, offset_x: float) -> Block:
	var shape: BlockShape = load("res://config/blocks/%s.tres" % shape_id)
	var physics: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, slot)
	_root.add_child(block)
	block.global_position = _field.to_global(Vector3(offset_x, AIR_Y_M, 0.0))
	return block


func _shape_count(body: Node) -> int:
	var count: int = 0
	for child: Node in body.get_children():
		if child is CollisionShape3D:
			count += 1
	return count


func test_fuse_emits_blocks_fused_with_the_new_members() -> void:
	var a: Block = _block("cube", 0, 0.0)
	var b: Block = _block("cube", 1, CUBE_SIDE_M)
	watch_signals(Events)
	var carrier: FusedBody = GlueFusion.fuse(a, b, _tuning)
	assert_signal_emitted(Events, "blocks_fused")
	var params: Array = get_signal_parameters(Events, "blocks_fused")
	assert_eq(params[0], carrier)
	assert_eq((params[1] as Array).size(), 2)


func test_merge_of_two_groups_conserves_members_mass_and_shapes() -> void:
	var a: Block = _block("cube", 0, 0.0)
	var b: Block = _block("L4", 1, CUBE_SIDE_M)
	var c: Block = _block("cube", 0, 3.0 * CUBE_SIDE_M)
	var d: Block = _block("cube", 1, 4.0 * CUBE_SIDE_M)
	var left: FusedBody = GlueFusion.fuse(a, b, _tuning)
	var right: FusedBody = GlueFusion.fuse(c, d, _tuning)
	var mass: float = left.mass + right.mass
	var shapes: int = _shape_count(left) + _shape_count(right)
	var carrier: FusedBody = GlueFusion.fuse(b, c, _tuning)
	assert_eq(carrier.members.size(), 4)
	assert_almost_eq(carrier.mass, mass, 0.0001)
	assert_eq(_shape_count(carrier), shapes, "shape count conserved")
	for block: Block in [a, b, c, d]:
		assert_eq(block.fused_carrier(), carrier)
		var expected: Transform3D = carrier.global_transform * carrier.member_offset(block)
		assert_lt(block.global_position.distance_to(expected.origin), 0.0001)
	var gone: FusedBody = right if carrier == left else left
	await get_tree().physics_frame
	assert_false(is_instance_valid(gone), "the absorbed carrier is freed")


func test_max_fused_cubes_caps_a_group_and_zero_is_unlimited() -> void:
	var capped: GlueDropTuning = _tuning.duplicate() as GlueDropTuning
	capped.max_fused_cubes = 3
	var a: Block = _block("cube", 0, 0.0)
	var b: Block = _block("cube", 0, CUBE_SIDE_M)
	var c: Block = _block("L4", 0, 2.0 * CUBE_SIDE_M)
	assert_not_null(GlueFusion.fuse(a, b, capped))
	assert_null(GlueFusion.fuse(c, b, capped), "2 + 4 cubes exceeds the cap of 3")
	assert_false(c.is_fused_member())
	assert_not_null(GlueFusion.fuse(c, b, _tuning), "0 means unlimited")


func test_disc_fusion_anchors_the_charged_member_and_pins_the_carrier() -> void:
	var rest_y: float = _field.surface_y() + CUBE_SIDE_M * 0.5
	var a: Block = _block("cube", 0, 0.0)
	a.global_position = _field.to_global(Vector3(0.0, rest_y, 0.0))
	var carrier: FusedBody = GlueFusion.fuse(a, _field, _tuning)
	assert_not_null(carrier)
	assert_true(carrier.is_disc_anchored())
	assert_true(carrier.anchored_members.has(a.get_instance_id()))
	assert_eq(carrier.members.size(), 1, "a lone anchored block keeps its one-member body")
	assert_true(carrier.freeze)
	var b: Block = _block("cube", 1, CUBE_SIDE_M)
	b.global_position = a.global_position + Vector3(CUBE_SIDE_M, 0.0, 0.0)
	assert_eq(GlueFusion.fuse(b, a, _tuning), carrier, "a block glued to the anchored one joins its body")
	assert_true(carrier.is_disc_anchored(), "and the group stays anchored")
	assert_eq(carrier.members.size(), 2)
