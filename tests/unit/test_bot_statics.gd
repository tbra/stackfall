extends GutTest
## core/ai/BotStatics.gd (Bontago-1t5.21, Bot V2 P2; Bontago-1t5.72 P4): orientation dedup, each
## orientation's own centre-of-mass margin (rule 1 on flat ground) and eligibility by it. Pure, no scene tree.

var _tuning: BotGenTuning = preload("res://config/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _bar5: BlockShape = preload("res://config/blocks/bar5.tres")
var _l4: BlockShape = preload("res://config/blocks/L4.tres")
var _s4: BlockShape = preload("res://config/blocks/S4.tres")
var _stack_tuning: BotStackTuning = preload("res://config/bot_stack_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics_tuning.tres")


func _info_with_height(shape: BlockShape, height: float) -> BotStatics.OrientationInfo:
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _tuning):
		if is_equal_approx(info.height, height):
			return info
	return null


func test_cube_has_one_orientation_and_pillar_two_heights() -> void:
	assert_eq(BotStatics.orientation_infos(_cube, _tuning).size(), 1)
	var heights: Array[float] = []
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(_pillar, _tuning):
		if not heights.has(info.height):
			heights.append(info.height)
	assert_eq(heights.size(), 2, "flat and upright")
	assert_true(heights.has(3.0))
	assert_true(heights.has(1.0))


func test_orientations_are_capped_and_distinct() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var infos: Array[BotStatics.OrientationInfo] = BotStatics.orientation_infos(shape, _tuning)
		assert_true(infos.size() <= _tuning.max_orientations_per_shape, "%s capped" % shape.id)
		assert_false(infos.is_empty())
		var signatures: Dictionary = {}
		for info: BotStatics.OrientationInfo in infos:
			assert_false(signatures.has(info.signature), "%s distinct" % shape.id)
			signatures[info.signature] = true


func _face_half_cubes() -> float:
	return (_physics.cube_size - _physics.cube_margin) * 0.5 / _physics.cube_size


func test_self_margin_of_a_centred_piece_is_its_face_half() -> void:
	var half: float = _face_half_cubes()
	assert_almost_eq(_info_with_height(_cube, 1.0).self_margin, half, 0.0001, "cube")
	assert_almost_eq(_info_with_height(_bar5, 5.0).self_margin, half, 0.0001, "upright bar5 stands on one cube")
	assert_almost_eq(_info_with_height(_pillar, 3.0).self_margin, half, 0.0001, "upright pillar")
	assert_almost_eq(_info_with_height(_bar5, 1.0).self_margin, half, 0.0001, "flat bar5: the short side binds")
	assert_almost_eq(_info_with_height(_bar5, 5.0).com_height, 2.5, 0.0001)


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


func test_filter_runs_before_the_cap() -> void:
	var capped: BotGenTuning = _tuning.duplicate() as BotGenTuning
	capped.max_orientations_per_shape = 1
	for shape: BlockShape in BlockShape.load_all_shapes():
		var infos: Array[BotStatics.OrientationInfo] = BotStatics.orientation_infos(shape, capped)
		assert_eq(infos.size(), 1, "%s keeps one" % shape.id)
		assert_gt(infos[0].self_margin, 0.0, "%s: the kept one stands on its own contact" % shape.id)
