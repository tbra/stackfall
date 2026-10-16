extends GutTest
## core/ai/BotCandidateGen.gd (Bot V2 P2): targeted TIP / STACK / STRIKE /
## FILL sites on a synthetic snake raster. Pure: real CellGrid + TerritoryRaster.

const MAP_RADIUS: float = 20.0
const CELL: float = 0.5
const HOME_A: Vector2 = Vector2(-15.0, 0.0)
const HOME_B: Vector2 = Vector2(15.0, 0.0)
const SNAKE_TOP_M: float = 1.0
const SNAKE_XS: Array[float] = [-10.0, -8.0, -6.0, -4.0, -2.0]
const TOWER_POS: Vector2 = Vector2(-6.0, 3.0)
const TOWER_TOP_M: float = 4.0
const CANDIDATE_COUNT: int = 110
const SEED: int = 99
const TIP_EDGE_TOLERANCE_M: float = 0.5
const ENEMY_POS: Vector2 = Vector2(5.0, 0.0)
const ENEMY_TOP_M: float = 5.0
const GOAL_POS: Vector2 = Vector2(-6.0, 1.5)
const GOAL_ZONE_M: float = 3.0
const HOLE_STEP_S: float = 1.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _tuning: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
var _stack_tuning: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _pillar: BlockShape = preload("res://config/blocks/pillar.tres")
var _slots: Array[PlayerSlot] = []


func before_each() -> void:
	_slots = [
		PlayerSlot.new(0, 0, "a", Color.WHITE, HOME_A),
		PlayerSlot.new(1, 1, "b", Color.WHITE, HOME_B),
	]


func _circles(with_tower: bool, with_enemy: bool = false) -> Array[InfluenceCircle]:
	var list: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(HOME_A, 0, 0, _territory_tuning),
		InfluenceCircle.for_home(HOME_B, 1, 1, _territory_tuning),
	]
	var body: int = 1
	for x: float in SNAKE_XS:
		list.append(InfluenceCircle.new(Vector2(x, 0.0), InfluenceCircle.radius_for_height(SNAKE_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, body, SNAKE_TOP_M))
		body += 1
	if with_tower:
		list.append(InfluenceCircle.new(TOWER_POS, InfluenceCircle.radius_for_height(TOWER_TOP_M, _territory_tuning, MAP_RADIUS), 0, 0, false, body, TOWER_TOP_M))
	if with_enemy:
		list.append(InfluenceCircle.new(ENEMY_POS, InfluenceCircle.radius_for_height(ENEMY_TOP_M, _territory_tuning, MAP_RADIUS), 1, 1, false, 99, ENEMY_TOP_M))
	return list


func _view(held: BlockShape, with_tower: bool = false, with_enemy: bool = false, goal_zone: bool = false) -> BotWorldView:
	var grid: CellGrid = CellGrid.new(MAP_RADIUS, CELL)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, _territory_tuning)
	var circles: Array[InfluenceCircle] = _circles(with_tower, with_enemy)
	var solver: TerritorySolver = TerritorySolver.new(_territory_tuning)
	if goal_zone:
		raster.set_goal_zones(PackedVector2Array([GOAL_POS]), GOAL_ZONE_M)
	raster.fill_ownership(circles, solver.solve(circles), with_enemy)
	raster.adopt_fill(raster, 0.1, with_enemy, false)
	if with_enemy:
		raster.fill_ownership(circles, solver.solve(circles), true)
		raster.adopt_fill(raster, HOLE_STEP_S, true, false)
	var xs: PackedFloat32Array = PackedFloat32Array()
	var zs: PackedFloat32Array = PackedFloat32Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	var teams: PackedInt32Array = PackedInt32Array()
	for circle: InfluenceCircle in circles:
		xs.append(circle.center.x)
		zs.append(circle.center.y)
		radii.append(circle.radius)
		teams.append(circle.team_id)
	var arrays: Dictionary = {"xs": xs, "zs": zs, "radii": radii, "teams": teams}
	return BotWorldView.build(
		0, 0, arrays, _slots, raster, PackedVector2Array([Vector2.ZERO]), 0.0, held, held, null,
		PackedVector2Array(), PackedVector2Array()
	)


func _intent(kind: BotIntent.Kind, target: Vector2 = HOME_B) -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.kind = kind
	intent.target = target
	return intent


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	return rng


func _sites(view: BotWorldView, intent: BotIntent, count: int = CANDIDATE_COUNT) -> Array[BotCandidate]:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = count
	return _site_list(view, intent, profile, _rng(), _tuning)


