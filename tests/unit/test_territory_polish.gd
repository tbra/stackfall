extends GutTest
## Bontago-1pi.11.33: packed-key render sort, circle-mode containment cull before
## the budget, and bake-on-settle.

const FIELD_RADIUS: float = 20.0


func _random_circles(rng: RandomNumberGenerator, count: int) -> Array[InfluenceCircle]:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(-8.0, 0.0), 4.0, 0, 0, true, -1),
		InfluenceCircle.new(Vector2(8.0, 0.0), 4.0, 1, 1, true, -2),
	]
	for i: int in range(count):
		var team: int = rng.randi_range(0, 1)
		var cx: float = (-7.0 if team == 0 else 7.0) + rng.randf_range(-4.0, 4.0)
		var radius: float = rng.randf_range(0.5, 6.0)
		circles.append(InfluenceCircle.new(Vector2(cx, rng.randf_range(-4.0, 4.0)), radius, team, team, false, i))
	return circles


func _job_raster(circles: Array[InfluenceCircle], max_circles: int, cull: bool) -> TerritoryRaster:
	var tuning: TerritoryTuning = TerritoryTuning.new()
	tuning.max_circles = max_circles
	var job: TerritorySolveJob = TerritorySolveJob.new()
	var used: Array[InfluenceCircle] = circles
	if cull:
		used = SandboxContainmentExperiment.build(circles)["circles"]
	job.circles = used
	job.solver_tuning = tuning
	job.holes_enabled = false
	job.fill_raster = TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, 1.0), tuning)
	if cull:
		job.circles = circles
	else:
		# Bypass the job's own cull: solve the uncut list directly.
		var solver: TerritorySolver = TerritorySolver.new(tuning)
		var groups: TerritoryGroups = solver.solve(circles)
		job.fill_raster.fill_ownership(circles, groups, false)
		return job.fill_raster
	job.run()
	return job.fill_raster


func test_render_sort_matches_comparator_order() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 33
	for round_index: int in range(10):
		var circles: Array[InfluenceCircle] = []
		var groups: TerritoryGroups = TerritoryGroups.new()
		for team: int in range(3):
			var ids: PackedInt32Array = PackedInt32Array()
			for n: int in range(rng.randi_range(1, 40)):
				ids.append(circles.size())
				circles.append(InfluenceCircle.new(
					Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0)),
					rng.randf_range(0.5, 8.0), team, team
				))
			groups.add_group(team, ids)
		var entries: Array = []
		for g: int in range(groups.group_count()):
			for i: int in groups.circles_of(g):
				entries.append([groups.team_of(g), circles[i].radius, circles[i].center.x, circles[i].center.y])
		entries.sort_custom(func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] < b[0]
			return a[1] > b[1])
		var render: Dictionary = TerritorySolveJob.build_render_list(circles, groups)
		var xs: PackedFloat32Array = render["xs"]
		assert_eq(xs.size(), entries.size())
		for i: int in range(entries.size()):
			assert_eq(render["teams"][i], entries[i][0])
			assert_eq(render["radii"][i], entries[i][1])
			assert_eq(xs[i], entries[i][2])
			assert_eq(render["zs"][i], entries[i][3])


func test_render_sort_ties_keep_insertion_order() -> void:
	var circles: Array[InfluenceCircle] = []
	var ids: PackedInt32Array = PackedInt32Array()
	for i: int in range(40):
		ids.append(i)
		circles.append(InfluenceCircle.new(Vector2(float(i), 0.0), 2.0, 0, 0))
	var groups: TerritoryGroups = TerritoryGroups.new()
	groups.add_group(0, ids)
	var render: Dictionary = TerritorySolveJob.build_render_list(circles, groups)
	for i: int in range(40):
		assert_eq(render["xs"][i], float(i))


func test_containment_cull_raster_equivalence_random_sets() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1133
	var culled_total: int = 0
	for round_index: int in range(12):
		var circles: Array[InfluenceCircle] = _random_circles(rng, rng.randi_range(20, 70))
		culled_total += int(SandboxContainmentExperiment.build(circles)["culled_count"])
		var plain: TerritoryRaster = _job_raster(circles, 0, false)
		var culled: TerritoryRaster = _job_raster(circles, 0, true)
		assert_eq(culled.owner_bytes(), plain.owner_bytes(), "owner bytes, round %d" % round_index)
		assert_eq(culled.state_bytes(), plain.state_bytes(), "state bytes, round %d" % round_index)
	assert_gt(culled_total, 0, "fixture must actually cull something")


