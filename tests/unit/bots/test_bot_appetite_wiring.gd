extends GutTest
## Bot risk appetite as the bot's callers see it: the candidate set BotSiteList.build offers for a view
## carrying an appetite, and BotController's per-match draw (appetite_report()). Candidate sets use
## hand-built snapshots; the controller runs against the fakes of test_bot_controller.gd.

const BotControllerTests: GDScript = preload("res://tests/unit/bots/test_bot_controller.gd")

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const TEAM: int = 0
const ENEMY: int = 1
const STACK_XZ: Vector2 = Vector2(-9.0, -4.0)
const STACK_CUBES: int = 2
const PILE_ORIGIN: Vector2 = Vector2(-5.0, 1.0)
const PILE_COLUMNS: int = 3
const PILE_ROWS: int = 2
const PILE_TILT_DEG: float = 30.0
const PILE_CIRCLE_TOP_M: float = 1.5
const BODY_MASS: float = 1.0
const CANDIDATE_COUNT: int = 40
const SEED: int = 5454
const CAUTIOUS: float = 0.0
const BOLD: float = 1.0
const TOL: float = 0.001
const FLAT_HEIGHT: float = 1.0
const MAX_FRAMES: int = 200

## First placement of a freshly set-up bot (x, z), recorded on the base before the appetite existed.
const GOLDEN_NORMAL: Vector2 = Vector2(-4.718863, 0.017645)
const GOLDEN_HARD: Vector2 = Vector2(-4.746507, -0.001535)

const COVERED_MODES: Array[int] = [
	MatchConfig.GameMode.CLASSIC,
	MatchConfig.GameMode.CAPTURE_THE_FLAG,
	MatchConfig.GameMode.ELIMINATION,
	MatchConfig.GameMode.DOMINATION,
]
const SEEDS: Array[int] = [1, 7, 42, 777, 90210]
const MID_VALUES: Array[float] = [0.0, 0.3, 0.6, 1.0]

var _territory_tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")
var _physics: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
var _bar3: BlockShape = preload("res://config/blocks/bar3.tres")
var _cube: BlockShape = preload("res://config/blocks/cube.tres")
var _bot_tuning: BotTuning = preload("res://config/bots/bot_tuning.tres")

var _slots: Array[PlayerSlot] = []
var _raster: TerritoryRaster = null
var _next_id: int = 100


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
	_raster.fill_ownership(circles, TerritorySolver.new(_territory_tuning).solve(circles), false)
	_raster.adopt_fill(_raster, 0.1, false, false)
	_next_id = 100
	BotThink._strategy_memory.clear()


# --- candidate sets ----------------------------------------------------------------------------------


func _pile_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for row: int in range(PILE_ROWS):
		for column: int in range(PILE_COLUMNS):
			out.append(PILE_ORIGIN + Vector2(float(column), float(row)) * _physics.cube_size)
	return out


## `circle_specs`: Array of [Vector2 xz, top m]; every one an own block circle. A null `appetite`
## leaves the view's default.
func _view(circle_specs: Array, mode: int, appetite: BotAppetite) -> BotWorldView:
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
	var view: BotWorldView = BotWorldView.build(
		0, TEAM, {"xs": xs, "zs": zs, "radii": radii, "teams": teams}, _slots, _raster,
		PackedVector2Array([Vector2.ZERO]), _territory_tuning.goal_zone_radius, _bar3, _cube, goal,
		PackedVector2Array(), PackedVector2Array()
	)
	if appetite != null:
		view.appetite = appetite
	return view


func _stack() -> BotStack:
	var stack: BotStack = BotStack.new()
	stack.cube_size = _physics.cube_size
	return stack


func _analysed(stack: BotStack) -> BotStack:
	while not stack.analyse_step(stack.body_count(), BotEvaluator.stack_tuning):
		pass
	return stack


func _add_column(stack: BotStack, xz: Vector2, count: int) -> void:
	for level: int in range(count):
		var y: float = (float(level) + 0.5) * _physics.cube_size
		stack.add_body(_next_id, TEAM, Basis.IDENTITY, PackedVector3Array([Vector3(xz.x, y, xz.y)]), BODY_MASS, true)
		_next_id += 1


func _add_pile(stack: BotStack) -> void:
	var tilt: Basis = Basis(Vector3.BACK, deg_to_rad(PILE_TILT_DEG))
	for xz: Vector2 in _pile_positions():
		stack.add_body(
			_next_id, TEAM, tilt, PackedVector3Array([Vector3(xz.x, _physics.cube_size * 0.5, xz.y)]), BODY_MASS, true
		)
		_next_id += 1


