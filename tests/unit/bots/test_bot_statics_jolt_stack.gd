extends GutTest
## STATICS_DESIGN 6.1, cases B, C, H and the no-hull lower-cut check: multi-level agreement between
## the bot's statics model (BotStability on a BotStackProbe snapshot) and real Jolt. A mismatch is a finding about
## the model, never a reason to move a case.

const CUBE_SHAPE: BlockShape = preload("res://config/blocks/cube.tres")
const CUBE8_SHAPE: BlockShape = preload("res://config/blocks/cube8.tres")
const BAR3_SHAPE: BlockShape = preload("res://config/blocks/bar3.tres")
const PILLAR_SHAPE: BlockShape = preload("res://config/blocks/pillar.tres")

## A 2x2 block's colliders leave a cube_margin seam along x = 0 and z = 0; a ray fired there falls to the disc.
const SEAM_NUDGE_M: float = 0.05
## B: the first bar's centre of mass over the cube8 base; the second bar's centre of mass over the first.
## Base edge 0.99: combined centre 0.84 (inside by 0.15) / 1.14 (outside by 0.15); the second bar passes rule 1 on
## the first in both (its patch on the first bar reaches 1.98).
const B_L1_COM_M: float = 0.49
const B_L2_INSIDE_COM_M: float = 1.19
const B_L2_OUTSIDE_COM_M: float = 1.79
## C: pillars at +-1 m; a bar centred between them / centred beyond one.
const C_PILLAR_X_M: float = 1.0
const C_BRIDGE_COM_M: float = 0.0
const C_OVERHANG_COM_M: float = 2.2
## H: loose cube columns of this many cubes.
const H_COLUMNS: Array[int] = [1, 2, 3]

var _scene: StaticsJoltScene = null


func before_each() -> void:
	_scene = StaticsJoltScene.new(self)
	_scene.build_world()


func after_each() -> void:
	_scene.teardown()


func _at(x: float) -> Vector2:
	return Vector2(x, SEAM_NUDGE_M)


## `known_gap` non-empty marks a recorded disagreement (STATICS_DESIGN 6.3): not weakened, the safe direction (never a
## false "stable") is still asserted and the mismatch is reported as pending.
func _agree(label: String, r: Dictionary, expect_stable: bool, known_gap: String = "") -> void:
	var text: String = "%s: %s" % [label, StaticsJoltScene.describe(r)]
	gut.p("AGREE %s" % text)
	if known_gap != "" and r["stood"] != r["predicted"]:
		assert_false(r["predicted"] and not r["stood"], "never a false stable, " + text)
		pending("%s | %s" % [known_gap, text])
		return
	assert_eq(r["stood"], r["predicted"], "model and Jolt agree, " + text)
	assert_eq(r["predicted"], expect_stable, "expected verdict, " + text)


## cube8 base with a bar3 lying on it, its centre of mass at B_L1_COM_M.
func _two_level() -> bool:
	if await _scene.put(CUBE8_SHAPE, 0, Vector2.ZERO) == null:
		return false
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	return await _scene.put(BAR3_SHAPE, o, _at(B_L1_COM_M)) != null


## B: each bar passes rule 1 on the one beneath, the pair does not (rule 2).
func test_b_two_level_overhang_inside_stands() -> void:
	assert_true(await _two_level())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	_agree("B- L2 COM %.2f" % B_L2_INSIDE_COM_M, await _scene.trial(BAR3_SHAPE, o, _at(B_L2_INSIDE_COM_M), 0.0), true)


func test_b_two_level_overhang_outside_falls_although_rule_one_passes() -> void:
	assert_true(await _two_level())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	var r: Dictionary = await _scene.trial(BAR3_SHAPE, o, _at(B_L2_OUTSIDE_COM_M), 0.0)
	_agree("B+ L2 COM %.2f" % B_L2_OUTSIDE_COM_M, r, false)
	assert_gt(float(r["margin"]), 0.0, "the new bar's own cut (rule 1) passes")
	assert_gte(int(r["binding"]), 0, "the combined centre of mass of the pair (a lower cut, rule 2) is what fails")


