extends GutTest
## Sandbox cone experiment; this does not test or alter the live territory rule.


func test_higher_cone_culls_contained_lower_point_but_preserves_home() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 6.0, 0, 0, true, -1),
		InfluenceCircle.new(Vector2.ZERO, 2.0, 0, 0, false, 11),
		InfluenceCircle.new(Vector2(1.0, 0.0), 2.0, 0, 0, false, 12),
	]
	var result: Dictionary = SandboxConeExperiment.build(circles, PackedFloat32Array([0.0, 10.0, 5.0]), 30.0)
	assert_eq(result["candidate_count"], 2)
	assert_eq(result["kept_count"], 1)
	assert_eq(result["culled_count"], 1)
	assert_eq(result["kept_indices"], PackedInt32Array([0, 1]))
	var projected: Array[InfluenceCircle] = result["circles"]
	assert_eq(projected[0].radius, 6.0, "Home keeps its original radius.")
	assert_almost_eq(projected[1].radius, 10.0 * tan(deg_to_rad(30.0)), 0.001)
	assert_eq(projected[1].body_id, 11)
	assert_eq(circles[1].radius, 2.0, "The input must not be mutated.")


func test_teams_are_separate_and_uncovered_low_point_survives() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
		InfluenceCircle.new(Vector2(10.0, 0.0), 1.0, 0),
		InfluenceCircle.new(Vector2.ZERO, 1.0, 1),
	]
	var result: Dictionary = SandboxConeExperiment.build(circles, PackedFloat32Array([10.0, 5.0, 5.0]), 30.0)
	assert_eq(result["culled_count"], 0)
	assert_eq(result["kept_indices"], PackedInt32Array([0, 1, 2]))


func test_output_order_and_metadata_follow_original_indices_after_height_sort() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2(10.0, 0.0), 2.0, 0, 3, false, 5),
		InfluenceCircle.new(Vector2.ZERO, 2.0, 0, 4, false, 6),
		InfluenceCircle.new(Vector2(0.1, 0.0), 2.0, 0, 5, false, 7),
	]
	var result: Dictionary = SandboxConeExperiment.build(circles, PackedFloat32Array([3.0, 9.0, 4.0]), 30.0)
	assert_eq(result["kept_indices"], PackedInt32Array([0, 1]))
	var projected: Array[InfluenceCircle] = result["circles"]
	assert_eq(projected[0].slot_id, 3)
	assert_eq(projected[0].body_id, 5)
	assert_eq(projected[1].slot_id, 4)
	assert_eq(projected[1].body_id, 6)


func test_equal_height_does_not_cull_a_point() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
	]
	var result: Dictionary = SandboxConeExperiment.build(circles, PackedFloat32Array([5.0, 5.0]), 30.0)
	assert_eq(result["culled_count"], 0)


func test_minimum_base_keeps_ground_block_visible_and_respects_cap() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 4.0, 0, 0, true),
		InfluenceCircle.new(Vector2(10.0, 0.0), 2.0, 0, 0, false, 11),
		InfluenceCircle.new(Vector2(20.0, 0.0), 2.0, 1, 1, false, 12),
	]
	var result: Dictionary = SandboxConeExperiment.build(
		circles, PackedFloat32Array([0.0, 0.0, 100.0]), 60.0,
		SandboxConeExperiment.BASE_FLOOR, 1.5, 27.0
	)
	var projected: Array[InfluenceCircle] = result["circles"]
	assert_eq(projected[1].radius, 1.5, "A block at disc height retains a footprint.")
	assert_eq(projected[2].radius, 27.0, "The current maximum radius also applies.")
	assert_eq(projected[0].radius, 4.0, "Home radius is unchanged.")


func test_additive_base_with_top_height_matches_current_radius_slope() -> void:
	var tuning: TerritoryTuning = TerritoryTuning.new()
	var top_height: float = 12.0
	var current_radius: float = InfluenceCircle.radius_for_height(top_height, tuning, 45.0)
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, current_radius, 0, 0, false, 11),
	]
	var angle: float = rad_to_deg(atan(tuning.influence_k))
	var result: Dictionary = SandboxConeExperiment.build(
		circles, PackedFloat32Array([top_height]), angle,
		SandboxConeExperiment.BASE_ADDITIVE, tuning.influence_base,
		tuning.influence_max_fraction * 45.0
	)
	var projected: Array[InfluenceCircle] = result["circles"]
	assert_almost_eq(projected[0].radius, current_radius, 0.0001)


func test_radius_cap_does_not_cull_equal_sized_tower_circles() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
	]
	var result: Dictionary = SandboxConeExperiment.build(
		circles, PackedFloat32Array([100.0, 80.0]), 60.0,
		SandboxConeExperiment.BASE_ADDITIVE, 1.5, 27.0
	)
	assert_eq(result["culled_count"], 0, "Equal capped radii cannot contain by height difference alone.")


func test_additive_top_variant_matches_current_territory_map_at_current_slope() -> void:
	var tuning: TerritoryTuning = TerritoryTuning.new()
	tuning.max_circles = 0
	var radius: float = 20.0
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(Vector2(-8.0, 0.0), 0, 0, tuning),
		InfluenceCircle.for_block(Vector2(-4.0, 0.0), 5.0, 0, 0, 11, tuning, radius),
		InfluenceCircle.for_block(Vector2(-4.0, 0.0), 10.0, 0, 0, 12, tuning, radius),
		InfluenceCircle.for_home(Vector2(8.0, 0.0), 1, 1, tuning),
		InfluenceCircle.for_block(Vector2(4.0, 0.0), 6.0, 1, 1, 21, tuning, radius),
	]
	var result: Dictionary = SandboxConeExperiment.build(
		circles, PackedFloat32Array([0.0, 5.0, 10.0, 0.0, 6.0]),
		rad_to_deg(atan(tuning.influence_k)), SandboxConeExperiment.BASE_ADDITIVE,
		tuning.influence_base, tuning.influence_max_fraction * radius
	)
	assert_gt(result["culled_count"], 0)
	var projected: Array[InfluenceCircle] = result["circles"]
	var grid: CellGrid = CellGrid.new(radius, 1.0)
	var current: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	current.update(circles, TerritorySolver.new(tuning).solve(circles), 0.0, false, false)
	var experiment: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	experiment.update(projected, TerritorySolver.new(tuning).solve(projected), 0.0, false, false)
	assert_eq(experiment.owner_bytes(), current.owner_bytes())
	assert_eq(experiment.state_bytes(), current.state_bytes())
