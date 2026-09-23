extends GutTest
## core/ai/BotPlacementScorer.gd (docs/M5_PLAN.md P2, Bontago-d5c.3): real
## placement scoring -- height gained, goal progress, stability, risk,
## combined by BotTuning's four weights -- plus flattest_orientations()'s
## pure geometry and pick_best()'s highest-scorer selection.
##
## Fixture style mirrors tests/unit/test_placement_rules.gd (a real CellGrid/
## TerritoryRaster, no Field/scene tree): BotCandidate is pure data, so every
## candidate here is hand-built rather than generated through
## game/BotController.gd (which this package's own brief does not own).

const MAP_RADIUS: float = 20.0
const CELL: float = 1.0

var _territory_tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _bot_tuning: BotTuning = preload("res://config/bot_tuning.tres")
var _cube_shape: BlockShape = preload("res://config/blocks/cube.tres")
var _bar4_shape: BlockShape = preload("res://config/blocks/bar4.tres")
var _slab6_shape: BlockShape = preload("res://config/blocks/slab6.tres")
var _pillar_shape: BlockShape = preload("res://config/blocks/pillar.tres")
var _l4_shape: BlockShape = preload("res://config/blocks/L4.tres")

## A 2x2-cube footprint, like the first four cells of config/blocks/slab6.tres.
var _two_by_two: Array[Vector3i] = [
	Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)
]

var _grid: CellGrid = null
var _raster: TerritoryRaster = null


func before_each() -> void:
	_grid = CellGrid.new(MAP_RADIUS, CELL)
	_raster = TerritoryRaster.new(_grid, _territory_tuning)


func _cell_centre(cx: int = 0, cy: int = 0) -> Vector2:
	return _grid.cell_center(_grid.res / 2 + cx, _grid.res / 2 + cy)


## The 2x2 footprint below is built with its origin on a cell centre (so each
## of its four sub-cubes lands aligned on its own single cell, giving exactly
## four covered cells -- an origin on a cell *corner* would have each sub-cube
## itself straddle a corner and cover up to nine cells in the union). The
## footprint's own geometric centre then sits half a cell in from that origin.
func _two_by_two_footprint_origin(cx: int = 0, cy: int = 0) -> Vector2:
	return _cell_centre(cx, cy)


func _two_by_two_footprint_centre(cx: int = 0, cy: int = 0) -> Vector2:
	return _two_by_two_footprint_origin(cx, cy) + Vector2(CELL, CELL) * 0.5


func _candidate(
	origin: Vector2,
	support_height: float = 0.0,
	footprint_cells: PackedInt32Array = PackedInt32Array(),
	on_top_of_own_stack: bool = false,
	corner_support_hits: int = -1
) -> BotCandidate:
	var candidate: BotCandidate = BotCandidate.new()
	candidate.origin = origin
	candidate.support_height = support_height
	candidate.footprint_cells = footprint_cells
	candidate.on_top_of_own_stack = on_top_of_own_stack
	candidate.corner_support_hits = corner_support_hits
	return candidate


func _score(
	candidate: BotCandidate,
	goal_positions: PackedVector2Array = PackedVector2Array(),
	enemy_circle_centers: PackedVector2Array = PackedVector2Array(),
	active_special_positions: PackedVector2Array = PackedVector2Array()
) -> float:
	return BotPlacementScorer.score(
		candidate, _raster, _grid, 0, goal_positions, enemy_circle_centers,
		active_special_positions, _bot_tuning, MAP_RADIUS
	)


## -- score(): stability -------------------------------------------------------

func test_a_fully_supported_flat_candidate_beats_a_corner_balanced_one() -> void:
	## docs/M5_PLAN.md P2: "A candidate resting entirely on
	## on_top_of_own_stack == true with full contact scores higher than one
	## balanced on a corner." Same footprint, same origin, same height --
	## only the contact/stack signals differ.
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		_two_by_two, Basis.IDENTITY, _two_by_two_footprint_origin(), CELL, _grid
	)
	assert_eq(footprint.size(), 4, "Setup: a grid-aligned 2x2 footprint covers exactly four cells.")

	var centre: Vector2 = _two_by_two_footprint_centre()
	var full_contact: BotCandidate = _candidate(centre, 3.0, footprint, true, 4)
	var corner_balanced: BotCandidate = _candidate(centre, 3.0, footprint, false, 1)
	assert_gt(_score(full_contact), _score(corner_balanced),
		"Full contact on its own stack must outscore a corner-balanced placement at equal height.")


