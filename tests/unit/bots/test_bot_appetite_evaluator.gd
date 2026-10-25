extends GutTest
## BotEvaluator.stability_risk and the proxy ordering under a bot's risk appetite. Tunables come
## from the shipped Resources; sites are plain BotCandidates on an open field.

const MAP_RADIUS: float = 45.0
const HOME: Vector2 = Vector2(-30.0, 0.0)
const TARGET: Vector2 = Vector2.ZERO
const FAR_SITE: Vector2 = Vector2(0.0, 30.0)
const LOW_TOP_M: float = 1.0
const SOUND_SLACK: float = 0.3
const UNSOUND_SLACK: float = -0.05
const TOLERANCE: float = 0.001

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _appetite: BotAppetiteTuning = BotAppetite.SHIPPED_TUNING


func _covered_mode() -> int:
	for mode: int in MatchConfig.GameMode.values():
		if mode != MatchConfig.GameMode.REACH_THE_SKY and _appetite.covers(mode):
			return mode
	return MatchConfig.GameMode.CLASSIC


func _view(appetite: BotAppetite, mode: int) -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var circles: Array[InfluenceCircle] = [InfluenceCircle.for_home(HOME, 0, 0, _tuning)]
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), true)
	raster.adopt_fill(raster, 0.1, true, false)
	var slots: Array[PlayerSlot] = [PlayerSlot.new(0, 0, "own", Color.WHITE, HOME)]
	var circle_data: Dictionary = {
		"xs": PackedFloat32Array([HOME.x]), "zs": PackedFloat32Array([HOME.y]),
		"radii": PackedFloat32Array([circles[0].radius]), "teams": PackedInt32Array([0]),
	}
	var view: BotWorldView = BotWorldView.build(
		0, 0, circle_data, slots, raster, PackedVector2Array([TARGET]), _tuning.goal_zone_radius,
		null, null, null, PackedVector2Array(), PackedVector2Array()
	)
	view.mode = mode
	view.appetite = appetite
	return view


func _site(origin: Vector2, top: float, slack: float) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.top_height = top
	c.stability_slack = slack
	return c


func _risk(c: BotCandidate, value: float, mode: int) -> float:
	return BotEvaluator.stability_risk(c, _view(BotAppetite.new(value), mode))


func _tall_top() -> float:
	return _appetite.height_risk_start_m + _appetite.height_risk_span_m


func _reach(c: BotCandidate, view: BotWorldView, intent: BotIntent) -> float:
	return BotEvaluator.proxy_terms(c, view, intent)[BotIntent.Term.REACH]


func _intent(tip_weight: float) -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.target = TARGET
	intent.weights[BotIntent.Term.REACH] = 1.0
	intent.weights[BotIntent.Term.TIP] = tip_weight
	return intent


func _score(c: BotCandidate, view: BotWorldView, intent: BotIntent) -> float:
	return BotEvaluator.score(BotEvaluator.proxy_terms(c, view, intent), intent)


func test_shipped_view_pays_the_topple_penalty_only_when_unsound() -> void:
	var view: BotWorldView = _view(BotAppetite.shipped(), _covered_mode())
	var penalty: float = BotEvaluator.tuning.topple_penalty
	assert_almost_eq(BotEvaluator.stability_risk(_site(FAR_SITE, LOW_TOP_M, UNSOUND_SLACK), view), penalty, TOLERANCE)
	assert_almost_eq(BotEvaluator.stability_risk(_site(FAR_SITE, LOW_TOP_M, 0.0), view), penalty, TOLERANCE, "slack 0 is unsound")
	assert_eq(BotEvaluator.stability_risk(_site(FAR_SITE, LOW_TOP_M, SOUND_SLACK), view), 0.0)
	assert_eq(BotEvaluator.stability_risk(_site(FAR_SITE, LOW_TOP_M, INF), view), 0.0, "unevaluated site")


func test_shipped_view_charges_no_height_risk() -> void:
	var view: BotWorldView = _view(BotAppetite.shipped(), _covered_mode())
	assert_eq(BotEvaluator.stability_risk(_site(FAR_SITE, _tall_top(), SOUND_SLACK), view), 0.0)


