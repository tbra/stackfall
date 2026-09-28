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
