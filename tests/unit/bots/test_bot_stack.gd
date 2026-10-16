extends GutTest
## core/ai/BotStack.gd (.53a): pure tower statics on synthetic snapshots, no scene tree.

const CUBE: float = 1.0
const HALF: float = 0.5
const MASS: float = 1.0
const EPS: float = 0.01

var _t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _stack: BotStack = null


func before_each() -> void:
	_stack = BotStack.new()
	_stack.cube_size = CUBE


func _cube(id: int, x: float, level: int, z: float = 0.0, team: int = 0) -> void:
	_body(id, [Vector3(x, HALF + float(level) * CUBE, z)], team)


func _body(id: int, cubes: Array[Vector3], team: int = 0, basis: Basis = Basis.IDENTITY, mass: float = MASS) -> void:
	_stack.add_body(id, team, basis, PackedVector3Array(cubes), mass, true)


func _analyse() -> void:
	_stack.analyse_step(_stack.body_count() + 1, _t)


func _ids(id: int) -> PackedInt64Array:
	return PackedInt64Array([id])


func test_centred_two_cube_tower_has_half_cube_margin() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 0.0, 1)
	_analyse()
	var m: float = _stack.load_margin(_ids(2), Vector3(0.0, 2.5, 0.0), MASS)
	assert_almost_eq(m, HALF, EPS)


func test_piece_beyond_top_edge_is_negative() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 0.0, 1)
	_analyse()
	assert_lt(_stack.load_margin(_ids(2), Vector3(0.7, 2.5, 0.0), MASS), 0.0)


func test_no_block_support_is_infinite() -> void:
	_cube(1, 0.0, 0)
	_analyse()
	assert_eq(_stack.load_margin(PackedInt64Array(), Vector3.ZERO, MASS), INF)
	assert_eq(_stack.load_margin(_ids(99), Vector3.ZERO, MASS), INF)


func test_overhang_fails_at_a_lower_contact() -> void:
	# Staircase of cubes shifted half a cube each level: the piece is fine on the top cube and
	# the top pair is fine on the middle one, but the whole load is outside the bottom contact.
	_cube(1, 0.0, 0)
	_cube(2, 0.5, 1)
	_cube(3, 1.0, 2)
	_analyse()
	var m: float = _stack.load_margin(_ids(3), Vector3(0.75, 3.5, 0.0), MASS)
	assert_lt(m, 0.0)
	assert_almost_eq(m, -0.25, EPS)


func test_two_legs_bridge_com_between_them_is_inside_the_hull() -> void:
	_cube(1, -1.0, 0)
	_cube(2, 1.0, 0)
	var bridge: Array[Vector3] = [
		Vector3(-1.0, 1.5, 0.0), Vector3(0.0, 1.5, 0.0), Vector3(1.0, 1.5, 0.0)
	]
	_body(3, bridge, 0, Basis.IDENTITY, 3.0 * MASS)
	_analyse()
	var m: float = _stack.load_margin(_ids(3), Vector3(0.0, 2.5, 0.0), MASS)
	assert_almost_eq(m, HALF, EPS)
	assert_true(_stack.is_sound(_stack.index_of(3)), "the bridge is sound")
	assert_true(_stack.is_sound(_stack.index_of(1)), "legs are not charged the whole bridge")


func test_tilted_body_is_unsound_and_so_is_what_rests_on_it() -> void:
	_cube(1, 0.0, 0)
	_body(2, [Vector3(0.0, 1.5, 0.0)], 0, Basis(Vector3.RIGHT, deg_to_rad(30.0)))
	_cube(3, 0.0, 2)
	_analyse()
	assert_true(_stack.is_sound(_stack.index_of(1)))
	assert_false(_stack.is_sound(_stack.index_of(2)))
	assert_false(_stack.is_sound(_stack.index_of(3)))


func test_cube_at_disc_level_rests_on_the_disc_and_floating_cube_does_not() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 5.0, 3)
	_analyse()
	assert_true(_stack.is_sound(_stack.index_of(1)))
	assert_false(_stack.is_sound(_stack.index_of(2)), "floating: no support at all")


func test_sound_tops_and_top_height() -> void:
	_cube(1, 0.0, 0, 0.0, 0)
	_cube(2, 0.0, 1, 0.0, 0)
	_cube(3, 3.0, 0, 0.0, 0)
	_cube(4, 6.0, 0, 0.0, 1)
	_analyse()
	var tops: PackedInt32Array = _stack.sound_tops(0)
	assert_eq(tops.size(), 2)
	assert_eq(_stack.body_ids[tops[0]], 2, "tallest first")
	assert_almost_eq(_stack.top_height(tops[0]), 2.0, EPS)
	assert_eq(_stack.sound_tops(1).size(), 1)


func test_rolled_bars_are_sound_with_the_lying_footprint() -> void:
	# A 3-long bar along local y, rolled 90 degrees about x and about z (lying), on the disc.
	var rolls: Array[Basis] = [
		Basis(Vector3.RIGHT, deg_to_rad(90.0)), Basis(Vector3.BACK, deg_to_rad(90.0))
	]
	var x: float = 0.0
	for roll: Basis in rolls:
		var s: BotStack = BotStack.new()
		s.cube_size = CUBE
		var cubes: PackedVector3Array = PackedVector3Array()
		for k: int in 3:
			cubes.append(Vector3(x, HALF, 0.0) + roll * Vector3(0.0, float(k) - 1.0, 0.0))
		s.add_body(1, 0, roll, cubes, 3.0 * MASS, true)
		s.analyse_step(2, _t)
		assert_true(s.is_sound(0), "lying bar is sound")
		assert_lt(s.body_tilt_deg[0], EPS)
		assert_eq(s._hull[0].size(), 4, "a rectangular footprint")
		var hull: PackedVector2Array = s._hull[0]
		var lo: Vector2 = hull[0]
		var hi: Vector2 = hull[0]
		for p: Vector2 in hull:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var size: Vector2 = hi - lo
		assert_almost_eq(maxf(size.x, size.y), 3.0, EPS)
		assert_almost_eq(minf(size.x, size.y), 1.0, EPS)
