class_name CloudOcclusionBounds
extends RefCounted
## Sun-occlusion bounds of the cloud puffs: one row per puff plus one record per clump, written
## while the puffs are generated and queried by sun_ray_cloud_occlusion(). Bounds only, no physics
## body exists for the puffs. Clump arrays share one index; a clump's puffs are rows
## first..first+count of `puffs`. Positions are in the clump's rest frame: the shader slides each
## clump by drift_offset * its speed (wrapped), so queries shift the ray back instead of every
## clump forward. Pure data and maths, no scene tree.

## Row layout of `puffs`: centre x, y, z, horizontal radius, vertical radius (both inflated like
## the shader's hull), and the world Y of the flat-base cut (NO_BASE_CUT when round).
const PUFF_STRIDE: int = 6
const COL_HORIZONTAL: int = 3
const COL_VERTICAL: int = 4
const COL_CUT: int = 5
const NO_BASE_CUT: float = -1.0e30
## The shader's `round_base_from` default: a base plane at or above it means whole ellipsoids.
const ROUND_BASE_FROM: float = 0.9
## Rays flatter than this are treated as horizontal by the clump height-slab prefilter.
const FLAT_RAY: float = 1.0e-6
const DEFAULT_TUNING: SunFlareConfig = preload("res://config/sky/sun_flare.tres")

var puffs: PackedFloat32Array = PackedFloat32Array()
var centre: PackedVector3Array = PackedVector3Array()
var radius: PackedFloat32Array = PackedFloat32Array()
var speed: PackedFloat32Array = PackedFloat32Array()
## per clump, its rest (x, z), wrap domain half-side and exclusion radius (0 = none), the same
## numbers the shader reads from the instance colour.
var rest: PackedVector2Array = PackedVector2Array()
var domain: PackedFloat32Array = PackedFloat32Array()
var excl: PackedFloat32Array = PackedFloat32Array()
var y_low: PackedFloat32Array = PackedFloat32Array()
var y_high: PackedFloat32Array = PackedFloat32Array()
var first: PackedInt32Array = PackedInt32Array()
var count: PackedInt32Array = PackedInt32Array()
## 1 for clumps of the upper layer, which the shader dithers away near the camera.
var upper: PackedByteArray = PackedByteArray()
var clear_start_m: float = 0.0
var clear_end_m: float = 0.0
## The shader's hull inflation (fraction of radius) the recorded rows are grown by; set by the
## builder before record_puff().
var inflate: float = 0.0
## Wrap and fade settings of the cloud drift the query evaluates clumps with.
var drift_config: CloudDriftConfig = CloudDriftState.DEFAULT_CONFIG


## Number of puff rows recorded so far (the `first_puff` of the next clump).
func puff_rows() -> int:
	return puffs.size() / PUFF_STRIDE


func clear() -> void:
	puffs.clear()
	centre.clear()
	radius.clear()
	speed.clear()
	rest.clear()
	domain.clear()
	excl.clear()
	y_low.clear()
	y_high.clear()
	first.clear()
	count.clear()
	upper.clear()
	clear_start_m = 0.0
	clear_end_m = 0.0


## Appends one puff's occlusion row (a spheroid: horizontal radius `horizontal`, vertical radius
## `vertical`, both grown by the shader's hull inflation `inflate`).
func record_puff(at: Vector3, horizontal: float, vertical: float, flat: float) -> void:
	var grow: float = 1.0 + inflate
	var cut: float = NO_BASE_CUT if flat >= ROUND_BASE_FROM else at.y - vertical * flat
	puffs.append_array(PackedFloat32Array([at.x, at.y, at.z, horizontal * grow, vertical * grow, cut]))


## The upper layer's camera-clearance fade the shader applies (metres of height above the ray origin).
func set_clear_fade(start_m: float, end_m: float) -> void:
	clear_start_m = start_m
	clear_end_m = end_m


## Closes the clump whose puffs start at row `first_puff`: its bounding sphere (rest frame),
## height slab and drift speed. `rest_data` is the instance colour the shader reads: (rest x,
## rest z, wrap domain half-side, exclusion radius).
func record_clump(first_puff: int, angular_speed: float, is_upper: bool, rest_data: Color) -> void:
	var rows: int = puff_rows()
	var low: Vector3 = Vector3(INF, INF, INF)
	var high: Vector3 = Vector3(-INF, -INF, -INF)
	for row: int in range(first_puff, rows):
		var base: int = row * PUFF_STRIDE
		var reach: Vector3 = Vector3(puffs[base + COL_HORIZONTAL], puffs[base + COL_VERTICAL], puffs[base + COL_HORIZONTAL])
		var at: Vector3 = Vector3(puffs[base], puffs[base + 1], puffs[base + 2])
		low = low.min(at - reach)
		high = high.max(at + reach)
	var middle: Vector3 = (low + high) * 0.5
	var bound: float = 0.0
	for row: int in range(first_puff, rows):
		var base: int = row * PUFF_STRIDE
		var at: Vector3 = Vector3(puffs[base], puffs[base + 1], puffs[base + 2])
		bound = maxf(bound, at.distance_to(middle) + maxf(puffs[base + COL_HORIZONTAL], puffs[base + COL_VERTICAL]))
	centre.append(middle)
	radius.append(bound)
	speed.append(angular_speed)
	rest.append(Vector2(rest_data.r, rest_data.g))
	domain.append(rest_data.b)
	excl.append(rest_data.a)
	y_low.append(low.y)
	y_high.append(high.y)
	first.append(first_puff)
	count.append(rows - first_puff)
	upper.append(1 if is_upper else 0)


