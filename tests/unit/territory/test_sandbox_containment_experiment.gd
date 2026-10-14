extends GutTest
## Exact-radius sandbox pruning must preserve the current territory result.


func test_contained_block_is_removed_without_changing_radius_or_home() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 6.0, 0, 0, true, -1),
		InfluenceCircle.new(Vector2(0.5, 0.0), 2.0, 0, 0, false, 11),
		InfluenceCircle.new(Vector2(8.0, 0.0), 4.0, 0, 0, false, 12),
	]
	var result: Dictionary = SandboxContainmentExperiment.build(circles)
	assert_eq(result["candidate_count"], 2)
	assert_eq(result["culled_count"], 1)
	assert_eq(result["kept_count"], 1)
	assert_eq(result["kept_indices"], PackedInt32Array([0, 2]))
	var kept: Array[InfluenceCircle] = result["circles"]
	assert_same(kept[0], circles[0])
	assert_same(kept[1], circles[2])
	assert_eq(kept[1].radius, 4.0)


func test_overlapping_but_not_contained_and_other_team_survive() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 5.0, 0),
		InfluenceCircle.new(Vector2(4.0, 0.0), 2.0, 0),
		InfluenceCircle.new(Vector2.ZERO, 2.0, 1),
	]
	var result: Dictionary = SandboxContainmentExperiment.build(circles)
	assert_eq(result["culled_count"], 0)
	assert_eq(result["kept_indices"], PackedInt32Array([0, 1, 2]))


func test_filtered_raster_matches_current_for_both_hole_modes() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(-8.0, 0.0), 6.0, 0, 0, true),
		InfluenceCircle.new(Vector2(-3.0, 0.0), 8.0, 0, 0, false, 11),
		InfluenceCircle.new(Vector2(-2.0, 0.0), 2.0, 0, 0, false, 12),
		InfluenceCircle.new(Vector2(8.0, 0.0), 6.0, 1, 1, true),
		InfluenceCircle.new(Vector2(3.0, 0.0), 8.0, 1, 1, false, 21),
		InfluenceCircle.new(Vector2(2.0, 0.0), 2.0, 1, 1, false, 22),
	]
	var filtered: Dictionary = SandboxContainmentExperiment.build(circles)
	assert_eq(filtered["culled_count"], 2)
	var reduced: Array[InfluenceCircle] = filtered["circles"]
	var tuning: TerritoryTuning = TerritoryTuning.new()
	tuning.max_circles = 0
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	for holes_enabled: bool in [false, true]:
		var current: TerritoryRaster = TerritoryRaster.new(grid, tuning)
		current.update(circles, TerritorySolver.new(tuning).solve(circles), 0.0, holes_enabled, false)
		var experiment: TerritoryRaster = TerritoryRaster.new(grid, tuning)
		experiment.update(reduced, TerritorySolver.new(tuning).solve(reduced), 0.0, holes_enabled, false)
		assert_eq(experiment.owner_bytes(), current.owner_bytes())
		assert_eq(experiment.state_bytes(), current.state_bytes())


func test_mixed_tower_and_pile_keep_the_same_map() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(-8.0, 0.0), 6.0, 0, 0, true),
		InfluenceCircle.new(Vector2(8.0, 0.0), 6.0, 1, 1, true),
	]
	for height: int in range(1, 31):
		circles.append(InfluenceCircle.new(
			Vector2(-7.0 + 0.03 * float(height % 4), 0.04 * float(height % 3)),
			2.0 + 0.9 * float(height), 0, 0, false, height
		))
	for block_index: int in range(60):
		circles.append(InfluenceCircle.new(
			Vector2(5.0 + float(block_index % 10) * 0.55, -2.0 + float(block_index / 10) * 0.55),
			2.4 + 0.05 * float(block_index % 5), 1, 1, false, 100 + block_index
		))
	var filtered: Dictionary = SandboxContainmentExperiment.build(circles)
	assert_gt(filtered["culled_count"], 20)
	var reduced: Array[InfluenceCircle] = filtered["circles"]
	var tuning: TerritoryTuning = TerritoryTuning.new()
	tuning.max_circles = 0
	var grid: CellGrid = CellGrid.new(20.0, 1.0)
	var current: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	current.update(circles, TerritorySolver.new(tuning).solve(circles), 0.0, false, false)
	var experiment: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	experiment.update(reduced, TerritorySolver.new(tuning).solve(reduced), 0.0, false, false)
	assert_eq(experiment.owner_bytes(), current.owner_bytes())
	assert_eq(experiment.state_bytes(), current.state_bytes())
