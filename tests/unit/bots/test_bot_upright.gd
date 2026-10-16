extends GutTest
## "they always lay blocks flat": in Reach the Sky the stack
## generator also offers the tallest orientations and the evaluator scores the height a placement gains,
## so a bar stands up on a sound top and lies flat only when the tower under it cannot carry it.
## Pure: real CellGrid + TerritoryRaster on a synthetic tower (the test_bot_candidate_gen fixture).

const MAP_RADIUS: float = 20.0
const CELL: float = 0.5
const HOME_A: Vector2 = Vector2(-15.0, 0.0)
const HOME_B: Vector2 = Vector2(15.0, 0.0)
const TOWER_POS: Vector2 = Vector2(-6.0, 3.0)
const TOWER_TOP_M: float = 4.0
const CANDIDATE_COUNT: int = 110
const SEED: int = 99
## DECISION: scripted centre-of-mass headroom of the tower under a site (the safe margin is 0.2 m).
const SOUND_MARGIN_M: float = 1.0
const TOPPLE_MARGIN_M: float = -0.1

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _gen_tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _strategy_tuning: BotStrategyTuning = preload("res://config/bots/bot_strategy_tuning.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _bar5: BlockShape = preload("res://config/blocks/bar5.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]


func _view(held: BlockShape, mode: int) -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
		InfluenceCircle.new(TOWER_POS, InfluenceCircle.radius_for_height(TOWER_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, 1, TOWER_TOP_M),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	raster.fill_ownership(circles, solver.solve(circles), false)
	raster.adopt_fill(raster, 0.1, false, false)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in circles:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	var arrays: Dictionary = {"xs": xs, "zs": zs, "radii": radii, "teams": teams}
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = mode
	goal.has_tower = true
	goal.tower_origin = TOWER_POS
	var view: BotWorldView = BotWorldView.build(
		0, 0, arrays, _slots, raster, PackedVector2Array([Vector2.ZERO]), 0.0, held, held, goal,
		PackedVector2Array(), PackedVector2Array()
	)
	view.mode = mode
	return view


func _intent() -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.kind = BotIntent.Kind.ANCHOR
	intent.target = TOWER_POS
	intent.weights = _strategy_tuning.weights_for(BotIntent.Kind.ANCHOR).duplicate()
	return intent


func _stack_sites(view: BotWorldView, tuning: BotGenTuning) -> Array[BotCandidate]:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array[BotCandidate] = []
	for c: BotCandidate in _site_list(view, _intent(), profile, rng, tuning):
		if c.site_kind == BotCandidateGen.SITE_STACK:
			out.append(c)
	return out


func _best(sites: Array[BotCandidate], view: BotWorldView) -> BotCandidate:
	var best: BotCandidate = null
	var best_score: float = -INF
	for c: BotCandidate in sites:
		var s: float = BotEvaluator.score(BotEvaluator.proxy_terms(c, view, _intent()), _intent())
		if s > best_score:
			best_score = s
			best = c
	return best


func _heights(sites: Array[BotCandidate]) -> Array[float]:
	var seen: Array[float] = []
	for c: BotCandidate in sites:
		if not seen.has(c.shape_height):
			seen.append(c.shape_height)
	seen.sort()
	return seen


func test_reach_the_sky_offers_upright_bar_on_the_tower_top() -> void:
	var view: BotWorldView = _view(_bar3, MatchConfig.GameMode.REACH_THE_SKY)
	var heights: Array[float] = _heights(_stack_sites(view, _gen_tuning))
	assert_true(heights.has(1.0), "the flat bar is still offered: %s" % [heights])
	assert_true(heights.has(3.0), "the upright bar is offered: %s" % [heights])


func test_sound_column_picks_the_bar_upright() -> void:
	for shape: BlockShape in [_bar3, _pillar]:
		var view: BotWorldView = _view(shape, MatchConfig.GameMode.REACH_THE_SKY)
		var picked: BotCandidate = _best(_stack_sites(view, _gen_tuning), view)
		assert_gt(picked.shape_height, 1.0, "%s stands up on a sound top (height %.0f)" % [shape.id, picked.shape_height])


func test_upright_bar5_centred_on_a_sound_top_is_stable_and_pays_no_tip_charge() -> void:
	# height is not a risk; only the centre of mass against the contact patches decides.
	var view: BotWorldView = _view(_bar5, MatchConfig.GameMode.REACH_THE_SKY)
	var info: BotStatics.OrientationInfo = null
	for candidate_info: BotStatics.OrientationInfo in BotStatics.orientation_infos(_bar5, _gen_tuning):
		if info == null or candidate_info.height > info.height:
			info = candidate_info
	assert_eq(info.height, 5.0)
	var c: BotCandidate = BotCandidate.new()
	c.origin = TOWER_POS
	c.orientation_index = info.index
	c.probe_points = BotStatics.contact_probe_points(c, info, view.cube_size, info.contact.size())
	c.cell_support.resize(c.probe_points.size())
	c.cell_support.fill(0.0)
	c.support_bodies.resize(c.probe_points.size())
	c.support_bodies.fill(-1)
	var bot_tuning: BotTuning = load("res://config/bots/bot_tuning.tres") as BotTuning
	var req: BotStability.Requirement = BotStability.requirement(
		bot_tuning.hard, view, BotEvaluator.stack_tuning, bot_tuning.stability_contact_tolerance_m
	)
	c.stability_slack = BotStability.evaluate(c, info, view, req).slack
	assert_gt(c.stability_slack, 0.0, "a centred upright bar5 stands")
	assert_eq(BotEvaluator.stability_risk(c), 0.0, "and pays no TIP charge")


func test_toppling_upright_loses_to_the_flat_piece() -> void:
	var view: BotWorldView = _view(_bar3, MatchConfig.GameMode.REACH_THE_SKY)
	var sites: Array[BotCandidate] = _stack_sites(view, _gen_tuning)
	for c: BotCandidate in sites:
		c.stability_slack = TOPPLE_MARGIN_M if c.shape_height > 1.0 else SOUND_MARGIN_M
	assert_eq(_best(sites, view).shape_height, 1.0, "a toppling upright bar loses to the flat one")


## The sites `BotCandidateGen.begin` builds once its fill has run to the end.
func _site_list(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(view, intent, profile, rng, tuning)
	while not job.fill_step(job.attempts_left()):
		pass
	return job.out
