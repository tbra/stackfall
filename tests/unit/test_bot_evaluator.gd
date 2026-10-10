extends GutTest
## core/ai/BotEvaluator.gd (Bontago-1t5.22, Bot V2 P3): proxy and measured terms on a
## synthetic two-team map: kill on an enemy snake joint, reach of a tall tip stack,
## waste inside own land, exposure inside enemy reach, no kill under HoleMode.OFF.
## Pure: a real CellGrid/TerritoryRaster, no scene tree.

const MAP_RADIUS: float = 45.0
const OWN_HOME: Vector2 = Vector2(-30.0, 0.0)
const ENEMY_HOME: Vector2 = Vector2(30.0, 0.0)
const BLOCK_TOP_M: float = 1.0
const TALL_TOP_M: float = 6.0
const HUGE_TOP_M: float = 8.0
const TARGET: Vector2 = Vector2.ZERO
const ENEMY_X: Array[float] = [22.0, 18.0, 14.0, 10.0]
const OWN_X: Array[float] = [-23.0, -19.0, -15.0, -11.0]
const JOINT_INDEX: int = 1
const TIP_INDEX: int = 3
const JOINT_DOWNSTREAM: int = 3
const TIGHT_OFFSET: float = 2.5
const AHEAD_STEP_M: float = 2.0
const NEAR_ENEMY: Vector2 = Vector2(12.5, 0.0)
const FAR_FROM_ENEMY: Vector2 = Vector2(-20.0, 15.0)
const OPEN_FIELD: Vector2 = Vector2(0.0, 30.0)
const DEEP_OWN: Vector2 = Vector2(-28.0, 1.0)
const RISKY: float = 0.5
const TOLERANCE: float = 0.001

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _view: BotWorldView = null
var _chains: BotChains = null


func _circles() -> Array[InfluenceCircle]:
	var out: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(OWN_HOME, 0, 0, _tuning),
		InfluenceCircle.for_home(ENEMY_HOME, 1, 1, _tuning),
	]
	for x: float in OWN_X:
		out.append(InfluenceCircle.for_block(Vector2(x, 0.0), BLOCK_TOP_M, 0, 0, 1, _tuning, MAP_RADIUS))
	for x: float in ENEMY_X:
		out.append(InfluenceCircle.for_block(Vector2(x, 0.0), BLOCK_TOP_M, 1, 1, 2, _tuning, MAP_RADIUS))
	return out


## Builds view + chains + raster; `off_mode` selects the argmax fill and the OFF goal context.
func _build(off_mode: bool) -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var circles: Array[InfluenceCircle] = _circles()
	raster.update(circles, TerritorySolver.new(_tuning).solve(circles), 0.1, not off_mode, false)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in circles:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	var slots: Array[PlayerSlot] = [
		PlayerSlot.new(0, 0, "own", Color.WHITE, OWN_HOME),
		PlayerSlot.new(1, 1, "enemy", Color.WHITE, ENEMY_HOME),
	]
	var goal: BotModeGoal = null
	if off_mode:
		goal = BotModeGoal.new()
		goal.no_overlap_mode = true
		goal.home_radius = _tuning.home_radius
	_view = BotWorldView.build(
		0, 0, {"xs": xs, "zs": zs, "radii": radii, "teams": teams}, slots, raster,
		PackedVector2Array([TARGET]), _tuning.goal_zone_radius, null, null, goal,
		PackedVector2Array(), PackedVector2Array()
	)
	_chains = BotChains.build(_view)


func _intent(weights: Dictionary) -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.target = TARGET
	for term: int in weights:
		intent.weights[term] = float(weights[term])
	return intent


func _site(origin: Vector2, top: float, risk: float = 0.0) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.top_height = top
	c.tip_risk = risk
	return c


func _measured(c: BotCandidate, intent: BotIntent, term: int) -> float:
	return BotEvaluator.measure(c, _view, _chains, intent)[term]


func _proxied(c: BotCandidate, intent: BotIntent, term: int) -> float:
	return BotEvaluator.proxy_terms(c, _view, intent)[term]


func test_view_strips_homes_and_chains_see_both_snakes() -> void:
	_build(false)
	assert_eq(_view.circle_count(), OWN_X.size() + ENEMY_X.size(), "only block circles remain")
	assert_eq(_chains.downstream(OWN_X.size() + JOINT_INDEX), JOINT_DOWNSTREAM, "enemy joint downstream")


func test_kill_equals_downstream_when_site_covers_enemy_joint() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.KILL: 1.0})
	var joint: Vector2 = Vector2(ENEMY_X[JOINT_INDEX], TIGHT_OFFSET)
	var tip: Vector2 = Vector2(ENEMY_X[TIP_INDEX], TIGHT_OFFSET)
	var on_joint: BotCandidate = _site(joint, BLOCK_TOP_M)
	var on_tip: BotCandidate = _site(tip, BLOCK_TOP_M)
	assert_almost_eq(_measured(on_joint, intent, BotIntent.Term.KILL), float(JOINT_DOWNSTREAM), TOLERANCE, "joint kill = downstream")
	assert_almost_eq(_measured(on_tip, intent, BotIntent.Term.KILL), 1.0, TOLERANCE, "tip kill = 1 circle")
	assert_almost_eq(_proxied(on_joint, intent, BotIntent.Term.KILL), 1.0, TOLERANCE, "proxy counts the covered circle")


