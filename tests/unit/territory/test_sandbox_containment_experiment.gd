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


