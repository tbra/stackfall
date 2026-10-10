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


# --- BotThink ------------------------------------------------------------------

func test_unlimited_budget_finishes_in_one_step_with_a_valid_place_decision() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	assert_true(think.step(BIG_BUDGET_US, _probe))
	assert_true(think.is_done())
	var decision: BotThink.Decision = think.decision()
	assert_eq(decision.kind, BotThink.DecisionKind.PLACE)
	assert_eq(think.candidates().size(), CANDIDATE_COUNT)
	assert_not_null(think.best_candidate())
	assert_eq(decision.origin, think.best_candidate().origin)
	assert_eq(PlacementRules.validate_point(decision.origin, _raster, 0), PlacementRules.Result.VALID)


func test_zero_budget_still_progresses_and_returns_false_while_unfinished() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	assert_false(think.step(0, _probe), "a spent budget returns false")
	assert_eq(think.candidates().size(), 1, "exactly one candidate of progress")
	assert_false(think.is_done())
	var steps: int = _run_to_done(think, 0)
	assert_lt(steps, STEP_GUARD)
	assert_eq(think.candidates().size(), CANDIDATE_COUNT)
	assert_true(think.is_done())
	assert_true(think.step(0, _probe), "done stays done")


func test_seeded_runs_are_deterministic_whatever_the_budget_slicing() -> void:
	var whole: BotThink = BotThink.new(_view(), _profile(), _rng())
	whole.step(BIG_BUDGET_US, _probe)
	var sliced: BotThink = BotThink.new(_view(), _profile(), _rng())
	_run_to_done(sliced, 0)
	assert_eq(sliced.decision().origin, whole.decision().origin)
	assert_eq(sliced.decision().orientation_index, whole.decision().orientation_index)
	for i: int in range(CANDIDATE_COUNT):
		assert_eq(sliced.candidates()[i].origin, whole.candidates()[i].origin, "candidate %d" % i)


func test_candidates_carry_v2_fields_and_probe_results() -> void:
	var think: BotThink = BotThink.new(_view(_pillar), _profile(), _rng())
	think.step(BIG_BUDGET_US, _probe)
	var candidate: BotCandidate = think.candidates()[0]
	assert_eq(candidate.site_kind, BotThink.SITE_LEGACY)
	assert_almost_eq(candidate.top_height, candidate.support_height + candidate.shape_height, 0.0001)
	assert_gt(candidate.shape_height, 0.0)
	assert_gt(_probe_calls, CANDIDATE_COUNT, "support plus footprint probes")
	assert_eq(candidate.cell_support.size(), mini(3, candidate.footprint_cells.size()))
	assert_gte(candidate.corner_support_hits, 0)


func test_finish_early_decides_from_candidates_gathered_so_far() -> void:
	var think: BotThink = BotThink.new(_view(), _profile(), _rng())
	think.step(0, _probe)
	think.finish_early()
	assert_true(think.is_done())
	assert_eq(think.decision().kind, BotThink.DecisionKind.PLACE)
	assert_eq(think.candidates().size(), 1)


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