func test_tall_tip_stack_beats_flat_pieces_on_reach() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.REACH: 1.0})
	var tip: Vector2 = Vector2(OWN_X[TIP_INDEX], 0.0)
	var tall_at_tip: BotCandidate = _site(tip, TALL_TOP_M)
	var flat_ahead: BotCandidate = _site(tip + Vector2(AHEAD_STEP_M, 0.0), BLOCK_TOP_M)
	var flat_behind: BotCandidate = _site(Vector2(OWN_X[TIP_INDEX - 1], 0.0), BLOCK_TOP_M)
	var reach_tall: float = _measured(tall_at_tip, intent, BotIntent.Term.REACH)
	var reach_ahead: float = _measured(flat_ahead, intent, BotIntent.Term.REACH)
	var reach_behind: float = _measured(flat_behind, intent, BotIntent.Term.REACH)
	assert_gt(reach_tall, reach_ahead, "tall tip stack out-reaches a flat piece ahead")
	assert_gt(reach_ahead, reach_behind, "a flat piece ahead beats one behind the tip")
	assert_almost_eq(reach_behind, 0.0, TOLERANCE, "behind the tip adds no reach")
	assert_gt(BotEvaluator.proxy(tall_at_tip, _view, intent), BotEvaluator.proxy(flat_ahead, _view, intent), "proxy order: tall over flat ahead")
	assert_gt(BotEvaluator.proxy(flat_ahead, _view, intent), BotEvaluator.proxy(flat_behind, _view, intent), "proxy order: ahead over behind")


func test_deep_inside_own_land_is_waste_with_no_area() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.AREA: 1.0, BotIntent.Term.WASTE: 1.0})
	var buried: BotCandidate = _site(DEEP_OWN, BLOCK_TOP_M)
	var open: BotCandidate = _site(OPEN_FIELD, BLOCK_TOP_M)
	assert_almost_eq(_measured(buried, intent, BotIntent.Term.AREA), 0.0, TOLERANCE, "no area gain inside own circles")
	assert_almost_eq(_measured(buried, intent, BotIntent.Term.WASTE), 1.0, TOLERANCE, "fully wasted")
	assert_gt(_measured(open, intent, BotIntent.Term.AREA), 0.0, "open field adds area")
	assert_almost_eq(_measured(open, intent, BotIntent.Term.WASTE), 0.0, TOLERANCE, "open field is not waste")
	assert_almost_eq(_proxied(buried, intent, BotIntent.Term.WASTE), 1.0, TOLERANCE, "proxy flags waste")
	assert_lt(BotEvaluator.proxy(buried, _view, intent), BotEvaluator.proxy(open, _view, intent), "score prefers the open field")


func test_exposure_inside_enemy_reach_only() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.EXPOSURE: 1.0})
	var near: BotCandidate = _site(NEAR_ENEMY, BLOCK_TOP_M)
	var far: BotCandidate = _site(FAR_FROM_ENEMY, BLOCK_TOP_M)
	assert_gt(_measured(near, intent, BotIntent.Term.EXPOSURE), 0.0, "measured exposure near the enemy snake")
	assert_almost_eq(_measured(far, intent, BotIntent.Term.EXPOSURE), 0.0, TOLERANCE, "none far away")
	assert_gt(_proxied(near, intent, BotIntent.Term.EXPOSURE), 0.0, "proxy exposure near the enemy snake")
	assert_lt(BotEvaluator.proxy(near, _view, intent), BotEvaluator.proxy(far, _view, intent), "exposure lowers the score")


func test_tip_risk_is_a_penalty() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.TIP: 2.0})
	var steady: BotCandidate = _site(OPEN_FIELD, BLOCK_TOP_M, 0.0)
	var risky: BotCandidate = _site(OPEN_FIELD, BLOCK_TOP_M, RISKY)
	assert_lt(BotEvaluator.proxy(risky, _view, intent), BotEvaluator.proxy(steady, _view, intent), "tip risk subtracts")


func test_off_mode_has_no_kill_term() -> void:
	_build(true)
	var intent: BotIntent = _intent({BotIntent.Term.KILL: 1.0, BotIntent.Term.AREA: 1.0})
	var on_joint: BotCandidate = _site(Vector2(ENEMY_X[JOINT_INDEX], TIGHT_OFFSET), HUGE_TOP_M)
	assert_almost_eq(_measured(on_joint, intent, BotIntent.Term.KILL), 0.0, TOLERANCE, "no kill under HoleMode.OFF")
	assert_almost_eq(_proxied(on_joint, intent, BotIntent.Term.KILL), 0.0, TOLERANCE, "no proxy kill either")
	assert_gt(_measured(on_joint, intent, BotIntent.Term.AREA), 0.0, "a taller kernel still wins cells")
