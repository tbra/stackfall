extends GutTest
## ("they will occasionally just abandon a tower and start a new one").
## Every path in BotStrategy._plan_sound_tower that leaves the remembered tower for a new base is pinned here with a
## scripted snapshot. Triggers found (before the fix each started a new base at once):
##  T1 an unsound block on top of the tower (a leaning piece, a stray) left sound_tops empty (a body with ANYTHING
##     on it is no top);
##  T2 the top moved more than base_match_radius_m from the remembered base (a long bar on a wide tower);
##  T3 one transient unsound frame (a block tilted past max_tilt_deg for a moment: sway, an impact) took the
##     whole chain above it out of the sound set;
##  T4 any top loss of collapse_drop_m, however tall the tower still was.
## Not triggers (checked): another own tower becoming taller (the plan only follows tops near the base), unsettled
## bodies (the last plan is reused), the 1t5.68 support-face rule (it only gates NEW bases).
## Pure: hand-built BotStack snapshots like test_bot_sound_base.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const TEAM: int = 0
const ENEMY: int = 1
const BASE_XZ: Vector2 = Vector2(-9.0, -4.0)
const OTHER_XZ: Vector2 = Vector2(-9.0, 4.0)
const BODY_MASS: float = 1.0
const BODY_ID_BASE: int = 100
const TILT_DEG: float = 10.0
const TOL: float = 0.01
const TALL: int = 20
const LOSS_TO: int = 16
const BAR_CUBES: int = 6

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _tuning: BotStrategyTuning = preload("res://config/bots/bot_strategy_tuning.tres")

var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _next_id: int = BODY_ID_BASE


func before_each() -> void:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(grid, _territory_tuning)
	_slots = [
		PlayerSlot.new(0, TEAM, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, ENEMY, "b", Color.WHITE, HOME_B),
	]
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, TEAM, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, ENEMY, _territory_tuning),
	]
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	_raster.update(circles, solver.solve(circles), 0.1, false, false)
	_next_id = BODY_ID_BASE
	BotThink._strategy_memory.clear()


func _view(specs: Array) -> BotWorldView:
	var xs: PackedFloat32Array = PackedFloat32Array([HOME_A.x, HOME_B.x])
	var zs: PackedFloat32Array = PackedFloat32Array([HOME_A.y, HOME_B.y])
	var radii: PackedFloat32Array = PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius])
	var teams: PackedInt32Array = PackedInt32Array([TEAM, ENEMY])
	for spec: Array in specs:
		var xz: Vector2 = spec[0] as Vector2
		xs.append(xz.x)
		zs.append(xz.y)
		radii.append(InfluenceCircle.radius_for_height(float(spec[1]), _territory_tuning, MAP_RADIUS))
		teams.append(TEAM)
	var goal: BotModeGoal = BotModeGoal.new()
	goal.mode = MatchConfig.GameMode.REACH_THE_SKY
	return BotWorldView.build(
		0, TEAM, {"xs": xs, "zs": zs, "radii": radii, "teams": teams}, _slots, _raster,
		PackedVector2Array([Vector2.ZERO]), _territory_tuning.goal_zone_radius, _bar3, _cube, goal,
		PackedVector2Array(), PackedVector2Array()
	)


func _stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = 1.0
	return stack


func _column(stack: BotStack, xz: Vector2, count: int, tilt_level: int = -1) -> void:
	for level: int in range(count):
		var basis: Basis = Basis(Vector3.BACK, deg_to_rad(TILT_DEG)) if level == tilt_level else Basis.IDENTITY
		var pos: Vector3 = Vector3(xz.x, float(level) + 0.5, xz.y)
		stack.add_body(_next_id, TEAM, basis, PackedVector3Array([pos]), BODY_MASS, true)
		_next_id += 1


func _analyse(stack: BotStack) -> BotStack:
	while not stack.analyse_step(stack.body_count(), BotEvaluator.stack_tuning):
		pass
	return stack


func _think(stack: BotStack, specs: Array, memory: Dictionary) -> BotIntent:
	var view: BotWorldView = _view(specs)
	view.stack = _analyse(stack)
	return BotStrategy.choose(view, BotChains.build(view), BotDifficultyProfile.new(), null, memory)


## A tower of `count` cubes at BASE_XZ the memory follows (one clean think).
func _established(memory: Dictionary, count: int) -> void:
	var stack: BotStack = _stack()
	_column(stack, BASE_XZ, count)
	var intent: BotIntent = _think(stack, [[BASE_XZ, float(count)]], memory)
	assert_false(intent.new_base)
	assert_lt(intent.target.distance_to(BASE_XZ), TOL)


