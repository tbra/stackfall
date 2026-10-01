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


## Bontago-1pi.11.22: the pre-change algorithm, kept verbatim as the oracle.
static func _oracle_build(
	circles: Array[InfluenceCircle],
	heights: PackedFloat32Array,
	angle_degrees: float,
	base_mode: int,
	base_radius: float,
	maximum_radius: float
) -> Dictionary:
	var count: int = mini(circles.size(), heights.size())
	var tangent: float = tan(deg_to_rad(clampf(angle_degrees, 0.0, 89.0)))
	var projected_radii: Array[float] = []
	var candidates: Array[int] = []
	for i: int in range(count):
		if circles[i].is_home:
			projected_radii.append(circles[i].radius)
			continue
		var radius: float = maxf(heights[i], 0.0) * tangent
		match base_mode:
			SandboxConeExperiment.BASE_FLOOR:
				radius = maxf(base_radius, radius)
			SandboxConeExperiment.BASE_ADDITIVE:
				radius += base_radius
		if base_mode != SandboxConeExperiment.BASE_NONE:
			radius = minf(radius, maximum_radius)
		projected_radii.append(radius)
		candidates.append(i)
	candidates.sort_custom(func(a: int, b: int) -> bool:
		if projected_radii[a] == projected_radii[b]:
			return a < b
		return projected_radii[a] > projected_radii[b]
	)
	var kept_block_indices: Array[int] = []
	var culled: PackedByteArray = PackedByteArray()
	culled.resize(count)
	var comparisons: int = 0
	for candidate_index: int in candidates:
		var candidate: InfluenceCircle = circles[candidate_index]
		var is_covered: bool = false
		for kept_index: int in kept_block_indices:
			var higher: InfluenceCircle = circles[kept_index]
			if higher.team_id != candidate.team_id:
				continue
			var radius_difference: float = projected_radii[kept_index] - projected_radii[candidate_index]
			if radius_difference <= 0.0:
				continue
			comparisons += 1
			if higher.center.distance_squared_to(candidate.center) <= radius_difference * radius_difference:
				is_covered = true
				break
		if is_covered:
			culled[candidate_index] = 1
		else:
			kept_block_indices.append(candidate_index)
	var projected: Array[InfluenceCircle] = []
	var kept_indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(count):
		var original: InfluenceCircle = circles[i]
		if culled[i] != 0:
			continue
		kept_indices.append(i)
		projected.append(InfluenceCircle.new(
			original.center, projected_radii[i], original.team_id,
			original.slot_id, original.is_home, original.body_id
		))
	return {
		"circles": projected,
		"candidate_count": candidates.size(),
		"kept_count": kept_block_indices.size(),
		"culled_count": candidates.size() - kept_block_indices.size(),
		"kept_indices": kept_indices,
		"comparison_count": comparisons,
	}


func _same_circle(a: InfluenceCircle, b: InfluenceCircle) -> bool:
	return (
		a.center == b.center and a.radius == b.radius and a.team_id == b.team_id
		and a.slot_id == b.slot_id and a.body_id == b.body_id and a.is_home == b.is_home
	)


func test_randomized_sets_match_the_pre_change_algorithm() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 2212
	var level_heights: PackedFloat32Array = PackedFloat32Array([0.0, 0.5, 1.0, 2.0, 3.5, 5.0])
	for set_index: int in range(500):
		var n: int = rng.randi_range(0, 300) if set_index % 10 != 0 else rng.randi_range(0, 4)
		var circles: Array[InfluenceCircle] = []
		var heights: PackedFloat32Array = PackedFloat32Array()
		var spread: float = rng.randf_range(1.0, 25.0)
		for i: int in range(n):
			var is_home: bool = rng.randi() % 25 == 0
			circles.append(InfluenceCircle.new(
				Vector2(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread)),
				rng.randf_range(1.0, 8.0), rng.randi() % 4, rng.randi() % 4, is_home, i
			))
			# Discrete levels force exact radius ties; some continuous values too.
			if rng.randf() < 0.7:
				heights.append(level_heights[rng.randi() % level_heights.size()])
			else:
				heights.append(rng.randf_range(0.0, 6.0))
		var mode: int = set_index % 3
		var angle: float = rng.randf_range(10.0, 60.0)
		var base_radius: float = rng.randf_range(0.0, 2.0)
		var max_radius: float = INF
		if rng.randf() < 0.5:
			max_radius = rng.randf_range(2.0, 10.0)
		var got: Dictionary = SandboxConeExperiment.build(circles, heights, angle, mode, base_radius, max_radius)
		var want: Dictionary = _oracle_build(circles, heights, angle, mode, base_radius, max_radius)
		for key: String in ["candidate_count", "kept_count", "culled_count", "kept_indices", "comparison_count"]:
			if got[key] != want[key]:
				fail_test("set %d key %s differs" % [set_index, key])
				return
		var got_circles: Array[InfluenceCircle] = got["circles"]
		var want_circles: Array[InfluenceCircle] = want["circles"]
		if got_circles.size() != want_circles.size():
			fail_test("set %d circle count differs" % set_index)
			return
		for i: int in range(got_circles.size()):
			if not _same_circle(got_circles[i], want_circles[i]):
				fail_test("set %d circle %d differs" % [set_index, i])
				return
	pass_test("500 randomized sets match the oracle")