## A view with one sound column the bot can stack on.
func _sound_view(mode: int, appetite: BotAppetite) -> BotWorldView:
	var view: BotWorldView = _view([[STACK_XZ, float(STACK_CUBES)]], mode, appetite)
	var stack: BotStack = _stack()
	_add_column(stack, STACK_XZ, STACK_CUBES)
	view.stack = _analysed(stack)
	return view


## A view whose only tower is a leaning pile (unsound).
func _pile_view(mode: int, appetite: BotAppetite) -> BotWorldView:
	var specs: Array = []
	for xz: Vector2 in _pile_positions():
		specs.append([xz, PILE_CIRCLE_TOP_M])
	var view: BotWorldView = _view(specs, mode, appetite)
	var stack: BotStack = _stack()
	_add_pile(stack)
	view.stack = _analysed(stack)
	return view


func _sites(view: BotWorldView, target: Vector2) -> Array[BotCandidate]:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = CANDIDATE_COUNT
	profile.stability_raycast_count = 9
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var intent: BotIntent = BotIntent.new()
	intent.kind = BotIntent.Kind.ANCHOR
	intent.target = target
	return BotSiteList.build(view, intent, profile, rng)


func _stack_sites(view: BotWorldView, target: Vector2) -> Array[BotCandidate]:
	var out: Array[BotCandidate] = []
	for site: BotCandidate in _sites(view, target):
		if site.site_kind == BotCandidateGen.SITE_STACK:
			out.append(site)
	return out


func _tallest(sites: Array[BotCandidate]) -> float:
	var tallest: float = 0.0
	for site: BotCandidate in sites:
		tallest = maxf(tallest, site.shape_height)
	return tallest


## A comparable fingerprint of a candidate list.
func _signature(sites: Array[BotCandidate]) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for site: BotCandidate in sites:
		out.append("%d|%d|%.3f|%.3f" % [site.site_kind, site.orientation_index, site.origin.x, site.origin.y])
	return out


func test_the_sound_stack_gets_stack_sites() -> void:
	var view: BotWorldView = _sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.new(BOLD))
	assert_gt(_stack_sites(view, STACK_XZ).size(), 0, "fixture: the sound column offers stack sites")


func test_a_cautious_classic_bot_lays_pieces_flat_on_a_stack() -> void:
	var sites: Array[BotCandidate] = _stack_sites(_sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.new(CAUTIOUS)), STACK_XZ)
	assert_gt(sites.size(), 0)
	assert_almost_eq(_tallest(sites), FLAT_HEIGHT, TOL, "no tall orientation at appetite 0")


func test_a_bold_classic_bot_offers_tall_orientations_on_a_sound_stack() -> void:
	var sites: Array[BotCandidate] = _stack_sites(_sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.new(BOLD)), STACK_XZ)
	assert_gt(_tallest(sites), FLAT_HEIGHT + TOL, "appetite 1 stands the bar up on a sound top")


func test_boldness_widens_the_tall_choice_in_every_covered_mode() -> void:
	for mode: int in COVERED_MODES:
		var cautious: float = _tallest(_stack_sites(_sound_view(mode, BotAppetite.new(CAUTIOUS)), STACK_XZ))
		var bold: float = _tallest(_stack_sites(_sound_view(mode, BotAppetite.new(BOLD)), STACK_XZ))
		assert_gt(bold, cautious + TOL, "mode %d: a bold bot offers a taller orientation" % mode)


func test_the_cautious_classic_candidate_set_equals_the_shipped_set() -> void:
	var shipped: PackedStringArray = _signature(_sites(_sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.shipped()), STACK_XZ))
	var cautious: PackedStringArray = _signature(_sites(_sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.new(CAUTIOUS)), STACK_XZ))
	assert_gt(shipped.size(), 0)
	assert_eq(cautious, shipped, "appetite 0 adds no tall orientation: the candidate list is the shipped one")


