class_name SandboxConeExperiment
extends RefCounted
## Cone-projected influence used by live matches and the sandbox A/B view.
## Optional base radius and cap allow comparison with the earlier formula.
## A retained cone removes another only when it completely contains it.
## Homes are never culled, and input circles are never mutated.
const BASE_NONE: int = 0
const BASE_FLOOR: int = 1
const BASE_ADDITIVE: int = 2
const HEIGHT_CENTER: int = 0
const HEIGHT_TOP: int = 1


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
	# Native lexicographic Array sort on [-radius, index] (64-bit, no rounding)
	# replaces a GDScript lambda comparator (Bontago-1pi.11.22).
	var sort_keys: Array = []
	sort_keys.resize(candidates.size())
	for k: int in range(candidates.size()):
		sort_keys[k] = [-projected_radii[candidates[k]], candidates[k]]
	sort_keys.sort()

	var kept_block_indices: Array[int] = []
	var culled: PackedByteArray = PackedByteArray()
	culled.resize(count)
	var comparisons: int = 0
	# Per-team kept cones in flat parallel arrays (stride = candidate count per
	# team lane), so the containment loop only visits same-team cones and no
	# packed array is copied per candidate.
	var lane_of_team: Dictionary = {}  ## team_id -> lane
	var lane_count: PackedInt32Array = PackedInt32Array()
	var stride: int = candidates.size()
	var kept_centers: PackedVector2Array = PackedVector2Array()
	var kept_radii: PackedFloat64Array = PackedFloat64Array()
	for key: Array in sort_keys:
		var candidate_index: int = key[1]
		var candidate: InfluenceCircle = circles[candidate_index]
		var candidate_radius: float = projected_radii[candidate_index]
		var lane: int = lane_of_team.get(candidate.team_id, -1)
		if lane < 0:
			lane = lane_count.size()
			lane_of_team[candidate.team_id] = lane
			lane_count.append(0)
			kept_centers.resize((lane + 1) * stride)
			kept_radii.resize((lane + 1) * stride)
		var base: int = lane * stride
		var is_covered: bool = false
		for n: int in range(base, base + lane_count[lane]):
			var radius_difference: float = kept_radii[n] - candidate_radius
			if radius_difference <= 0.0:
				continue
			comparisons += 1
			if kept_centers[n].distance_squared_to(candidate.center) <= radius_difference * radius_difference:
				is_covered = true
				break
		if is_covered:
			culled[candidate_index] = 1
		else:
			kept_block_indices.append(candidate_index)
			kept_centers[base + lane_count[lane]] = candidate.center
			kept_radii[base + lane_count[lane]] = candidate_radius
			lane_count[lane] += 1

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
