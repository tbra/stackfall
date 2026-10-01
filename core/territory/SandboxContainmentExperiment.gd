class_name SandboxContainmentExperiment
extends RefCounted
## Sandbox-only exact pruning of redundant same-team influence circles.
## A containing circle dominates the contained circle's radius-distance score
## everywhere and preserves its graph connections. Original radii are unchanged.

const CONTAINMENT_MARGIN: float = 0.0001


static func build(circles: Array[InfluenceCircle]) -> Dictionary:
	var order: Array[int] = []
	for i: int in range(circles.size()):
		order.append(i)
	# Largest first, so a discarded block cannot be needed to contain another.
	# Prefer a home at equal radius; homes themselves are never removed.
	# Native lexicographic sort on [-radius, not-home, index] (same order as the
	# former lambda comparator; Bontago-1pi.11.33).
	var keys: Array = []
	keys.resize(circles.size())
	for i: int in range(circles.size()):
		keys[i] = [-circles[i].radius, 0 if circles[i].is_home else 1, i]
	keys.sort()
	for k: int in range(keys.size()):
		var key: Array = keys[k]
		order[k] = key[2]
	var kept: Array[int] = []
	var removed: PackedByteArray = PackedByteArray()
	removed.resize(circles.size())
	var candidates: int = 0
	var comparisons: int = 0
	for index: int in order:
		var candidate: InfluenceCircle = circles[index]
		if candidate.is_home:
			kept.append(index)
			continue
		candidates += 1
		var covered: bool = false
		for kept_index: int in kept:
			var containing: InfluenceCircle = circles[kept_index]
			if containing.team_id != candidate.team_id:
				continue
			var radius_gap: float = containing.radius - candidate.radius
			if radius_gap <= CONTAINMENT_MARGIN:
				continue
			comparisons += 1
			var reach: float = radius_gap - CONTAINMENT_MARGIN
			if containing.center.distance_squared_to(candidate.center) <= reach * reach:
				covered = true
				break
		if covered:
			removed[index] = 1
		else:
			kept.append(index)
	var filtered: Array[InfluenceCircle] = []
	var kept_indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(circles.size()):
		if removed[i] != 0:
			continue
		filtered.append(circles[i])
		kept_indices.append(i)
	return {
		"circles": filtered,
		"candidate_count": candidates,
		"kept_count": filtered.size() - (circles.size() - candidates),
		"culled_count": circles.size() - filtered.size(),
		"kept_indices": kept_indices,
		"comparison_count": comparisons,
	}
