extends GutTest
## Territory render polish: the circle-mode containment cull before the shader
## budget, and the overlay's bake-on-settle.

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


func _overlay_with_bake() -> TerritoryOverlay:
	var map_def: MapDef = MapDef.new()
	var overlay: TerritoryOverlay = TerritoryOverlay.new()
	overlay.configure(map_def, load("res://config/territory/territory_visuals.tres"), load("res://config/territory/territory_tuning.tres"))
	add_child_autofree(overlay)
	overlay._bake_headless_ok = true
	return overlay


func _upload(overlay: TerritoryOverlay, radius: float) -> void:
	overlay.set_circles(
		PackedFloat32Array([0.0]), PackedFloat32Array([0.0]), PackedFloat32Array([radius]),
		PackedInt32Array([0]), PackedVector2Array(), PackedFloat32Array(), true
	)


## A bake that ran stores the circle set it rendered as `_bake_key`; a deferred one leaves the old key.
func test_bake_is_deferred_during_churn_and_runs_once_on_settle() -> void:
	var overlay: TerritoryOverlay = _overlay_with_bake()
	_upload(overlay, 5.0)
	var first_key: Array = overlay._bake_key.duplicate()
	assert_false(first_key.is_empty(), "first bake is immediate")
	overlay.set_churning(true)
	for i: int in range(6):
		_upload(overlay, 6.0 + float(i))
	assert_eq(overlay._bake_key, first_key, "no bake while churning")
	assert_true(overlay._bake_pending)
	overlay.set_churning(false)
	assert_ne(overlay._bake_key, first_key, "one bake on settle")
	assert_false(overlay._bake_pending)


func test_deferred_bake_is_flushed_at_the_staleness_cap() -> void:
	var overlay: TerritoryOverlay = _overlay_with_bake()
	_upload(overlay, 5.0)
	overlay.set_churning(true)
	_upload(overlay, 7.0)
	var first_key: Array = overlay._bake_key.duplicate()
	overlay._bake_deadline_msec -= 600
	overlay._process(0.016)
	assert_ne(overlay._bake_key, first_key, "cap reached while still churning")


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


