extends GutTest
## core/ai/BotStatics.gd (Bontago-1t5.21, Bot V2 P2; Bontago-1t5.72 P4): orientation dedup, each
## orientation's own centre-of-mass margin (rule 1 on flat ground) and eligibility by it. Pure, no scene tree.

var _tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _l4: BlockShape = preload("res://config/blocks/L4.tres")
var _s4: BlockShape = preload("res://config/blocks/S4.tres")
var _stack_tuning: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")


func _face_half_cubes() -> float:
	return (_physics.cube_size - _physics.cube_margin) * 0.5 / _physics.cube_size


func test_inverted_l4_com_is_a_quarter_cube_inside() -> void:
	var found: bool = false
	for i: int in range(BlockOrientations.count()):
		var info: BotStatics.OrientationInfo = BotStatics.orientation_info(_l4, i)
		if info.height == 3.0 and info.contact.size() == 1:
			found = true
			assert_almost_eq(info.self_margin, _face_half_cubes() - 0.25, 0.01, "COM 0.25 cube from the stem's axis")
	assert_true(found, "the inverted L4 (foot on top) exists")


func test_every_offered_orientation_is_eligible_by_self_margin() -> void:
	var floor_cubes: float = _stack_tuning.numeric_tolerance_m / _physics.cube_size
	for shape: BlockShape in BlockShape.load_all_shapes():
		for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
			assert_gt(info.self_margin, floor_cubes, "%s orientation %d" % [shape.id, info.index])


func test_orientation_with_the_com_off_its_contact_is_filtered_out() -> void:
	# L4 on its side and S4 upright have the COM outside (or exactly on the edge of) their contact.
	var floor_cubes: float = _stack_tuning.numeric_tolerance_m / _physics.cube_size
	for shape: BlockShape in [_l4, _s4]:
		var ineligible: int = 0
		for i: int in range(BlockOrientations.count()):
			if BotStatics.orientation_info(shape, i).self_margin <= floor_cubes:
				ineligible += 1
		assert_gt(ineligible, 0, "%s has orientations whose COM is outside their contact" % shape.id)
		for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
			assert_gt(info.self_margin, floor_cubes, "%s offers only eligible orientations" % shape.id)
