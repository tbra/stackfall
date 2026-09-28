class_name SandboxConeExperiment
extends RefCounted
## Sandbox-only alternative to the current influence rule. Optional base radius
## and cap let the cone be compared with the current block-radius formula.
## A retained cone removes another only when it completely contains it.
## Homes are never culled, and input circles are never mutated.
const BASE_NONE: int = 0
const BASE_FLOOR: int = 1
const BASE_ADDITIVE: int = 2


static func build(
	circles: Array[InfluenceCircle],
	heights: PackedFloat32Array,
	angle_degrees: float,
	base_mode: int = BASE_NONE,
	base_radius: float = 0.0,
	maximum_radius: float = INF
) -> Dictionary:
	assert(circles.size() == heights.size(), "Every circle needs a measured height.")
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
			BASE_FLOOR:
				radius = maxf(base_radius, radius)
			BASE_ADDITIVE:
				radius += base_radius
		if base_mode != BASE_NONE:
			radius = minf(radius, maximum_radius)
		projected_radii.append(radius)
		candidates.append(i)
	# Largest projected radius first; original index breaks ties deterministically.
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
			original.center,
			projected_radii[i],
			original.team_id,
			original.slot_id,
			original.is_home,
			original.body_id
		))
	return {
		"circles": projected,
		"candidate_count": candidates.size(),
		"kept_count": kept_block_indices.size(),
		"culled_count": candidates.size() - kept_block_indices.size(),
		"kept_indices": kept_indices,
		"comparison_count": comparisons,
	}