func test_a_view_without_a_drawn_appetite_keeps_the_shipped_sites_in_every_covered_mode() -> void:
	for mode: int in COVERED_MODES:
		var plain: BotWorldView = _sound_view(mode, null)
		var sites: Array[BotCandidate] = _stack_sites(plain, STACK_XZ)
		assert_gt(sites.size(), 0, "mode %d" % mode)
		assert_almost_eq(_tallest(sites), FLAT_HEIGHT, TOL, "mode %d: shipped keeps flat-first orientations" % mode)
		assert_eq(
			_signature(_sites(plain, STACK_XZ)),
			_signature(_sites(_sound_view(mode, BotAppetite.shipped()), STACK_XZ)),
			"mode %d: the default view is the shipped appetite" % mode
		)


func test_reach_the_sky_offers_tall_orientations_for_any_appetite() -> void:
	var reference: PackedStringArray = _signature(_sites(
		_sound_view(MatchConfig.GameMode.REACH_THE_SKY, BotAppetite.shipped()), STACK_XZ
	))
	for value: float in MID_VALUES:
		var view: BotWorldView = _sound_view(MatchConfig.GameMode.REACH_THE_SKY, BotAppetite.new(value))
		assert_gt(_tallest(_stack_sites(view, STACK_XZ)), FLAT_HEIGHT + TOL, "Sky stands the bar up at appetite %.1f" % value)
		assert_eq(_signature(_sites(view, STACK_XZ)), reference, "Sky is exactly the shipped set at appetite %.1f" % value)


func test_a_mode_switched_off_by_data_keeps_the_shipped_orientations() -> void:
	var tuning: BotAppetiteTuning = BotAppetite.SHIPPED_TUNING.duplicate() as BotAppetiteTuning
	tuning.appetite_modes = 0
	var sites: Array[BotCandidate] = _stack_sites(
		_sound_view(MatchConfig.GameMode.CLASSIC, BotAppetite.new(BOLD, tuning)), STACK_XZ
	)
	assert_gt(sites.size(), 0)
	assert_almost_eq(_tallest(sites), FLAT_HEIGHT, TOL, "a bold bot in an uncovered mode lays pieces flat")


func test_unsound_tops_are_kept_by_a_bold_bot_and_skipped_by_a_cautious_one() -> void:
	for mode: int in COVERED_MODES:
		var cautious: BotWorldView = _pile_view(mode, BotAppetite.new(CAUTIOUS))
		var bold: BotWorldView = _pile_view(mode, BotAppetite.new(BOLD))
		assert_eq(_stack_sites(cautious, PILE_ORIGIN).size(), 0, "mode %d: cautious skips the leaning pile" % mode)
		assert_gt(_stack_sites(bold, PILE_ORIGIN).size(), 0, "mode %d: bold keeps it" % mode)


func test_reach_the_sky_always_skips_unsound_tops() -> void:
	for value: float in MID_VALUES:
		var view: BotWorldView = _pile_view(MatchConfig.GameMode.REACH_THE_SKY, BotAppetite.new(value))
		assert_eq(_stack_sites(view, PILE_ORIGIN).size(), 0, "Sky skips the pile at appetite %.1f" % value)


func test_the_shipped_appetite_keeps_unsound_tops_outside_sky() -> void:
	for mode: int in COVERED_MODES:
		assert_gt(_stack_sites(_pile_view(mode, BotAppetite.shipped()), PILE_ORIGIN).size(), 0, "mode %d" % mode)


# --- controller --------------------------------------------------------------------------------------


func _fake_match(slot_id: int, seed_value: int) -> Object:
	var fake: Object = BotControllerTests.BotControllerFakeMatch.new()
	var config: MatchConfig = MatchConfig.new()
	config.rng_seed = seed_value
	config.goal_flag_count = 1
	config.disc_size_step = 1
	fake.config = config
	fake.slot_count_value = 2
	fake.slots_by_id[slot_id] = PlayerSlot.new(slot_id, slot_id, "Bot %d" % slot_id, Color.WHITE, Vector2(1.0, 0.0))
	fake.team_by_slot[slot_id] = slot_id
	fake.held_shapes[slot_id] = _cube
	fake.release_locked[slot_id] = false
	var raster: TerritoryRaster = TerritoryRaster.new(CellGrid.new(20.0, 1.0), _territory_tuning)
	fake.raster_value = raster
	fake.cell_grid_value = raster.grid()
	var home: Array[InfluenceCircle] = [InfluenceCircle.for_home(Vector2(1.0, 0.0), slot_id, slot_id, _territory_tuning)]
	raster.fill_ownership(home, TerritorySolver.new(_territory_tuning).solve(home), false)
	raster.adopt_fill(raster, 0.1, false, false)
	return fake


