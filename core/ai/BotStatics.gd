class_name BotStatics
extends RefCounted
## Bot V2 orientation statics (docs/BOT_AI_REDESIGN.md 2.2, 2.3 step 4): pure geometry for the oriented
## pieces. Which site is stable is decided by BotStability (the owner's two centre-of-mass rules); what is
## left here is each orientation's own rule 1 (self_margin), eligibility by it, and the probe layout.
##
## DECISION: cube offsets are in the SPAWN frame, B*(cell - bottom_center()),
## exactly where BlockFactory puts the collision cubes around the pivot the host is given
## (`candidate.origin` is that pivot). An earlier version placed them at B*cell, shifted by B*pivot
## (up to 1.4 m), so probes looked at the wrong patch. `cell_support` entries
## still line up with the cubes they were measured under (footprint_cells_of).

const SHIPPED_TUNING: BotGenTuning = preload("res://config/bots/bot_gen_tuning.tres")
const SHIPPED_PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const SHIPPED_STACK_TUNING: BotStackTuning = preload("res://config/bots/bot_stack_tuning.tres")
## Slack when comparing a probed cell centre with a cube centre.
const MATCH_EPSILON_M: float = 0.001
## Half a cube in cube units (a supported cube's square extends this far).
const HALF_CUBE: float = 0.5
## Per-process cache of orientation_infos (key: shape + tuning instance and the values it reads). Holds plain RefCounted data only; bounded by MAX_CACHE_ENTRIES.
const MAX_CACHE_ENTRIES: int = 64
static var _info_cache: Dictionary = {}


## One orientation of a shape, reduced to what the statics and the generator need.
class OrientationInfo:
	extends RefCounted
	var index: int = 0
	## Height in cube units (a flat pillar is 1, upright 3).
	var height: float = 1.0
	## (footprint, contact, height) key; orientations sharing it are interchangeable.
	var signature: String = ""
	## Cube centres projected on the ground relative to the pivot (`candidate.origin`), in cube
	## units: the spawn frame B*(cell - pivot).
	var cubes: PackedVector2Array = PackedVector2Array()
	## The bottom layer's cubes (the ones that can rest on the surface).
	var contact: PackedVector2Array = PackedVector2Array()
	var com: Vector2 = Vector2.ZERO
	## (B*bottom_center()).xz in cube units: raw rotated cells sit this far from the pivot frame.
	var pivot_shift: Vector2 = Vector2.ZERO
	## Rotated bounding-box centre minus the pivot, xz, cube units (0 for yaw-only orientations).
	var center_shift: Vector2 = Vector2.ZERO
	## Number of bottom cubes (grip area in cubes).
	var contact_area: float = 0.0
	## number of cubes in the top layer (the landing area the next piece gets).
	var top_area: float = 0.0
	## rule 1 of the owner's statics on the flat disc, in cube units: the signed distance of the
	## centre of mass inside the hull of the bottom cubes' contact squares (face half (cube - cube_margin) / 2),
	## positive inside. A property of the orientation alone; the stability model (BotStability) judges real sites.
	var self_margin: float = 0.0
	## the centre of mass above the bottom face, cube units (cubes are uniform).
	var com_height: float = 0.5


## Describes orientation `index` of `shape` (pure geometry, no support information).
static func orientation_info(shape: BlockShape, index: int) -> OrientationInfo:
	var info: OrientationInfo = OrientationInfo.new()
	info.index = index
	var basis: Basis = BlockOrientations.get_basis(index)
	var pivot_rotated: Vector3 = basis * shape.bottom_center()
	info.pivot_shift = Vector2(pivot_rotated.x, pivot_rotated.z)
	var centre_offset: Vector3 = shape.rotated_center_offset(basis, 1.0)
	info.center_shift = Vector2(centre_offset.x, centre_offset.z)
	var layer_y: PackedInt32Array = PackedInt32Array()
	var first_y: int = roundi((basis * Vector3(shape.cells[0])).y)
	var min_y: int = first_y
	var max_y: int = first_y
	for cell: Vector3i in shape.cells:
		var v: Vector3 = basis * Vector3(cell)
		var y: int = roundi(v.y)
		layer_y.append(y)
		min_y = mini(min_y, y)
		max_y = maxi(max_y, y)
		info.cubes.append(Vector2(roundf(v.x), roundf(v.z)) - info.pivot_shift)
	info.height = float(max_y - min_y + 1)
	var sum: Vector2 = Vector2.ZERO
	var top_cubes: int = 0
	var layer_sum: float = 0.0
	for i: int in range(info.cubes.size()):
		sum += info.cubes[i]
		layer_sum += float(layer_y[i] - min_y)
		if layer_y[i] == min_y:
			info.contact.append(info.cubes[i])
		if layer_y[i] == max_y:
			top_cubes += 1
	info.top_area = float(top_cubes)
	if not info.cubes.is_empty():
		info.com = sum / float(info.cubes.size())
		info.com_height = layer_sum / float(info.cubes.size()) + HALF_CUBE
	info.self_margin = _self_margin(info)
	info.contact_area = float(info.contact.size())
	info.signature = _signature(info)
	return info


## Rule 1 on the flat disc (OrientationInfo.self_margin): cube units.
static func _self_margin(info: OrientationInfo) -> float:
	var physics: PhysicsTuning = SHIPPED_PHYSICS_TUNING
	var half: float = (physics.cube_size - physics.cube_margin) * HALF_CUBE / physics.cube_size
	var corners: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in info.contact:
		corners.append_array(BotGeom2D.square(offset, Vector2(half, 0.0), Vector2(0.0, half)))
	return BotGeom2D.signed_inside_hull(BotGeom2D.hull(corners), info.com)