func test_a_fresh_view_keeps_the_shipped_charge() -> void:
	var view: BotWorldView = _view(BotAppetite.shipped(), _covered_mode())
	view.appetite = BotWorldView.new().appetite
	assert_almost_eq(BotEvaluator.stability_risk(_site(FAR_SITE, LOW_TOP_M, UNSOUND_SLACK), view), BotEvaluator.tuning.topple_penalty, TOLERANCE)
	assert_eq(BotEvaluator.stability_risk(_site(FAR_SITE, _tall_top(), SOUND_SLACK), view), 0.0)


func test_cautious_bot_pays_at_least_the_topple_penalty_on_an_unsound_site() -> void:
	var risk: float = _risk(_site(FAR_SITE, LOW_TOP_M, UNSOUND_SLACK), 0.0, _covered_mode())
	assert_true(risk >= BotEvaluator.tuning.topple_penalty - TOLERANCE)


func test_bold_bot_pays_less_than_the_cautious_one_on_a_barely_unsound_site() -> void:
	var mode: int = _covered_mode()
	var c: BotCandidate = _site(FAR_SITE, LOW_TOP_M, UNSOUND_SLACK)
	assert_lt(_risk(c, 1.0, mode), _risk(c, 0.0, mode))
	assert_gt(_risk(c, 1.0, mode), 0.0, "still not free")


func test_bold_bot_still_pays_in_full_far_below_the_band() -> void:
	var deep: BotCandidate = _site(FAR_SITE, LOW_TOP_M, -_appetite.unsound_band_m * 2.0)
	assert_almost_eq(_risk(deep, 1.0, _covered_mode()), BotEvaluator.tuning.topple_penalty, TOLERANCE)


func test_sky_charge_is_the_shipped_binary_for_every_appetite() -> void:
	var sky: int = MatchConfig.GameMode.REACH_THE_SKY
	for v: float in [0.0, 0.5, 1.0]:
		assert_almost_eq(_risk(_site(FAR_SITE, _tall_top(), UNSOUND_SLACK), v, sky), BotEvaluator.tuning.topple_penalty, TOLERANCE)
		assert_eq(_risk(_site(FAR_SITE, _tall_top(), SOUND_SLACK), v, sky), 0.0, "no height risk in Sky")


func test_sound_tall_site_costs_more_than_the_same_site_low() -> void:
	var mode: int = _covered_mode()
	var tall: BotCandidate = _site(FAR_SITE, _tall_top(), SOUND_SLACK)
	var low: BotCandidate = _site(FAR_SITE, LOW_TOP_M, SOUND_SLACK)
	for v: float in [0.0, 1.0]:
		assert_gt(_risk(tall, v, mode), _risk(low, v, mode), "appetite %s" % v)


func test_sound_tall_site_costs_a_bold_bot_less() -> void:
	var tall: BotCandidate = _site(FAR_SITE, _tall_top(), SOUND_SLACK)
	var mode: int = _covered_mode()
	assert_lt(_risk(tall, 1.0, mode), _risk(tall, 0.0, mode))


func test_height_is_read_from_support_plus_shape_when_top_is_lower() -> void:
	var mode: int = _covered_mode()
	var via_support: BotCandidate = _site(FAR_SITE, 0.0, SOUND_SLACK)
	via_support.support_height = _tall_top() - 1.0
	via_support.shape_height = 1.0
	var via_top: BotCandidate = _site(FAR_SITE, _tall_top(), SOUND_SLACK)
	assert_almost_eq(_risk(via_support, 0.0, mode), _risk(via_top, 0.0, mode), TOLERANCE)
	assert_gt(_risk(via_support, 0.0, mode), 0.0)


