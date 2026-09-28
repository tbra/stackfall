class_name SandboxConeComparison
extends RefCounted
## One-shot sandbox-only A/B calculation; never writes the authoritative raster.
## Both sides use the same settled-block snapshot and an uncapped solver.
const MODE_CONE: int = 0
const MODE_CONTAINMENT: int = 1
const HEIGHT_CENTER: int = 0
const HEIGHT_TOP: int = 1

static func measure(field: Field, mode: int, angle_degrees: float, height_source: int, base_mode: int) -> Dictionary:
	var live_raster: TerritoryRaster = Match.raster()
	var registry: BlockRegistry = Match.registry()
	if field == null or live_raster == null or registry == null or Match.config == null:
		return {"error": "Start a sandbox match before measuring territory."}
	if mode != MODE_CONE and mode != MODE_CONTAINMENT:
		return {"error": "Unknown territory experiment."}
	if mode == MODE_CONE and (height_source != HEIGHT_CENTER and height_source != HEIGHT_TOP):
		return {"error": "Unknown cone height source."}
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
			if mode == MODE_CONE:
				heights.append(0.0)
	for circle: InfluenceCircle in registry.influence_circles(slots, tuning, map_def):
		if mode == MODE_CONE:
			var body: Block = instance_from_id(circle.body_id) as Block
			if body == null:
				continue
			if height_source == HEIGHT_TOP:
				heights.append(registry.top_height_for_block(body))
			else:
				var local_com: Vector3 = field.to_local(body.global_transform * body.center_of_mass)
				heights.append(maxf(local_com.y, 0.0))
		circles.append(circle)
	var t1: int = Time.get_ticks_usec()

	var baseline_solver: TerritorySolver = TerritorySolver.new(tuning)
	var baseline_groups: TerritoryGroups = baseline_solver.solve(circles)
	var t2: int = Time.get_ticks_usec()
	var holes_enabled: bool = Match.config.hole_mode != MatchConfig.HoleMode.OFF
	var permanent_holes: bool = Match.config.hole_mode == MatchConfig.HoleMode.PERMANENT
	var baseline: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	baseline.update(circles, baseline_groups, 0.0, holes_enabled, permanent_holes)
	var t3: int = Time.get_ticks_usec()

	var filtered: Dictionary
	if mode == MODE_CONE:
		filtered = SandboxConeExperiment.build(
			circles, heights, angle_degrees, base_mode, tuning.influence_base,
			tuning.influence_max_fraction * map_def.field_radius
		)
	else:
		filtered = SandboxContainmentExperiment.build(circles)
	var experiment_circles: Array[InfluenceCircle] = filtered["circles"]
	var t4: int = Time.get_ticks_usec()
	var experiment_solver: TerritorySolver = TerritorySolver.new(tuning)
	var experiment_groups: TerritoryGroups = experiment_solver.solve(experiment_circles)
	var t5: int = Time.get_ticks_usec()
	var experimental: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	experimental.update(experiment_circles, experiment_groups, 0.0, holes_enabled, permanent_holes)
	var t6: int = Time.get_ticks_usec()

	var original_owners: PackedByteArray = baseline.owner_bytes()
	var original_states: PackedByteArray = baseline.state_bytes()
	var experiment_owners: PackedByteArray = experimental.owner_bytes()
	var experiment_states: PackedByteArray = experimental.state_bytes()
	var changed: int = 0
	for index: int in grid.in_disk_cells():
		if original_owners[index] != experiment_owners[index] or original_states[index] != experiment_states[index]:
			changed += 1
	var result: Dictionary = {
		"method": "Cone" if mode == MODE_CONE else "Containment",
		"candidate_count": filtered["candidate_count"],
		"kept_count": filtered["kept_count"],
		"culled_count": filtered["culled_count"],
		"comparison_count": filtered["comparison_count"],
		"different_cells": changed,
		"different_percent": 100.0 * float(changed) / maxf(float(grid.in_disk_cell_count()), 1.0),
		"collect_ms": float(t1 - t0) / 1000.0,
		"old_solve_ms": float(t2 - t1) / 1000.0,
		"old_raster_ms": float(t3 - t2) / 1000.0,
		"old_total_ms": float(t3 - t0) / 1000.0,
		"experiment_filter_ms": float(t4 - t3) / 1000.0,
		"experiment_solve_ms": float(t5 - t4) / 1000.0,
		"experiment_raster_ms": float(t6 - t5) / 1000.0,
		"experiment_total_ms": float((t1 - t0) + (t6 - t3)) / 1000.0,
	}
	return {"metrics": result, "baseline": baseline, "experiment": experimental}
