class_name PerchPlanner
extends RefCounted
## Bontago-adt.3: pure rules for the cosmetic perching birds (no scene tree, no
## autoloads; unit-tested in tests/unit/test_perch_planner.gd). Everything is
## horizontal (X/Z) unless a function says otherwise; positions are world
## Vector3s, the disc surface height is passed in by the caller.

## Number of probe points on the edge-margin ring that must lie on the disc.
const EDGE_PROBES: int = 16


## True when `spot` (world, only X/Z used) is at least radii[i] away from every
## points[i]. points and radii are parallel arrays.
static func is_clear(spot: Vector3, points: PackedVector3Array, radii: PackedFloat32Array) -> bool:
	for i: int in range(points.size()):
		var dx: float = spot.x - points[i].x
		var dz: float = spot.z - points[i].z
		if dx * dx + dz * dz < radii[i] * radii[i]:
			return false
	return true


## True when `spot` and EDGE_PROBES points on a ring of `margin` around it all
## satisfy `on_disc` (Callable(Vector2 world_xz) -> bool).
static func is_on_disc(spot: Vector3, margin: float, on_disc: Callable) -> bool:
	if not bool(on_disc.call(Vector2(spot.x, spot.z))):
		return false
	for i: int in range(EDGE_PROBES):
		var angle: float = TAU * float(i) / float(EDGE_PROBES)
		var probe: Vector2 = Vector2(spot.x, spot.z) + Vector2(cos(angle), sin(angle)) * margin
		if not bool(on_disc.call(probe)):
			return false
	return true


## Picks a landing spot: up to `tries` random points within `search_radius` of the
## disc centre `centre`, returning the first that is on the disc (with margin)
## and clear of every hazard. Returns null when none qualifies.
static func pick_spot(
	rng: RandomNumberGenerator,
	centre: Vector3,
	search_radius: float,
	margin: float,
	on_disc: Callable,
	hazard_points: PackedVector3Array,
	hazard_radii: PackedFloat32Array,
	tries: int
) -> Variant:
	for _attempt: int in range(maxi(tries, 1)):
		var angle: float = rng.randf() * TAU
		var distance: float = sqrt(rng.randf()) * search_radius
		var spot: Vector3 = centre + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		if not is_on_disc(spot, margin, on_disc):
			continue
		if not is_clear(spot, hazard_points, hazard_radii):
			continue
		return spot
	return null


## True when `point` is within `radius` (3D) of `bird`.
static func within(bird: Vector3, point: Vector3, radius: float) -> bool:
	return bird.distance_squared_to(point) <= radius * radius


## True when any of `points` is within `radius` (3D) of `bird`.
static func any_within(bird: Vector3, points: PackedVector3Array, radius: float) -> bool:
	for point: Vector3 in points:
		if within(bird, point, radius):
			return true
	return false


## True when any block position sits above `bird` (higher by more than
## `min_height`) within `radius` horizontally.
static func block_overhead(bird: Vector3, blocks: PackedVector3Array, radius: float, min_height: float) -> bool:
	for block: Vector3 in blocks:
		if block.y - bird.y <= min_height:
			continue
		var dx: float = block.x - bird.x
		var dz: float = block.z - bird.z
		if dx * dx + dz * dz <= radius * radius:
			return true
	return false


## Flee reason for a perched bird: &"" when calm, else &"camera", &"cursor" or
## &"overhead" (impacts are delivered as events, not polled).
static func flee_reason(
	bird: Vector3,
	camera: Variant,
	cursors: PackedVector3Array,
	blocks: PackedVector3Array,
	camera_radius: float,
	cursor_radius: float,
	overhead_radius: float,
	overhead_min_height: float
) -> StringName:
	if camera != null and within(bird, camera as Vector3, camera_radius):
		return &"camera"
	if any_within(bird, cursors, cursor_radius):
		return &"cursor"
	if block_overhead(bird, blocks, overhead_radius, overhead_min_height):
		return &"overhead"
	return &""


# --- Tower (block-top) perching -----------------------------------------------

## Minimum world-up component for a box face to count as a "top" face.
const TOP_FACE_MIN_UP_DOT: float = 0.97
## Heights above a top face at which the free-space probes are taken (fraction
## of the clear height; the first is just above the surface).
const CLEAR_PROBE_SURFACE_M: float = 0.08


