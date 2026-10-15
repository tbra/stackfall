extends GutTest
## BotStability disturbance allowance and tilted disc (Bontago-1t5.72.6, STATICS_DESIGN 2.6 and 3.1). Pure.

const CUBE: float = 1.0
const EPS: float = 0.001
const G: float = 9.8
const PROBE_CONTACT: float = 0.15
const LEVER: float = 1.5
const TOP_HIGH: float = 12.0
const TOP_LOW: float = 2.0
const TILT_SLOPE: float = 0.1

var _stack_t: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _storm: StormTuning = preload("res://config/weather/storm.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _gen_t: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _view: BotWorldView = null


func before_each() -> void:
	_view = BotWorldView.new()
	_view.cube_size = CUBE


func _req(aim: float = 0.0) -> BotStability.Requirement:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.aim_noise_m = aim
	return BotStability.requirement(profile, _view, _stack_t, PROBE_CONTACT)


func _storm_view(intensity: float) -> void:
	_view.wind_tuning = _storm
	_view.weather_intensity = intensity
	_view.gravity_local = Vector3.DOWN * G


func test_storm_allowance_is_lever_times_accel_ratio_at_the_cut_top() -> void:
	_storm_view(1.0)
	var req: BotStability.Requirement = _req()
	assert_almost_eq(req.wind_accel_ratio, _storm.max_accel / G, EPS)
	var expected: float = _stack_t.numeric_tolerance_m + _storm.max_accel / G * LEVER
	assert_almost_eq(BotStability.required_piece(req, LEVER, TOP_HIGH + _storm.cap_height_m), expected, EPS)
	assert_almost_eq(
		BotStability.required_lower(req, 8.0, 2.0, LEVER, _storm.cap_height_m + 1.0),
		_stack_t.numeric_tolerance_m + req.aim_m * 0.25 + _storm.max_accel / G * LEVER, EPS
	)


func test_gift_allowance_only_when_gifts_are_on() -> void:
	assert_eq(_req().gift_m, 0.0)
	_view.gifts_enabled = true
	var req: BotStability.Requirement = _req()
	assert_almost_eq(req.gift_m, _stack_t.gift_disturbance_m, EPS)
	assert_almost_eq(
		BotStability.required_piece(req, LEVER, TOP_LOW), _stack_t.numeric_tolerance_m + _stack_t.gift_disturbance_m, EPS
	)
	assert_almost_eq(
		BotStability.required_lower(req, 2.0, 2.0, LEVER, TOP_LOW),
		_stack_t.numeric_tolerance_m + _stack_t.gift_disturbance_m, EPS
	)


func test_tilted_disc_moves_the_piece_margin_by_lever_times_shift() -> void:
	var info: BotStatics.OrientationInfo = null
	for i: BotStatics.OrientationInfo in BotStatics.orientation_infos(_cube, _gen_t):
		info = i
		break
	var c: BotCandidate = BotCandidate.new()
	c.origin = Vector2.ZERO
	c.orientation_index = info.index
	c.support_height = 0.0
	for offset: Vector2 in info.contact:
		c.probe_points.append(offset * CUBE)
		c.cell_support.append(0.0)
		c.support_bodies.append(-1)
	var level: BotStability.Result = BotStability.evaluate(c, info, _view, _req())
	_view.gravity_local = Vector3(TILT_SLOPE * G, -G, 0.0)
	var tilted: BotStability.Result = BotStability.evaluate(c, info, _view, _req())
	assert_almost_eq(level.piece_margin - tilted.piece_margin, TILT_SLOPE * info.com_height * CUBE, EPS)
