class_name SandboxConeExperiment
extends RefCounted
## Sandbox-only alternative to the current influence rule. A block's projected
## cone has radius height * tan(angle) at the disc; a higher, retained cone can
## remove a lower point only when it completely contains that lower cone.
## Homes are never culled, and input circles are never mutated.


static func build(
	circles: Array[InfluenceCircle],
	center_heights: PackedFloat32Array,
	angle_degrees: float
) -> Dictionary:
	assert(circles.size() == center_heights.size(), "Every circle needs a center height.")
	var count: int = mini(circles.size(), center_heights.size())
	var tangent: float = tan(deg_to_rad(clampf(angle_degrees, 0.0, 89.0)))
	var candidates: Array[int] = []
	for i: int in range(count):
		if not circles[i].is_home:
			candidates.append(i)
	# Highest first; original index breaks height ties for deterministic output.
	candidates.sort_custom(func(a: int, b: int) -> bool:
		if center_heights[a] == center_heights[b]:
			return a < b
		return center_heights[a] > center_heights[b]
	)

	var kept_block_indices: Array[int] = []
	var culled: PackedByteArray = PackedByteArray()
	culled.resize(count)
	var comparisons: int = 0
	for candidate_index: int in candidates:
		var candidate: InfluenceCircle = circles[candidate_index]
		var candidate_height: float = maxf(center_heights[candidate_index], 0.0)
		var is_covered: bool = false
		for kept_index: int in kept_block_indices:
			var higher: InfluenceCircle = circles[kept_index]
			if higher.team_id != candidate.team_id:
				continue
			var height_difference: float = maxf(center_heights[kept_index], 0.0) - candidate_height
			if height_difference <= 0.0:
				continue
			comparisons += 1
			var containment_reach: float = height_difference * tangent
			if higher.center.distance_squared_to(candidate.center) <= containment_reach * containment_reach:
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
		var projected_radius: float = original.radius if original.is_home else maxf(center_heights[i], 0.0) * tangent
		projected.append(InfluenceCircle.new(
			original.center,
			projected_radius,
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