## How much the puffs hide the sun seen along the ray from `from` toward the unit-ish `dir`,
## 0 (clear sky) .. 1 (fully hidden). The sun is at infinity, so the ray is a half-line. Cheap
## bounds test, no physics: clumps first by a height slab and a bounding sphere (each clump's wind
## shift undone on the ray: the shader moves clumps by drift_offset * their speed, wrapped), then
## only the few puffs of a clump the ray enters, as spheroids with a soft silhouette
## (`tuning.cloud_edge_softness`) and the shader's camera-clearance fade for the upper layer.
## Transmittances multiply, so several thin puffs add up. `drift` is the integrated cloud wind to
## evaluate at. The puffs are assumed to sit at the world origin, as Skybox places them.
func ray_cover(from: Vector3, dir: Vector3, tuning: SunFlareConfig, drift: Vector2) -> float:
	var clumps: int = speed.size()
	if clumps == 0 or dir.length_squared() <= 0.0:
		return 0.0
	var settings: SunFlareConfig = tuning if tuning != null else DEFAULT_TUNING
	var ray: Vector3 = dir.normalized()
	var flat_ray: bool = absf(ray.y) < FLAT_RAY
	var transmittance: float = 1.0
	for clump: int in range(clumps):
		# Height slab: the half-line must reach this clump's height range at all.
		if flat_ray:
			if from.y < y_low[clump] or from.y > y_high[clump]:
				continue
		elif maxf((y_low[clump] - from.y) / ray.y, (y_high[clump] - from.y) / ray.y) < 0.0:
			continue
		var rest_at: Vector2 = rest[clump]
		var wrapped: Vector2 = CloudDriftMath.wrapped_position(rest_at, CloudDriftMath.clump_shift(drift, speed[clump]), domain[clump])
		var shown: float = CloudDriftMath.visibility(wrapped, domain[clump], excl[clump], drift_config)
		if shown <= 0.0:
			continue
		var moved: Vector2 = wrapped - rest_at
		var origin: Vector3 = Vector3(from.x - moved.x, from.y, from.z - moved.y)
		var heading: Vector3 = ray
		var to_centre: Vector3 = centre[clump] - origin
		var along: float = to_centre.dot(heading)
		var bound: float = radius[clump]
		if along < -bound or to_centre.length_squared() - along * along > bound * bound:
			continue
		var start: int = first[clump]
		var is_upper: bool = upper[clump] != 0
		for row: int in range(start, start + count[clump]):
			transmittance *= 1.0 - _puff_cover(origin, heading, row, is_upper, settings) * shown
		if transmittance <= 0.0:
			return 1.0
	return clampf(1.0 - transmittance, 0.0, 1.0)


## One puff's share (0..1) of hiding the ray `origin` + t * `heading` (rest frame): the ray
## through the spheroid, soft toward its silhouette, clipped to the flat base and, for the
## upper layer, faded by the shader's camera-clearance dither.
func _puff_cover(origin: Vector3, heading: Vector3, row: int, is_upper: bool, settings: SunFlareConfig) -> float:
	var base: int = row * PUFF_STRIDE
	var horizontal: float = puffs[base + COL_HORIZONTAL]
	var vertical: float = puffs[base + COL_VERTICAL]
	var local: Vector3 = Vector3((origin.x - puffs[base]) / horizontal, (origin.y - puffs[base + 1]) / vertical,
			(origin.z - puffs[base + 2]) / horizontal)
	var local_heading: Vector3 = Vector3(heading.x / horizontal, heading.y / vertical, heading.z / horizontal)
	var speed_sq: float = local_heading.length_squared()
	var along: float = local.dot(local_heading)
	var miss_sq: float = maxf(local.length_squared() - along * along / speed_sq, 0.0)
	if miss_sq >= 1.0:
		return 0.0
	var closest: float = -along / speed_sq
	var half_chord: float = sqrt((1.0 - miss_sq) / speed_sq)
	var t_in: float = closest - half_chord
	var t_out: float = closest + half_chord
	var cut: float = puffs[base + COL_CUT]
	if cut > NO_BASE_CUT:
		if heading.y > FLAT_RAY:
			t_in = maxf(t_in, (cut - origin.y) / heading.y)
		elif heading.y < -FLAT_RAY:
			t_out = minf(t_out, (cut - origin.y) / heading.y)
		elif origin.y < cut:
			return 0.0
	if t_out <= maxf(t_in, 0.0):
		return 0.0
	var softness: float = clampf(settings.cloud_edge_softness, 0.0, 1.0)
	var cover: float = 1.0 - smoothstep(1.0 - softness, 1.0, sqrt(miss_sq))
	if is_upper and clear_end_m > 0.0:
		var entry_y: float = origin.y + maxf(t_in, 0.0) * heading.y
		cover *= smoothstep(clear_start_m, maxf(clear_end_m, clear_start_m + FLAT_RAY), entry_y - origin.y)
	return cover
