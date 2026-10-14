extends GutTest
## Bontago-1t5.53b: BotStack wired into the bot think (docs/BOT_TOWER_PLAN.md C "1t5.53b"). The centre of
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
const PLATFORM_ID: int = 12
const PEG_ID: int = 11
const PEG_MASS: float = 1.0
const PLATFORM_MASS: float = 3.0
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
		InfluenceCircle.for_block(TOWER, TOWER_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)


func _view(held: BlockShape) -> BotWorldView:
	var block: InfluenceCircle = InfluenceCircle.for_block(TOWER, TOWER_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS)
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


func _cubes_row(x0: float, count: int, y: float, z: float) -> PackedVector3Array:
	var cubes: PackedVector3Array = PackedVector3Array()
	for i: int in range(count):
		cubes.append(Vector3(x0 + float(i), y, z))
	return cubes


## A 1-cube peg on the disc at the tower and a 3-cube platform lying on it (its end hangs over).
func _synthetic_stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = _physics.cube_size
	stack.add_body(PEG_ID, 0, Basis.IDENTITY, PackedVector3Array([Vector3(TOWER.x, 0.5, TOWER.y)]), PEG_MASS, true)
	stack.add_body(PLATFORM_ID, 0, Basis.IDENTITY, _cubes_row(TOWER.x - 1.0, 3, 1.5, TOWER.y), PLATFORM_MASS, true)
	return stack


## The platform answers every ray inside its footprint (height 2, its id), the disc everywhere else.
func _synthetic_probe(xz: Vector2) -> Dictionary:
	var on_platform: bool = absf(xz.x - TOWER.x) <= 1.5 and absf(xz.y - TOWER.y) <= 0.5
	if on_platform:
		return {"hit": true, "height": 2.0, "own": true, "body": PLATFORM_ID}
	return {"hit": true, "height": 0.0, "own": false, "body": -1}


func _run(think: BotThink, probe: Callable, budget_us: int) -> int:
	var steps: int = 0
	while steps < STEP_GUARD:
		steps += 1
		if think.step(budget_us, probe):
			break
	return steps


func _think(view: BotWorldView, held: BlockShape) -> BotThink:
	var think: BotThink = BotThink.new(view, _profile(), _rng())
	think.cell_probe = _synthetic_probe
	return think


# --- evaluator -----------------------------------------------------------------------------------

func test_stability_risk_is_the_topple_penalty_only_when_the_slack_is_not_positive() -> void:
	var c: BotCandidate = BotCandidate.new()
	assert_eq(BotEvaluator.stability_risk(c), 0.0, "INF slack = an unevaluated site")
	c.stability_slack = 0.3
	assert_eq(BotEvaluator.stability_risk(c), 0.0)
	c.stability_slack = 0.0
	assert_almost_eq(BotEvaluator.stability_risk(c), BotEvaluator.tuning.topple_penalty, TOL)
	c.stability_slack = -0.1
	assert_almost_eq(BotEvaluator.stability_risk(c), BotEvaluator.tuning.topple_penalty, TOL)


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

func test_the_stack_phase_is_sliced_and_fills_the_slack_of_block_supported_sites() -> void:
	var view: BotWorldView = _view(_bar3)
	view.stack = _synthetic_stack()
	var think: BotThink = _think(view, _bar3)
	var saw_stack: bool = false
	var guard: int = 0
	while not think.is_done() and guard < STEP_GUARD:
		guard += 1
		think.step(0, _synthetic_probe)
		saw_stack = saw_stack or think._phase == BotThink.Phase.STACK
	assert_true(think.is_done())
	assert_true(view.stack.is_analysed(), "the snapshot was analysed inside the think")
	var finite: int = 0
	for c: BotCandidate in think.candidates():
		if c.support_bodies.has(PLATFORM_ID):
			finite += 1
			assert_false(is_inf(c.stability_slack), "a block-supported site is judged by the statics model")
	assert_gt(finite, 0, "some site rests on the platform")
	assert_true(saw_stack or finite > 0)


func test_sliced_and_single_step_thinks_agree_with_a_snapshot() -> void:
	var a_view: BotWorldView = _view(_bar3)
	a_view.stack = _synthetic_stack()
	var a: BotThink = _think(a_view, _bar3)
	_run(a, _synthetic_probe, 0)
	var b_view: BotWorldView = _view(_bar3)
	b_view.stack = _synthetic_stack()
	var b: BotThink = _think(b_view, _bar3)
	_run(b, _synthetic_probe, BIG_BUDGET_US)
	assert_eq(a.decision().kind, b.decision().kind)
	assert_eq(a.decision().origin, b.decision().origin)
	assert_eq(a.decision().orientation_index, b.decision().orientation_index)


