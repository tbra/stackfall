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


func test_equal_height_does_not_cull_a_point() -> void:
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
		InfluenceCircle.new(Vector2.ZERO, 1.0, 0),
	]
	var result: Dictionary = SandboxConeExperiment.build(circles, PackedFloat32Array([5.0, 5.0]), 30.0)
	assert_eq(result["culled_count"], 0)


func test_additive_top_variant_matches_current_territory_map_at_current_slope() -> void:
	var tuning: TerritoryTuning = TerritoryTuning.new()
	tuning.max_circles = 0
	var radius: float = 20.0
	var circles: Array[InfluenceCircle] = [
		InfluenceCircle.for_home(Vector2(-8.0, 0.0), 0, 0, tuning),
		InfluenceCircle.new(Vector2(-4.0, 0.0), InfluenceCircle.radius_for_height(5.0, tuning, radius), 0, 0, false, 11, 5.0),
		InfluenceCircle.new(Vector2(-4.0, 0.0), InfluenceCircle.radius_for_height(10.0, tuning, radius), 0, 0, false, 12, 10.0),
		InfluenceCircle.for_home(Vector2(8.0, 0.0), 1, 1, tuning),
		InfluenceCircle.new(Vector2(4.0, 0.0), InfluenceCircle.radius_for_height(6.0, tuning, radius), 1, 1, false, 21, 6.0),
	]
	var result: Dictionary = SandboxConeExperiment.build(
		circles, PackedFloat32Array([0.0, 5.0, 10.0, 0.0, 6.0]),
		InfluenceCircle.CONE_HALF_ANGLE_DEGREES, SandboxConeExperiment.BASE_ADDITIVE,
		tuning.influence_base, tuning.influence_max_fraction * radius
	)
	assert_gt(result["culled_count"], 0)
	var projected: Array[InfluenceCircle] = result["circles"]
	var grid: CellGrid = CellGrid.new(radius, 1.0)
	var current: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	current.fill_ownership(circles, TerritorySolver.new(tuning).solve(circles), false)
	current.adopt_fill(current, 0.0, false, false)
	var experiment: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	experiment.fill_ownership(projected, TerritorySolver.new(tuning).solve(projected), false)
	experiment.adopt_fill(experiment, 0.0, false, false)
	assert_eq(experiment.owner_bytes(), current.owner_bytes())
	assert_eq(experiment.state_bytes(), current.state_bytes())