func test_t1_an_unsound_block_on_top_does_not_abandon_the_tower() -> void:
	var memory: Dictionary = {}
	_established(memory, 4)
	var probe: BotStack = _stack()
	_column(probe, BASE_XZ, 5, 4)
	_analyse(probe)
	assert_true(probe.sound_tops(TEAM).is_empty(), "the old list is empty: that was the abandon trigger")
	var stack: BotStack = _stack()
	_column(stack, BASE_XZ, 5, 4)
	var intent: BotIntent = _think(stack, [[BASE_XZ, 5.0]], memory)
	assert_false(intent.new_base, "the tower below the leaning block still stands")
	assert_lt(intent.target.distance_to(BASE_XZ), TOL)


func test_t2_a_top_far_from_the_base_but_rooted_there_keeps_the_tower() -> void:
	var memory: Dictionary = {}
	_established(memory, 2)
	var stack: BotStack = _stack()
	var far: Vector2 = BASE_XZ + Vector2(float(BAR_CUBES - 1), 0.0)
	_column(stack, BASE_XZ, 2)
	_column(stack, far, 2)
	var cubes: PackedVector3Array = PackedVector3Array()
	for i: int in range(BAR_CUBES):
		cubes.append(Vector3(BASE_XZ.x + float(i), 2.5, BASE_XZ.y))
	stack.add_body(_next_id, TEAM, Basis.IDENTITY, cubes, BODY_MASS * float(BAR_CUBES), true)
	var intent: BotIntent = _think(stack, [[BASE_XZ, 3.0], [far, 2.0]], memory)
	assert_false(intent.new_base, "the bar's centre is beyond base_match_radius_m but it rests on the base column")
	assert_lt(intent.target.distance_to(BASE_XZ + Vector2(float(BAR_CUBES - 1) * 0.5, 0.0)), TOL)


func test_t3_one_unsound_frame_keeps_the_tower_for_the_grace_thinks_only() -> void:
	var memory: Dictionary = {}
	_established(memory, 4)
	for think: int in range(_tuning.collapse_grace_thinks):
		var swayed: BotStack = _stack()
		_column(swayed, BASE_XZ, 4, 0)
		var kept: BotIntent = _think(swayed, [[BASE_XZ, 4.0]], memory)
		assert_false(kept.new_base, "think %d of the sway keeps the tower" % think)
		assert_lt(kept.target.distance_to(BASE_XZ), TOL)
	# The sway stops: the tower is followed again and the grace counter resets.
	var calm: BotStack = _stack()
	_column(calm, BASE_XZ, 4)
	assert_false(_think(calm, [[BASE_XZ, 4.0]], memory).new_base)
	assert_false(memory.has("sky_lost"))
	# A persistent loss still starts a new base once the grace time has run out.
	var intent: BotIntent = null
	for think: int in range(_tuning.collapse_grace_thinks + 1):
		var gone: BotStack = _stack()
		_column(gone, BASE_XZ, 4, 0)
		intent = _think(gone, [[BASE_XZ, 4.0]], memory)
	assert_true(intent.new_base, "the third unsound think is a real collapse")
	assert_true(memory["sky_pending"] as bool)


func test_t4_losing_the_top_pieces_of_a_tall_tower_keeps_it() -> void:
	var memory: Dictionary = {}
	_established(memory, TALL)
	var stack: BotStack = _stack()
	_column(stack, BASE_XZ, LOSS_TO)
	var intent: BotIntent = _think(stack, [[BASE_XZ, float(LOSS_TO)]], memory)
	assert_false(intent.new_base, "16 of 20 m is not a collapse (more than collapse_drop_m, but over half left)")
	assert_lt(intent.target.distance_to(BASE_XZ), TOL)
	assert_almost_eq(memory["sky_peak"] as float, float(TALL), TOL, "the peak is not lowered")


func test_a_real_collapse_starts_a_new_base_after_the_grace_time() -> void:
	var memory: Dictionary = {}
	_established(memory, TALL)
	var intent: BotIntent = null
	for i: int in range(_tuning.collapse_grace_thinks + 1):
		var stack: BotStack = _stack()
		_column(stack, BASE_XZ, 3)
		intent = _think(stack, [[BASE_XZ, 3.0]], memory)
		if i < _tuning.collapse_grace_thinks:
			assert_false(intent.new_base, "inside the grace time the base is kept")
	assert_true(intent.new_base, "after the grace time a new base starts")


func test_another_taller_own_tower_does_not_pull_the_bot_away() -> void:
	var memory: Dictionary = {}
	_established(memory, 3)
	var stack: BotStack = _stack()
	_column(stack, BASE_XZ, 4)
	_column(stack, OTHER_XZ, 9)
	var intent: BotIntent = _think(stack, [[BASE_XZ, 4.0], [OTHER_XZ, 9.0]], memory)
	assert_false(intent.new_base)
	assert_lt(intent.target.distance_to(BASE_XZ), TOL, "the remembered tower is still the target (not a trigger)")
