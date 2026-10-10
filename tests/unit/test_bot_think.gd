extends GutTest
## core/ai/BotThink.gd, BotWorldView.gd, BotIntent.gd (Bontago-1t5.19, Bot V2 P1): the
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
const STEP_GUARD: int = 500
const HARD_SITE_COUNT: int = 110
## Generous ceiling for one unsliceable chunk on a loaded machine (a frame is 16700 us).
const CHUNK_LIMIT_US: int = 40000
const SURFACE_HEIGHT: float = 0.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
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
		InfluenceCircle.for_block(BLOCK_CIRCLE_POS, BLOCK_CIRCLE_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)


func _render_arrays() -> Dictionary:
	var block: InfluenceCircle = InfluenceCircle.for_block(
		BLOCK_CIRCLE_POS, BLOCK_CIRCLE_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS
	)
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


func _run_to_done(think: BotThink, budget_us: int) -> int:
	var steps: int = 0
	while steps < STEP_GUARD:
		steps += 1
		if think.step(budget_us, _probe):
			break
	return steps


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


# --- Home circles stripped from the view --------------------------------------

func test_view_strips_home_circles_and_keeps_block_circles() -> void:
	var view: BotWorldView = _view()
	assert_eq(view.circle_count(), 1, "only the block circle survives")
	assert_eq(Vector2(view.cx[0], view.cz[0]), BLOCK_CIRCLE_POS)
	assert_eq(view.cteam[0], 0)
	assert_true(view.has_home)
	assert_eq(view.own_home, HOME_A)
	assert_eq(view.enemy_homes, PackedVector2Array([HOME_B]))
	assert_eq(view.enemy_home_teams, PackedInt32Array([1]))


func test_view_top_height_inverts_the_cone_radius() -> void:
	var view: BotWorldView = _view()
	assert_almost_eq(view.top_height(0), BLOCK_CIRCLE_TOP_M, 0.01)
	assert_eq(view.indices_of_team(0), PackedInt32Array([0]))
	assert_eq(view.indices_of_team(1), PackedInt32Array())


func test_view_enemy_circle_centers_are_enemy_homes_plus_enemy_block_circles() -> void:
	var view: BotWorldView = _view()
	assert_eq(view.enemy_circle_centers(), PackedVector2Array([HOME_B]), "own block circle is not an enemy")
	var arrays: Dictionary = _render_arrays()
	var teams: PackedInt32Array = arrays["teams"] as PackedInt32Array
	teams[2] = 1
	arrays["teams"] = teams
	var enemy_view: BotWorldView = BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array(), 0.0, _cube, null, null,
		PackedVector2Array(), PackedVector2Array()
	)
	assert_eq(enemy_view.enemy_circle_centers().size(), 2)


func test_circle_near_but_not_at_a_home_is_kept() -> void:
	# A render-list circle at the home radius but offset from every home stays.
	var arrays: Dictionary = _render_arrays()
	var xs: PackedFloat32Array = arrays["xs"] as PackedFloat32Array
	xs[2] = HOME_A.x + 0.5
	arrays["xs"] = xs
	var radii: PackedFloat32Array = arrays["radii"] as PackedFloat32Array
	radii[2] = _territory_tuning.home_radius
	arrays["radii"] = radii
	var view: BotWorldView = BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array(), 0.0, _cube, null, null,
		PackedVector2Array(), PackedVector2Array()
	)
	assert_eq(view.circle_count(), 1)


# --- BotThink (Bontago-1t5.23: the assembled V2 pipeline) -----------------------

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


func test_zero_budget_still_progresses_and_returns_false_while_unfinished() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	assert_false(think.step(0, _probe), "a spent budget returns false")
	assert_false(think.is_done())
	var steps: int = _run_to_done(think, 0)
	assert_lt(steps, STEP_GUARD)
	assert_gt(steps, 3, "plan, sites, per-site probes, rank, measure and pick are separate units")
	assert_true(think.is_done())
	assert_true(think.step(0, _probe), "done stays done")


