extends GutTest
## Bontago-1pi.11.28 (P-ASYNC): the WorkerThreadPool territory solve must be
## bit-identical to the synchronous one.
##   A  raster split: update() == fill_ownership(shadow) + adopt_fill()
##   B  TerritorySolveJob: inline run() == run() inside a WorkerThreadPool task
##   C  end to end through MatchTerritory, every game mode, sync vs async
##   D  lifecycle: abort / timer end with a job in flight

const GRID_RADIUS: float = 16.0
const GRID_CELL: float = 1.0
const RANDOM_STEPS: int = 200
const RANDOM_BLOCKS: int = 14
const WAIT_TIMEOUT_MS: int = 5000

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")
var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _spy_records: Array = []
var _saved_threshold: int = 0


func before_each() -> void:
	_saved_threshold = Match._territory_tuning.async_solve_min_circles


func after_each() -> void:
	Match._territory_tuning.async_solve_min_circles = _saved_threshold
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


# --- helpers ---------------------------------------------------------------------------

func _random_circles(rng: RandomNumberGenerator) -> Array[InfluenceCircle]:
	var circles: Array[InfluenceCircle] = []
	circles.append(InfluenceCircle.new(Vector2(-9.0, 0.0), 6.0, 0, 0, true))
	circles.append(InfluenceCircle.new(Vector2(9.0, 1.0), 6.0, 1, 1, true))
	circles.append(InfluenceCircle.new(Vector2(0.0, -10.0), 6.0, 2, 2, true))
	for i: int in range(RANDOM_BLOCKS):
		var team: int = rng.randi_range(0, 2)
		circles.append(InfluenceCircle.new(
			Vector2(rng.randf_range(-12.0, 12.0), rng.randf_range(-12.0, 12.0)),
			rng.randf_range(1.5, 6.0), team, team, false, 100 + i
		))
	return circles


func _assert_rasters_equal(x: TerritoryRaster, y: TerritoryRaster, label: String) -> void:
	assert_eq(x.owner_bytes(), y.owner_bytes(), "%s: owner bytes" % label)
	assert_eq(x.state_bytes(), y.state_bytes(), "%s: state bytes" % label)
	assert_eq(x.holes_opened(), y.holes_opened(), "%s: opened order" % label)
	assert_eq(x.holes_closed(), y.holes_closed(), "%s: closed order" % label)
	assert_eq(x._active, y._active, "%s: active order" % label)
	assert_eq(x._contested_time, y._contested_time, "%s: contested_time" % label)
	assert_eq(x._group_ids, y._group_ids, "%s: group ids" % label)
	for team: int in range(3):
		assert_eq(x.team_share(team), y.team_share(team), "%s: share %d" % [label, team])


func _wait_for(job: TerritorySolveJob) -> void:
	var start: int = Time.get_ticks_msec()
	while not WorkerThreadPool.is_task_completed(job.task_id) and Time.get_ticks_msec() - start < WAIT_TIMEOUT_MS:
		OS.delay_msec(1)
	WorkerThreadPool.wait_for_task_completion(job.task_id)


# --- A: raster split -------------------------------------------------------------------

func _raster_split_run(holes_enabled: bool, permanent: bool) -> void:
	var grid: CellGrid = CellGrid.new(GRID_RADIUS, GRID_CELL)
	var x: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var y: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var shadow: TerritoryRaster = TerritoryRaster.new(grid, _tuning)
	var solver: TerritorySolver = TerritorySolver.new(_tuning)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2811
	var mismatches: int = 0
	for step: int in range(RANDOM_STEPS):
		# A fresh random layout every few steps, the same one otherwise, so both
		# changing and unchanging boards (timers draining) are covered.
		var circles: Array[InfluenceCircle] = _random_circles(rng) if step % 4 == 0 else _last_circles
		_last_circles = circles
		var groups: TerritoryGroups = solver.solve(circles)
		var delta: float = [0.05, 0.1, 0.25][rng.randi_range(0, 2)]
		x.update(circles, groups, delta, holes_enabled, permanent)
		shadow.fill_ownership(circles, groups, holes_enabled)
		y.adopt_fill(shadow, delta, holes_enabled, permanent)
		if x.owner_bytes() != y.owner_bytes() or x._active != y._active or x._contested_time != y._contested_time \
				or x.holes_opened() != y.holes_opened() or x.holes_closed() != y.holes_closed():
			mismatches += 1
			_assert_rasters_equal(x, y, "step %d" % step)
			if mismatches > 2:
				return
		if step % 7 == 3:
			var cx: int = rng.randi_range(2, grid.res - 3)
			var cy: int = rng.randi_range(2, grid.res - 3)
			x.force_hole_cell(cx, cy, 1.0, permanent)
			y.force_hole_cell(cx, cy, 1.0, permanent)
	assert_eq(mismatches, 0, "The split fill matched update() on all %d steps." % RANDOM_STEPS)
	_assert_rasters_equal(x, y, "final")
	for cy: int in range(grid.res):
		for cx: int in range(grid.res):
			assert_eq(x.group_at(cx, cy), y.group_at(cx, cy))