func test_risk_adds_the_fall_charge_and_the_height_risk() -> void:
	var mode: int = _covered_mode()
	var bot: BotAppetite = BotAppetite.new(0.4)
	var view: BotWorldView = _view(bot, mode)
	var c: BotCandidate = _site(FAR_SITE, _tall_top(), UNSOUND_SLACK)
	var expected: float = BotEvaluator.tuning.topple_penalty * bot.fall_probability(UNSOUND_SLACK, mode) + bot.height_risk(_tall_top(), mode)
	assert_almost_eq(BotEvaluator.stability_risk(c, view), expected, TOLERANCE)


func test_proxy_tip_term_carries_the_appetite_charge() -> void:
	var mode: int = _covered_mode()
	var c: BotCandidate = _site(FAR_SITE, LOW_TOP_M, UNSOUND_SLACK)
	var intent: BotIntent = _intent(1.0)
	var cautious: float = BotEvaluator.proxy_terms(c, _view(BotAppetite.new(0.0), mode), intent)[BotIntent.Term.TIP]
	var bold: float = BotEvaluator.proxy_terms(c, _view(BotAppetite.new(1.0), mode), intent)[BotIntent.Term.TIP]
	assert_lt(bold, cautious)


## An unsound site closer to the target wins only when its REACH gain beats the reduced charge.
func test_proxy_ordering_picks_an_unsound_site_only_when_reach_beats_the_charge() -> void:
	var mode: int = _covered_mode()
	var penalty: float = BotEvaluator.tuning.topple_penalty
	var bold_charge: float = penalty * BotAppetite.new(1.0).fall_probability(UNSOUND_SLACK, mode)
	assert_lt(bold_charge, penalty, "precondition: a bold bot is charged less")
	var gain: float = (bold_charge + penalty) * 0.5
	var safe: BotCandidate = _site(FAR_SITE, LOW_TOP_M, SOUND_SLACK)
	var unsound: BotCandidate = _site(FAR_SITE - Vector2(0.0, gain), LOW_TOP_M, UNSOUND_SLACK)
	var intent: BotIntent = _intent(1.0)
	var cautious: BotWorldView = _view(BotAppetite.new(0.0), mode)
	var bold: BotWorldView = _view(BotAppetite.new(1.0), mode)
	var shipped: BotWorldView = _view(BotAppetite.shipped(), mode)
	assert_almost_eq(_reach(unsound, bold, intent) - _reach(safe, bold, intent), gain, TOLERANCE, "precondition: REACH gain")
	assert_gt(_score(safe, cautious, intent), _score(unsound, cautious, intent), "cautious keeps the sound site")
	assert_gt(_score(safe, shipped, intent), _score(unsound, shipped, intent), "shipped keeps the sound site")
	assert_gt(_score(unsound, bold, intent), _score(safe, bold, intent), "bold takes the closer unsound site")


func test_proxy_ordering_picks_a_tall_site_only_when_reach_beats_the_height_risk() -> void:
	var mode: int = _covered_mode()
	var tall: BotCandidate = _site(FAR_SITE, _tall_top(), SOUND_SLACK)
	var low: BotCandidate = _site(FAR_SITE, LOW_TOP_M, SOUND_SLACK)
	var plain: BotIntent = _intent(0.0)
	var cautious: BotWorldView = _view(BotAppetite.new(0.0), mode)
	var bold: BotWorldView = _view(BotAppetite.new(1.0), mode)
	var gain: float = _reach(tall, cautious, plain) - _reach(low, cautious, plain)
	assert_gt(gain, 0.0, "precondition: height extends the reach")
	var cautious_risk: float = cautious.appetite.height_risk(_tall_top(), mode)
	var bold_risk: float = bold.appetite.height_risk(_tall_top(), mode)
	assert_gt(cautious_risk, bold_risk, "precondition: appetite relieves the height risk")
	# Weight the TIP term so the REACH gain lies between the bold and the cautious height charge.
	var intent: BotIntent = _intent(2.0 * gain / (cautious_risk + bold_risk))
	assert_gt(_score(low, cautious, intent), _score(tall, cautious, intent), "cautious stays low")
	assert_gt(_score(tall, bold, intent), _score(low, bold, intent), "bold goes tall")
