extends GutTest
## Bontago-1t5.41: V2 bots read the active wind and avoid tall exposed placements in it.

const STORM: StormTuning = preload("res://config/weather/storm.tres")
const TOLERANCE: float = 0.0001
const LOW_TOP_M: float = 2.0
const TALL_TOP_M: float = 9.0
const TIP_RISK_WEIGHT: float = 3.0
const REACH_WEIGHT: float = 0.2
const TARGET: Vector2 = Vector2(30.0, 0.0)
const TALL_ORIGIN: Vector2 = Vector2(2.0, 0.0)
const LOW_ORIGIN: Vector2 = Vector2(1.0, 0.0)


func _view(windy: bool) -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.team_id = 0
	view.field_radius = 40.0
	if windy:
		view.weather_id = WeatherIds.STORM
		view.weather_intensity = 1.0
		view.wind_tuning = STORM
	return view


func _site(origin: Vector2, top: float) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.top_height = top
	return c


func _intent() -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.target = TARGET
	intent.weights[BotIntent.Term.TIP] = TIP_RISK_WEIGHT
	intent.weights[BotIntent.Term.REACH] = REACH_WEIGHT
	return intent


func test_wind_prefers_low_over_tall_that_calm_preferred() -> void:
	var intent: BotIntent = _intent()
	var tall: BotCandidate = _site(TALL_ORIGIN, TALL_TOP_M)
	var low: BotCandidate = _site(LOW_ORIGIN, LOW_TOP_M)
	var calm: BotWorldView = _view(false)
	assert_gt(BotEvaluator.proxy(tall, calm, intent), BotEvaluator.proxy(low, calm, intent), "calm prefers tall")
	var storm: BotWorldView = _view(true)
	assert_gt(BotEvaluator.proxy(low, storm, intent), BotEvaluator.proxy(tall, storm, intent), "storm prefers low")
	assert_eq(BotEvaluator.wind_tip(low, storm), 0.0, "below the wind threshold nothing is added")
	assert_gt(BotEvaluator.wind_tip(tall, storm), 0.0, "a tall stack is exposed")


# --- Bontago-1t5.46: Breeze gusts and wind direction ---

const BREEZE: BreezeTuning = preload("res://config/breeze/breeze.tres")
const GUST_CENTRE: Vector3 = Vector3(0.0, 6.0, 0.0)
const GUST_RADIUS_M: float = 6.0
const FAR_M: float = 20.0
const LIVE_RADIUS_M: float = 20.0

var _saved_tuning: BotEvalTuning = null


func before_each() -> void:
	_saved_tuning = BotEvaluator.tuning
	BotEvaluator.tuning = _saved_tuning.duplicate() as BotEvalTuning


func after_each() -> void:
	BotEvaluator.tuning = _saved_tuning


func _gusty(heading: Vector2 = Vector2.RIGHT, power: float = 1.0) -> BotWorldView:
	var view: BotWorldView = _view(false)
	view.add_gust(GUST_CENTRE, GUST_RADIUS_M, heading, power)
	view.breeze_tuning = BREEZE
	return view


func test_inside_gust_is_penalised_outside_is_not() -> void:
	var view: BotWorldView = _gusty()
	var inside: BotCandidate = _site(Vector2(1.0, 0.0), TALL_TOP_M)
	var outside: BotCandidate = _site(Vector2(FAR_M, 0.0), TALL_TOP_M)
	assert_gt(BotEvaluator.breeze_tip(inside, view), 0.0)
	assert_eq(BotEvaluator.breeze_tip(outside, view), 0.0)
	var intent: BotIntent = _intent()
	assert_lt(BotEvaluator.proxy(inside, view, intent) - BotEvaluator.proxy(inside, _view(false), intent), 0.0)


func test_storm_heading_grades_rim_side_only() -> void:
	var view: BotWorldView = _view(true)
	view.live_radius = LIVE_RADIUS_M
	var rim: BotCandidate = _site(Vector2(LIVE_RADIUS_M - 1.0, 0.0), TALL_TOP_M)
	var plain: float = BotEvaluator.wind_tip(rim, view)
	view.wind_dir = Vector2.LEFT
	assert_almost_eq(BotEvaluator.wind_tip(rim, view), plain, TOLERANCE, "wind blowing inward changes nothing")
	view.wind_dir = Vector2.RIGHT
	assert_gt(BotEvaluator.wind_tip(rim, view), plain, "wind blowing at the rim is worse")
	var centre: BotCandidate = _site(Vector2.ZERO, TALL_TOP_M)
	view.wind_dir = Vector2.ZERO
	var unknown: float = BotEvaluator.wind_tip(centre, view)
	view.wind_dir = Vector2.RIGHT
	assert_almost_eq(BotEvaluator.wind_tip(centre, view), unknown, TOLERANCE, "central site unchanged")
