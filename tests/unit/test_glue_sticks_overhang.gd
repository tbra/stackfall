extends GutTest
## Owner playtest 2026-10-08 (Bontago-1pi.85.65): a glued block dropped off the
## side of another block must stick to it; it fails if it slides off and touches
## the disc. The control drops the same block without glue and must reach the disc.

const CUBE_SIDE_M: float = 1.2
## Glued block's centre starts this far (m) from the resting block's centre: on the
## side edge (half the footprint overhangs) and well past it (mostly unsupported).
const OVERHANG_EDGE_M: float = 0.6
const OVERHANG_FAR_M: float = 0.85
const DROP_GAP_M: float = 0.6
const PRE_SETTLE_FRAMES: int = 40
const OBSERVE_FRAMES: int = 300

var _field: Field
var _blocks_root: Node3D
var _tuning: GlueDropTuning = preload("res://config/glue_drop_tuning.tres")


func before_each() -> void:
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)


func _cube(slot_id: int, at: Vector3) -> Block:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var physics: PhysicsTuning = load("res://config/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, physics, slot_id)
	_blocks_root.add_child(block)
	block.global_position = at
	return block


## Returns {touched_disc, attached, bonds}. Drops a cube off the side of a resting one.
func _drop_off_side(glued: bool, offset_m: float) -> Dictionary:
	var rest_y: float = _field.surface_y() + CUBE_SIDE_M * 0.5
	var base: Block = _cube(0, _field.to_global(Vector3(0.0, rest_y, 0.0)))
	for _i: int in range(PRE_SETTLE_FRAMES):
		await get_tree().physics_frame
	var dropped: Block = _cube(1, base.global_position + Vector3(offset_m, CUBE_SIDE_M + DROP_GAP_M, 0.0))
	dropped.contact_monitor = true
	dropped.max_contacts_reported = _tuning.max_contacts_reported
	if glued:
		var glue: GlueDrops = GlueDrops.new()
		dropped.add_child(glue)
		glue.bind(dropped, _tuning)
	var touched_disc: bool = false
	for _i: int in range(OBSERVE_FRAMES):
		await get_tree().physics_frame
		for body: Node3D in dropped.get_colliding_bodies():
			touched_disc = touched_disc or body == _field
	var bonded_to_base: bool = false
	var bonds: int = 0
	for child: Node in dropped.get_children():
		if child is GlueJoint:
			bonds += 1
			bonded_to_base = bonded_to_base or (child as GlueJoint).bodies_match(dropped, base)
	var attached: bool = (
		not touched_disc
		and dropped.global_position.y > base.global_position.y + CUBE_SIDE_M * 0.5
		and Vector2(dropped.global_position.x - base.global_position.x, dropped.global_position.z - base.global_position.z).length()
		< CUBE_SIDE_M
	)
	return {"touched_disc": touched_disc, "attached": attached, "bonded": bonded_to_base, "bonds": bonds}


func test_unglued_block_dropped_off_the_side_reaches_the_disc() -> void:
	for offset_m: float in [OVERHANG_EDGE_M, OVERHANG_FAR_M]:
		var result: Dictionary = await _drop_off_side(false, offset_m)
		assert_true(result["touched_disc"], "control: without glue the block at %.2f m must slide off" % offset_m)
		for child: Node in _blocks_root.get_children():
			child.free()


func test_glued_block_dropped_off_the_side_sticks_and_never_touches_the_disc() -> void:
	for offset_m: float in [OVERHANG_EDGE_M, OVERHANG_FAR_M]:
		var result: Dictionary = await _drop_off_side(true, offset_m)
		assert_false(result["touched_disc"], "glued block at %.2f m must not slide off onto the disc" % offset_m)
		assert_true(result["bonded"], "glued block must be bonded to the block it landed on")
		assert_true(result["attached"], "glued block must still sit on the block")
		for child: Node in _blocks_root.get_children():
			child.free()