var _last_circles: Array[InfluenceCircle] = []


func test_raster_split_matches_update_legacy_temporary() -> void:
	_raster_split_run(true, false)


func test_raster_split_matches_update_legacy_permanent() -> void:
	_raster_split_run(true, true)


func test_raster_split_matches_update_v2() -> void:
	_raster_split_run(false, false)


# --- B: job inline vs worker -----------------------------------------------------------

func _make_job(circles: Array[InfluenceCircle], grid: CellGrid, cone: bool, holes: bool) -> TerritorySolveJob:
	var job: TerritorySolveJob = TerritorySolveJob.new()
	job.circles = circles
	job.cone_enabled = cone
	if cone:
		var heights: PackedFloat32Array = PackedFloat32Array()
		for i: int in range(circles.size()):
			heights.append(0.0 if circles[i].is_home else 0.7 + 0.37 * float(i % 9))
		job.heights = heights
		job.cone_angle = 55.0
		job.cone_base_mode = SandboxConeExperiment.BASE_ADDITIVE
		job.cone_base_radius = _tuning.influence_base
		job.cone_max_radius = _tuning.influence_max_fraction * GRID_RADIUS
	job.holes_enabled = holes
	job.solver_tuning = _tuning.duplicate() as TerritoryTuning
	job.fill_raster = TerritoryRaster.new(grid, _tuning)
	return job


func _assert_jobs_equal(a: TerritorySolveJob, b: TerritorySolveJob, label: String) -> void:
	assert_eq(a.out_circles.size(), b.out_circles.size(), "%s: circle count" % label)
	for i: int in range(mini(a.out_circles.size(), b.out_circles.size())):
		var p: InfluenceCircle = a.out_circles[i]
		var q: InfluenceCircle = b.out_circles[i]
		assert_true(
			p.center == q.center and p.radius == q.radius and p.team_id == q.team_id
			and p.slot_id == q.slot_id and p.is_home == q.is_home and p.body_id == q.body_id,
			"%s: circle %d" % [label, i]
		)
	assert_eq(a.groups.team_ids, b.groups.team_ids, "%s: group teams" % label)
	assert_eq(a.groups.circle_indices.size(), b.groups.circle_indices.size())
	for g: int in range(a.groups.group_count()):
		assert_eq(a.groups.circles_of(g), b.groups.circles_of(g), "%s: group %d members" % [label, g])
	assert_eq(a.render, b.render, "%s: render arrays" % label)
	assert_eq(a.fill_raster._group_ids, b.fill_raster._group_ids, "%s: group ids" % label)
	assert_eq(a.fill_raster._team_ids, b.fill_raster._team_ids, "%s: team ids" % label)
	assert_eq(a.fill_raster._newly_contested, b.fill_raster._newly_contested, "%s: contested order" % label)


