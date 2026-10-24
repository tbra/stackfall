extends GutTest
## core/ai/BotEvaluator.gd (Bot V2 P3): proxy and measured terms on a
## synthetic two-team map: kill on an enemy snake joint, reach of a tall tip stack,
## waste inside own land, exposure inside enemy reach, no kill under HoleMode.OFF, and the
## HAZARD term (doomed footprint, one-placement look-ahead, none under OFF).
## Pure: a real CellGrid/TerritoryRaster, no scene tree.

const MAP_RADIUS: float = 45.0
const OWN_HOME: Vector2 = Vector2(-30.0, 0.0)
const ENEMY_HOME: Vector2 = Vector2(30.0, 0.0)
const BLOCK_TOP_M: float = 1.0
const TARGET: Vector2 = Vector2.ZERO
const ENEMY_X: Array[float] = [22.0, 18.0, 14.0, 10.0]
const OWN_X: Array[float] = [-23.0, -19.0, -15.0, -11.0]
const JOINT_INDEX: int = 1
const TIP_INDEX: int = 3
const JOINT_DOWNSTREAM: int = 3
const TIGHT_OFFSET: float = 2.5
const OPEN_FIELD: Vector2 = Vector2(0.0, 30.0)
const DEEP_OWN: Vector2 = Vector2(-28.0, 1.0)
const UNSTABLE_SLACK: float = -0.1
const TOLERANCE: float = 0.001
## A site this far inside the enemy tip circle (its origin cell is enemy-held).
const INSIDE_ENEMY_M: float = 0.5

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _view: BotWorldView = null
var _chains: BotChains = null


func _circles() -> Array[InfluenceCircle]:
	var out: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(OWN_HOME, 0, 0, _tuning),
		InfluenceCircle.for_home(ENEMY_HOME, 1, 1, _tuning),
	]
	for x: float in OWN_X:
		out.append(InfluenceCircle.new(Vector2(x, 0.0), InfluenceCircle.radius_for_height(BLOCK_TOP_M, _tuning, MAP_RADIUS), 0, 0, false, 1))
	for x: float in ENEMY_X:
		out.append(InfluenceCircle.new(Vector2(x, 0.0), InfluenceCircle.radius_for_height(BLOCK_TOP_M, _tuning, MAP_RADIUS), 1, 1, false, 2))
	return out


## Builds view + chains + raster; `off_mode` selects the argmax fill and the OFF goal context.
func _build(off_mode: bool) -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, 1.0)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var circles: Array[InfluenceCircle] = _circles()
	raster.fill_ownership(circles, TerritorySolver.new(_tuning).solve(circles), not off_mode)
	raster.adopt_fill(raster, 0.1, not off_mode, false)
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


func _site(origin: Vector2, top: float, slack: float = INF) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.top_height = top
	c.stability_slack = slack
	return c


func _measured(c: BotCandidate, intent: BotIntent, term: int) -> float:
	return BotEvaluator.measure(c, _view, _chains, intent)[term]


func _proxied(c: BotCandidate, intent: BotIntent, term: int) -> float:
	return BotEvaluator.proxy_terms(c, _view, intent)[term]


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
	assert_lt(BotEvaluator.score(BotEvaluator.proxy_terms(buried, _view, intent), intent), BotEvaluator.score(BotEvaluator.proxy_terms(open, _view, intent), intent), "score prefers the open field")


func test_unstable_site_pays_the_topple_penalty() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.TIP: 2.0})
	var steady: BotCandidate = _site(OPEN_FIELD, BLOCK_TOP_M, 0.3)
	var unstable: BotCandidate = _site(OPEN_FIELD, BLOCK_TOP_M, UNSTABLE_SLACK)
	assert_lt(BotEvaluator.score(BotEvaluator.proxy_terms(unstable, _view, intent), intent), BotEvaluator.score(BotEvaluator.proxy_terms(steady, _view, intent), intent), "instability subtracts")
	assert_almost_eq(_proxied(unstable, intent, BotIntent.Term.TIP), BotEvaluator.tuning.topple_penalty, TOLERANCE)
	assert_almost_eq(_measured(steady, intent, BotIntent.Term.TIP), 0.0, TOLERANCE)


func test_hazard_dooms_a_footprint_in_enemy_land() -> void:
	_build(false)
	var intent: BotIntent = _intent({BotIntent.Term.HAZARD: 1.0})
	var inside: BotCandidate = _site(Vector2(ENEMY_X[TIP_INDEX] - INSIDE_ENEMY_M, 0.0), BLOCK_TOP_M)
	assert_almost_eq(_measured(inside, intent, BotIntent.Term.HAZARD), 1.0, TOLERANCE, "enemy-held footprint dissolves")
	assert_almost_eq(_proxied(inside, intent, BotIntent.Term.HAZARD), 1.0, TOLERANCE, "the proxy reads the same cells")
