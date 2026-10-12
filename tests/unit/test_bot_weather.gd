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