func test_job_on_a_worker_matches_inline() -> void:
	var grid: CellGrid = CellGrid.new(GRID_RADIUS, GRID_CELL)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	for round_index: int in range(6):
		var circles: Array[InfluenceCircle] = _random_circles(rng)
		var cone: bool = round_index % 2 == 0
		var holes: bool = round_index % 3 != 0
		var inline_job: TerritorySolveJob = _make_job(circles, grid, cone, holes)
		var worker_job: TerritorySolveJob = _make_job(circles, grid, cone, holes)
		inline_job.run()
		worker_job.task_id = WorkerThreadPool.add_task(worker_job.run)
		_wait_for(worker_job)
		_assert_jobs_equal(inline_job, worker_job, "round %d cone=%s holes=%s" % [round_index, cone, holes])
		assert_gt(inline_job.render["xs"].size(), 0, "fixture: the render list is not empty")

		# cache_hit path: groups reused, no render rebuilt, fill still runs.
		var hit_inline: TerritorySolveJob = _make_job(circles, grid, false, holes)
		hit_inline.cache_hit = true
		hit_inline.cached_groups = inline_job.groups
		hit_inline.circles = inline_job.out_circles
		var hit_worker: TerritorySolveJob = _make_job(circles, grid, false, holes)
		hit_worker.cache_hit = true
		hit_worker.cached_groups = inline_job.groups
		hit_worker.circles = inline_job.out_circles
		hit_inline.run()
		hit_worker.task_id = WorkerThreadPool.add_task(hit_worker.run)
		_wait_for(hit_worker)
		_assert_jobs_equal(hit_inline, hit_worker, "cache hit round %d" % round_index)
		assert_true(hit_inline.render.is_empty(), "A cache hit builds no render list.")
		assert_eq(hit_inline.fill_raster._group_ids, inline_job.fill_raster._group_ids, "same fill from cached groups")


# --- C: end to end, every mode ---------------------------------------------------------

class _TimeSpyChecker:
	extends WinChecker
	var total: float = 0.0

	func update(raster: TerritoryRaster, delta: float) -> void:
		total += delta
		super.update(raster, delta)


func _world() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func _config(mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, minutes: int) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 3
	config.hot_seat = true
	config.hole_mode = holes
	config.block_timer = 6.0
	config.rng_seed = 99
	config.sudden_death = false
	config.game_mode = mode
	config.round_timer_minutes = minutes
	return config


func _start(mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, minutes: int, threshold: int) -> void:
	_world()
	Match._territory_tuning.async_solve_min_circles = threshold
	Match.start_match(_config(mode, holes, minutes))
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._territory._solve_accum = 0.0


func _place_blocks(first: int, count: int) -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	for slot: int in range(3):
		var home: Vector2 = Match.slot(slot).home_position
		for i: int in range(count):
			var block: Block = BlockFactory.build(shape, load("res://config/physics_tuning.tres") as PhysicsTuning, slot)
			_field.add_child(block)
			block.freeze = true
			var spot: Vector2 = home - home.normalized() * (3.0 + 2.1 * float(first + i))
			spot += Vector2(home.normalized().y, -home.normalized().x) * (0.4 * float((first + i) % 3))
			block.global_position = _field.to_global(Vector3(spot.x, 0.5 + 0.9 * float(i % 3), spot.y))
			Events.block_placed.emit(block, shape.id)
			_registry._entries[block.get_instance_id()].is_settled = true
	_registry.mark_territory_dirty()


func _on_updated(raster: TerritoryRaster, _groups: TerritoryGroups) -> void:
	var render: Dictionary = Match._territory.circle_render_arrays()
	_spy_records.append(["updated", raster.owner_bytes().duplicate(), raster.state_bytes().duplicate(), (render["xs"] as PackedFloat32Array).duplicate(), (render["radii"] as PackedFloat32Array).duplicate(), (render["teams"] as PackedInt32Array).duplicate()])


func _on_shares(shares: PackedFloat32Array) -> void:
	_spy_records.append(["shares", shares.duplicate()])


func _on_holes(opened: PackedInt32Array, closed: PackedInt32Array) -> void:
	_spy_records.append(["holes", opened.duplicate(), closed.duplicate()])


