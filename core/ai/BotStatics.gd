class_name BotStatics
extends RefCounted
## Bot V2 analytic statics (docs/BOT_AI_REDESIGN.md 2.2 option B, 2.3 step 4): a cheap,
## pure tip-over estimate for an oriented piece, no physics. Two factors, combined as
## a probabilistic OR: (1) overhang -- how far the centre of mass lies outside the
## rectangle spanned by the bottom cubes that actually rest on something; (2)
## slenderness -- height over the smaller side of that rectangle.
##
## DECISION (Bontago-1t5.21): the support polygon is approximated by the bounding
## rectangle of the supported bottom cubes (an over-approximation for concave bottoms
## such as arch5, erring towards "stable"), and every cube has equal mass.
## DECISION: cube offsets are the shape's raw cell offsets rotated by the orientation,
## the same convention as PlacementRules.footprint_cells and BotThink's probes, so
## `cell_support` entries line up with the cubes they were measured under.

const SHIPPED_TUNING: BotGenTuning = preload("res://config/bot_gen_tuning.tres")
const SHIPPED_PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Slack when comparing a probed cell centre with a cube centre.
const MATCH_EPSILON_M: float = 0.001
## Half a cube in cube units (a supported cube's square extends this far).
const HALF_CUBE: float = 0.5
## Floor for tuning values used as divisors.
const MIN_DIVISOR: float = 0.001
## tip_risk cube_size sentinel: use the shipped PhysicsTuning cube size (callers with a
## BotWorldView pass view.cube_size).
const NO_CUBE_SIZE: float = -1.0
## Per-process cache of orientation_infos (key: shape + tuning instance and the tuning
## values it reads). Holds plain RefCounted data only; bounded by MAX_CACHE_ENTRIES.
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
	## Cube centres projected on the ground, in cube units, rotated raw cell offsets.
	var cubes: PackedVector2Array = PackedVector2Array()
	## The bottom layer's cubes (the ones that can rest on the surface).
	var contact: PackedVector2Array = PackedVector2Array()
	var com: Vector2 = Vector2.ZERO
	## Tip risk on a flat, fully supporting surface.
	var flat_risk: float = 0.0
	## Number of bottom cubes (grip area in cubes).
	var contact_area: float = 0.0


## Tip risk 0..1 of candidate `c` (its orientation of `shape`). With per-cell probe
## results (`c.cell_support`) the supported bottom cubes are found through `grid`;
## without a grid the unsupported share of the probed cells drives an overhang term;
## with no probes at all it is the flat-ground risk of the orientation.
static func tip_risk(
	c: BotCandidate, shape: BlockShape, grid: CellGrid = null, tuning: BotGenTuning = null, cube_size: float = NO_CUBE_SIZE
) -> float:
	if c == null or shape == null or shape.cells.is_empty():
		return 0.0
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var info: OrientationInfo = orientation_info(shape, c.orientation_index, t)
	if c.cell_support.is_empty() or c.footprint_cells.is_empty():
		return info.flat_risk
	if grid != null:
		var supported: PackedVector2Array = _supported_contacts(c, info, grid, t, cube_size)
		return _risk(info, supported, t)
	return _combine(info.flat_risk, _unsupported_overhang(c, t))


## Describes orientation `index` of `shape` (pure geometry, no support information).
static func orientation_info(shape: BlockShape, index: int, tuning: BotGenTuning = null) -> OrientationInfo:
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var info: OrientationInfo = OrientationInfo.new()
	info.index = index
	var basis: Basis = BlockOrientations.get_basis(index)
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
		info.cubes.append(Vector2(roundf(v.x), roundf(v.z)))
	info.height = float(max_y - min_y + 1)
	var sum: Vector2 = Vector2.ZERO
	for i: int in range(info.cubes.size()):
		sum += info.cubes[i]
		if layer_y[i] == min_y:
			info.contact.append(info.cubes[i])
	if not info.cubes.is_empty():
		info.com = sum / float(info.cubes.size())
	info.contact_area = float(info.contact.size())
	info.signature = _signature(info)
	info.flat_risk = _risk(info, info.contact, t)
	return info


