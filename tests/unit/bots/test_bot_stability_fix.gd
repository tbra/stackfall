extends GutTest
## Bontago-1t5.72.10: the aim error erodes the merged support region once (not each cube top), and a contact the host
## would lift on is never ignored. Pure, no scene tree.

const CUBE: float = 1.0
const HALF: float = 0.5
const MASS: float = 2.0
const FACE_HALF: float = 0.49
const EASY_AIM: float = 0.5
const SLIVER_M: float = 0.05
const PROBE_CONTACT: float = 0.15

var _stack_t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _gen_t: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _view: BotWorldView = null
var _stack: BotStack = null


func before_each() -> void:
	_stack = BotStack.new()
	_stack.cube_size = CUBE
	_view = BotWorldView.new()
	_view.cube_size = CUBE


## One body of `size` x `size` cubes on the disc, its corner cube centred at x = z = 0.
func _plate(id: int, size: int, x0: float = 0.0, levels: int = 1) -> void:
	var cubes: PackedVector3Array = PackedVector3Array()
	for level: int in levels:
		for i: int in size:
			for j: int in size:
				cubes.append(Vector3(x0 + float(i) * CUBE, HALF + float(level) * CUBE, float(j) * CUBE))
	_stack.add_body(id, 0, Basis.IDENTITY, cubes, MASS, true, FACE_HALF)


func _analysed() -> void:
	_stack.analyse_step(_stack.body_count() + 1, _stack_t)
	_view.stack = _stack


func _req(aim: float) -> BotStability.Requirement:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.aim_noise_m = aim
	return BotStability.requirement(profile, _view, _stack_t, PROBE_CONTACT)


func _cube_info() -> BotStatics.OrientationInfo:
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(_cube, _gen_t):
		if info.contact.size() == 1:
			return info
	return null


## A cube candidate at `origin` probed at `support_height` on body `body_id` (-1 = disc).
func _candidate(origin: Vector2, support_height: float, body_id: int) -> BotCandidate:
	var info: BotStatics.OrientationInfo = _cube_info()
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.orientation_index = info.index
	c.support_height = support_height
	for offset: Vector2 in info.contact:
		c.probe_points.append(origin + offset * CUBE)
		c.cell_support.append(support_height)
		c.support_bodies.append(body_id)
	return c


func _judge(c: BotCandidate, aim: float) -> BotStability.Result:
	return BotStability.evaluate(c, _cube_info(), _view, _req(aim))


func test_easy_on_a_1x1_top_is_refused() -> void:
	_plate(1, 1)
	_analysed()
	var r: BotStability.Result = _judge(_candidate(Vector2.ZERO, CUBE, 1), EASY_AIM)
	assert_lt(r.slack, 0.0)


func test_erosion_keeps_the_exposed_edge() -> void:
	# A piece 0.4 m off the centre of a 2x2 top is inside at aim 0.3 on the exposed side, outside at 0.5.
	_plate(1, 2)
	_analysed()
	var edge_piece: Vector2 = Vector2(HALF + 0.6, HALF)
	assert_lt(_judge(_candidate(edge_piece, CUBE, 1), EASY_AIM).slack, 0.0, "com 0.1 m from the exposed edge")
	assert_gt(_judge(_candidate(Vector2(HALF + 0.3, HALF), CUBE, 1), EASY_AIM).slack, 0.0)


func test_sliver_overlap_the_host_lifts_on_sets_the_plane() -> void:
	# A cube on the disc whose footprint clips a 2-cube column by 5 cm: the host lifts it onto the column, so it
	# never rests "on the disc" and it tips off the sliver.
	_plate(1, 1, 0.0, 2)
	_analysed()
	var x: float = 2.0 * FACE_HALF - SLIVER_M
	var r: BotStability.Result = _judge(_candidate(Vector2(x, 0.0), 0.0, -1), 0.0)
	assert_almost_eq(r.plane_y, 2.0 * CUBE, 0.001, "plane is the column top, not the disc")
	assert_lt(r.slack, 0.0, "slack %f" % r.slack)
