extends GutTest
## Bontago-1t5.72.3 (STATICS_DESIGN 6.1, cases A, D, E, F, G): single-level agreement between the bot's statics model
## (BotStability on a BotStackProbe snapshot) and real Jolt. Each case sits +-0.1 m around a centre-of-mass boundary
## (the boundary itself is chaotic); the scene settles behind a quiet gate; "stood" is the settled outcome.
## A mismatch is a finding about the model, never a reason to move a case.

const CUBE8_SHAPE: BlockShape = preload("res://config/blocks/cube8.tres")
const BAR3_SHAPE: BlockShape = preload("res://config/blocks/bar3.tres")
const BAR4_SHAPE: BlockShape = preload("res://config/blocks/bar4.tres")
const BAR5_SHAPE: BlockShape = preload("res://config/blocks/bar5.tres")
const L4_SHAPE: BlockShape = preload("res://config/blocks/L4.tres")
const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")

## Half-width of a cube8 top face along x (cube centre 0.5 + collider half 0.49).
const EDGE_M: float = 0.99
## Boundary offsets (metres): the centre of mass this far inside / outside the support edge.
const INSIDE_M: float = 0.1
const OUTSIDE_M: float = 0.1
## Case G: nominal centre of mass 0.2 inside the edge; Hard-ish and Easy-ish worst-case aim errors around it.
## Case F: far enough in that the overhanging column still overlaps the base by more than min_contact_overlap_m.
const WELL_INSIDE_M: float = 0.8
const AIM_SMALL_M: float = 0.15
const AIM_LARGE_M: float = 0.25

## A 2x2 block's colliders leave a cube_margin seam along x = 0 and z = 0; a column ray fired exactly there falls
## through to the disc. Sites sit this far off the seam, as real bot sites (jittered, 9 rays) do.
const SEAM_NUDGE_M: float = 0.05

var _scene: StaticsJoltScene = null


func before_each() -> void:
	_scene = StaticsJoltScene.new(self)
	_scene.build_world()


func after_each() -> void:
	_scene.teardown()


func _at(x: float) -> Vector2:
	return Vector2(x, SEAM_NUDGE_M)


func _base() -> bool:
	return await _scene.put(CUBE8_SHAPE, 0, Vector2.ZERO) != null


## `known_gap` non-empty marks a recorded disagreement (STATICS_DESIGN 6.3): the case is not weakened, the safe
## direction (never a false "stable") is still asserted, and the mismatch is reported as pending.
func _agree(label: String, r: Dictionary, expect_stable: bool, known_gap: String = "") -> void:
	var text: String = "%s: %s" % [label, StaticsJoltScene.describe(r)]
	gut.p("AGREE %s" % text)
	if known_gap != "" and r["stood"] != r["predicted"]:
		assert_false(r["predicted"] and not r["stood"], "never a false stable, " + text)
		pending("%s | %s" % [known_gap, text])
		return
	assert_eq(r["stood"], r["predicted"], "model and Jolt agree, " + text)
	assert_eq(r["predicted"], expect_stable, "expected verdict, " + text)


## A: bar3 lying along x, COM 0.1 inside / outside the cube8 edge.
func test_a_cantilever_inside_stands() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	_agree("A- cantilever COM %.2f" % (EDGE_M - INSIDE_M), await _scene.trial(BAR3_SHAPE, o, _at(EDGE_M - INSIDE_M), 0.0), true)


func test_a_cantilever_outside_falls() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	_agree("A+ cantilever COM %.2f" % (EDGE_M + OUTSIDE_M), await _scene.trial(BAR3_SHAPE, o, _at(EDGE_M + OUTSIDE_M), 0.0), false)


## D: L4 lying flat, COM centred on the cube8 top / pivoted on an upright bar3's 1x1 top (COM outside).
func test_d_l_topper_centred_on_a_wide_top_stands() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(L4_SHAPE, false)
	_agree("D- L4 centred on cube8", await _scene.trial(L4_SHAPE, o, _at(SEAM_NUDGE_M), 0.0), true)


