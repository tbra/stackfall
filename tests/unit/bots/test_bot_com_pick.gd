extends GutTest
## BotStack wired into the bot think. The centre of
## mass of the tower under a site decides how the site ranks: a sliced STACK phase analyses the snapshot,
## PROBE fills BotCandidate.stability_slack (BotStability), BotEvaluator.stability_risk adds the topple penalty to
## the TIP term. Pure tests use hand-built BotStack snapshots; the physics tests use a real Field with settled
## blocks and the real column ray (no match, no controller).

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
const SETTLE_FRAMES: int = 90
const LIFT: float = 0.02
const OFFSET_TOP_DX: float = 0.3
const TOL: float = 0.001
const FAR_BLOCK: Vector2 = Vector2(12.0, 5.0)

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _stack_tuning: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")

var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _field: Field = null
var _registry: BlockRegistry = null
var _map_def: MapDef = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
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
	return BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, held, _cube, null, PackedVector2Array(), PackedVector2Array()
	)


func _profile() -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	return profile


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _run(think: BotThink, probe: Callable, budget_us: int) -> int:
	var steps: int = 0
	while steps < STEP_GUARD:
		steps += 1
		if think.step(budget_us, probe):
			break
	return steps


# --- evaluator -----------------------------------------------------------------------------------


func test_a_site_with_a_negative_slack_ranks_below_an_identical_safe_one() -> void:
	var view: BotWorldView = _view(_cube)
	var intent: BotIntent = BotIntent.new()
	intent.kind = BotIntent.Kind.ANCHOR
	intent.target = TOWER
	intent.weights = PackedFloat32Array([1.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0])  # REACH 1, TIP 3 (the tower-building weights)
	var safe_site: BotCandidate = BotCandidate.new()
	safe_site.origin = TOWER
	safe_site.top_height = 4.0
	safe_site.stability_slack = 0.3
	var risky: BotCandidate = BotCandidate.new()
	risky.origin = TOWER
	risky.top_height = 4.0
	risky.stability_slack = -0.05
	var safe_score: float = BotEvaluator.proxy(safe_site, view, intent)
	var risky_score: float = BotEvaluator.proxy(risky, view, intent)
	assert_lt(risky_score, safe_score, "proxy")
	var tip: int = BotIntent.Term.TIP
	var penalty_floor: float = BotEvaluator.tuning.topple_penalty * intent.weights[tip]
	assert_gte(safe_score - risky_score, penalty_floor - TOL, "the topple penalty is paid in full")


# --- think wiring ---------------------------------------------------------------------------------

# --- real bodies -----------------------------------------------------------------------------------


func _make_field() -> void:
	_map_def = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map_def.field_radius = MAP_RADIUS
	_field = autofree(Field.new())
	_field.map_def = _map_def
	add_child_autofree(_field)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	_registry.configure(_field, _map_def)


func _spawn(shape: BlockShape, local: Vector3) -> Block:
	var block: Block = BlockFactory.build(shape, _physics, 0)
	_field.add_child(block)
	block.position = local
	Events.block_placed.emit(block, shape.id)
	return block


## A 3-cube column at TOWER with one more cube on top shifted by OFFSET_TOP_DX, plus a far cube.
func _build_column() -> Array[Block]:
	_make_field()
	var blocks: Array[Block] = []
	for level: int in range(3):
		blocks.append(_spawn(_cube, Vector3(TOWER.x, float(level) * _physics.cube_size + LIFT, TOWER.y)))
	blocks.append(_spawn(_cube, Vector3(TOWER.x + OFFSET_TOP_DX, 3.0 * _physics.cube_size + LIFT, TOWER.y)))
	blocks.append(_spawn(_cube, Vector3(FAR_BLOCK.x, LIFT, FAR_BLOCK.y)))
	await wait_physics_frames(SETTLE_FRAMES)
	return blocks


func _team_of(slot: int) -> int:
	return slot


func test_a_real_probe_think_never_picks_a_toppling_site_when_a_safe_one_exists() -> void:
	var blocks: Array[Block] = await _build_column()
	var view: BotWorldView = _view(_bar3)
	view.stack = BotStackProbe.build(
		_registry, _field, PackedVector2Array([TOWER]), _stack_tuning, _physics.cube_size, _team_of
	)
	var space: PhysicsDirectSpaceState3D = _field.direct_space()
	var ray: Callable = func(xz: Vector2) -> Dictionary:
		var hit: Dictionary = _field.raycast_disk_column(space, xz)
		if hit.is_empty():
			return {"hit": false, "height": 0.0, "own": false, "body": -1}
		var body: Block = hit.get("collider") as Block
		return {
			"hit": true, "height": _field.to_local(hit["position"] as Vector3).y, "own": body != null,
			"body": body.get_instance_id() if body != null else -1,
		}
	var think: BotThink = BotThink.new(view, _profile(), _rng())
	think.cell_probe = ray
	_run(think, ray, BIG_BUDGET_US)
	assert_true(think.is_done())
	var safe_exists: bool = false
	var negative: int = 0
	for c: BotCandidate in think.candidates():
		if c.stability_slack > 0.0:
			safe_exists = true
		else:
			negative += 1
	gut.p("sites=%d negative=%d top block=%s" % [think.candidates().size(), negative, blocks[3].name])
	assert_true(safe_exists)
	if think.best_candidate() != null:
		assert_gt(think.best_candidate().stability_slack, 0.0, "the pick keeps the tower's centre of mass inside its supports")