## One scripted match; returns every observable the async solve could change.
func _scenario(mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, threshold: int) -> Dictionary:
	_start(mode, holes, 0, threshold)
	_spy_records = []
	# The step counters live on the Match autoload and survive start_match().
	var solves_base: int = Match._territory.solve_step_count()
	var skips_base: int = Match._territory.clean_skip_count()
	var spy: _TimeSpyChecker = null
	if mode == MatchConfig.GameMode.CLASSIC:
		spy = _TimeSpyChecker.new(Match._territory._goal_positions, 100.0)
		Match._territory._win_checker = spy
	Events.territory_updated.connect(_on_updated)
	Events.territory_share_changed.connect(_on_shares)
	Events.hole_cells_changed.connect(_on_holes)
	_place_blocks(0, 8)
	var deltas: Array[float] = [0.1, 0.25, 0.05, 0.2]
	var step_log: Array = []
	var async_kickoffs: int = 0
	for round_index: int in range(14):
		if round_index == 5:
			_place_blocks(8, 5)
		if round_index == 8 and mode == MatchConfig.GameMode.ELIMINATION:
			var coords: Vector2i = Match.cell_grid().world_to_cell(Match.slot(1).home_position)
			Match._check_home_flags(PackedInt32Array([Match.cell_grid().cell_index(coords.x, coords.y)]))
		if round_index % 3 == 0:
			(_registry as BlockRegistry).block_settled.emit(round_index % 3, 2.0 + float(round_index))
		Match._territory._tick_territory(deltas[round_index % deltas.size()])
		if Match._territory.solve_pending():
			async_kickoffs += 1
			var start: int = Time.get_ticks_msec()
			while not WorkerThreadPool.is_task_completed(Match._territory._pending.task_id) and Time.get_ticks_msec() - start < WAIT_TIMEOUT_MS:
				OS.delay_msec(1)
		# Applies the finished job (and its owed catch-up steps) in async runs;
		# a no-op accumulate in the synchronous run.
		Match._territory._tick_territory(0.0)
		step_log.append(Match._territory._solve_accum)
	Events.territory_updated.disconnect(_on_updated)
	Events.territory_share_changed.disconnect(_on_shares)
	Events.hole_cells_changed.disconnect(_on_holes)
	var objective: ModeObjective = Match._territory._objective
	return {
		"records": _spy_records.duplicate(true),
		"accum": step_log,
		"solves": Match._territory.solve_step_count() - solves_base,
		"skips": Match._territory.clean_skip_count() - skips_base,
		"checker_total": spy.total if spy != null else -1.0,
		"scores": objective.scores(),
		"extra": objective.extra_state(),
		"winner": Match.winner_team(),
		"state": Match.state(),
		"pending": Match._territory.solve_pending(),
		"async_kickoffs": async_kickoffs,
	}


func _assert_scenario_equal(sync_result: Dictionary, async_result: Dictionary, label: String) -> void:
	assert_false(async_result["pending"], "%s: nothing left in flight" % label)
	assert_eq(sync_result["async_kickoffs"], 0, "%s: threshold 0 stays synchronous" % label)
	assert_gt(async_result["async_kickoffs"], 0, "%s: the async run really used a worker" % label)
	var a: Array = sync_result["records"]
	var b: Array = async_result["records"]
	assert_gt(a.size(), 0, "%s: fixture produced territory updates" % label)
	assert_eq(a.size(), b.size(), "%s: same event count" % label)
	if a.size() == b.size():
		for i: int in range(a.size()):
			assert_eq(a[i], b[i], "%s: event %d" % [label, i])
	for key: String in ["accum", "solves", "skips", "checker_total", "scores", "extra", "winner", "state"]:
		assert_eq(sync_result[key], async_result[key], "%s: %s" % [label, key])


func _compare_mode(mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, label: String) -> void:
	var sync_result: Dictionary = _scenario(mode, holes, 0)
	var async_result: Dictionary = _scenario(mode, holes, 1)
	_assert_scenario_equal(sync_result, async_result, label)


func test_classic_matches_sync_off_and_temporary() -> void:
	_compare_mode(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.OFF, "classic/off")
	_compare_mode(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.TEMPORARY, "classic/temporary")


func test_capture_flag_scores_match_sync() -> void:
	_compare_mode(MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.HoleMode.OFF, "ctf/off")
	_compare_mode(MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.HoleMode.TEMPORARY, "ctf/temporary")


func test_reach_sky_records_match_sync() -> void:
	_compare_mode(MatchConfig.GameMode.REACH_THE_SKY, MatchConfig.HoleMode.OFF, "sky/off")
	_compare_mode(MatchConfig.GameMode.REACH_THE_SKY, MatchConfig.HoleMode.TEMPORARY, "sky/temporary")


func test_elimination_outcome_matches_sync() -> void:
	_compare_mode(MatchConfig.GameMode.ELIMINATION, MatchConfig.HoleMode.OFF, "elim/off")
	_compare_mode(MatchConfig.GameMode.ELIMINATION, MatchConfig.HoleMode.TEMPORARY, "elim/temporary")


# --- D: lifecycle ----------------------------------------------------------------------