func test_tip_sites_sit_at_the_snake_edge_nearest_the_target() -> void:
	var view: BotWorldView = _view(_pillar)
	var sites: Array[BotCandidate] = _sites(view, _intent(BotIntent.Kind.RACE))
	var last: int = view.circle_count() - 1
	var edge: Vector2 = Vector2(view.cx[last] + view.cr[last], 0.0)
	var nearest: float = INF
	for c: BotCandidate in sites:
		if c.site_kind == BotCandidateGen.SITE_TIP:
			nearest = minf(nearest, c.origin.distance_to(edge))
	assert_true(nearest <= TIP_EDGE_TOLERANCE_M, "nearest tip site %.2f m from the edge" % nearest)


func test_pillar_stands_upright_at_the_tip() -> void:
	var sites: Array[BotCandidate] = _sites(_view(_pillar), _intent(BotIntent.Kind.RACE))
	var first_tip: BotCandidate = null
	for c: BotCandidate in sites:
		if c.site_kind == BotCandidateGen.SITE_TIP:
			first_tip = c
			break
	assert_not_null(first_tip)
	assert_almost_eq(first_tip.shape_height, 3.0, 0.001, "upright pillar at the best tip")
	var info: BotStatics.OrientationInfo = BotStatics.orientation_info(_pillar, first_tip.orientation_index)
	assert_gt(info.self_margin * _physics.cube_size, _stack_tuning.numeric_tolerance_m, "eligible by its own margin")


func test_stack_tops_get_the_flattest_orientation() -> void:
	var sites: Array[BotCandidate] = _sites(_view(_pillar, true), _intent(BotIntent.Kind.ANCHOR))
	var stack_sites: int = 0
	for c: BotCandidate in sites:
		if c.site_kind == BotCandidateGen.SITE_STACK:
			stack_sites += 1
			assert_almost_eq(c.shape_height, 1.0, 0.001, "flat on a stack")
			assert_true(c.support_height >= _tuning.stack_min_height_m)
	assert_true(stack_sites > 0)


func _assert_all_placeable(view: BotWorldView, sites: Array[BotCandidate]) -> void:
	for c: BotCandidate in sites:
		var cell: Vector2i = view.grid.world_to_cell(c.origin)
		assert_false(view.raster.is_contested(cell.x, cell.y), "not contested")
		assert_false(view.raster.is_hole(cell.x, cell.y), "not a hole")
		assert_false(view.raster.is_goal_zone(cell.x, cell.y), "not in the goal zone")
		assert_eq(view.raster.team_at(cell.x, cell.y), view.team_id, "own territory")


func test_no_site_in_contested_or_hole_cells_and_tips_back_off() -> void:
	var view: BotWorldView = _view(_pillar, false, true)
	var contested: int = 0
	for cell_index: int in view.grid.in_disk_cells():
		var coords: Vector2i = view.grid.cell_coords(cell_index)
		if view.raster.is_contested(coords.x, coords.y) or view.raster.is_hole(coords.x, coords.y):
			contested += 1
	assert_true(contested > 0, "fixture has contested cells")
	var sites: Array[BotCandidate] = _sites(view, _intent(BotIntent.Kind.RACE))
	_assert_all_placeable(view, sites)
	var tips: int = 0
	for c: BotCandidate in sites:
		if c.site_kind == BotCandidateGen.SITE_TIP:
			tips += 1
	assert_true(tips > 0, "tip sites back off from the contested edge")


func test_no_site_in_the_goal_no_build_zone() -> void:
	var view: BotWorldView = _view(_pillar, false, false, true)
	var sites: Array[BotCandidate] = _sites(view, _intent(BotIntent.Kind.RACE))
	assert_true(sites.size() > 0)
	_assert_all_placeable(view, sites)


func test_no_site_outside_own_territory() -> void:
	var view: BotWorldView = _view(_pillar, true)
	for c: BotCandidate in _sites(view, _intent(BotIntent.Kind.RACE)):
		assert_true(c.origin.x < HOME_B.x - _territory_tuning.home_radius, "stays on own side of the enemy home")
	_assert_all_placeable(view, _sites(view, _intent(BotIntent.Kind.RACE)))


## The sites `BotCandidateGen.begin` builds once its fill has run to the end.
func _site_list(
	view: BotWorldView, intent: BotIntent, profile: BotDifficultyProfile,
	rng: RandomNumberGenerator, tuning: BotGenTuning = null
) -> Array[BotCandidate]:
	var job: BotCandidateGen.SiteJob = BotCandidateGen.begin(view, intent, profile, rng, tuning)
	while not job.fill_step(job.attempts_left()):
		pass
	return job.out