func _field() -> Field:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_bot_disk"
	map_def.field_radius = 10.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	var field: Field = Field.new()
	field.map_def = map_def
	add_child_autofree(field)
	return field


func _controller(fake: Object) -> BotController:
	var controller: BotController = BotController.new()
	add_child_autofree(controller)
	var tuning: BotTuning = _bot_tuning.duplicate() as BotTuning
	tuning.release_delay_min_s = 0.0
	tuning.release_delay_max_s = 0.0
	controller.tuning = tuning
	controller.set_match_provider(fake)
	controller.set_net_provider(BotControllerTests.BotControllerFakeNet.new())
	return controller


func _report(slot_id: int, seed_value: int, difficulty: MatchConfig.AiDifficulty = MatchConfig.AiDifficulty.NORMAL) -> String:
	var controller: BotController = _controller(_fake_match(slot_id, seed_value))
	controller.setup(slot_id, difficulty, _field(), null)
	return controller.appetite_report()


## "slot:value" -> value, with the slot checked.
func _value_of(report: String, slot_id: int) -> float:
	var parts: PackedStringArray = report.split(":")
	assert_eq(parts.size(), 2, "report '%s' is slot:value" % report)
	if parts.size() != 2:
		return -1.0
	assert_eq(parts[0].to_int(), slot_id, "report '%s' names the slot" % report)
	assert_true(parts[1].is_valid_float(), "report '%s' carries a number" % report)
	return parts[1].to_float()


func test_the_report_names_the_slot_and_a_value_in_range() -> void:
	assert_between(_value_of(_report(3, 777), 3), 0.0, 1.0)


func test_the_same_seed_and_slot_draw_the_same_appetite() -> void:
	for seed_value: int in SEEDS:
		assert_eq(_report(2, seed_value), _report(2, seed_value), "seed %d" % seed_value)


func test_different_slots_and_seeds_draw_different_appetites() -> void:
	assert_ne(_report(1, 777), _report(2, 777), "two bots of one match differ")
	var distinct: Dictionary = {}
	for seed_value: int in SEEDS:
		distinct[_report(1, seed_value)] = true
	assert_gt(distinct.size(), 1, "the match seed moves the draw")


func test_the_draw_stays_inside_each_tier_range() -> void:
	for difficulty: MatchConfig.AiDifficulty in [
		MatchConfig.AiDifficulty.EASY, MatchConfig.AiDifficulty.NORMAL, MatchConfig.AiDifficulty.HARD
	]:
		var bounds: Vector2 = _bot_tuning.profile_for(difficulty).appetite_range
		for seed_value: int in SEEDS:
			var value: float = _value_of(_report(1, seed_value, difficulty), 1)
			assert_between(value, bounds.x - TOL, bounds.y + TOL, "tier %d seed %d" % [difficulty, seed_value])


func test_an_unseeded_match_still_draws_a_valid_appetite() -> void:
	assert_between(_value_of(_report(1, -1), 1), 0.0, 1.0)


## The first request a freshly set-up bot sends. It depends on the think and aim stream, so it moves if
## the appetite draw ever consumes from that stream.
func _first_placement(slot_id: int, seed_value: int, difficulty: MatchConfig.AiDifficulty) -> Vector2:
	var fake: Object = _fake_match(slot_id, seed_value)
	var controller: BotController = _controller(fake)
	controller.setup(slot_id, difficulty, _field(), null)
	Events.feed_block_issued.emit(slot_id, &"cube", &"")
	var frames: int = 0
	while fake.request_place_calls.is_empty() and frames < MAX_FRAMES:
		controller._physics_process(1.0 / 60.0)
		frames += 1
	assert_eq(fake.request_place_calls.size(), 1, "the bot placed once")
	if fake.request_place_calls.is_empty():
		return Vector2.INF
	var origin: Vector3 = fake.request_place_calls[0]["origin"] as Vector3
	return Vector2(origin.x, origin.z)


func test_the_think_and_aim_stream_is_unchanged_by_the_appetite_draw() -> void:
	var normal: Vector2 = _first_placement(0, 777, MatchConfig.AiDifficulty.NORMAL)
	var hard: Vector2 = _first_placement(1, 4242, MatchConfig.AiDifficulty.HARD)
	assert_almost_eq(normal, GOLDEN_NORMAL, Vector2(TOL, TOL), "Normal slot 0 seed 777")
	assert_almost_eq(hard, GOLDEN_HARD, Vector2(TOL, TOL), "Hard slot 1 seed 4242")
