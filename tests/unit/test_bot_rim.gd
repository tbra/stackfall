extends GutTest
## Bontago-1t5.42: V2 bots see the live (shrunk) radius and avoid the disc rim.

const FULL_RADIUS_M: float = 30.0
const SHRUNK_RADIUS_M: float = 20.0
const CELL_M: float = 1.0
const TIP_WEIGHT: float = 3.0
const REACH_WEIGHT: float = 0.2
const TARGET: Vector2 = Vector2(5.0, 0.0)
const CENTRAL: Vector2 = Vector2(4.0, 0.0)
const RIM: Vector2 = Vector2(19.0, 0.0)
const OUTSIDE: Vector2 = Vector2(24.0, 0.0)
const LEVEL_TOP_M: float = 2.0


func _view(live: float) -> BotWorldView:
	var view: BotWorldView = BotWorldView.new()
	view.team_id = 0
	view.field_radius = FULL_RADIUS_M
	view.live_radius = live
	return view


func _site(origin: Vector2) -> BotCandidate:
	var c: BotCandidate = BotCandidate.new()
	c.origin = origin
	c.top_height = LEVEL_TOP_M
	return c


func _intent() -> BotIntent:
	var intent: BotIntent = BotIntent.new()
	intent.target = TARGET
	intent.weights[BotIntent.Term.TIP] = TIP_WEIGHT
	intent.weights[BotIntent.Term.REACH] = REACH_WEIGHT
	return intent


func test_full_size_central_scores_unchanged() -> void:
	var intent: BotIntent = _intent()
	var c: BotCandidate = _site(CENTRAL)
	var legacy: BotWorldView = _view(0.0)
	var full: BotWorldView = _view(FULL_RADIUS_M)
	assert_eq(BotEvaluator.rim_risk(c, full), 0.0, "far from the rim, no term")
	assert_eq(BotEvaluator.proxy(c, full, intent), BotEvaluator.proxy(c, legacy, intent), "bit-identical")


func test_rim_candidate_scores_below_central() -> void:
	var intent: BotIntent = _intent()
	var shrunk: BotWorldView = _view(SHRUNK_RADIUS_M)
	assert_lt(BotEvaluator.proxy(_site(RIM), shrunk, intent), BotEvaluator.proxy(_site(CENTRAL), shrunk, intent))
	var full: BotWorldView = _view(FULL_RADIUS_M)
	assert_lt(BotEvaluator.rim_risk(_site(Vector2(FULL_RADIUS_M - 0.5, 0.0)), full), BotEvaluator.tuning.rim_outside_penalty)
	assert_gt(BotEvaluator.rim_risk(_site(Vector2(FULL_RADIUS_M - 0.5, 0.0)), full), 0.0, "full-size rim also graded")


func test_beyond_live_radius_never_chosen() -> void:
	var intent: BotIntent = _intent()
	var shrunk: BotWorldView = _view(SHRUNK_RADIUS_M)
	var best: BotCandidate = null
	var best_score: float = -INF
	# The outside site sits nearer the target direction weight-wise only if the rim is ignored.
	intent.target = OUTSIDE
	for c: BotCandidate in [_site(CENTRAL), _site(RIM), _site(OUTSIDE)]:
		var s: float = BotEvaluator.proxy(c, shrunk, intent)
		if s > best_score:
			best_score = s
			best = c
	assert_ne(best.origin, OUTSIDE)
	assert_true(BotEvaluator.rim_risk(_site(OUTSIDE), shrunk) >= BotEvaluator.tuning.rim_outside_penalty)


func test_shrink_biases_to_centre() -> void:
	var shrunk: BotWorldView = _view(SHRUNK_RADIUS_M)
	var near: float = BotEvaluator.rim_risk(_site(Vector2(1.0, 0.0)), shrunk)
	var mid: float = BotEvaluator.rim_risk(_site(Vector2(10.0, 0.0)), shrunk)
	assert_lt(near, mid)
	assert_true(shrunk.is_shrunk())
	assert_false(_view(FULL_RADIUS_M).is_shrunk())


func test_live_radius_read_from_shrunk_raster() -> void:
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres") as TerritoryTuning
	var grid: CellGrid = CellGrid.new(FULL_RADIUS_M, CELL_M)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	var full: float = BotWorldView.live_radius_from_raster(raster, grid)
	assert_gt(full, FULL_RADIUS_M - 2.0 * CELL_M)
	for index: int in grid.in_disk_cells():
		var xy: Vector2i = grid.cell_coords(index)
		if grid.index_center(index).length() > SHRUNK_RADIUS_M:
			raster.force_hole_cell(xy.x, xy.y, 0.0, true)
	var live: float = BotWorldView.live_radius_from_raster(raster, grid)
	assert_true(live <= SHRUNK_RADIUS_M and live > SHRUNK_RADIUS_M - 2.0 * CELL_M, "live=%f" % live)