## C: a bar bridging two pillars is carried by both; one resting on a single pillar's edge is not.
func _two_pillars() -> bool:
	var up: int = _scene.orientation(PILLAR_SHAPE, true)
	if await _scene.put(PILLAR_SHAPE, up, Vector2(-C_PILLAR_X_M, 0.0)) == null:
		return false
	return await _scene.put(PILLAR_SHAPE, up, Vector2(C_PILLAR_X_M, 0.0)) != null


func test_c_bridge_across_two_pillars_stands() -> void:
	assert_true(await _two_pillars())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	_agree("C- bridge COM %.1f" % C_BRIDGE_COM_M, await _scene.trial(BAR3_SHAPE, o, Vector2(C_BRIDGE_COM_M, 0.0), 0.0), true)


func test_c_bar_resting_on_one_pillar_end_falls() -> void:
	assert_true(await _two_pillars())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	_agree("C+ overhang COM %.1f" % C_OVERHANG_COM_M, await _scene.trial(BAR3_SHAPE, o, Vector2(C_OVERHANG_COM_M, 0.0), 0.0), false)


## H: loose 1x1 columns of cubes. A cube on top is predicted and stands. An upright bar3 on top is predicted stable
## (every cut has 0.49 m of margin) while Jolt may drop it (measured 0/6): STATICS_DESIGN 6.3 says
## record such a divergence and do not tune the model.
func _loose_column(count: int) -> bool:
	for level: int in count:
		if await _scene.put(CUBE_SHAPE, 0, Vector2.ZERO) == null:
			return false
	return true


func test_h_cube_on_a_loose_column_stands() -> void:
	for count: int in H_COLUMNS:
		_scene.teardown()
		_scene.build_world()
		assert_true(await _loose_column(count))
		_agree("H cube on col%d" % count, await _scene.trial(CUBE_SHAPE, 0, Vector2.ZERO, 0.0), true)


func test_h_upright_bar3_on_a_loose_column() -> void:
	var up: int = _scene.orientation(BAR3_SHAPE, true)
	for count: int in H_COLUMNS:
		_scene.teardown()
		_scene.build_world()
		assert_true(await _loose_column(count))
		_agree(
			"H bar3 on col%d" % count, await _scene.trial(BAR3_SHAPE, up, Vector2.ZERO, 0.0), true,
			"Jolt: an upright bar3 on a loose 1x1 column falls; statics says it stands (design 6.3)"
		)


## A lower cut with no support hull must never read as a false "stable" (BotStack.lower_cuts: INF for a body with no
## known hull). With the base of case B left out of the snapshot (the snapshot cap), the first bar has no known
## supporter; whatever the model reads, a stable verdict must stand in Jolt.
func _partial_snapshot() -> BotStack:
	return _scene.snapshot(_at(B_L1_COM_M), 1)


func test_no_hull_lower_cut_is_never_a_false_stable() -> void:
	assert_true(await _two_level())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	var partial: BotStack = _partial_snapshot()
	assert_eq(partial.body_count(), 1, "the snapshot holds the first bar only")
	var falls: Dictionary = await _scene.trial(BAR3_SHAPE, o, _at(B_L2_OUTSIDE_COM_M), 0.0, Vector2.ZERO, partial)
	_agree("INF-gap pair overhang (base missing)", falls, false)
	assert_false(falls["predicted"] and not falls["stood"], "never a false stable")


func test_no_hull_lower_cut_with_a_stable_load() -> void:
	assert_true(await _two_level())
	var o: int = _scene.orientation(BAR3_SHAPE, false)
	var partial: BotStack = _partial_snapshot()
	var r: Dictionary = await _scene.trial(BAR3_SHAPE, o, _at(B_L2_INSIDE_COM_M), 0.0, Vector2.ZERO, partial)
	gut.p("AGREE INF-gap stable load (base missing): %s" % StaticsJoltScene.describe(r))
	assert_false(r["predicted"] and not r["stood"], "a stable verdict stands in Jolt")