## Top face of a box collision shape: {"center": Vector3, "size": Vector2} for
## the face whose outward normal points (nearly) world-up, else null.
## `box_global` is the shape node's global transform, `half` its local half
## extents (BoxShape3D.size * 0.5).
static func top_face(box_global: Transform3D, half: Vector3) -> Variant:
	var axes: Array[Vector3] = [box_global.basis.x, box_global.basis.y, box_global.basis.z]
	var halves: Array[float] = [half.x, half.y, half.z]
	for axis_index: int in range(3):
		var axis: Vector3 = axes[axis_index]
		var scale_along: float = axis.length()
		if scale_along <= 0.0:
			continue
		var direction: Vector3 = axis / scale_along
		var up_dot: float = direction.y
		if absf(up_dot) < TOP_FACE_MIN_UP_DOT:
			continue
		var sign_up: float = 1.0 if up_dot > 0.0 else -1.0
		var centre: Vector3 = box_global.origin + direction * sign_up * halves[axis_index] * scale_along
		var other_a: int = (axis_index + 1) % 3
		var other_b: int = (axis_index + 2) % 3
		var size: Vector2 = Vector2(
			halves[other_a] * 2.0 * axes[other_a].length(),
			halves[other_b] * 2.0 * axes[other_b].length()
		)
		return {"center": centre, "size": size}
	return null


## True when world point `p` lies inside the box described by its inverse global
## transform and half extents.
static func box_contains_point(inverse_global: Transform3D, half: Vector3, p: Vector3) -> bool:
	var local: Vector3 = inverse_global * p
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


## True when nothing occupies the space above a top face: five columns (centre
## and four points `footprint_half` out) are probed just above the surface and
## at `clear_height`, against every box except index `skip` (the face's own). `origins`/`bounds`
## (centre and bounding radius per box) only serve as a cheap pre-filter.
static func top_is_free(
	face_centre: Vector3,
	footprint_half: float,
	clear_height: float,
	inverse_globals: Array[Transform3D],
	halves: PackedVector3Array,
	origins: PackedVector3Array,
	bounds: PackedFloat32Array,
	skip: int
) -> bool:
	var offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(footprint_half, 0.0, 0.0), Vector3(-footprint_half, 0.0, 0.0),
		Vector3(0.0, 0.0, footprint_half), Vector3(0.0, 0.0, -footprint_half),
	]
	var heights: Array[float] = [CLEAR_PROBE_SURFACE_M, clear_height * 0.5, clear_height]
	for i: int in range(inverse_globals.size()):
		if i == skip:
			continue
		# Cheap reject: box entirely below the face or too far sideways.
		var dx: float = origins[i].x - face_centre.x
		var dz: float = origins[i].z - face_centre.z
		var reach: float = bounds[i] + footprint_half
		if dx * dx + dz * dz > reach * reach or origins[i].y + bounds[i] < face_centre.y:
			continue
		for offset: Vector3 in offsets:
			for height: float in heights:
				var probe: Vector3 = face_centre + offset + Vector3(0.0, height, 0.0)
				if box_contains_point(inverse_globals[i], halves[i], probe):
					return false
	return true


## First candidate (scanning from a random start) whose face centre is clear of
## every hazard; returns its index or -1.
static func pick_candidate(
	rng: RandomNumberGenerator,
	candidates: PackedVector3Array,
	hazard_points: PackedVector3Array,
	hazard_radii: PackedFloat32Array
) -> int:
	var count: int = candidates.size()
	if count == 0:
		return -1
	var start: int = rng.randi() % count
	for step: int in range(count):
		var index: int = (start + step) % count
		if is_clear(candidates[index], hazard_points, hazard_radii):
			return index
	return -1


## True when the tracked block transform differs from its landing anchor by more
## than `epsilon` in position or by more than a small angle in rotation.
static func block_moved(anchor: Transform3D, current: Transform3D, epsilon: float) -> bool:
	if anchor.origin.distance_to(current.origin) > epsilon:
		return true
	# Orientation drift: compare the rotated Y and X axes (angle ~ epsilon rad per metre).
	return (
		anchor.basis.y.normalized().distance_to(current.basis.y.normalized()) > epsilon
		or anchor.basis.x.normalized().distance_to(current.basis.x.normalized()) > epsilon
	)