func test_containment_cull_runs_before_the_budget() -> void:
	# Cap below the raw count but above the culled count: with the cull first
	# nothing meaningful is dropped, so the result equals the unbudgeted raster.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 77
	var checked: int = 0
	for round_index: int in range(12):
		var circles: Array[InfluenceCircle] = _random_circles(rng, 60)
		var kept_count: int = (SandboxContainmentExperiment.build(circles)["circles"] as Array).size()
		if kept_count >= circles.size():
			continue
		var cap: int = kept_count
		var ideal: TerritoryRaster = _job_raster(circles, 0, false)
		var culled_first: TerritoryRaster = _job_raster(circles, cap, true)
		assert_eq(culled_first.owner_bytes(), ideal.owner_bytes(), "budget after cull, round %d" % round_index)
		assert_eq(culled_first.state_bytes(), ideal.state_bytes())
		checked += 1
	assert_gt(checked, 0)


func _overlay_with_bake() -> TerritoryOverlay:
	var map_def: MapDef = MapDef.new()
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	add_child_autofree(overlay)
	overlay._bake_headless_ok = true
	return overlay


func _upload(overlay: TerritoryOverlay, radius: float) -> void:
	overlay.set_circles(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([radius]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), true
	)


func test_bake_is_deferred_during_churn_and_runs_once_on_settle() -> void:
	var overlay: TerritoryOverlay = _overlay_with_bake()
	_upload(overlay, 5.0)
	assert_eq(overlay.bake_count(), 1, "first bake is immediate")
	overlay.set_churning(true)
	for i: int in range(6):
		_upload(overlay, 6.0 + float(i))
	assert_eq(overlay.bake_count(), 1, "no bake while churning")
	assert_true(overlay.bake_pending())
	overlay.set_churning(false)
	assert_eq(overlay.bake_count(), 2, "one bake on settle")
	assert_false(overlay.bake_pending())


func test_deferred_bake_is_flushed_at_the_staleness_cap() -> void:
	var overlay: TerritoryOverlay = _overlay_with_bake()
	_upload(overlay, 5.0)
	overlay.set_churning(true)
	_upload(overlay, 7.0)
	assert_eq(overlay.bake_count(), 1)
	overlay._bake_deadline_msec -= 600
	overlay._process(0.016)
	assert_eq(overlay.bake_count(), 2, "cap reached while still churning")


func test_bake_after_expired_solve_deferral_is_immediate() -> void:
	# F4: a solve applied after waiting the full cap leaves the bake no budget.
	var overlay: TerritoryOverlay = _overlay_with_bake()
	_upload(overlay, 5.0)
	overlay.set_churning(true, 0.5)
	_upload(overlay, 7.0)
	assert_eq(overlay.bake_count(), 2, "no further deferral after a full solve wait")
	assert_false(overlay.bake_pending())


func test_worst_case_visible_delay_stays_within_the_cap() -> void:
	var overlay: TerritoryOverlay = _overlay_with_bake()
	var cap_msec: int = int(overlay._tuning.solve_defer_max_s * 1000.0)
	for waited_s: float in [0.0, 0.1, 0.3, 0.45]:
		overlay.set_churning(false)
		_upload(overlay, 5.0 + waited_s * 10.0)
		var baked: int = overlay.bake_count()
		overlay.set_churning(true, waited_s)
		_upload(overlay, 9.0 + waited_s * 10.0)
		assert_true(overlay.bake_pending(), "parked for waited %.2f" % waited_s)
		var park_msec: int = overlay._bake_deadline_msec - Time.get_ticks_msec()
		var total: int = int(waited_s * 1000.0) + park_msec
		assert_lte(total, cap_msec, "solve wait + bake park within cap, waited %.2f" % waited_s)
		# A later, fresher solve cannot extend the original deadline.
		var deadline: int = overlay._bake_deadline_msec
		overlay.set_churning(true, 0.0)
		_upload(overlay, 11.0 + waited_s * 10.0)
		assert_lte(overlay._bake_deadline_msec, deadline)
		overlay._bake_deadline_msec = Time.get_ticks_msec() - 1
		overlay._process(0.016)
		assert_eq(overlay.bake_count(), baked + 1, "parked bake and the fresher one merged into one")
		assert_false(overlay.bake_pending(), "flushed at deadline")


func _group_signature(circles: Array[InfluenceCircle], groups: TerritoryGroups, keep: Dictionary) -> Array:
	var sig: Array = []
	for g: int in range(groups.group_count()):
		var members: Array = []
		for i: int in groups.circles_of(g):
			var c: InfluenceCircle = circles[i]
			var key: String = "%s|%s|%s" % [c.center, c.radius, c.team_id]
			if keep.has(key):
				members.append(key)
		members.sort()
		sig.append([groups.team_of(g), members])
	sig.sort()
	return sig