func test_d_l_topper_pivoted_on_a_one_cube_top_falls() -> void:
	var up: int = _scene.orientation(BAR3_SHAPE, true)
	assert_true(await _scene.put(BAR3_SHAPE, up, Vector2.ZERO) != null)
	var o: int = _scene.orientation(L4_SHAPE, false)
	var info: BotStatics.OrientationInfo = _scene.info_of(L4_SHAPE, o)
	# The cube farthest from the centre of mass sits over the bar's axis, so the COM hangs outside the 1x1 patch.
	var far: Vector2 = info.cubes[0]
	for p: Vector2 in info.cubes:
		if p.distance_to(info.com) > far.distance_to(info.com):
			far = p
	var com: Vector2 = (info.com - far) * PhysicsTuning.new().cube_size
	_agree("D+ L4 on a 1x1 top", await _scene.trial(L4_SHAPE, o, com, 0.0), false)


## E: upright bars 3/4/5 centred on a cube8 and on a pillar; bar3 with the COM 0.1 inside and 0.2 outside the edge.
func test_e_upright_bars_centred_stand_on_a_cube8() -> void:
	for shape: BlockShape in [BAR3_SHAPE, BAR4_SHAPE, BAR5_SHAPE]:
		_scene.teardown()
		_scene.build_world()
		assert_true(await _base())
		_agree("E %s on cube8" % shape.id, await _scene.trial(shape, _scene.orientation(shape, true), _at(SEAM_NUDGE_M), 0.0), true)


func test_e_upright_bars_centred_stand_on_a_pillar() -> void:
	for shape: BlockShape in [BAR3_SHAPE, BAR4_SHAPE, BAR5_SHAPE]:
		_scene.teardown()
		_scene.build_world()
		assert_true(await _scene.put(PILLAR_SHAPE, _scene.orientation(PILLAR_SHAPE, true), Vector2.ZERO) != null)
		_agree("E %s on pillar" % shape.id, await _scene.trial(shape, _scene.orientation(shape, true), _at(SEAM_NUDGE_M), 0.0), true)


func test_e_upright_bar3_with_its_com_inside_the_edge_stands() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, true)
	_agree("E bar3 COM inside edge", await _scene.trial(BAR3_SHAPE, o, _at(EDGE_M - INSIDE_M), 0.0), true)


func test_e_upright_bar3_with_its_com_outside_the_edge_falls() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, true)
	_agree("E bar3 COM 0.2 outside edge", await _scene.trial(BAR3_SHAPE, o, _at(EDGE_M + 2.0 * OUTSIDE_M), 0.0), false)


## F: cube8 on cube8 offset 0.89 / 1.09.
## The piece's overhanging column overlaps the base by less than min_contact_overlap_m (0.1 m) at 0.89, so the model
## drops that sliver from the support region and reads -0.01 where the true margin is +0.10: conservative.
func test_f_cube8_on_cube8_inside_stands() -> void:
	assert_true(await _base())
	_agree(
		"F- cube8 offset %.2f" % (EDGE_M - INSIDE_M), await _scene.trial(CUBE8_SHAPE, 0, _at(EDGE_M - INSIDE_M), 0.0), true,
		"model drops a contact strip narrower than min_contact_overlap_m (conservative: Jolt stands, model refuses)"
	)


func test_f_cube8_on_cube8_well_inside_stands() -> void:
	assert_true(await _base())
	_agree("F- cube8 offset %.2f" % WELL_INSIDE_M, await _scene.trial(CUBE8_SHAPE, 0, _at(WELL_INSIDE_M), 0.0), true)


func test_f_cube8_on_cube8_outside_falls() -> void:
	assert_true(await _base())
	_agree("F+ cube8 offset %.2f" % (EDGE_M + OUTSIDE_M), await _scene.trial(CUBE8_SHAPE, 0, _at(EDGE_M + OUTSIDE_M), 0.0), false)


## G: case A with the COM 0.2 inside the edge. The model is asked for aim error e; Jolt gets the piece shifted by e
## (outward, the worst case). e = 0.15 predicts stable and stands; e = 0.25 predicts unstable and falls.
func test_g_small_aim_error_is_tolerated() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	var nominal: Vector2 = _at(EDGE_M - 2.0 * INSIDE_M)
	_agree("G e=%.2f" % AIM_SMALL_M, await _scene.trial(BAR3_SHAPE, o, nominal, AIM_SMALL_M, Vector2(AIM_SMALL_M, 0.0)), true)


func test_g_large_aim_error_is_refused() -> void:
	assert_true(await _base())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	var nominal: Vector2 = _at(EDGE_M - 2.0 * INSIDE_M)
	_agree("G e=%.2f" % AIM_LARGE_M, await _scene.trial(BAR3_SHAPE, o, nominal, AIM_LARGE_M, Vector2(AIM_LARGE_M, 0.0)), false)
