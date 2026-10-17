extends GutTest
## After a topple Reach the Sky bots stop building on the
## leaning pile. The tower-top site filter keeps unsound tops out, the Reach the Sky plan targets the tallest
## SOUND top (or a new base after a collapse), the generator adds FOUNDATION sites at a new base, and the stack
## analysis now runs before the plan. the new base and its sites no longer keep a clearance from the
## debris; they only never rest on the leaning pile (tests/unit/bots/test_bot_debris_surface.gd covers the rule). Pure: hand-built BotStack snapshots, a synthetic
## raster, no scene tree.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const TEAM: int = 0
const ENEMY: int = 1
const PILE_TILT_DEG: float = 30.0
## The leaning pile: six single-cube bodies on a 3 x 2 grid.
const PILE_ORIGIN: Vector2 = Vector2(-5.0, 1.0)
const PILE_COLUMNS: int = 3
const PILE_ROWS: int = 2
const PILE_CIRCLE_TOP_M: float = 1.5
## The sound stack beside it.
const STACK_XZ: Vector2 = Vector2(-9.0, -4.0)
const BODY_MASS: float = 1.0
const BODY_ID_BASE: int = 100
const CANDIDATE_COUNT: int = 40
const SEED: int = 5454
const STEP_GUARD: int = 800
const BIG_BUDGET_US: int = 60000000
const TOL: float = 0.01
## A column of cubes tall enough to make the numbers below readable.
const PEAK_M: float = 9.0
const SOUND_TOP_M: float = 4.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _strategy_tuning: BotStrategyTuning = preload("res://config/bots/bot_strategy_tuning.tres")

var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _next_id: int = BODY_ID_BASE


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, TEAM, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, ENEMY, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, TEAM, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, ENEMY, _territory_tuning),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.fill_ownership(circles, solver.solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)
	_next_id = BODY_ID_BASE
	BotThink._strategy_memory.clear()


## `circle_specs`: Array of [Vector2 xz, top m]; every one is an own block circle.
func _view(circle_specs: Array, tower_xz: Variant = null, mode: int = MatchConfig.GameMode.REACH_THE_SKY) -> BotWorldView:
	var xs: PackedFloat32Array = PackedFloat32Array([HOME_A.x, HOME_B.x])
	var zs: PackedFloat32Array = PackedFloat32Array([HOME_A.y, HOME_B.y])
	var radii: PackedFloat32Array = PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius])
	var teams: PackedInt32Array = PackedInt32Array([TEAM, ENEMY])
	for spec: Array in circle_specs:
		var xz: Vector2 = spec[0] as Vector2
		xs.append(xz.x)
		zs.append(xz.y)
		radii.append(InfluenceCircle.radius_for_height(float(spec[1]), _territory_tuning, MAP_RADIUS))
		teams.append(TEAM)
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = mode
	if tower_xz != null:
		goal.has_tower = true
		goal.tower_origin = tower_xz as Vector2
	var view: BotWorldView = BotWorldView.build(
		0, TEAM, {"xs": xs, "zs": zs, "radii": radii, "teams": teams}, _slots, _raster,
		PackedVector2Array([Vector2.ZERO]), _territory_tuning.goal_zone_radius, _bar3, _cube, goal,
		PackedVector2Array(), PackedVector2Array()
	)
	return view


func _profile() -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	return profile


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _pile_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for row: int in range(PILE_ROWS):
		for column: int in range(PILE_COLUMNS):
			out.append(PILE_ORIGIN + Vector2(float(column), float(row)) * _physics.cube_size)
	return out


## Adds the tilted pile (unsound) to `stack`.
func _add_pile(stack: BotStack) -> void:
	var tilt: Basis = Basis(Vector3.BACK, deg_to_rad(PILE_TILT_DEG))
	for xz: Vector2 in _pile_positions():
		stack.add_body(
			_next_id, TEAM, tilt, PackedVector3Array([Vector3(xz.x, _physics.cube_size * 0.5, xz.y)]),
			BODY_MASS, true
		)
		_next_id += 1


## Adds an upright column of `count` cubes at `xz` (sound).
func _add_column(stack: BotStack, xz: Vector2, count: int) -> void:
	for level: int in range(count):
		var y: float = (float(level) + 0.5) * _physics.cube_size
		stack.add_body(_next_id, TEAM, Basis.IDENTITY, PackedVector3Array([Vector3(xz.x, y, xz.y)]), BODY_MASS, true)
		_next_id += 1


