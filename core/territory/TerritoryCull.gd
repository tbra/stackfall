class_name TerritoryCull
extends RefCounted
## One cull for the territory solve: drops every non-home circle that a larger
## kept same-team circle fully contains (plan TERRITORY_CLEANUP 2.1).
##
## Homes are never dropped and never act as containers. Input is not mutated;
## the survivors keep the input order. Pure logic: no scene tree (CLAUDE.md).


## Returns the circles that survive the containment cull.
static func drop_contained(circles: Array[InfluenceCircle]) -> Array[InfluenceCircle]:
	var candidates: Array[int] = []
	for i: int in range(circles.size()):
		if not circles[i].is_home:
			candidates.append(i)
	# Largest radius first; original index breaks ties. Native lexicographic sort
	# on [-radius, index] (64-bit, no rounding) instead of a lambda comparator.
	var sort_keys: Array = []
	sort_keys.resize(candidates.size())
	for k: int in range(candidates.size()):
		sort_keys[k] = [-circles[candidates[k]].radius, candidates[k]]
	sort_keys.sort()

	var culled: PackedByteArray = PackedByteArray()
	culled.resize(circles.size())
	# Per-team kept circles in flat parallel arrays (stride = candidate count per
	# team lane), so the loop only visits same-team circles and copies no packed
	# array per candidate.
	var lane_of_team: Dictionary = {}  ## team_id -> lane
	var lane_count: PackedInt32Array = PackedInt32Array()
	var stride: int = candidates.size()
	var kept_centers: PackedVector2Array = PackedVector2Array()
	var kept_radii: PackedFloat64Array = PackedFloat64Array()
	for key: Array in sort_keys:
		var candidate_index: int = key[1]
		var candidate: InfluenceCircle = circles[candidate_index]
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
			var radius_difference: float = kept_radii[n] - candidate.radius
			if radius_difference <= 0.0:
				continue
			if kept_centers[n].distance_squared_to(candidate.center) <= radius_difference * radius_difference:
				is_covered = true
				break
		if is_covered:
			culled[candidate_index] = 1
		else:
			kept_centers[base + lane_count[lane]] = candidate.center
			kept_radii[base + lane_count[lane]] = candidate.radius
			lane_count[lane] += 1

	var survivors: Array[InfluenceCircle] = []
	for i: int in range(circles.size()):
		if culled[i] == 0:
			survivors.append(circles[i])
	return survivors
