extends GutTest
## Bontago-1t5.69 (owner playtest 2026-10-14: "they always lay blocks flat"): in Reach the Sky the stack
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

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _gen_tuning: BotGenTuning = preload("res://config/bot_gen_tuning.tres")
var _strategy_tuning: BotStrategyTuning = preload("res://config/bot_strategy_tuning.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _bar4: BlockShape = preload("res://config/blocks/bar4.tres")
var _bar5: BlockShape = preload("res://config/blocks/bar5.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _l4: BlockShape = preload("res://config/blocks/L4.tres")
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
		InfluenceCircle.for_block(TOWER_POS, TOWER_TOP_M, 0, 0, 1, _territory_tuning, MAP_RADIUS),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	raster.update(circles, solver.solve(circles), 0.1, false, false)
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
	goal.tower_height = TOWER_TOP_M
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
	for c: BotCandidate in BotCandidateGen.sites(view, _intent(), profile, rng, tuning):
		if c.site_kind == BotCandidateGen.SITE_STACK:
			out.append(c)
	return out


func _best(sites: Array[BotCandidate], view: BotWorldView) -> BotCandidate:
	var best: BotCandidate = null
	var best_score: float = -INF
	for c: BotCandidate in sites:
		var s: float = BotEvaluator.proxy(c, view, _intent())
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


func test_classic_and_switched_off_keep_flat_first_stack_orientations() -> void:
	var classic: BotWorldView = _view(_bar3, MatchConfig.GameMode.CLASSIC)
	assert_false(_heights(_stack_sites(classic, _gen_tuning)).has(3.0), "classic does not stand the bar up")
	var off: BotGenTuning = _gen_tuning.duplicate() as BotGenTuning
	off.stack_tall_variants = 0
	var sky: BotWorldView = _view(_bar3, MatchConfig.GameMode.REACH_THE_SKY)
	assert_false(_heights(_stack_sites(sky, off)).has(3.0), "stack_tall_variants 0 switches the offer off")


func test_sound_column_picks_the_bar_upright() -> void:
	for shape: BlockShape in [_bar3, _pillar]:
		var view: BotWorldView = _view(shape, MatchConfig.GameMode.REACH_THE_SKY)
		var picked: BotCandidate = _best(_stack_sites(view, _gen_tuning), view)
		assert_gt(picked.shape_height, 1.0, "%s stands up on a sound top (height %.0f)" % [shape.id, picked.shape_height])


func test_bar4_and_bar5_stand_up_on_a_sound_top() -> void:
	# Bontago-1t5.71: slenderness is a soft penalty, not a generation cap (real physics: tests/unit/test_bot_slender_1014.gd).
	for shape: BlockShape in [_bar4, _bar5]:
		var view: BotWorldView = _view(shape, MatchConfig.GameMode.REACH_THE_SKY)
		var sites: Array[BotCandidate] = _stack_sites(view, _gen_tuning)
		var upright: float = float(shape.cells.size())
		assert_true(_heights(sites).has(upright), "upright %s is offered" % shape.id)
		assert_eq(_best(sites, view).shape_height, upright, "%s stands up on a sound top" % shape.id)


func test_upright_bar5_centred_on_a_sound_top_is_stable_and_pays_no_tip_charge() -> void:
	# Bontago-1t5.72: height is not a risk; only the centre of mass against the contact patches decides.
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
	var bot_tuning: BotTuning = load("res://config/bot_tuning.tres") as BotTuning
	var req: BotStability.Requirement = BotStability.requirement(
		bot_tuning.hard_v2, view, BotEvaluator.stack_tuning, bot_tuning.stability_contact_tolerance_m
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


func test_height_term_is_reach_the_sky_only() -> void:
	var sky: BotWorldView = _view(_bar3, MatchConfig.GameMode.REACH_THE_SKY)
	var classic: BotWorldView = _view(_bar3, MatchConfig.GameMode.CLASSIC)
	var c: BotCandidate = BotCandidate.new()
	c.support_height = TOWER_TOP_M
	c.shape_height = 3.0
	c.top_height = TOWER_TOP_M + 3.0
	c.top_area = 1.0
	assert_gt(BotEvaluator.height_gain(c, sky), 0.0, "height is rewarded in Reach the Sky")
	assert_eq(BotEvaluator.height_gain(c, classic), 0.0, "other modes score as before")
	c.top_height = TOWER_TOP_M
	assert_eq(BotEvaluator.height_gain(c, sky), 0.0, "a piece that does not rise above its support gains nothing")


func test_new_base_beside_taller_debris_still_stands_the_bar_up() -> void:
	# The own tallest block (tower_height 4 m) is debris; the new base is a sound 1 m high surface.
	var view: BotWorldView = _view(_bar3, MatchConfig.GameMode.REACH_THE_SKY)
	var base_height: float = 1.0
	var flat: BotCandidate = BotCandidate.new()
	flat.support_height = base_height
	flat.shape_height = 1.0
	flat.top_height = base_height + 1.0
	flat.top_area = 3.0
	var upright: BotCandidate = BotCandidate.new()
	upright.support_height = base_height
	upright.shape_height = 3.0
	upright.top_height = base_height + 3.0
	upright.top_area = 1.0
	assert_gt(BotEvaluator.proxy(upright, view, _intent()), BotEvaluator.proxy(flat, view, _intent()),
		"upright wins on a sound low base even though the debris is taller")


func test_every_orientation_reports_its_top_layer() -> void:
	for info: BotStatics.OrientationInfo in BotStatics.orientation_infos(_l4, _gen_tuning):
		assert_gt(info.top_area, 0.0, "orientation %d has a top layer" % info.index)

