extends GutTest
## core/ai/BotStability.gd + the OrientationInfo additions (P1b, STATICS_DESIGN 2.3 and 3): the piece cut
## with aim erosion, the lower cuts, the unknown-block and probe-only paths, the calm requirement. Pure, no scene tree.

const CUBE: float = 1.0
const HALF: float = 0.5
const MASS: float = 2.0
const FACE_HALF: float = 0.49
const EPS: float = 0.001
const AIM: float = 0.3
const UNKNOWN_BODY: int = 9999
const TILT_DEG: float = 20.0
const PROBE_CONTACT: float = 0.15

var _stack_t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _gen_t: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _domino: BlockShape = preload("res://config/blocks/domino.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _view: BotWorldView = null
var _stack: BotStack = null


func before_each() -> void:
	_stack = BotStack.new()
	_stack.cube_size = CUBE
	_view = BotWorldView.new()
	_view.cube_size = CUBE


func _add(id: int, x: float, level: int, basis: Basis = Basis.IDENTITY) -> void:
	var cube: Vector3 = Vector3(x, HALF + float(level) * CUBE, 0.0)
	_stack.add_body(id, 0, basis, PackedVector3Array([cube]), MASS, true, FACE_HALF)


func _analysed() -> void:
	_stack.analyse_step(_stack.body_count() + 1, _stack_t)
	_view.stack = _stack


func _req(aim: float = AIM) -> BotStability.Requirement:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.aim_noise_m = aim
	return BotStability.requirement(profile, _view, _stack_t, PROBE_CONTACT)


func _info(shape: BlockShape, height: float, contact: int) -> BotStatics.OrientationInfo:
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(shape, _gen_t):
		if is_equal_approx(info.height, height) and info.contact.size() == contact:
			return info
	return null


## A candidate whose every bottom cube was probed on `support_height`; `body_id` -1 = the disc.
func _candidate(
	info: BotStatics.OrientationInfo, origin: Vector2, support_height: float, body_id: int
) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.orientation_index = info.index
	c.support_height = support_height
	for offset: Vector2 in info.contact:
		c.probe_points.append(origin + offset * CUBE)
		c.cell_support.append(support_height)
		c.support_bodies.append(body_id)
	return c


func _on_body(
	info: BotStatics.OrientationInfo, origin: Vector2, support_height: float, body_index: int
) -> BotCandidate:
	return _candidate(info, origin, support_height, _stack.body_ids[body_index])


func test_orientation_info_self_margin_and_com_height() -> void:
	var cube: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	assert_almost_eq(cube.self_margin, FACE_HALF, EPS)
	assert_almost_eq(cube.com_height, 0.5, EPS)
	var upright: BotStatics.OrientationInfo = _info(_pillar, 3.0, 1)
	assert_almost_eq(upright.com_height, 1.5, EPS)
	assert_almost_eq(upright.self_margin, FACE_HALF, EPS)
	var tipping: int = 0
	for shape: BlockShape in BlockShape.load_all_shapes():
		for i: int in range(BlockOrientations.count()):
			tipping += 1 if BotStatics.orientation_info(shape, i).self_margin < 0.0 else 0
	assert_gt(tipping, 0, "some orientations have their centre of mass outside their own contact squares")


func test_requirement_is_calm_and_load_scaled() -> void:
	var req: BotStability.Requirement = _req(AIM)
	assert_almost_eq(req.aim_m, AIM * _stack_t.aim_margin_share, EPS)
	assert_almost_eq(req.face_half_m, FACE_HALF, EPS)
	assert_almost_eq(req.probe_contact_m, PROBE_CONTACT, EPS)
	assert_eq(req.gift_m, 0.0)
	assert_null(req.wind_tuning)
	assert_almost_eq(BotStability.required_piece(req, 1.0, 3.0), _stack_t.numeric_tolerance_m, EPS)
	assert_almost_eq(BotStability.required_lower(req, 2.0, 2.0, 1.0, 3.0), _stack_t.numeric_tolerance_m + req.aim_m, EPS)
	assert_almost_eq(
		BotStability.required_lower(req, 8.0, 2.0, 1.0, 3.0), _stack_t.numeric_tolerance_m + req.aim_m * 0.25, EPS
	)


func test_cube_on_the_flat_disc_is_stable_whatever_the_aim() -> void:
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var c: BotCandidate = _candidate(info, Vector2(3.0, 2.0), 0.0, -1)
	_add(1, 20.0, 0)
	_analysed()
	var r: BotStability.Result = BotStability.evaluate(c, info, _view, _req(0.6))
	assert_almost_eq(r.piece_margin, FACE_HALF, EPS, "no erosion on the disc")
	assert_gt(r.slack, 0.0)
	assert_eq(r.binding, BotStability.BINDING_PIECE)
	assert_true(r.known)


func test_aim_erosion_gives_the_exact_margin_on_a_block() -> void:
	_add(1, 0.0, 0)
	_analysed()
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var centred: BotStability.Result = BotStability.evaluate(
		_on_body(info, Vector2.ZERO, CUBE, 0), info, _view, _req()
	)
	assert_almost_eq(centred.piece_margin, FACE_HALF - AIM, EPS, "the top face shrunk by the aim error")
	assert_gt(centred.slack, 0.0)
	assert_almost_eq(centred.plane_y, CUBE, EPS)
	var shifted: BotStability.Result = BotStability.evaluate(
		_on_body(info, Vector2(AIM, 0.0), CUBE, 0), info, _view, _req()
	)
	assert_lt(shifted.slack, 0.0, "a cube dropped 0.3 m off a 1 m block may tip for this aim error")


func test_lower_cut_binds_when_the_load_overhangs_a_carrier() -> void:
	_add(1, 0.0, 0)
	_add(2, 0.45, 1)
	_analysed()
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var r: BotStability.Result = BotStability.evaluate(
		_on_body(info, Vector2(0.9, 0.0), 2.0 * CUBE, 1), info, _view, _req(0.0)
	)
	assert_gt(r.piece_margin, 0.0, "the piece itself sits on its carrier")
	assert_lt(r.slack, 0.0, "but the pair overhangs the base")
	assert_eq(r.binding, _stack.index_of(2), "the cut at body 2: the pair of body 2 and the piece over the base")


func test_tilted_support_rejects() -> void:
	_add(1, 0.0, 0, Basis(Vector3.RIGHT, deg_to_rad(TILT_DEG)))
	_analysed()
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var r: BotStability.Result = BotStability.evaluate(
		_on_body(info, Vector2.ZERO, CUBE, 0), info, _view, _req()
	)
	assert_eq(r.slack, -INF)
	assert_eq(r.binding, BotStability.BINDING_PIECE)


func test_unknown_block_is_assumed_and_marked() -> void:
	_add(1, 20.0, 0)
	_analysed()
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var r: BotStability.Result = BotStability.evaluate(
		_candidate(info, Vector2.ZERO, CUBE, UNKNOWN_BODY), info, _view, _req()
	)
	assert_false(r.known)
	assert_almost_eq(r.piece_margin, FACE_HALF - AIM, EPS, "the unknown block covers the probed square, shrunk by aim")
	assert_gt(r.slack, 0.0)


func test_probe_only_fallback_without_a_snapshot() -> void:
	var info: BotStatics.OrientationInfo = _info(_domino, 1.0, 2)
	var c: BotCandidate = _candidate(info, Vector2.ZERO, 0.0, -1)
	var whole: BotStability.Result = BotStability.evaluate(c, info, _view, _req())
	assert_false(whole.known)
	assert_gt(whole.slack, 0.0, "both cubes on the disc")
	c.cell_support[0] = BotThink.NO_SUPPORT
	var half_hole: BotStability.Result = BotStability.evaluate(c, info, _view, _req())
	assert_lt(half_hole.slack, 0.0, "a hole under one cube leaves the centre of mass over the gap")
	assert_eq(half_hole.binding, BotStability.BINDING_PIECE)


func test_no_supported_cube_is_unstable() -> void:
	var info: BotStatics.OrientationInfo = _info(_cube, 1.0, 1)
	var c: BotCandidate = _candidate(info, Vector2.ZERO, CUBE, -1)
	c.cell_support[0] = BotThink.NO_SUPPORT
	assert_eq(BotStability.evaluate(c, info, _view, _req()).slack, -INF)