## disk-local xz of the real bottom-cube centres of `c` (its pivot `c.origin` plus the
## spawn-frame contact offsets), ordered from the outermost inward (descending distance from the contact
## centroid, ties in contact order) and cut to `max_count`: a capped tier still probes the cubes that decide
## an overhang. Deterministic; empty for no contact cubes or a non-positive `max_count`.
static func contact_probe_points(
	c: BotCandidate, info: OrientationInfo, cube_size: float, max_count: int
) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var total: int = info.contact.size()
	if total == 0 or max_count <= 0:
		return points
	var centroid: Vector2 = Vector2.ZERO
	for offset: Vector2 in info.contact:
		centroid += offset
	centroid /= float(total)
	var order: Array[int] = []
	for i: int in range(total):
		order.append(i)
	order.sort_custom(func(a: int, b: int) -> bool:
		var da: float = info.contact[a].distance_squared_to(centroid)
		var db: float = info.contact[b].distance_squared_to(centroid)
		if not is_equal_approx(da, db):
			return da > db
		return a < b
	)
	for i: int in range(mini(max_count, total)):
		points.append(c.origin + info.contact[order[i]] * cube_size)
	return points


## Cells covered by the piece when its pivot is at `origin` (disk xz): exact spawn-frame footprint.
static func footprint_cells_of(
	shape: BlockShape, info: OrientationInfo, origin: Vector2, cube_size: float, grid: CellGrid
) -> PackedInt32Array:
	return PlacementRules.footprint_cells(
		shape.cells, BlockOrientations.get_basis(info.index), origin - info.pivot_shift * cube_size, cube_size, grid
	)


## The distinct, eligible (self_margin) (footprint, contact, height) orientations of `shape`, at most
## `tuning.max_orientations_per_shape`; when none is eligible, the one with the largest self_margin.
## Deterministic: distinct heights are served
## round-robin (largest grip first inside a height) so a cap never drops a height class.
static func orientation_infos(shape: BlockShape, tuning: BotGenTuning = null) -> Array[OrientationInfo]:
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var kept: Array[OrientationInfo] = []
	if shape == null or shape.cells.is_empty():
		return kept
	var key: String = "%d|%d|%s|%s|%s" % [
		shape.get_instance_id(), t.get_instance_id(), "%s%d" % [shape.id, shape.cells.size()],
		t.max_orientations_per_shape, SHIPPED_STACK_TUNING.numeric_tolerance_m
	]
	if _info_cache.has(key):
		return _info_cache[key] as Array[OrientationInfo]
	var seen: Dictionary = {}
	var distinct: Array[OrientationInfo] = []
	for i: int in range(BlockOrientations.count()):
		var info: OrientationInfo = orientation_info(shape, i)
		if seen.has(info.signature):
			continue
		seen[info.signature] = true
		distinct.append(info)
	# P4: an orientation is offered only when its own centre of mass is inside the hull of its
	# bottom contact squares by more than the numeric tolerance (rule 1 on flat ground). Filtering happens
	# before the cap, so an ineligible orientation never takes a round-robin slot.
	var cube: float = SHIPPED_PHYSICS_TUNING.cube_size
	var best: OrientationInfo = distinct[0]
	for info: OrientationInfo in distinct:
		if info.self_margin * cube > SHIPPED_STACK_TUNING.numeric_tolerance_m:
			kept.append(info)
		if info.self_margin > best.self_margin:
			best = info
	if kept.is_empty():
		kept.append(best)
	kept.sort_custom(func(a: OrientationInfo, b: OrientationInfo) -> bool:
		if a.height != b.height:
			return a.height < b.height
		if a.contact_area != b.contact_area:
			return a.contact_area > b.contact_area
		return a.index < b.index
	)
	if kept.size() > t.max_orientations_per_shape:
		kept = _round_robin_by_height(kept, t.max_orientations_per_shape)
	if _info_cache.size() >= MAX_CACHE_ENTRIES:
		_info_cache.clear()
	_info_cache[key] = kept
	return kept


static func _round_robin_by_height(sorted_infos: Array[OrientationInfo], limit: int) -> Array[OrientationInfo]:
	var buckets: Array[Array] = []
	var last_height: float = -1.0
	for info: OrientationInfo in sorted_infos:
		if buckets.is_empty() or info.height != last_height:
			buckets.append([])
			last_height = info.height
		buckets[buckets.size() - 1].append(info)
	var out: Array[OrientationInfo] = []
	var round_index: int = 0
	while out.size() < limit:
		var added: bool = false
		for bucket: Array in buckets:
			if round_index < bucket.size() and out.size() < limit:
				out.append(bucket[round_index] as OrientationInfo)
				added = true
		if not added:
			break
		round_index += 1
	return out


static func _signature(info: OrientationInfo) -> String:
	var min_x: float = INF
	var min_z: float = INF
	for p: Vector2 in info.cubes:
		min_x = minf(min_x, p.x)
		min_z = minf(min_z, p.y)
	var footprint: PackedStringArray = _normalised_keys(info.cubes, min_x, min_z)
	var contact: PackedStringArray = _normalised_keys(info.contact, min_x, min_z)
	return "%d|%s|%s" % [int(info.height), ",".join(footprint), ",".join(contact)]


static func _normalised_keys(points: PackedVector2Array, min_x: float, min_z: float) -> PackedStringArray:
	var keys: PackedStringArray = PackedStringArray()
	for p: Vector2 in points:
		keys.append("%d:%d" % [roundi(p.x - min_x), roundi(p.y - min_z)])
	keys.sort()
	var unique: PackedStringArray = PackedStringArray()
	for key: String in keys:
		if unique.is_empty() or unique[unique.size() - 1] != key:
			unique.append(key)
	return unique
