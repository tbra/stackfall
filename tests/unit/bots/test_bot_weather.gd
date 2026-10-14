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


func test_calm_weather_scores_unchanged() -> void:
	var intent: BotIntent = _intent()
	var tall: BotCandidate = _site(TALL_ORIGIN, TALL_TOP_M)
	var plain: BotWorldView = _view(false)
	assert_eq(BotEvaluator.wind_tip(tall, plain), 0.0, "no wind, no extra tip")
	var calm_storm: BotWorldView = _view(true)
	calm_storm.weather_intensity = 0.0
	assert_eq(
		BotEvaluator.proxy(tall, calm_storm, intent), BotEvaluator.proxy(tall, plain, intent),
		"zero intensity scores bit-identically"
	)
	var rain: BotWorldView = _view(false)
	rain.weather_id = &"rain"
	rain.weather_intensity = 1.0
	assert_eq(BotEvaluator.proxy(tall, rain, intent), BotEvaluator.proxy(tall, plain, intent), "rain has no wind term")


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


func test_wind_scales_with_intensity() -> void:
	var tall: BotCandidate = _site(TALL_ORIGIN, TALL_TOP_M)
	var storm: BotWorldView = _view(true)
	var full: float = BotEvaluator.wind_tip(tall, storm)
	storm.weather_intensity = 0.5
	assert_almost_eq(BotEvaluator.wind_tip(tall, storm), full * 0.5, TOLERANCE, "linear in intensity")


# --- Bontago-1t5.46: Breeze gusts and wind direction ---

const BREEZE: BreezeTuning = preload("res://config/weather/breeze.tres")
const GUST_CENTRE: Vector3 = Vector3(0.0, 6.0, 0.0)
const GUST_RADIUS_M: float = 6.0
const OFFSET_M: float = 3.0
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


func test_no_gust_adds_nothing() -> void:
	var tall: BotCandidate = _site(Vector2(OFFSET_M, 0.0), TALL_TOP_M)
	assert_eq(BotEvaluator.breeze_tip(tall, _view(false)), 0.0)
	var intent: BotIntent = _intent()
	var empty: BotWorldView = _view(false)
	empty.breeze_tuning = BREEZE
	assert_eq(BotEvaluator.proxy(tall, empty, intent), BotEvaluator.proxy(tall, _view(false), intent))


func test_inside_gust_is_penalised_outside_is_not() -> void:
	var view: BotWorldView = _gusty()
	var inside: BotCandidate = _site(Vector2(1.0, 0.0), TALL_TOP_M)
	var outside: BotCandidate = _site(Vector2(FAR_M, 0.0), TALL_TOP_M)
	assert_gt(BotEvaluator.breeze_tip(inside, view), 0.0)
	assert_eq(BotEvaluator.breeze_tip(outside, view), 0.0)
	var intent: BotIntent = _intent()
	assert_lt(BotEvaluator.proxy(inside, view, intent) - BotEvaluator.proxy(inside, _view(false), intent), 0.0)


func test_downwind_site_scores_worse_than_upwind() -> void:
	var view: BotWorldView = _gusty()
	var down: BotCandidate = _site(Vector2(OFFSET_M, 0.0), TALL_TOP_M)
	var up: BotCandidate = _site(Vector2(-OFFSET_M, 0.0), TALL_TOP_M)
	assert_gt(BotEvaluator.breeze_tip(down, view), BotEvaluator.breeze_tip(up, view), "lee side is graded worse")
	BotEvaluator.tuning.breeze_lee_gain = 0.0
	assert_almost_eq(BotEvaluator.breeze_tip(down, view), BotEvaluator.breeze_tip(up, view), TOLERANCE, "no lee gain = host sphere")


func test_gust_ignores_low_pieces_and_scales_with_power_and_weight() -> void:
	var view: BotWorldView = _gusty()
	var site: Vector2 = Vector2(1.0, 0.0)
	assert_eq(BotEvaluator.breeze_tip(_site(site, LOW_TOP_M), view), 0.0, "below the Breeze threshold")
	var tall: BotCandidate = _site(site, TALL_TOP_M)
	var full: float = BotEvaluator.breeze_tip(tall, view)
	assert_almost_eq(BotEvaluator.breeze_tip(tall, _gusty(Vector2.RIGHT, 0.5)), full * 0.5, TOLERANCE)
	BotEvaluator.tuning.breeze_tip_weight = 0.0
	assert_eq(BotEvaluator.breeze_tip(tall, view), 0.0)


func test_gust_power_peaks_then_fades_then_expires() -> void:
	assert_almost_eq(BotWorldView.gust_power(0.8, 0.0, 2.0), 0.8, TOLERANCE, "young gust counts at its peak")
	assert_almost_eq(BotWorldView.gust_power(1.0, 1.0, 2.0), 1.0, TOLERANCE)
	var late: float = BotWorldView.gust_power(1.0, 1.8, 2.0)
	assert_gt(late, 0.0)
	assert_lt(late, 1.0)
	assert_eq(BotWorldView.gust_power(1.0, 2.0, 2.0), 0.0)
	assert_eq(BotWorldView.gust_power(1.0, 0.0, 0.0), 0.0)


func test_downwind_rim_factor() -> void:
	var view: BotWorldView = _view(false)
	view.live_radius = LIVE_RADIUS_M
	assert_almost_eq(BotEvaluator.downwind_rim_factor(Vector2(LIVE_RADIUS_M, 0.0), Vector2.RIGHT, view), 1.0, TOLERANCE)
	var near: Vector2 = Vector2(LIVE_RADIUS_M - 1.0, 0.0)
	assert_gt(BotEvaluator.downwind_rim_factor(near, Vector2.RIGHT, view), 0.0)
	assert_eq(BotEvaluator.downwind_rim_factor(near, Vector2.LEFT, view), 0.0, "open disc downwind")
	assert_eq(BotEvaluator.downwind_rim_factor(near, Vector2.ZERO, view), 0.0, "unknown heading")
	view.live_radius = 0.0
	assert_eq(BotEvaluator.downwind_rim_factor(near, Vector2.RIGHT, view), 0.0, "unknown radius")


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


func test_gust_heading_toward_rim_is_worse() -> void:
	var toward: BotWorldView = _gusty(Vector2.RIGHT)
	var away: BotWorldView = _gusty(Vector2.LEFT)
	toward.live_radius = LIVE_RADIUS_M
	away.live_radius = LIVE_RADIUS_M
	toward.gust_center[0] = Vector3(LIVE_RADIUS_M - 1.0, 6.0, 0.0)
	away.gust_center[0] = Vector3(LIVE_RADIUS_M - 1.0, 6.0, 0.0)
	var rim: BotCandidate = _site(Vector2(LIVE_RADIUS_M - 1.0, 0.0), TALL_TOP_M)
	BotEvaluator.tuning.breeze_lee_gain = 0.0
	assert_gt(BotEvaluator.breeze_tip(rim, toward), BotEvaluator.breeze_tip(rim, away))