## The distinct (footprint, contact, height) orientations of `shape`, at most
## `tuning.max_orientations_per_shape`, deterministic: distinct heights are served
## round-robin (largest grip first inside a height) so a cap never drops a height class.
static func orientation_infos(shape: BlockShape, tuning: BotGenTuning = null) -> Array[OrientationInfo]:
	var t: BotGenTuning = tuning if tuning != null else SHIPPED_TUNING
	var kept: Array[OrientationInfo] = []
	if shape == null or shape.cells.is_empty():
		return kept
	var key: String = "%d|%d|%s|%s|%s|%s" % [
		shape.get_instance_id(), t.get_instance_id(), "%s%d" % [shape.id, shape.cells.size()],
		t.max_orientations_per_shape, t.slender_safe, "%s|%s" % [t.slender_max, t.overhang_full_cubes]
	]
	if _info_cache.has(key):
		return _info_cache[key] as Array[OrientationInfo]
	var seen: Dictionary = {}
	for i: int in range(BlockOrientations.count()):
		var info: OrientationInfo = orientation_info(shape, i, t)
		if seen.has(info.signature):
			continue
		seen[info.signature] = true
		kept.append(info)
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


## Risk of `info` resting only on `supported` bottom cubes (offsets in cube units).
static func _risk(info: OrientationInfo, supported: PackedVector2Array, t: BotGenTuning) -> float:
	if supported.is_empty():
		return 1.0
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for p: Vector2 in supported:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var dx: float = maxf(maxf(min_x - HALF_CUBE - info.com.x, info.com.x - (max_x + HALF_CUBE)), 0.0)
	var dz: float = maxf(maxf(min_z - HALF_CUBE - info.com.y, info.com.y - (max_z + HALF_CUBE)), 0.0)
	var overhang: float = clampf(Vector2(dx, dz).length() / maxf(t.overhang_full_cubes, MIN_DIVISOR), 0.0, 1.0)
	var base: float = minf(max_x - min_x + 1.0, max_z - min_z + 1.0)
	var slender: float = info.height / maxf(base, 1.0)
	var slender_risk: float = clampf(
		(slender - t.slender_safe) / maxf(t.slender_max - t.slender_safe, MIN_DIVISOR), 0.0, 1.0
	)
	return _combine(overhang, slender_risk)


static func _combine(a: float, b: float) -> float:
	return 1.0 - (1.0 - clampf(a, 0.0, 1.0)) * (1.0 - clampf(b, 0.0, 1.0))


## True when probed support `height` counts as contact with the pivot's support.
static func _is_contact(height: float, c: BotCandidate, t: BotGenTuning) -> bool:
	return height != BotThink.NO_SUPPORT and absf(height - c.support_height) <= t.contact_tolerance_m


## Overhang term from the unsupported share of the probed cells alone.
static func _unsupported_overhang(c: BotCandidate, t: BotGenTuning) -> float:
	var total: int = c.cell_support.size()
	var unsupported: int = 0
	for height: float in c.cell_support:
		if not _is_contact(height, c, t):
			unsupported += 1
	var share: float = float(unsupported) / float(maxi(total, 1))
	return clampf((share - t.unsupported_safe_fraction) / maxf(1.0 - t.unsupported_safe_fraction, MIN_DIVISOR), 0.0, 1.0)


## The bottom cubes whose probed cells (matched through `grid`) are mostly contact; a
## cube with no probed cell under it is assumed supported.
static func _supported_contacts(
	c: BotCandidate, info: OrientationInfo, grid: CellGrid, t: BotGenTuning, cube_size: float
) -> PackedVector2Array:
	var cube: float = cube_size if cube_size > 0.0 else SHIPPED_PHYSICS_TUNING.cube_size
	var reach: float = (cube + grid.cell_size) * 0.5 - MATCH_EPSILON_M
	var probed: int = mini(c.cell_support.size(), c.footprint_cells.size())
	var centers: PackedVector2Array = PackedVector2Array()
	for i: int in range(probed):
		centers.append(grid.index_center(c.footprint_cells[i]))
	var supported: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in info.contact:
		var world: Vector2 = c.origin + offset * cube
		var matches: int = 0
		var contact_hits: int = 0
		for i: int in range(probed):
			if absf(centers[i].x - world.x) <= reach and absf(centers[i].y - world.y) <= reach:
				matches += 1
				if _is_contact(c.cell_support[i], c, t):
					contact_hits += 1
		if matches == 0 or float(contact_hits) / float(matches) >= t.supported_cell_fraction:
			supported.append(offset)
	return supported
