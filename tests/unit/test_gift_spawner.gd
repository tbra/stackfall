extends GutTest
## Spec 2.6 "Gift spawning [ORIGINAL target]": probability per placement
## window, not the retired seconds-based interval (docs/M4_PLAN.md header
## amendment). Covers GiftSpawner's pure chance mapping and spawn-point pick.

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const SEED_DRAWS: int = 200

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _grid: CellGrid = null
var _solver: TerritorySolver = null
var _raster: TerritoryRaster = null
var _config: GiftConfig = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_solver = TerritorySolver.new(_tuning)
	_raster = TerritoryRaster.new(_grid, _tuning)
	_config = GiftConfig.new()
	_config.spawn_max_attempts = 32
	_config.spawn_edge_margin_m = 2.0
	_config.max_live_crates = 1


func _home(x: float, z: float, team: int) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, z), _tuning.home_radius, team, team, true, -1)


## Legacy (holes_enabled = true) fill, the ruleset that ever sets
## is_contested()/is_hole() (TerritoryRaster class comment).
func _rasterize_legacy(circles: Array[InfluenceCircle], delta: float = 0.1) -> void:
	_raster.update(circles, _solver.solve(circles), delta, true, false)


## A contested strip between two adjacent home circles, leaving most of the
## disk uncontested so pick_spawn_point has somewhere valid to land too.
func _contested_strip() -> void:
	_rasterize_legacy([_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)] as Array[InfluenceCircle])


## Two huge, identically centred circles of different teams: every in-disk
## cell is stamped by team 0 first, then team 1 contests all of it.
func _entire_disk_contested() -> void:
	_rasterize_legacy([
		InfluenceCircle.new(Vector2.ZERO, MAP_RADIUS * 2.0, 0, 0, true, -1),
		InfluenceCircle.new(Vector2.ZERO, MAP_RADIUS * 2.0, 1, 1, true, -1),
	] as Array[InfluenceCircle])


## -- chance_for_frequency ----------------------------------------------------

func test_chance_is_zero_at_frequency_zero() -> void:
	assert_eq(GiftSpawner.chance_for_frequency(_config, 0.0), 0.0)


func test_chance_is_the_max_at_frequency_one_hundred() -> void:
	assert_almost_eq(
		GiftSpawner.chance_for_frequency(_config, 100.0), _config.frequency_to_chance_max, 0.0001
	)


func test_chance_is_monotonic_in_frequency() -> void:
	var previous: float = -1.0
	for freq: int in range(0, 101, 5):
		var chance: float = GiftSpawner.chance_for_frequency(_config, float(freq))
		assert_gte(chance, previous, "Never decreases as frequency rises.")
		previous = chance


func test_chance_is_clamped_for_out_of_range_frequency() -> void:
	assert_eq(GiftSpawner.chance_for_frequency(_config, -50.0), 0.0)
	assert_almost_eq(
		GiftSpawner.chance_for_frequency(_config, 500.0), _config.frequency_to_chance_max, 0.0001
	)


## -- should_spawn -------------------------------------------------------------

func test_should_spawn_is_false_at_zero_chance() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(20):
		rng.seed = seed_value
		assert_false(GiftSpawner.should_spawn(_config, 0.0, 0, rng))


func test_should_spawn_is_true_at_chance_one() -> void:
	_config.frequency_to_chance_max = 1.0
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(20):
		rng.seed = seed_value
		assert_true(GiftSpawner.should_spawn(_config, 100.0, 0, rng))


func test_should_spawn_never_true_when_already_at_the_live_cap() -> void:
	_config.frequency_to_chance_max = 1.0
	_config.max_live_crates = 1
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(20):
		rng.seed = seed_value
		assert_false(GiftSpawner.should_spawn(_config, 100.0, 1, rng),
			"Chance 1 still must not spawn once max_live_crates are already live.")


## -- pick_spawn_point ---------------------------------------------------------

func test_pick_spawn_point_avoids_contested_and_hole_cells_and_stays_off_the_rim() -> void:
	_contested_strip()
	var effective_radius: float = MAP_RADIUS - _config.spawn_edge_margin_m
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var found_at_least_one: bool = false

	for seed_value: int in range(SEED_DRAWS):
		rng.seed = seed_value
		var point: Vector2 = GiftSpawner.pick_spawn_point(_raster, _grid, rng, _config)
		if GiftSpawner.is_no_spawn_point(point):
			continue
		found_at_least_one = true

		assert_lte(point.length(), effective_radius + 0.001,
			"Stays inside the disk minus the edge margin.")
		var cell: Vector2i = _grid.world_to_cell(point)
		assert_true(_grid.in_bounds(cell.x, cell.y))
		assert_true(_grid.is_in_disk(cell.x, cell.y))
		assert_false(_raster.is_contested(cell.x, cell.y),
			"Never lands on a contested cell.")
		assert_false(_raster.is_hole(cell.x, cell.y), "Never lands on a hole.")

	assert_true(found_at_least_one, "Setup: most of the disk is still open.")


func test_pick_spawn_point_avoids_holes_once_the_strip_has_holed_through() -> void:
	var circles: Array[InfluenceCircle] = [_home(-3.0, 0.0, 0), _home(3.0, 0.0, 1)]
	for i: int in range(10):
		_rasterize_legacy(circles)

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	for seed_value: int in range(SEED_DRAWS):
		rng.seed = seed_value
		var point: Vector2 = GiftSpawner.pick_spawn_point(_raster, _grid, rng, _config)
		if GiftSpawner.is_no_spawn_point(point):
			continue
		var cell: Vector2i = _grid.world_to_cell(point)
		assert_false(_raster.is_hole(cell.x, cell.y))


func test_pick_spawn_point_returns_the_sentinel_when_the_whole_disk_is_contested() -> void:
	_entire_disk_contested()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	var point: Vector2 = GiftSpawner.pick_spawn_point(_raster, _grid, rng, _config)
	assert_true(GiftSpawner.is_no_spawn_point(point))


func test_pick_spawn_point_is_deterministic_for_the_same_seed() -> void:
	_contested_strip()
	var rng_a: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_a.seed = 7
	var rng_b: RandomNumberGenerator = RandomNumberGenerator.new()
	rng_b.seed = 7

	var point_a: Vector2 = GiftSpawner.pick_spawn_point(_raster, _grid, rng_a, _config)
	var point_b: Vector2 = GiftSpawner.pick_spawn_point(_raster, _grid, rng_b, _config)
	assert_eq(point_a, point_b)


func test_is_no_spawn_point_recognises_the_sentinel_only() -> void:
	assert_true(GiftSpawner.is_no_spawn_point(GiftSpawner.NO_SPAWN_POINT))
	assert_false(GiftSpawner.is_no_spawn_point(Vector2.ZERO))
	assert_false(GiftSpawner.is_no_spawn_point(Vector2(15.0, -15.0)))