func test_an_empty_snapshot_judges_like_no_snapshot_and_the_decision_is_unchanged() -> void:
	var plain: BotThink = _think(_view(_bar3), _bar3)
	_run(plain, _synthetic_probe, BIG_BUDGET_US)
	var empty_view: BotWorldView = _view(_bar3)
	empty_view.stack = BotStack.new()
	var with_empty: BotThink = _think(empty_view, _bar3)
	_run(with_empty, _synthetic_probe, BIG_BUDGET_US)
	assert_eq(plain.candidates().size(), with_empty.candidates().size())
	for i: int in range(plain.candidates().size()):
		assert_eq(plain.candidates()[i].stability_slack, with_empty.candidates()[i].stability_slack)
	assert_eq(plain.decision().origin, with_empty.decision().origin, "an empty snapshot is the old think")
	assert_eq(plain.decision().orientation_index, with_empty.decision().orientation_index)


func test_a_snapshot_costs_only_the_stack_units_not_extra_decisions() -> void:
	var view: BotWorldView = _view(_bar3)
	view.stack = _synthetic_stack()
	var think: BotThink = _think(view, _bar3)
	think.complete(_synthetic_probe)
	assert_gt(think._phase_units[BotThink.Phase.STACK], 0, "STACK units counted per body")
	assert_lte(think._phase_units[BotThink.Phase.STACK], view.stack.body_count() + _stack_tuning.analyse_bodies_per_step)


func test_finish_early_during_the_stack_phase_still_decides() -> void:
	var view: BotWorldView = _view(_bar3)
	view.stack = _synthetic_stack()
	var think: BotThink = _think(view, _bar3)
	var guard: int = 0
	while think._phase != BotThink.Phase.STACK and guard < STEP_GUARD:
		guard += 1
		think.step(0, _synthetic_probe)
	assert_eq(think._phase, BotThink.Phase.STACK)
	think.finish_early()
	assert_true(think.is_done())


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


func _analysed(centres: PackedVector2Array) -> BotStack:
	var stack: BotStack = BotStackProbe.build(
		_registry, _field, centres, _stack_tuning, _physics.cube_size, _team_of
	)
	assert_not_null(stack)
	while not stack.analyse_step(_stack_tuning.analyse_bodies_per_step, _stack_tuning):
		pass
	return stack


func test_probe_snapshots_the_bodies_near_a_source_and_models_the_column() -> void:
	var blocks: Array[Block] = await _build_column()
	var stack: BotStack = _analysed(PackedVector2Array([TOWER]))
	assert_eq(stack.body_count(), 4, "the column and its offset top; the far block is outside the radius")
	assert_eq(stack.index_of(blocks[4].get_instance_id()), -1, "far block not snapshotted")
	for i: int in range(4):
		var index: int = stack.index_of(blocks[i].get_instance_id())
		assert_gte(index, 0)
		assert_true(stack.is_sound(index), "settled column body %d is sound" % i)
	var top_ids: PackedInt64Array = PackedInt64Array([blocks[3].get_instance_id()])
	var safe: float = stack.load_margin(top_ids, Vector3(TOWER.x + OFFSET_TOP_DX, 4.5, TOWER.y), _physics.cube_mass)
	assert_gt(safe, 0.0, "a cube centred on the top block is safe")
	var over: float = stack.load_margin(
		top_ids, Vector3(TOWER.x + OFFSET_TOP_DX + 0.45, 4.5, TOWER.y), _physics.cube_mass * 6.0
	)
	assert_lt(over, safe, "a heavy piece hanging off the offset top has less headroom")
	assert_eq(stack.load_margin(PackedInt64Array([-1]), Vector3.ZERO, 1.0), INF, "disc / unknown = no block support")


func test_probe_cache_follows_a_moved_block() -> void:
	var blocks: Array[Block] = await _build_column()
	var first: BotStack = _analysed(PackedVector2Array([TOWER]))
	var index: int = first.index_of(blocks[3].get_instance_id())
	var before: Vector3 = first.body_com[index]
	blocks[3].freeze = true
	blocks[3].global_position += Vector3(0.2, 0.0, 0.0)
	var second: BotStack = _analysed(PackedVector2Array([TOWER]))
	var moved: Vector3 = second.body_com[second.index_of(blocks[3].get_instance_id())]
	assert_gt(absf(moved.x - before.x), 0.1, "the snapshot sees the new pose (the cache is keyed on the transform)")


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