func _stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = _physics.cube_size
	return stack


func _analysed(stack: BotStack) -> BotStack:
	while not stack.analyse_step(stack.body_count(), BotEvaluator.stack_tuning):
		pass
	return stack


func _pile_circle_specs() -> Array:
	var specs: Array = []
	for xz: Vector2 in _pile_positions():
		specs.append([xz, PILE_CIRCLE_TOP_M])
	return specs


func _choose(view: BotWorldView, memory: Dictionary) -> BotIntent:
	var profile: BotDifficultyProfile = _profile()
	return BotStrategy.choose(view, BotChains.build(view), profile, null, memory)


## replaces the old clearance pins: true when a probe at disk-local `point` hits an unsound
## (leaning pile) block in the snapshot.
func _over_unsound(stack: BotStack, point: Vector2) -> bool:
	var body: int = stack.surface_at(point)
	return body >= 0 and not stack.is_sound(body)


## True when a bottom cube of the piece with its pivot at `origin` stands over an unsound block.
func _rests_on_unsound(stack: BotStack, origin: Vector2, info: BotStatics.OrientationInfo) -> bool:
	for offset: Vector2 in info.contact:
		if _over_unsound(stack, origin + offset * _physics.cube_size):
			return true
	return false


func _clearance_of(point: Vector2) -> float:
	var nearest: float = INF
	for xz: Vector2 in _pile_positions():
		nearest = minf(nearest, xz.distance_to(point))
	return nearest


# --- plan: sound tops --------------------------------------------------------------------------------