func test_stability_prefers_a_centred_origin_over_one_outside_the_footprint() -> void:
	var footprint: PackedInt32Array = PlacementRules.footprint_cells(
		_two_by_two, Basis.IDENTITY, _two_by_two_footprint_origin(), CELL, _grid
	)
	var centre: Vector2 = _two_by_two_footprint_centre()
	var centred: BotCandidate = _candidate(centre, 0.0, footprint, false, 4)
	var off_centre: BotCandidate = _candidate(centre + Vector2(10.0, 10.0), 0.0, footprint, false, 4)
	assert_gt(_score(centred), _score(off_centre),
		"A centre of mass inside the supported footprint scores higher than one far outside it.")


## -- score(): goal progress ---------------------------------------------------

func test_closer_to_goal_beats_farther_all_else_equal() -> void:
	var goal: PackedVector2Array = PackedVector2Array([Vector2(15.0, 0.0)])
	var closer: BotCandidate = _candidate(Vector2(10.0, 0.0), 2.0)
	var farther: BotCandidate = _candidate(Vector2(-10.0, 0.0), 2.0)
	assert_gt(_score(closer, goal), _score(farther, goal),
		"A candidate nearer the goal flag scores higher, all else equal.")


func test_a_candidate_whose_estimated_circle_already_reaches_the_goal_scores_at_least_as_well() -> void:
	var goal: PackedVector2Array = PackedVector2Array([Vector2(2.0, 0.0)])
	# Bontago-d5c.9 (rebalanced): support_height is held equal between the two
	# candidates so only the goal metric differs -- a taller *oriented shape*
	# (shape_height, not support_height) right next to the goal makes its
	# estimated influence circle already reach the goal (a negative
	# goal-progress metric), without also picking up the unrelated height-term
	# bonus a differing support_height would have conflated this with.
	var reaching: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	reaching.shape_height = 20.0
	var not_reaching: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	assert_gt(_score(reaching, goal), _score(not_reaching, goal))


func test_taller_shape_height_estimates_a_larger_goal_progress_radius() -> void:
	# Bontago-d5c.9 (item E): BotCandidate.shape_height (the oriented shape's
	# own height in cube units) feeds InfluenceCircle.radius_for_height()
	# alongside support_height -- at equal support_height, a taller shape
	# estimates a larger future influence radius, which is a better (higher)
	# goal-progress score.
	var goal: PackedVector2Array = PackedVector2Array([Vector2(15.0, 0.0)])
	var tall: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	tall.shape_height = 3.0
	var short: BotCandidate = _candidate(Vector2(0.0, 0.0), 2.0)
	short.shape_height = 0.0
	assert_gt(_score(tall, goal), _score(short, goal),
		"A taller oriented shape at equal support height scores higher via the goal-progress metric alone.")


## -- score(): risk -------------------------------------------------------------

func test_a_candidate_inside_the_enemy_territory_risk_radius_is_penalised() -> void:
	var safe: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var risky: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var enemy_far: PackedVector2Array = PackedVector2Array(
		[Vector2(0.0, 0.0) + Vector2(_bot_tuning.risk_enemy_territory_radius_m * 10.0, 0.0)]
	)
	var enemy_near: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.0)])
	assert_gt(_score(safe, PackedVector2Array(), enemy_far), _score(risky, PackedVector2Array(), enemy_near),
		"A candidate close to an enemy circle center is penalised relative to a safe one.")


func test_a_candidate_inside_the_active_special_risk_radius_is_penalised() -> void:
	var safe: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var risky: BotCandidate = _candidate(Vector2(0.0, 0.0), 1.0)
	var special_far: PackedVector2Array = PackedVector2Array(
		[Vector2(_bot_tuning.risk_active_special_radius_m * 10.0, 0.0)]
	)
	var special_near: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.0)])
	assert_gt(
		_score(safe, PackedVector2Array(), PackedVector2Array(), special_far),
		_score(risky, PackedVector2Array(), PackedVector2Array(), special_near),
		"A candidate close to an active special is penalised relative to a safe one."
	)


