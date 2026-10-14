extends GutTest
## core/ai/BotStack.gd cut model + core/ai/BotGeom2D.gd (Bontago-1t5.72 P1a, STATICS_DESIGN 2.2-2.4): up-closure cuts,
## the piece cut, lower cuts, the memo, the int-keyed down-set and face-centred outlines. Pure, no scene tree.

const CUBE: float = 1.0
const HALF: float = 0.5
const MASS: float = 1.0
const EPS: float = 0.01
const FACE_HALF: float = 0.49
const TILT_DEG: float = 6.0

var _t: BotStackTuning = preload("res://config/bot_stack_tuning.tres")
var _stack: BotStack = null


func before_each() -> void:
	_stack = BotStack.new()
	_stack.cube_size = CUBE


func _cube(id: int, x: float, level: int, z: float = 0.0, face_half: float = -1.0) -> void:
	_body(id, [Vector3(x, HALF + float(level) * CUBE, z)], Basis.IDENTITY, MASS, face_half)


func _body(
	id: int, cubes: Array[Vector3], basis: Basis = Basis.IDENTITY, mass: float = MASS, face_half: float = -1.0
) -> void:
	_stack.add_body(id, 0, basis, PackedVector3Array(cubes), mass, true, face_half)


func _analyse() -> void:
	_stack.analyse_step(_stack.body_count() + 1, _t)


func _bar(id: int, xs: Array[float], level: int) -> void:
	var cubes: Array[Vector3] = []
	for x: float in xs:
		cubes.append(Vector3(x, HALF + float(level) * CUBE, 0.0))
	_body(id, cubes, Basis.IDENTITY, MASS * float(xs.size()))


func _bounds(poly: PackedVector2Array) -> Rect2:
	var lo: Vector2 = poly[0]
	var hi: Vector2 = poly[0]
	for p: Vector2 in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


func test_geom_hull_is_ccw_and_signed_inside_is_the_edge_distance() -> void:
	var pts: PackedVector2Array = PackedVector2Array(
		[Vector2(0, 0), Vector2(2, 0), Vector2(2, 1), Vector2(0, 1), Vector2(1, 0.5)]
	)
	var hull: PackedVector2Array = BotGeom2D.hull(pts)
	assert_eq(hull.size(), 4)
	assert_gt(BotGeom2D.area(hull), 0.0, "counter-clockwise")
	assert_almost_eq(BotGeom2D.signed_inside_hull(hull, Vector2(1.0, 0.5)), 0.5, 0.0001)
	assert_almost_eq(BotGeom2D.signed_inside_hull(hull, Vector2(2.3, 0.5)), -0.3, 0.0001)
	assert_eq(BotGeom2D.signed_inside_hull(PackedVector2Array(), Vector2.ZERO), -INF)
	assert_eq(BotGeom2D.erode(BotGeom2D.hull(pts), 0.6).size(), 0, "a 1 m wide strip has nothing left at 0.6")
	assert_eq(BotGeom2D.rect_overlap(Vector2(0, 0), Vector2(1, 1), Vector2(2, 2), Vector2(3, 3)).size(), 0)


func test_chain_cut_equals_the_contact_hull() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 0.5, 1)
	_cube(3, 1.0, 2)
	_analyse()
	for id: int in [1, 2, 3]:
		var b: int = _stack.index_of(id)
		var cut: BotStack.Cut = _stack.cut_of(b)
		assert_eq(cut.hull, _stack._hull[b], "chain cut hull == body hull for %d" % id)
	var mid: BotStack.Cut = _stack.cut_of(_stack.index_of(2))
	assert_eq(mid.members.size(), 2, "the body and what rests on it")
	assert_almost_eq(mid.mass, 2.0 * MASS, EPS)
	assert_almost_eq(mid.com.x, 0.75, EPS)


func test_bridge_cut_hull_contains_the_other_leg() -> void:
	_cube(1, -1.0, 0)
	_cube(2, 1.0, 0)
	_bar(3, [-1.0, 0.0, 1.0], 1)
	_analyse()
	var leg: BotStack.Cut = _stack.cut_of(_stack.index_of(1))
	assert_true(leg.has(_stack.index_of(3)), "the bridge is in the leg's up-closure")
	assert_false(leg.has(_stack.index_of(2)))
	var box: Rect2 = _bounds(leg.hull)
	assert_almost_eq(box.position.x, -1.5, EPS)
	assert_almost_eq(box.end.x, 1.5, EPS, "the patch on the other leg widens the region")
	# The combined centre (leg + bridge) is 0.5 over: inside the widened region, not the leg's own top.
	assert_gt(leg.margin, 0.0)