func test_abort_and_restart_with_a_job_in_flight_leave_nothing_pending() -> void:
	_start(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.TEMPORARY, 0, 1)
	_place_blocks(0, 6)
	Match._territory._tick_territory(0.1)
	assert_true(Match._territory.solve_pending(), "fixture: a solve is in flight")
	Match.abort_match()
	assert_false(Match._territory.solve_pending())
	_start(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.TEMPORARY, 0, 1)
	_place_blocks(0, 6)
	Match._territory._tick_territory(0.1)
	assert_true(Match._territory.solve_pending())
	Match.start_match(_config(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.TEMPORARY, 0))
	assert_false(Match._territory.solve_pending(), "A new match cancels the old job.")


func _timer_end_winner(threshold: int) -> Array:
	_start(MatchConfig.GameMode.CAPTURE_THE_FLAG, MatchConfig.HoleMode.OFF, 1, threshold)
	_place_blocks(0, 8)
	Match._territory._tick_territory(0.1)
	var pending_before: bool = Match._territory.solve_pending()
	Match._lifecycle._match_timer_left = 0.01
	Match._lifecycle._tick_match_timer(0.02)
	return [Match.state(), Match.winner_team(), Match._territory.solve_pending(), pending_before,
		Match._territory._objective.scores()]


func test_round_timer_end_flushes_the_job_and_matches_sync() -> void:
	var sync_result: Array = _timer_end_winner(0)
	var async_result: Array = _timer_end_winner(1)
	assert_true(async_result[3] as bool, "fixture: the job was in flight at the round end")
	assert_false(async_result[2] as bool, "The round end flushed it.")
	assert_eq(async_result[0], Match.State.END)
	assert_eq(sync_result[0], async_result[0])
	assert_eq(sync_result[1], async_result[1], "same winner")
	assert_eq(sync_result[4], async_result[4], "same scores")


# --- E: steady state (Bontago-1pi.11.28 fix pass) ---------------------------------------

func _steady_state_check(holes: MatchConfig.HoleMode, label: String) -> void:
	_start(MatchConfig.GameMode.CLASSIC, holes, 0, 1)
	_place_blocks(0, 8)
	# Drain the dirty solve: kick off, wait, apply, until the board is clean.
	for _i: int in range(6):
		Match._territory._tick_territory(0.1)
		if Match._territory.solve_pending():
			var start: int = Time.get_ticks_msec()
			while not WorkerThreadPool.is_task_completed(Match._territory._pending.task_id) and Time.get_ticks_msec() - start < WAIT_TIMEOUT_MS:
				OS.delay_msec(1)
			Match._territory._tick_territory(0.0)
	assert_false(Match._territory.solve_pending(), "%s: settled" % label)
	var solves_before: int = Match._territory.solve_step_count()
	var updates: Array = []
	var on_update: Callable = func(_r: TerritoryRaster, _g: TerritoryGroups) -> void: updates.append(1)
	Events.territory_updated.connect(on_update)
	for _i: int in range(40):
		Match._territory._tick_territory(0.1)
		assert_false(Match._territory.solve_pending(), "%s: no job launched at rest" % label)
	Events.territory_updated.disconnect(on_update)
	assert_eq(Match._territory.solve_step_count(), solves_before, "%s: no solve step at rest" % label)
	if holes == MatchConfig.HoleMode.OFF:
		assert_eq(updates.size(), 0, "%s: no territory_updated at rest" % label)


func test_no_job_and_no_update_at_rest_v2() -> void:
	_steady_state_check(MatchConfig.HoleMode.OFF, "v2")


func test_no_job_at_rest_legacy() -> void:
	_steady_state_check(MatchConfig.HoleMode.TEMPORARY, "legacy")


# --- F: mid-flight events and authority loss (Bontago-1pi.11.28 review fixes) -------------

func _wait_pending() -> void:
	if Match._territory.solve_pending():
		var start: int = Time.get_ticks_msec()
		while not WorkerThreadPool.is_task_completed(Match._territory._pending.task_id) and Time.get_ticks_msec() - start < WAIT_TIMEOUT_MS:
			OS.delay_msec(1)


func _drain(rounds: int) -> void:
	for _i: int in range(rounds):
		Match._territory._tick_territory(0.1)
		_wait_pending()
		Match._territory._tick_territory(0.0)