## -- score(): height -----------------------------------------------------------

func test_a_taller_candidate_scores_higher_all_else_equal() -> void:
	var tall: BotCandidate = _candidate(Vector2.ZERO, 5.0)
	var flat: BotCandidate = _candidate(Vector2.ZERO, 0.0)
	assert_gt(_score(tall), _score(flat))


## -- flattest_orientations -----------------------------------------------------

func test_cube_flattest_orientation_is_the_identity() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_cube_shape, 5)
	assert_false(result.is_empty())
	assert_eq(result[0], 0, "Any face of a cube is equally flat; the tie-break picks the identity first.")


func _assert_flat(shape: BlockShape, orientation_index: int) -> void:
	var basis: Basis = BlockOrientations.get_basis(orientation_index)
	var min_height: float = INF
	var max_height: float = -INF
	for cell: Vector3i in shape.cells:
		var height: float = (basis * Vector3(cell)).y
		min_height = minf(min_height, height)
		max_height = maxf(max_height, height)
	assert_almost_eq(min_height, max_height, 0.01,
		"Every cube of the flattest orientation must sit at the same height (lying flat, not standing on end).")


func test_bar4_flattest_orientation_lies_flat_not_on_end() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_bar4_shape, 5)
	assert_false(result.is_empty())
	_assert_flat(_bar4_shape, result[0])


func test_slab6_flattest_orientation_lies_flat_not_on_end() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_slab6_shape, 5)
	assert_false(result.is_empty())
	_assert_flat(_slab6_shape, result[0])


func test_pillar_flattest_orientation_lies_flat_not_on_end() -> void:
	# config/blocks/pillar.tres is a 3-cube vertical column
	# (Vector3i(0,0,0),(0,1,0),(0,2,0)) -- orientation 0 (identity) stands it
	# on end (heights 0/1/2, not flat), so the flattest lay must not be it.
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_pillar_shape, 5)
	assert_false(result.is_empty())
	assert_ne(result[0], 0, "orientation 0 stands the pillar on end; the flattest lay must not be the identity.")
	_assert_flat(_pillar_shape, result[0])


func test_l4_flattest_orientation_lies_flat_not_on_end() -> void:
	# config/blocks/L4.tres's cells span y = 0..2 under the identity
	# orientation (not flat), so its flattest lay must not be orientation 0.
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_l4_shape, 5)
	assert_false(result.is_empty())
	assert_ne(result[0], 0, "orientation 0 does not lay the L4 flat; the flattest lay must not be the identity.")
	_assert_flat(_l4_shape, result[0])


func test_flattest_orientations_returns_distinct_indices_up_to_max_count() -> void:
	var result: Array[int] = BotPlacementScorer.flattest_orientations(_cube_shape, 6)
	assert_eq(result.size(), 6)
	var seen: Dictionary = {}
	for index: int in result:
		assert_false(seen.has(index), "flattest_orientations() must not repeat an index.")
		seen[index] = true


func test_flattest_orientations_is_empty_for_a_shapeless_block_or_zero_count() -> void:
	var no_cells: BlockShape = BlockShape.new()
	assert_true(BotPlacementScorer.flattest_orientations(no_cells, 5).is_empty())
	assert_true(BotPlacementScorer.flattest_orientations(_cube_shape, 0).is_empty())


## -- pick_best ------------------------------------------------------------------

func test_pick_best_returns_null_on_an_empty_list() -> void:
	var empty: Array[BotCandidate] = []
	assert_null(BotPlacementScorer.pick_best(
		empty, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS
	))


func test_pick_best_returns_the_highest_scoring_candidate() -> void:
	var low: BotCandidate = _candidate(Vector2.ZERO, 0.0)
	var high: BotCandidate = _candidate(Vector2.ZERO, 5.0)
	var mid: BotCandidate = _candidate(Vector2.ZERO, 2.0)
	var candidates: Array[BotCandidate] = [low, high, mid]
	var best: BotCandidate = BotPlacementScorer.pick_best(
		candidates, _raster, _grid, 0, PackedVector2Array(), PackedVector2Array(), PackedVector2Array(),
		_bot_tuning, MAP_RADIUS
	)
	assert_eq(best, high)