func test_cull_preserves_groups_with_cut_off_circles() -> void:
	# A team-0 island far from any home (cut off), with a contained circle inside it,
	# plus a chain to the home with a contained circle: groups must be identical.
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(-8.0, 0.0), 4.0, 0, 0, true, -1),
		InfluenceCircle.new(Vector2(8.0, 0.0), 4.0, 1, 1, true, -2),
		InfluenceCircle.new(Vector2(-5.0, 0.0), 3.0, 0, 0, false, 0),
		InfluenceCircle.new(Vector2(-5.0, 0.5), 1.0, 0, 0, false, 1),
		InfluenceCircle.new(Vector2(0.0, 12.0), 3.0, 0, 0, false, 2),
		InfluenceCircle.new(Vector2(0.2, 12.0), 1.0, 0, 0, false, 3),
		InfluenceCircle.new(Vector2(0.0, -12.0), 2.5, 1, 1, false, 4),
		InfluenceCircle.new(Vector2(0.0, -12.0), 0.8, 1, 1, false, 5),
	]
	var culled_list: Array[InfluenceCircle] = SandboxContainmentExperiment.build(circles)["circles"]
	assert_eq(culled_list.size(), circles.size() - 3, "three contained circles removed")
	var keep: Dictionary = {}
	for c: InfluenceCircle in culled_list:
		keep["%s|%s|%s" % [c.center, c.radius, c.team_id]] = true
	var tuning: TerritoryTuning = TerritoryTuning.new()
	var plain: TerritoryGroups = TerritorySolver.new(tuning).solve(circles)
	var culled: TerritoryGroups = TerritorySolver.new(tuning).solve(culled_list)
	assert_eq(culled.group_count(), plain.group_count())
	assert_eq(
		_group_signature(culled_list, culled, keep), _group_signature(circles, plain, keep),
		"groups equal once culled members are ignored"
	)


func test_cull_with_cap_below_kept_is_at_least_as_close_to_uncapped() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 5133
	var checked: int = 0
	for round_index: int in range(12):
		var circles: Array[InfluenceCircle] = _random_circles(rng, 70)
		var kept_count: int = (SandboxContainmentExperiment.build(circles)["circles"] as Array).size()
		var cap: int = kept_count - 6
		if cap < 4 or kept_count >= circles.size():
			continue
		var ideal: PackedByteArray = _job_raster(circles, 0, false).owner_bytes()
		var old_path: PackedByteArray = _job_raster(circles, cap, false).owner_bytes()
		var new_path: PackedByteArray = _job_raster(circles, cap, true).owner_bytes()
		var old_diff: int = 0
		var new_diff: int = 0
		for i: int in range(ideal.size()):
			old_diff += 1 if old_path[i] != ideal[i] else 0
			new_diff += 1 if new_path[i] != ideal[i] else 0
		assert_lte(new_diff, old_diff, "culled+budgeted no farther from uncapped, round %d" % round_index)
		checked += 1
	assert_gt(checked, 0)


func test_async_solve_path_with_cull_matches_inline() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 9133
	var circles: Array[InfluenceCircle] = _random_circles(rng, 60)
	var tuning: TerritoryTuning = TerritoryTuning.new()
	var jobs: Array[TerritorySolveJob] = []
	for i: int in range(2):
		var job: TerritorySolveJob = TerritorySolveJob.new()
		job.circles = circles
		job.solver_tuning = tuning
		job.holes_enabled = false
		job.fill_raster = TerritoryRaster.new(CellGrid.new(FIELD_RADIUS, 1.0), tuning)
		jobs.append(job)
	jobs[0].run()
	jobs[1].task_id = WorkerThreadPool.add_task(jobs[1].run)
	WorkerThreadPool.wait_for_task_completion(jobs[1].task_id)
	assert_lt(jobs[1].out_circles.size(), circles.size(), "cull fired on the worker")
	assert_eq(jobs[1].out_circles.size(), jobs[0].out_circles.size())
	assert_eq(jobs[1].fill_raster.owner_bytes(), jobs[0].fill_raster.owner_bytes())
	assert_eq(jobs[1].fill_raster.state_bytes(), jobs[0].fill_raster.state_bytes())
	assert_eq(jobs[1].render["radii"], jobs[0].render["radii"])
	assert_eq(jobs[1].groups.group_count(), jobs[0].groups.group_count())