## Kick a 0.5 s tick, fire `event` while the job is in flight (sync: right after
## the solve), then drain. Returns every outcome the event could change.
func _midflight_outcome(
	mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, threshold: int, event: Callable
) -> Dictionary:
	_start(mode, holes, 0, threshold)
	_place_blocks(0, 8)
	Match._territory._tick_territory(0.5)
	if threshold > 0:
		assert_true(Match._territory.solve_pending(), "fixture: a solve is in flight")
	event.call()
	_wait_pending()
	Match._territory._tick_territory(0.0)
	_drain(8)
	var shares: PackedFloat32Array = PackedFloat32Array()
	for t: int in range(Match.config.team_count()):
		shares.append(Match._territory._raster.team_share(t))
	var alive: Array = []
	for slot_index: int in range(3):
		alive.append(Match.slot(slot_index).home_flag_alive)
	return {
		"owners": Match._territory._raster.owner_bytes().duplicate(),
		"states": Match._territory._raster.state_bytes().duplicate(),
		"shares": shares,
		"alive": alive,
		"scores": Match._territory._objective.scores(),
		"winner": Match.winner_team(),
		"state": Match.state(),
		"pending": Match._territory.solve_pending(),
	}


func _compare_midflight(
	mode: MatchConfig.GameMode, holes: MatchConfig.HoleMode, event: Callable, label: String
) -> void:
	var sync_result: Dictionary = _midflight_outcome(mode, holes, 0, event)
	var async_result: Dictionary = _midflight_outcome(mode, holes, 1, event)
	assert_false(async_result["pending"], "%s: nothing left in flight" % label)
	for key: String in ["owners", "states", "shares", "alive", "scores", "winner", "state"]:
		assert_eq(sync_result[key], async_result[key], "%s: %s" % [label, key])


func _punch_event() -> void:
	Match._territory.punch_special_hole(Match.slot(1).home_position * 0.5, 3.0, 600.0)


func _shrink_event() -> void:
	Match._territory.shrink_to_radius(12.0)


func _eliminate_event() -> void:
	var coords: Vector2i = Match.cell_grid().world_to_cell(Match.slot(1).home_position)
	Match._check_home_flags(PackedInt32Array([Match.cell_grid().cell_index(coords.x, coords.y)]))


func test_punch_during_flight_matches_sync() -> void:
	_compare_midflight(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.TEMPORARY, _punch_event, "punch")


func test_shrink_during_flight_matches_sync() -> void:
	_compare_midflight(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.PERMANENT, _shrink_event, "shrink/permanent")
	_compare_midflight(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.OFF, _shrink_event, "shrink/v2")


func test_elimination_during_flight_matches_sync() -> void:
	_compare_midflight(MatchConfig.GameMode.ELIMINATION, MatchConfig.HoleMode.OFF, _eliminate_event, "elim/v2")
	_compare_midflight(MatchConfig.GameMode.ELIMINATION, MatchConfig.HoleMode.TEMPORARY, _eliminate_event, "elim/legacy")


func test_forced_dirty_apply_reruns_through_the_worker_not_inline() -> void:
	_start(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.OFF, 0, 1)
	_place_blocks(0, 8)
	Match._territory._tick_territory(0.5)
	assert_true(Match._territory.solve_pending(), "fixture: first job in flight")
	var solves_after_kickoff: int = Match._territory.solve_step_count()
	Match._territory.mark_dirty()
	_wait_pending()
	Match._territory._tick_territory(0.0)
	assert_true(Match._territory.solve_pending(), "The forced re-solve is a new worker job.")
	assert_eq(Match._territory.solve_step_count(), solves_after_kickoff + 1, "exactly one kickoff, no inline solve")
	_wait_pending()
	Match._territory._tick_territory(0.0)
	assert_false(Match._territory.solve_pending())


func test_job_pending_across_demotion_is_cancelled() -> void:
	_start(MatchConfig.GameMode.CLASSIC, MatchConfig.HoleMode.OFF, 0, 1)
	_place_blocks(0, 8)
	Match._territory._tick_territory(0.1)
	assert_true(Match._territory.solve_pending(), "fixture: a solve is in flight")
	var provider: _NotHostProvider = _NotHostProvider.new()
	Match._net_provider = provider
	Match._territory._tick_territory(0.1)
	Match._net_provider = null
	assert_false(Match._territory.solve_pending(), "Losing authority cancels the in-flight job.")


class _NotHostProvider:
	func is_host() -> bool:
		return false