func test_seeded_runs_are_deterministic_whatever_the_budget_slicing() -> void:
	var whole: BotThink = BotThink.new(_view(), _profile(), _rng())
	whole.step(BIG_BUDGET_US, _probe)
	var sliced: BotThink = BotThink.new(_view(), _profile(), _rng())
	_run_to_done(sliced, 0)
	assert_eq(sliced.decision().origin, whole.decision().origin)
	assert_eq(sliced.decision().orientation_index, whole.decision().orientation_index)
	assert_eq(sliced.candidates().size(), whole.candidates().size())
	for i: int in range(whole.candidates().size()):
		assert_eq(sliced.candidates()[i].origin, whole.candidates()[i].origin, "candidate %d" % i)


func test_candidates_carry_v2_fields_and_probe_results() -> void:
	var think: BotThink = BotThink.new(_view(_pillar), _profile(), _rng())
	think.step(BIG_BUDGET_US, _probe)
	var candidate: BotCandidate = think.candidates()[0]
	assert_ne(candidate.site_kind, BotThink.SITE_LEGACY, "targeted sites, not the retired sampler")
	assert_almost_eq(candidate.top_height, candidate.support_height + candidate.shape_height, 0.0001)
	assert_gt(candidate.shape_height, 0.0)
	assert_gt(_probe_calls, think.candidates().size(), "support plus footprint probes")
	assert_eq(candidate.cell_support.size(), mini(3, candidate.footprint_cells.size()))
	assert_gte(candidate.corner_support_hits, 0)
	assert_between(candidate.tip_risk, 0.0, 1.0)


func test_finish_early_decides_from_what_was_gathered() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	think.step(0, _probe)
	think.finish_early()
	assert_true(think.is_done())
	assert_eq(think.decision().kind, BotThink.DecisionKind.PLACE)
	assert_gt(think.candidates().size(), 0)


func test_finish_early_before_any_step_still_plans_and_decides() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	think.finish_early()
	assert_eq(think.decision().kind, BotThink.DecisionKind.PLACE)


func test_decision_terms_are_measured_for_the_top_k_and_proxy_when_k_is_zero() -> void:
	var measured_profile: BotDifficultyProfile = _profile()
	measured_profile.eval_top_k = 4
	var measured: BotThink = BotThink.new(_view(), measured_profile, _rng())
	measured.step(BIG_BUDGET_US, _probe)
	var view: BotWorldView = _view()
	var expected: PackedFloat32Array = BotEvaluator.measure(
		measured.best_candidate(), view, BotChains.build(view), measured.intent()
	)
	assert_eq(measured.decision().terms, expected, "top-k winner carries its measured terms")
	var proxy_profile: BotDifficultyProfile = _profile()
	proxy_profile.eval_top_k = 0
	var proxied: BotThink = BotThink.new(_view(), proxy_profile, _rng())
	proxied.step(BIG_BUDGET_US, _probe)
	assert_eq(
		proxied.decision().terms,
		BotEvaluator.proxy_terms(proxied.best_candidate(), view, proxied.intent()),
		"no measured stage: the proxy terms"
	)


func test_argmax_tier_is_stable_and_pool_tier_varies_with_the_seed() -> void:
	var hard_origins: Dictionary = {}
	var easy_origins: Dictionary = {}
	for seed_value: int in range(12):
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = SEED + seed_value
		var hard: BotDifficultyProfile = _profile()
		hard.eval_top_k = 0
		var easy: BotDifficultyProfile = _profile()
		easy.eval_top_k = 0
		easy.pick_pool = 5
		easy.pick_temperature = 4.0
		var hard_think: BotThink = BotThink.new(_view(), hard, rng)
		hard_think.step(BIG_BUDGET_US, _probe)
		hard_origins[hard_think.decision().origin] = true
		var easy_rng: RandomNumberGenerator = RandomNumberGenerator.new()
		easy_rng.seed = SEED + seed_value
		var easy_think: BotThink = BotThink.new(_view(), easy, easy_rng)
		easy_think.step(BIG_BUDGET_US, _probe)
		easy_origins[easy_think.decision().origin] = true
	assert_lt(hard_origins.size(), 3, "argmax barely depends on the rng (site generation only)")
	assert_gt(easy_origins.size(), 1, "a pool pick varies")


