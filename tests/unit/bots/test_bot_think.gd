extends GutTest
## core/ai/BotThink.gd, BotWorldView.gd, BotIntent.gd (Bot V2 P1): the
## resumable legacy-equivalent think-cycle driven by a fake physics probe, plus the
## world view's home-circle stripping. Pure: a real CellGrid/TerritoryRaster, no scene tree.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const BLOCK_CIRCLE_POS: Vector2 = Vector2(-6.0, 1.0)
const BLOCK_CIRCLE_TOP_M: float = 3.0
const CANDIDATE_COUNT: int = 30
const SEED: int = 4242
## Generous: only proves a long budget finishes in one step.
const BIG_BUDGET_US: int = 60000000
const SURFACE_HEIGHT: float = 0.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")

var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _probe_calls: int = 0


func before_each() -> void:
	_probe_calls = 0
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
		InfluenceCircle.new(BLOCK_CIRCLE_POS, InfluenceCircle.radius_for_height(BLOCK_CIRCLE_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, 7, BLOCK_CIRCLE_TOP_M),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.fill_ownership(circles, solver.solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)


func _render_arrays() -> Dictionary:
	var block: InfluenceCircle = InfluenceCircle.new(BLOCK_CIRCLE_POS, InfluenceCircle.radius_for_height(BLOCK_CIRCLE_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, 7, BLOCK_CIRCLE_TOP_M)
	return {
		"xs": PackedFloat32Array([HOME_A.x, HOME_B.x, BLOCK_CIRCLE_POS.x]),
		"zs": PackedFloat32Array([HOME_A.y, HOME_B.y, BLOCK_CIRCLE_POS.y]),
		"radii": PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius, block.radius]),
		"teams": PackedInt32Array([0, 1, 0]),
	}


func _view(held: BlockShape = null) -> BotWorldView:
	return BotWorldView.build(
		0, 0, _render_arrays(), _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, held if held != null else _cube, _pillar, null,
		PackedVector2Array(), PackedVector2Array()
	)


func _profile() -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 3
	return profile


func _probe(_xz: Vector2) -> Dictionary:
	_probe_calls += 1
	return {"hit": true, "height": SURFACE_HEIGHT, "own": false}


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


# --- Home circles stripped from the view --------------------------------------

# --- BotThink (the assembled V2 pipeline) -----------------------


func test_unlimited_budget_finishes_in_one_step_with_a_valid_place_decision() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	assert_true(think.step(BIG_BUDGET_US, _probe))
	assert_true(think.is_done())
	var decision: BotThink.Decision = think.decision()
	assert_eq(decision.kind, BotThink.DecisionKind.PLACE)
	assert_gt(think.candidates().size(), 0)
	assert_lte(think.candidates().size(), CANDIDATE_COUNT)
	assert_not_null(think.best_candidate())
	assert_eq(decision.origin, think.best_candidate().origin)
	assert_eq(PlacementRules.validate_point(decision.origin, _raster, 0), PlacementRules.Result.VALID)
	assert_eq(decision.terms.size(), BotIntent.Term.size())
	assert_eq(decision.intent, int(think.intent().kind))


func test_goal_gap_inside_finish_range_plans_a_finish() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	think.step(BIG_BUDGET_US, _probe)
	assert_eq(think.intent().kind, BotIntent.Kind.FINISH)
	assert_eq(think.intent().target, Vector2.ZERO)


func test_revalidate_falls_back_when_the_choice_became_invalid_after_the_think() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	think.step(BIG_BUDGET_US, _probe)
	var first: BotCandidate = think.best_candidate()
	var cell: Vector2i = _grid.world_to_cell(first.origin)
	_raster.force_hole_cell(cell.x, cell.y, 1.0, true)
	var second: BotCandidate = think.revalidate()
	assert_not_null(second)
	assert_ne(second.origin, first.origin)
	assert_eq(think.decision().origin, second.origin)
	assert_eq(PlacementRules.validate_point(second.origin, _raster, 0), PlacementRules.Result.VALID)


# --- Gift claim term ------------------------------------------

const GIFT_TEST_VALUE: float = 100.0
const GIFT_PROBE_STEP_M: float = 0.5


func _gift_view(gifts: PackedVector2Array) -> BotWorldView:
	return BotWorldView.build(
		0, 0, _render_arrays(), _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, _cube, _pillar, null, PackedVector2Array(), gifts
	)


func _gift_think(gifts: PackedVector2Array, scale: float) -> BotThink:
	var profile: BotDifficultyProfile = _profile()
	profile.gift_claim_scale = scale
	var think: BotThink = BotThink.new(_gift_view(gifts), profile, _rng())
	var strategy: BotStrategyTuning = BotStrategyTuning.new()
	strategy.gift_claim_value = GIFT_TEST_VALUE
	think.strategy_tuning = strategy
	return think


## A point beyond the frontier (not own territory) that `c`'s new circle covers but the
## baseline pick's circle does not.
func _gift_point_for(c: BotCandidate, baseline: BotCandidate, view: BotWorldView) -> Variant:
	var radius: float = BotEvaluator.future_radius(c, view)
	var reach: float = GIFT_PROBE_STEP_M
	while reach < radius - 1.0:
		for dir: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			var p: Vector2 = c.origin + dir * reach
			var cell: Vector2i = _grid.world_to_cell(p)
			if not _grid.in_bounds(cell.x, cell.y) or _raster.team_at(cell.x, cell.y) == 0:
				continue
			if baseline.origin.distance_to(p) > BotEvaluator.future_radius(baseline, view):
				return p
		reach += GIFT_PROBE_STEP_M
	return null


func test_v2_targets_a_reachable_unclaimed_gift_over_a_plain_placement() -> void:
	var base: BotThink = _gift_think(PackedVector2Array(), 1.0)
	base.step(BIG_BUDGET_US, _probe)
	var baseline: BotCandidate = base.best_candidate()
	assert_not_null(baseline)
	var view: BotWorldView = _gift_view(PackedVector2Array())
	var gift: Variant = null
	for c: BotCandidate in base.candidates():
		if c != baseline:
			gift = _gift_point_for(c, baseline, view)
			if gift != null:
				break
	assert_not_null(gift, "fixture: a candidate must reach a non-own cell the baseline does not")
	if gift == null:
		return
	var with_gift: BotThink = _gift_think(PackedVector2Array([gift as Vector2]), 1.0)
	with_gift.step(BIG_BUDGET_US, _probe)
	var chosen: BotCandidate = with_gift.best_candidate()
	assert_not_null(chosen)
	assert_lte(
		chosen.origin.distance_to(gift as Vector2), BotEvaluator.future_radius(chosen, view),
		"the pick's new circle must cover the gift"
	)
	# Scale 0 (a tier that ignores gifts) keeps the plain pick.
	var ignoring: BotThink = _gift_think(PackedVector2Array([gift as Vector2]), 0.0)
	ignoring.step(BIG_BUDGET_US, _probe)
	assert_eq(ignoring.best_candidate().origin, baseline.origin)