func test_the_target_is_the_sound_stack_not_the_pile() -> void:
	var specs: Array = _pile_circle_specs()
	specs.append([STACK_XZ, 2.0])
	# The mode context names the tallest settled block (a pile block): that is the old, wrong target.
	var view: BotWorldView = _view(specs, PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	_add_column(stack, STACK_XZ, 2)
	view.stack = _analysed(stack)
	var intent: BotIntent = _choose(view, {})
	assert_false(intent.new_base, "a sound stack exists: no new base")
	assert_lt(intent.target.distance_to(STACK_XZ), TOL, "the target is the sound stack's top")


func test_a_pile_alone_starts_a_new_base_off_the_debris() -> void:
	var view: BotWorldView = _view(_pile_circle_specs(), PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	view.stack = _analysed(stack)
	var intent: BotIntent = _choose(view, {})
	assert_true(intent.new_base, "no sound top: a new base")
	assert_false(_over_unsound(view.stack, intent.target), "the base does not rest on the leaning pile")
	assert_eq(
		PlacementRules.validate_point(intent.target, _raster, TEAM), PlacementRules.Result.VALID,
		"the base is valid own land"
	)
	assert_gte(view.stack.rest_margin(PackedVector2Array([intent.target]), intent.target, BODY_MASS), 0.0)


func test_tower_top_sites_skip_the_leaning_pile_but_keep_the_sound_stack() -> void:
	var specs: Array = _pile_circle_specs()
	specs.append([STACK_XZ, 2.0])
	var view: BotWorldView = _view(specs, PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	_add_column(stack, STACK_XZ, 2)
	view.stack = _analysed(stack)
	var intent: BotIntent = BotStrategy._make(_strategy_tuning, BotIntent.Kind.ANCHOR, STACK_XZ)
	var on_stack: int = 0
	for site: BotCandidate in BotSiteList.build(view, intent, _profile(), _rng()):
		if site.site_kind != BotCandidateGen.SITE_STACK:
			continue
		var info: BotStatics.OrientationInfo = BotStatics.orientation_info(view.held, site.orientation_index)
		var centre: Vector2 = site.origin + info.center_shift * _physics.cube_size
		assert_gt(_clearance_of(centre), 1.0, "a STACK site never sits on a pile block")
		if centre.distance_to(STACK_XZ) < 1.5:
			on_stack += 1
	assert_gt(on_stack, 0, "the sound stack still gets STACK sites")


# --- plan: memory ------------------------------------------------------------------------------------


func test_the_base_persists_while_the_tower_grows() -> void:
	var memory: Dictionary = {}
	var base_targets: Array[Vector2] = []
	for height: int in range(2, 5):
		var specs: Array = [[STACK_XZ, float(height)]]
		var view: BotWorldView = _view(specs, STACK_XZ)
		var stack: BotStack = _stack()
		_add_column(stack, STACK_XZ, height)
		view.stack = _analysed(stack)
		var intent: BotIntent = _choose(view, memory)
		assert_false(intent.new_base, "no collapse at height %d" % height)
		base_targets.append(intent.target)
	for target: Vector2 in base_targets:
		assert_lt(target.distance_to(STACK_XZ), TOL, "the tower keeps being the target")
	assert_almost_eq(memory["sky_peak"] as float, 4.0, TOL, "the peak follows the top")


func test_a_collapse_moves_the_base() -> void:
	# the grace time has run out (sky_lost), so the collapse starts the new base at once.
	var memory: Dictionary = {
		"sky_base": STACK_XZ, "sky_peak": PEAK_M, "sky_pending": false,
		"sky_lost": _strategy_tuning.collapse_grace_thinks,
	}
	var specs: Array = _pile_circle_specs()
	specs.append([STACK_XZ, SOUND_TOP_M])
	var view: BotWorldView = _view(specs, PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	_add_column(stack, STACK_XZ, int(SOUND_TOP_M))
	view.stack = _analysed(stack)
	var intent: BotIntent = _choose(view, memory)
	assert_true(intent.new_base, "the sound top (4 m) is far under the old peak (9 m)")
	assert_gt(intent.target.distance_to(STACK_XZ), 0.0)
	assert_false(_over_unsound(view.stack, intent.target), "the new base is off the leaning pile")
	assert_true(memory["sky_pending"] as bool, "the new base is remembered")
	# The same snapshot again keeps the same new base (no flip-flop between pieces).
	var again: BotIntent = _choose(view, memory)
	assert_true(again.new_base)
	assert_eq(again.target, intent.target)


func test_a_small_drop_keeps_building_on_the_remaining_stack() -> void:
	var memory: Dictionary = {"sky_base": STACK_XZ, "sky_peak": SOUND_TOP_M + 1.0, "sky_pending": false}
	var specs: Array = _pile_circle_specs()
	specs.append([STACK_XZ, SOUND_TOP_M])
	var view: BotWorldView = _view(specs, PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	_add_column(stack, STACK_XZ, int(SOUND_TOP_M))
	view.stack = _analysed(stack)
	var intent: BotIntent = _choose(view, memory)
	assert_false(intent.new_base)
	assert_lt(intent.target.distance_to(STACK_XZ), TOL)


# --- think wiring ------------------------------------------------------------------------------------


func _flat_probe(_xz: Vector2) -> Dictionary:
	return {"hit": true, "height": 0.0, "own": false, "body": -1}


func test_the_think_analyses_the_stack_first_and_picks_off_the_pile() -> void:
	var view: BotWorldView = _view(_pile_circle_specs(), PILE_ORIGIN)
	var stack: BotStack = _stack()
	_add_pile(stack)
	view.stack = stack
	var think: BotThink = BotThink.new(view, _profile(), _rng())
	think.cell_probe = _flat_probe
	assert_eq(think._phase, BotThink.Phase.STACK, "the analysis runs before the plan")
	var guard: int = 0
	var done: bool = false
	while not done and guard < STEP_GUARD:
		guard += 1
		done = think.step(BIG_BUDGET_US, _flat_probe)
	assert_true(done)
	assert_true(think.intent().new_base, "the plan saw the analysed pile")
	var decision: BotThink.Decision = think.decision()
	assert_eq(decision.kind, BotThink.DecisionKind.PLACE)
	var info: BotStatics.OrientationInfo = BotStatics.orientation_info(view.held, decision.orientation_index)
	assert_false(_rests_on_unsound(view.stack, decision.origin, info), "the piece does not land on the pile")


func _pile_stack_sites(mode: int) -> int:
	var view: BotWorldView = _view(_pile_circle_specs(), PILE_ORIGIN, mode)
	var stack: BotStack = _stack()
	_add_pile(stack)
	view.stack = _analysed(stack)
	var intent: BotIntent = BotStrategy._make(_strategy_tuning, BotIntent.Kind.ANCHOR, PILE_ORIGIN)
	var count: int = 0
	for site: BotCandidate in BotSiteList.build(view, intent, _profile(), _rng()):
		if site.site_kind == BotCandidateGen.SITE_STACK:
			count += 1
	return count


func test_only_reach_the_sky_skips_unsound_tops() -> void:
	assert_gt(_pile_stack_sites(MatchConfig.GameMode.CLASSIC), 0, "Classic keeps the unsound top as a site")
	assert_eq(_pile_stack_sites(MatchConfig.GameMode.REACH_THE_SKY), 0, "Reach the Sky skips it")