func test_diamond_cuts() -> void:
	# A lying bar on the disc carries two cubes, which carry a bridge: the diamond.
	_bar(1, [-1.0, 0.0, 1.0], 0)
	_cube(2, -1.0, 1)
	_cube(3, 1.0, 1)
	_bar(4, [-1.0, 0.0, 1.0], 2)
	_analyse()
	var base: BotStack.Cut = _stack.cut_of(_stack.index_of(1))
	assert_eq(base.members.size(), 4, "everything above the base")
	var left: BotStack.Cut = _stack.cut_of(_stack.index_of(2))
	assert_eq(left.members.size(), 2, "the left pillar and the bridge")
	var box: Rect2 = _bounds(left.hull)
	assert_almost_eq(box.end.x, 1.5, EPS, "the bridge's patch on the right pillar is external to the left cut")


func test_staircase_still_gives_minus_a_quarter_through_lower_cuts() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 0.5, 1)
	_cube(3, 1.0, 2)
	_analyse()
	var top: int = _stack.index_of(3)
	var pc: BotStack.PieceCut = _stack.piece_cut(PackedVector2Array([Vector2(0.75, 0.0)]), HALF, 0.0, 0.0, PackedByteArray())
	assert_eq(pc.supports, PackedInt32Array([top]))
	assert_almost_eq(pc.plane_y, 3.0, EPS)
	var rows: PackedFloat32Array = _stack.lower_cuts(pc, Vector3(0.75, 3.5, 0.0), MASS, Vector2.ZERO)
	assert_eq(rows.size(), 3 * BotStack.LOWER_ROW)
	var worst: float = INF
	var i: int = 0
	while i < rows.size():
		worst = minf(worst, rows[i + 1])
		i += BotStack.LOWER_ROW
	assert_almost_eq(worst, -0.25, EPS)


func test_piece_cut_patch_and_aim_erosion() -> void:
	_cube(1, 0.0, 0, 0.0, FACE_HALF)
	_analyse()
	var near_edge: PackedVector2Array = PackedVector2Array([Vector2(0.4, 0.0)])
	var plain: BotStack.PieceCut = _stack.piece_cut(near_edge, FACE_HALF, 0.0, 0.0, PackedByteArray())
	assert_true(plain.flat)
	assert_almost_eq(plain.plane_y, 1.0, EPS)
	var box: Rect2 = _bounds(plain.points)
	assert_almost_eq(box.position.x, 0.4 - FACE_HALF, EPS, "the piece's own face edge")
	assert_almost_eq(box.end.x, FACE_HALF, EPS, "the carrier's top edge (collider half-width)")
	var eroded: BotStack.PieceCut = _stack.piece_cut(near_edge, FACE_HALF, 0.0, 0.1, PackedByteArray())
	assert_almost_eq(_bounds(eroded.points).end.x, FACE_HALF - 0.1, EPS, "aim shrinks the carrier's face")
	var easy: BotStack.PieceCut = _stack.piece_cut(PackedVector2Array([Vector2.ZERO]), FACE_HALF, 0.0, 0.5, PackedByteArray())
	assert_eq(easy.points.size(), 0, "a 1x1 top erodes to nothing at aim 0.5")
	assert_eq(easy.supports.size(), 1, "the support is still recorded")


func test_piece_cut_never_erodes_the_disc() -> void:
	_cube(1, 5.0, 0)
	_analyse()
	var pc: BotStack.PieceCut = _stack.piece_cut(PackedVector2Array([Vector2.ZERO]), FACE_HALF, 0.0, 0.5, PackedByteArray())
	assert_true(pc.on_disc)
	assert_eq(pc.points.size(), 4)
	assert_eq(pc.owners[0], -1)
	var none: BotStack.PieceCut = _stack.piece_cut(PackedVector2Array([Vector2.ZERO]), FACE_HALF, 0.0, 0.5, PackedByteArray([0]))
	assert_eq(none.points.size(), 0, "disc_ok = 0 leaves no disc patch")


