class_name SandboxConeComparison
extends RefCounted
## One-shot sandbox-only A/B calculation; never writes the authoritative raster.
## Both sides use the same settled-block snapshot and an uncapped solver.

static func measure(field: Field, angle_degrees: float) -> Dictionary:
	var live_raster: TerritoryRaster = Match.raster()
	var registry: BlockRegistry = Match.registry()
	if field == null or live_raster == null or registry == null or Match.config == null:
		return {"error": "Start a sandbox match before measuring territory."}
	var tuning: TerritoryTuning = live_raster.tuning().duplicate(true) as TerritoryTuning
	tuning.max_circles = 0 # Measuring all points; never change the live cap.
	var grid: CellGrid = live_raster.grid()
	var map_def: MapDef = Match.config.map_def()
	var slots: Array[PlayerSlot] = []
	var circles: Array[InfluenceCircle] = []
	var heights: PackedFloat32Array = PackedFloat32Array()
	var t0: int = Time.get_ticks_usec()
	for slot_id: int in range(Match.slot_count()):
		var slot: PlayerSlot = Match.slot(slot_id)
		slots.append(slot)
		if slot.home_flag_alive:
			circles.append(InfluenceCircle.for_home(slot.home_position, slot.team_id, slot.slot_id, tuning))
			heights.append(0.0)
	for circle: InfluenceCircle in registry.influence_circles(slots, tuning, map_def):
		var body: Block = instance_from_id(circle.body_id) as Block
		if body == null:
			continue
		circles.append(circle)
		var local_com: Vector3 = field.to_local(body.global_transform * body.center_of_mass)
		heights.append(maxf(local_com.y, 0.0))
	var t1: int = Time.get_ticks_usec()

	var baseline_solver: TerritorySolver = TerritorySolver.new(tuning)
	var baseline_groups: TerritoryGroups = baseline_solver.solve(circles)
	var t2: int = Time.get_ticks_usec()
	var holes_enabled: bool = Match.config.hole_mode != MatchConfig.HoleMode.OFF
	var permanent_holes: bool = Match.config.hole_mode == MatchConfig.HoleMode.PERMANENT
	var baseline: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	baseline.update(circles, baseline_groups, 0.0, holes_enabled, permanent_holes)
	var t3: int = Time.get_ticks_usec()

	var filtered: Dictionary = SandboxConeExperiment.build(circles, heights, angle_degrees)
	var cone_circles: Array[InfluenceCircle] = filtered["circles"]
	var t4: int = Time.get_ticks_usec()
	var cone_solver: TerritorySolver = TerritorySolver.new(tuning)
	var cone_groups: TerritoryGroups = cone_solver.solve(cone_circles)
	var t5: int = Time.get_ticks_usec()
	var experimental: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	experimental.update(cone_circles, cone_groups, 0.0, holes_enabled, permanent_holes)
	var t6: int = Time.get_ticks_usec()

	var original_owners: PackedByteArray = baseline.owner_bytes()
	var original_states: PackedByteArray = baseline.state_bytes()
	var cone_owners: PackedByteArray = experimental.owner_bytes()
	var cone_states: PackedByteArray = experimental.state_bytes()
	var changed: int = 0
	for index: int in grid.in_disk_cells():
		if original_owners[index] != cone_owners[index] or original_states[index] != cone_states[index]:
			changed += 1
	var result: Dictionary = {
		"candidate_count": filtered["candidate_count"],
		"kept_count": filtered["kept_count"],
		"culled_count": filtered["culled_count"],
		"different_percent": 100.0 * float(changed) / maxf(float(grid.in_disk_cell_count()), 1.0),
		"collect_ms": float(t1 - t0) / 1000.0,
		"old_solve_ms": float(t2 - t1) / 1000.0,
		"old_raster_ms": float(t3 - t2) / 1000.0,
		"old_total_ms": float(t3 - t0) / 1000.0,
		"cone_filter_ms": float(t4 - t3) / 1000.0,
		"cone_solve_ms": float(t5 - t4) / 1000.0,
		"cone_raster_ms": float(t6 - t5) / 1000.0,
		"cone_total_ms": float((t1 - t0) + (t6 - t3)) / 1000.0,
	}
	return {"metrics": result, "baseline": baseline, "cone": experimental}
