extends GutTest
## the evaluator's TIP term reads BotStability.slack. test_bot_think_determinism has no
## snapshot, so this pins one full Reach the Sky think over a scripted sound tower (a stacked-site decision), shows an
## unstable taller top losing to a stable one, and that the topple penalty outweighs the height bonus for every intent.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const TOWER: Vector2 = Vector2(-6.0, 1.0)
const TOWER_TOP_M: float = 3.0
const CANDIDATE_COUNT: int = 40
const SEED: int = 5353
const STEP_GUARD: int = 800
const BIG_BUDGET_US: int = 60000000
const PLATFORM_ID: int = 12
const PEG_ID: int = 11
const PEG_MASS: float = 1.0
const PLATFORM_MASS: float = 3.0
const PINNED_ORIGIN: Vector2 = Vector2(-6.5, 1.0)
const PINNED_ORIENTATION: int = 3
const PINNED_SITE_KIND: int = BotCandidateGen.SITE_STACK
const STABLE_SLACK: float = 0.3
const UNSTABLE_SLACK: float = -0.1
const LOW_HEIGHT: float = 1.0
const TALL_HEIGHT: float = 3.0
const MAX_PIECE_HEIGHT_M: float = 5.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _strategy: BotStrategyTuning = preload("res://config/bots/bot_strategy_tuning.tres")

var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
		InfluenceCircle.new(TOWER, InfluenceCircle.radius_for_height(TOWER_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, 7, TOWER_TOP_M),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.fill_ownership(circles, solver.solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)


func _view(held: BlockShape) -> BotWorldView:
	var block: InfluenceCircle = InfluenceCircle.new(TOWER, InfluenceCircle.radius_for_height(TOWER_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, 7, TOWER_TOP_M)
	var arrays: Dictionary = {
		"xs": PackedFloat32Array([HOME_A.x, HOME_B.x, TOWER.x]),
		"zs": PackedFloat32Array([HOME_A.y, HOME_B.y, TOWER.y]),
		"radii": PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius, block.radius]),
		"teams": PackedInt32Array([0, 1, 0]),
	}
	var view: BotWorldView = BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, held, _cube, null, PackedVector2Array(), PackedVector2Array()
	)
	view.mode = MatchConfig.GameMode.REACH_THE_SKY
	return view


func _stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = _physics.cube_size
	stack.add_body(PEG_ID, 0, Basis.IDENTITY, PackedVector3Array([Vector3(TOWER.x, 0.5, TOWER.y)]), PEG_MASS, true)
	var cubes: PackedVector3Array = PackedVector3Array()
	for i: int in range(3):
		cubes.append(Vector3(TOWER.x - 1.0 + float(i), 1.5, TOWER.y))
	stack.add_body(PLATFORM_ID, 0, Basis.IDENTITY, cubes, PLATFORM_MASS, true)
	return stack


func _probe(xz: Vector2) -> Dictionary:
	if absf(xz.x - TOWER.x) <= 1.5 and absf(xz.y - TOWER.y) <= 0.5:
		return {"hit": true, "height": 2.0, "own": true, "body": PLATFORM_ID}
	return {"hit": true, "height": 0.0, "own": false, "body": -1}


func _think() -> BotThink:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	var view: BotWorldView = _view(_bar3)
	view.stack = _stack()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var think: BotThink = BotThink.new(view, profile, rng)
	think.cell_probe = _probe
	var steps: int = 0
	while steps < STEP_GUARD and not think.step(BIG_BUDGET_US, _probe):
		steps += 1
	return think


func _site(height: float, slack: float) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = TOWER
	c.support_height = TOWER_TOP_M
	c.shape_height = height
	c.top_height = TOWER_TOP_M + height
	c.top_area = 1.0
	c.stability_slack = slack
	return c


func test_a_scripted_tower_think_picks_the_pinned_stable_site() -> void:
	var think: BotThink = _think()
	assert_true(think.is_done())
	var best: BotCandidate = think.best_candidate()
	assert_not_null(best)
	assert_gt(best.stability_slack, 0.0, "the pick is stable under the statics model")
	assert_eq(best.origin, PINNED_ORIGIN, "pinned origin")
	assert_eq(best.orientation_index, PINNED_ORIENTATION, "pinned orientation")
	assert_eq(best.site_kind, PINNED_SITE_KIND, "pinned site kind")


func test_an_unstable_taller_top_loses_to_a_stable_one_in_every_intent() -> void:
	var view: BotWorldView = _view(_bar3)
	for kind: int in BotIntent.Kind.values():
		var intent: BotIntent = BotIntent.new()
		intent.kind = kind as BotIntent.Kind
		intent.target = TOWER
		intent.weights = _strategy.weights_for(kind).duplicate()
		intent.weights.resize(BotIntent.Term.size())
		var stable: BotCandidate = _site(LOW_HEIGHT, STABLE_SLACK)
		var unstable: BotCandidate = _site(TALL_HEIGHT, UNSTABLE_SLACK)
		assert_gt(
			BotEvaluator.score(BotEvaluator.proxy_terms(stable, view, intent), intent), BotEvaluator.score(BotEvaluator.proxy_terms(unstable, view, intent), intent),
			"%s: the stable site outranks the taller unstable one" % BotIntent.Kind.keys()[kind]
		)


func test_the_topple_penalty_outweighs_the_largest_height_bonus_for_every_intent() -> void:
	var view: BotWorldView = _view(_bar3)
	var base: BotCandidate = _site(LOW_HEIGHT, STABLE_SLACK)
	var tallest: BotCandidate = _site(MAX_PIECE_HEIGHT_M, STABLE_SLACK)
	var reach_gain: float = (
		BotEvaluator.future_radius(tallest, view) - BotEvaluator.future_radius(base, view)
		+ BotEvaluator.height_gain(tallest, view)
	)
	for kind: int in BotIntent.Kind.values():
		var weights: PackedFloat32Array = _strategy.weights_for(kind)
		var tip_weight: float = weights[BotIntent.Term.TIP]
		var reach_weight: float = weights[BotIntent.Term.REACH]
		var label: String = String(BotIntent.Kind.keys()[kind])
		assert_gt(tip_weight, 0.0, "%s weighs TIP" % label)
		assert_gt(
			BotEvaluator.tuning.topple_penalty * tip_weight, reach_weight * reach_gain,
			"%s: an unstable site cannot buy its way back with height" % label
		)