func test_piece_cut_bridging_two_columns_widens_the_lower_region() -> void:
	_cube(1, -1.0, 0)
	_cube(2, 1.0, 0)
	_analyse()
	var centres: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(0.0, 0.0), Vector2(1.0, 0.0)])
	var pc: BotStack.PieceCut = _stack.piece_cut(centres, HALF, 0.0, 0.0, PackedByteArray())
	assert_eq(pc.supports.size(), 2)
	var com: Vector3 = Vector3(0.0, 1.5, 0.0)
	var rows: PackedFloat32Array = _stack.lower_cuts(pc, com, 3.0 * MASS, Vector2.ZERO)
	var i: int = 0
	while i < rows.size():
		assert_gt(rows[i + 1], 0.0, "a bridge centred between its legs rests on both")
		i += BotStack.LOWER_ROW
	var one_leg: PackedVector2Array = PackedVector2Array([Vector2(-1.0, 0.0), Vector2(0.0, 0.0), Vector2(-2.0, 0.0)])
	var off: BotStack.PieceCut = _stack.piece_cut(one_leg, HALF, 0.0, 0.0, PackedByteArray())
	var off_rows: PackedFloat32Array = _stack.lower_cuts(off, Vector3(-1.0, 1.5, 0.0), 3.0 * MASS, Vector2.ZERO)
	assert_gt(off_rows[1], 0.0, "centred over one leg it stands")
	var tipped: PackedFloat32Array = _stack.lower_cuts(off, Vector3(-2.2, 1.5, 0.0), 3.0 * MASS, Vector2.ZERO)
	assert_lt(tipped[1], 0.0, "the centre of mass past the leg's edge tips")


func test_gravity_shift_moves_the_lower_margin_by_lever_times_shift() -> void:
	_cube(1, 0.0, 0)
	_analyse()
	var pc: BotStack.PieceCut = _stack.piece_cut(PackedVector2Array([Vector2.ZERO]), HALF, 0.0, 0.0, PackedByteArray())
	var com: Vector3 = Vector3(0.0, 1.5, 0.0)
	var flat: PackedFloat32Array = _stack.lower_cuts(pc, com, MASS, Vector2.ZERO)
	var shifted: PackedFloat32Array = _stack.lower_cuts(pc, com, MASS, Vector2(0.1, 0.0))
	assert_almost_eq(flat[1] - shifted[1], 0.1 * flat[3], 0.0001)


func test_cut_memo_and_down_set_cache() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 0.0, 1)
	_cube(3, 3.0, 0)
	_analyse()
	var b: int = _stack.index_of(2)
	assert_same(_stack.cut_of(b), _stack.cut_of(b), "memoised")
	var fresh: BotStack = BotStack.new()
	fresh.cube_size = CUBE
	for i: int in _stack.body_count():
		fresh.add_body(_stack.body_ids[i], 0, Basis.IDENTITY, PackedVector3Array([_stack.cube_pos[i]]), MASS, true)
	fresh.analyse_step(10, _t)
	var a: BotStack.Cut = _stack.cut_of(b)
	var c: BotStack.Cut = fresh.cut_of(fresh.index_of(2))
	assert_eq(a.hull, c.hull)
	assert_eq(a.com, c.com)
	assert_eq(a.margin, c.margin)
	var mixed: PackedInt32Array = PackedInt32Array([_stack.index_of(3), b])
	var swapped: PackedInt32Array = PackedInt32Array([b, _stack.index_of(3)])
	assert_eq(_stack.down_set(mixed).size(), 3)
	assert_eq(_stack.down_set(swapped), _stack.down_set(mixed), "order of the support set does not matter")
	assert_eq(_stack.down_set(PackedInt32Array([b])), _stack.down_set(PackedInt32Array([b])))
	assert_null(_stack.cut_of(99))
	assert_null(BotStack.new().cut_of(0), "null before analysis")


func test_tilted_faces_are_centred_on_the_face() -> void:
	var tilt: Basis = Basis(Vector3.BACK, deg_to_rad(TILT_DEG))
	_body(1, [Vector3(0.0, HALF, 0.0)], tilt, MASS, FACE_HALF)
	_analyse()
	var shift: float = FACE_HALF * sin(deg_to_rad(TILT_DEG))
	var top: Rect2 = _bounds(_stack._top_poly[0])
	var bot: Rect2 = _bounds(_stack._bot_poly[0])
	var top_mid: float = top.position.x + top.size.x * HALF
	var bot_mid: float = bot.position.x + bot.size.x * HALF
	assert_almost_eq(top_mid, -shift, 0.0001, "the top face leans away from the cube centre")
	assert_almost_eq(bot_mid, shift, 0.0001)


func test_face_half_defaults_to_half_a_cube_and_takes_the_collider_value() -> void:
	_cube(1, 0.0, 0)
	_cube(2, 3.0, 0, 0.0, FACE_HALF)
	_analyse()
	assert_almost_eq(_stack.body_face_half[0], HALF, 0.00001)
	assert_almost_eq(_stack.body_face_half[1], FACE_HALF, 0.00001)
	assert_almost_eq(_bounds(_stack._top_poly[1]).size.x, 2.0 * FACE_HALF, 0.0001)