func test_unsliceable_chunks_stay_far_below_a_frame() -> void:
	# PLAN (chains + strategy) and SITES (110 targeted sites) are single chunks; step() only
	# checks the budget between chunks, so each must stay cheap (a frame is 16.7 ms).
	var profile: BotDifficultyProfile = _profile()
	profile.candidate_count = HARD_SITE_COUNT
	var think: BotThink = BotThink.new(_view(), profile, _rng())
	var worst_us: int = 0
	for _chunk: int in range(2):
		var before: int = Time.get_ticks_usec()
		think.step(0, _probe)
		worst_us = maxi(worst_us, Time.get_ticks_usec() - before)
	assert_lt(worst_us, CHUNK_LIMIT_US, "plan and sites chunks (us)")
	assert_gt(think.candidates().size(), 0)


func test_finish_early_mid_probe_ranks_only_probed_sites() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	while think._phase != BotThink.Phase.PROBE:
		think.step(0, _probe)
	for _i: int in range(3):
		think.step(0, _probe)
	var probed: int = think._probe_index
	assert_gt(probed, 0)
	assert_lt(probed, think.candidates().size(), "precondition: still probing")
	think.finish_early()
	for position: int in think._ranked:
		assert_lt(position, probed, "an unprobed site never outranks a probed one")


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


func test_decision_origin_is_revalidated_against_the_live_raster() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	# Drive to the PICK stage, then poison the best-ranked site's cell as a hole.
	while not think.is_done() and think._phase != BotThink.Phase.PICK:
		think.step(0, _probe)
	var first: BotCandidate = think.candidates()[think._ranked[0]]
	var cell: Vector2i = _grid.world_to_cell(first.origin)
	_raster.force_hole_cell(cell.x, cell.y, 1.0, true)
	assert_ne(PlacementRules.validate_point(first.origin, _raster, 0), PlacementRules.Result.VALID, "the poison took")
	think.step(BIG_BUDGET_US, _probe)
	assert_ne(think.decision().origin, first.origin, "the poisoned best site is skipped")
	assert_eq(PlacementRules.validate_point(think.decision().origin, _raster, 0), PlacementRules.Result.VALID)


func test_no_held_shape_waits() -> void:
	var view: BotWorldView = _view()
	view.held = null
	var think: BotThink = BotThink.new(view, _profile(), _rng())
	assert_true(think.step(BIG_BUDGET_US, _probe))
	assert_eq(think.decision().kind, BotThink.DecisionKind.WAIT)
	assert_null(think.best_candidate())


func test_intent_mask_bits_follow_the_kind_enum() -> void:
	var mask: int = (1 << int(BotIntent.Kind.RACE)) | (1 << int(BotIntent.Kind.FINISH))
	assert_true(BotIntent.is_enabled(mask, BotIntent.Kind.RACE))
	assert_true(BotIntent.is_enabled(mask, BotIntent.Kind.FINISH))
	assert_false(BotIntent.is_enabled(mask, BotIntent.Kind.STRIKE))
	assert_eq(BotIntent.new().weights.size(), BotIntent.Term.size())


# --- Gift claim term (Bontago-1t5.25) ------------------------------------------

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


func test_shipped_easy_weighs_gifts_below_normal_and_hard() -> void:
	var tuning: BotTuning = load("res://config/bot_tuning.tres")
	assert_lt(tuning.easy.gift_claim_scale, tuning.normal.gift_claim_scale)
	assert_lt(tuning.easy.gift_claim_scale, tuning.hard.gift_claim_scale)
