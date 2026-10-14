extends GutTest
## Bontago-1t5.30: the sliced V2 think (FILL / RANK in budgeted slices) must choose exactly what
## the one-shot think chooses, and must keep choosing what the pre-slicing pipeline chose
## (BASELINE_MD5 was captured from main 5150b091 before the change).
## Bontago-1t5.37: the same holds with the per-cell rays on BotThink.cell_probe (the
## controller's wiring), and for the deadline driver (a few slices, then complete()).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0
const HOME_A: Vector2 = Vector2(-10.0, 0.0)
const HOME_B: Vector2 = Vector2(10.0, 0.0)
const BLOCK_CIRCLE_POS: Vector2 = Vector2(-6.0, 1.0)
const BLOCK_CIRCLE_TOP_M: float = 3.0
const HARD_SITE_COUNT: int = 110
const HARD_TOP_K: int = 12
const FIRST_SEED: int = 9001
const DECISIONS: int = 24
const BIG_BUDGET_US: int = 60000000
const STEP_GUARD: int = 5000
const SHAPE_IDS: Array[String] = ["cube", "pillar", "L4", "T4", "arch5", "plus5", "stair6"]
const WAVE_SCALE: float = 0.7
const WAVE_HEIGHT_M: float = 0.8
# DECISION (Bontago-1t5.55.1): re-baselined once. The bot now models the piece in the spawn frame
# (cubes at B*(cell - pivot), origin = pivot), so sites, footprints and probes legitimately change.
# Old 3703bcb9cdab17f12e340a391ee5f05c (main 4c474d41), new below.
const BASELINE_MD5: String = "610fd6bfd53c89ae1101771485635286"
## Slices the deadline driver takes before complete() runs the rest.
const DEADLINE_SLICES: int = 3
## A small positive slice: step() then also weighs the next unit's predicted cost.
const SMALL_BUDGET_US: int = 200

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _grid: CellGrid = null
var _raster: TerritoryRaster = null
var _slots: Array[PlayerSlot] = []
var _probe_calls: int = 0
var _cell_probe_calls: int = 0


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
		InfluenceCircle.for_block(BLOCK_CIRCLE_POS, BLOCK_CIRCLE_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS),
	]
	_raster.update(circles, TerritorySolver.new(_territory_tuning).solve(circles), 0.1, false, false)


func _view(held: BlockShape) -> BotWorldView:
	var block: InfluenceCircle = InfluenceCircle.for_block(
		BLOCK_CIRCLE_POS, BLOCK_CIRCLE_TOP_M, 0, 0, 7, _territory_tuning, MAP_RADIUS
	)
	var arrays: Dictionary = {
		"xs": PackedFloat32Array([HOME_A.x, HOME_B.x, BLOCK_CIRCLE_POS.x]),
		"zs": PackedFloat32Array([HOME_A.y, HOME_B.y, BLOCK_CIRCLE_POS.y]),
		"radii": PackedFloat32Array([_territory_tuning.home_radius, _territory_tuning.home_radius, block.radius]),
		"teams": PackedInt32Array([0, 1, 0]),
	}
	return BotWorldView.build(
		0, 0, arrays, _slots, _raster, PackedVector2Array([Vector2.ZERO]),
		_territory_tuning.goal_zone_radius, held, held, null, PackedVector2Array(), PackedVector2Array()
	)


func _wave(xz: Vector2) -> float:
	return maxf(sin(xz.x * WAVE_SCALE) * cos(xz.y * WAVE_SCALE), 0.0) * WAVE_HEIGHT_M


func _probe(xz: Vector2) -> Dictionary:
	_probe_calls += 1
	var height: float = _wave(xz)
	return {"hit": true, "height": height, "own": height > 0.0}


## BotController._probe_cell's contract: the same ray without the own-block lookup.
func _cell_probe(xz: Vector2) -> Dictionary:
	_cell_probe_calls += 1
	return {"hit": true, "height": _wave(xz)}


func _profile() -> BotDifficultyProfile:
	var profile: BotDifficultyProfile = BotDifficultyProfile.new()
	profile.candidate_count = HARD_SITE_COUNT
	profile.stability_raycast_count = 6
	profile.eval_top_k = HARD_TOP_K
	profile.pick_pool = 1
	return profile


func _decide(shape: BlockShape, seed_value: int, budget_us: int, cell_rays: bool = false, deadline: bool = false) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var think: BotThink = BotThink.new(_view(shape), _profile(), rng)
	if cell_rays:
		think.cell_probe = _cell_probe
	var steps: int = 0
	if deadline:
		while steps < DEADLINE_SLICES and not think.step(budget_us, _probe):
			steps += 1
		think.complete(_probe)
	while steps < STEP_GUARD and not think.step(budget_us, _probe):
		steps += 1
	var d: BotThink.Decision = think.decision()
	return "%d:%.2f,%.2f:%d:%d" % [d.kind, d.origin.x, d.origin.y, d.orientation_index, d.intent]


func _fingerprint(budget_us: int, cell_rays: bool = false, deadline: bool = false) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(DECISIONS):
		var shape: BlockShape = load("res://config/blocks/%s.tres" % SHAPE_IDS[i % SHAPE_IDS.size()]) as BlockShape
		parts.append(_decide(shape, FIRST_SEED + i, budget_us, cell_rays, deadline))
	return "|".join(parts)


func test_sliced_think_equals_one_shot_think() -> void:
	assert_eq(_fingerprint(0), _fingerprint(BIG_BUDGET_US), "slice size never changes the decisions")


func test_decisions_match_the_pre_slicing_baseline() -> void:
	assert_eq(_fingerprint(BIG_BUDGET_US).md5_text(), BASELINE_MD5)


func test_cell_probe_wiring_keeps_the_decisions_whatever_the_slicing() -> void:
	_cell_probe_calls = 0
	var sliced: String = _fingerprint(0, true)
	assert_gt(_cell_probe_calls, 0, "the per-cell rays go to cell_probe")
	assert_eq(sliced, _fingerprint(BIG_BUDGET_US, true), "slice size never changes the decisions")
	assert_eq(sliced.md5_text(), BASELINE_MD5, "cell_probe answers like probe, so the choice is unchanged")


func test_cell_probe_takes_every_cell_ray_and_probe_one_ray_per_site() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = FIRST_SEED
	var think: BotThink = BotThink.new(_view(load("res://config/blocks/L4.tres") as BlockShape), _profile(), rng)
	think.cell_probe = _cell_probe
	_probe_calls = 0
	_cell_probe_calls = 0
	think.step(BIG_BUDGET_US, _probe)
	var cell_rays: int = 0
	for candidate: BotCandidate in think.candidates():
		cell_rays += candidate.cell_support.size()
	assert_gt(think.candidates().size(), 0)
	assert_eq(_probe_calls, think.candidates().size(), "probe: the support ray of each site only")
	assert_eq(_cell_probe_calls, cell_rays, "cell_probe: every footprint-cell ray (no holes on this board)")


func test_deadline_driver_and_predicted_slices_keep_the_decisions() -> void:
	assert_eq(_fingerprint(0, false, true).md5_text(), BASELINE_MD5, "a few slices, then complete() at the deadline tick")
	assert_eq(_fingerprint(SMALL_BUDGET_US).md5_text(), BASELINE_MD5, "slices cut by the predicted cost of the next unit")
