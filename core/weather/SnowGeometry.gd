class_name SnowGeometry
extends RefCounted
## Pure snow geometry and wire format (Bontago-22y.6). No scene tree: the host
## effect and every client renderer build from these same functions, so a
## snow collider and the mesh drawn for it come from one list of points.
##
## A "patch" is one snowy square: a block's upward-facing cell top or a disc
## drift. Its frame has +Y along the surface normal and the square centred on
## the origin in XZ. A patch is one rounded, slightly tilted, lumpy dome: a
## height grid over a rounded-square footprint, zero on the rim. The mesh is
## that grid; the collider is the convex hull of the same grid points. The
## dome is (nearly) concave-down, so hull top and drawn surface agree within
## a few millimetres (tested). Its layout comes from a seed per patch, so only
## (owner, cell, level) crosses the wire.

## Block-local axis directions; the index is the wire value of a patch face.
const AXES: Array[Vector3i] = [
	Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
	Vector3i(0, 1, 0), Vector3i(0, -1, 0),
	Vector3i(0, 0, 1), Vector3i(0, 0, -1),
]
const AXIS_UP: int = 2

## Sides of a patch in its own frame (+X, -X, +Z, -Z) for neighbour queries.
const SIDE_PX: int = 0
const SIDE_NX: int = 1
const SIDE_PZ: int = 2
const SIDE_NZ: int = 3
const SIDE_COUNT: int = 4

## Dome parameter layout: tilt x/z, bump amplitude, bump phases u/v.
const D_TX: int = 0
const D_TZ: int = 1
const D_BUMP: int = 2
const D_PU: int = 3
const D_PV: int = 4
const DOME_STRIDE: int = 5

## Wire format. Architecture, not tunables.
const WIRE_VERSION: int = 2
const WIRE_KEYS: PackedStringArray = ["v", "seed", "c", "b", "d"]
## Disc patches use this owner id in the seed (block net ids are >= 1).
const DISC_OWNER: int = -1
## Largest cell index a block patch may name (blocks have a few cells).
const MAX_BLOCK_CELL_INDEX: int = 63
const MASK32: int = 0xFFFFFFFF
const HASH_MUL: int = 0x45d9f3b
const HASH_SEED: int = 0x9e3779b9
const UNIT_HASH_SEED: int = 0x51ed270b
const UNIT_HASH_RANGE: float = 4294967296.0
## Numerical slack for key rounding and degenerate triangles.
const EPS: float = 0.000001
## Upper bound on concavity passes over a dome grid (it converges sooner).
const CONCAVIFY_PASSES: int = 12
## A squareness at or below this maps the dome grid onto a circle.
const ROUND_SQUARENESS: float = 2.0
## Draw ranges (fractions) for a dome's random tilt and bump strength.
const TILT_DRAW_MIN: float = 0.6
const BUMP_DRAW_MIN: float = 0.5
## Hard caps keeping a dome positive and nearly concave whatever the tuning.
const TILT_HARD_MAX: float = 0.9
const BUMP_HARD_MAX: float = 0.5


# --- Deterministic seeding ---------------------------------------------------------

## 32-bit integer mix; identical on every machine (no engine hash involved).
static func mix(h: int, value: int) -> int:
	var x: int = (h ^ (value & MASK32)) & MASK32
	x = ((((x >> 16) ^ x) & MASK32) * HASH_MUL) & MASK32
	x = ((((x >> 16) ^ x) & MASK32) * HASH_MUL) & MASK32
	x = ((x >> 16) ^ x) & MASK32
	return x


static func patch_seed(weather_seed: int, owner_id: int, cell_key: int, axis: int) -> int:
	var h: int = mix(HASH_SEED, weather_seed)
	h = mix(h, weather_seed >> 32)
	h = mix(h, owner_id)
	h = mix(h, cell_key)
	return mix(h, axis)


## A value in [0, 1) from two ints (disc cover thresholds).
static func unit_hash(a: int, b: int) -> float:
	return float(mix(mix(UNIT_HASH_SEED, a), b)) / UNIT_HASH_RANGE


## One patch's dome parameters (DOME_STRIDE floats) from its seed.
static func dome_params(seed_value: int, tuning: SnowTuning) -> PackedFloat32Array:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tilt: float = clampf(tuning.cap_tilt_max, 0.0, TILT_HARD_MAX)
	var angle: float = rng.randf_range(0.0, TAU)
	var amount: float = tilt * rng.randf_range(TILT_DRAW_MIN, 1.0)
	var tx: float = cos(angle) * amount
	var tz: float = sin(angle) * amount
	# |tx| + |tz| <= tilt keeps the dome positive everywhere inside the rim.
	var l1: float = absf(tx) + absf(tz)
	if l1 > tilt and l1 > 0.0:
		tx *= tilt / l1
		tz *= tilt / l1
	var bump: float = clampf(tuning.cap_bump_amp, 0.0, BUMP_HARD_MAX) * rng.randf_range(BUMP_DRAW_MIN, 1.0)
	return PackedFloat32Array([tx, tz, bump, rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU)])


## Footprint edge fraction of a patch at `level`: light snow is a smaller
## dusting, heavy snow covers (nearly) the whole face.
static func fill_for_level(level: int, tuning: SnowTuning) -> float:
	if tuning.depth_levels <= 1:
		return tuning.cap_fill_heavy
	var t: float = float(clampi(level, 1, tuning.depth_levels) - 1) / float(tuning.depth_levels - 1)
	return lerpf(tuning.cap_fill_light, tuning.cap_fill_heavy, t)


## Peak height of a patch at `level` (0 at level 0).
static func dome_height(level: int, tuning: SnowTuning) -> float:
	if level <= 0:
		return 0.0
	return maxf(tuning.level_height(level), tuning.cap_min_height_m)


## Highest point a dome at `level` can reach above its base (for queries).
static func dome_max_height(level: int, tuning: SnowTuning) -> float:
	var tilt: float = clampf(tuning.cap_tilt_max, 0.0, TILT_HARD_MAX)
	var bump: float = clampf(tuning.cap_bump_amp, 0.0, BUMP_HARD_MAX)
	return tuning.cap_lift_m + dome_height(level, tuning) * (1.0 + tilt) * (1.0 + bump)


## The (n + 1)^2 grid points of a dome, row-major, in the patch frame
## (lifted by cap_lift_m). Rim points sit at the lift height. Empty at level 0.
## `squareness` overrides tuning.cap_squareness when > 0 (disc drifts are
## round, block caps follow the square face).
static func dome_points(params: PackedFloat32Array, patch_edge: float, level: int, tuning: SnowTuning, squareness: float = 0.0) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if level <= 0:
		return points
	var n: int = maxi(tuning.cap_segments, 2)
	var half: float = patch_edge * fill_for_level(level, tuning) * 0.5
	var peak: float = dome_height(level, tuning)
	var q: float = maxf(squareness if squareness > 0.0 else tuning.cap_squareness, 1.0)
	var round_footprint: bool = squareness > 0.0 and squareness <= ROUND_SQUARENESS
	var p: float = maxf(tuning.cap_roundness, 1.0)
	var freq: float = tuning.cap_bump_freq
	points.resize((n + 1) * (n + 1))
	for j: int in range(n + 1):
		var row_v: float = float(j) / float(n) * 2.0 - 1.0
		for i: int in range(n + 1):
			var u: float = float(i) / float(n) * 2.0 - 1.0
			var v: float = row_v
			var r: float = pow(pow(absf(u), q) + pow(absf(v), q), 1.0 / q)
			if round_footprint:
				# Square grid mapped onto the unit disc (elliptical grid
				# mapping): the grid's own border becomes the circular rim,
				# so a drift's outline is round, not a grid staircase.
				var su: float = u * sqrt(1.0 - v * v * 0.5)
				var sv: float = v * sqrt(1.0 - u * u * 0.5)
				u = su
				v = sv
				r = minf(Vector2(u, v).length(), 1.0)
			var base: float = maxf(0.0, 1.0 - pow(r, p))
			var tilt: float = 1.0 + params[D_TX] * u + params[D_TZ] * v
			var bump: float = 1.0 + params[D_BUMP] * sin(freq * u + params[D_PU]) * sin(freq * v + params[D_PV])
			points[j * (n + 1) + i] = Vector3(u * half, tuning.cap_lift_m + peak * base * tilt * bump, v * half)
	_concavify(points, n + 1)
	return points


## Block top-face snow (Bontago-mp0.31). Unlike dome_points() this is a flat
## plateau at the level's depth over the whole face, with a soft quarter-sine
## shoulder along the OUTER rims only: a side whose neighbour cell carries
## snow (`neighbor_levels`, one entry per SIDE_* in the patch frame, 0 = none)
## is extended flush to the cell boundary with no shoulder, and its height
## blends toward the mean of both levels so two cell patches meet without a
## seam. A run of cells therefore reads as one continuous layer. A patch with
## no snowy neighbour keeps the seeded tilt (a block set on it rests crooked);
## bumps are not used. Grid points are clustered toward the edges (sine warp)
## so the shoulder is resolved. Concave like the dome, so hull == drawn surface.
static func cap_points(params: PackedFloat32Array, patch_edge: float, pitch: float, level: int, neighbor_levels: PackedInt32Array, tuning: SnowTuning) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	if level <= 0:
		return points
	var n: int = maxi(tuning.cap_segments, 2)
	var fill_half: float = patch_edge * fill_for_level(level, tuning) * 0.5
	var peak: float = dome_height(level, tuning)
	var ext: PackedFloat32Array = PackedFloat32Array([fill_half, fill_half, fill_half, fill_half])
	var merged: PackedByteArray = PackedByteArray([0, 0, 0, 0])
	var npeak: PackedFloat32Array = PackedFloat32Array([peak, peak, peak, peak])
	var any_merged: bool = false
	for side: int in range(SIDE_COUNT):
		if side < neighbor_levels.size() and neighbor_levels[side] > 0:
			merged[side] = 1
			ext[side] = pitch * 0.5
			npeak[side] = (peak + dome_height(neighbor_levels[side], tuning)) * 0.5
			any_merged = true
	var rim_w: float = maxf(tuning.cap_rim_width_m, EPS)
	var tilt_x: float = 0.0 if any_merged else params[D_TX]
	var tilt_z: float = 0.0 if any_merged else params[D_TZ]
	var row: int = n + 1
	points.resize(row * row)
	for j: int in range(row):
		var v: float = sin(float(j) / float(n) * PI - PI * 0.5)
		var z: float = v * (ext[SIDE_PZ] if v >= 0.0 else ext[SIDE_NZ])
		for i: int in range(row):
			var u: float = sin(float(i) / float(n) * PI - PI * 0.5)
			var x: float = u * (ext[SIDE_PX] if u >= 0.0 else ext[SIDE_NX])
			var inv_sum: float = 0.0
			var open_sides: int = 0
			var height: float = peak
			for side: int in range(SIDE_COUNT):
				var coord: float = x if side < SIDE_PZ else z
				var positive: bool = (side == SIDE_PX or side == SIDE_PZ)
				var extent: float = ext[side]
				var toward: float = coord if positive else -coord
				if merged[side] == 1:
					var w: float = clampf(toward / maxf(extent, EPS), 0.0, 1.0)
					height += w * w * (npeak[side] - peak)
				else:
					inv_sum += 1.0 / maxf(extent - toward, EPS)
					open_sides += 1
			var profile: float = 1.0
			if open_sides > 0:
				var edge_dist: float = float(open_sides) / inv_sum
				profile = sin(clampf(edge_dist / rim_w, 0.0, 1.0) * PI * 0.5)
			var tilt: float = 1.0 + tilt_x * u + tilt_z * v
			points[j * row + i] = Vector3(x, tuning.cap_lift_m + height * profile * tilt, z)
	_concavify(points, row)
	return points


## Raises grid heights until every point is at least the midpoint of each
## pair of neighbours around it (rows, columns, both diagonals): the grid
## becomes (discretely) concave, so the convex hull of the points, which is
## the collider, lies on the drawn surface instead of bridging over dips.
static func _concavify(points: PackedVector3Array, row: int) -> void:
	for _pass: int in range(CONCAVIFY_PASSES):
		var changed: bool = false
		for j: int in range(1, row - 1):
			for i: int in range(1, row - 1):
				var index: int = j * row + i
				var h: float = points[index].y
				var target: float = maxf(
					maxf((points[index - 1].y + points[index + 1].y) * 0.5, (points[index - row].y + points[index + row].y) * 0.5),
					maxf((points[index - row - 1].y + points[index + row + 1].y) * 0.5, (points[index - row + 1].y + points[index + row - 1].y) * 0.5)
				)
				if target > h + EPS:
					points[index].y = target
					changed = true
		if not changed:
			return


## Smooth-shaded triangles of a dome grid (skipping flat rim cells), with
## the engine front-face winding. `points` must come from dome_points();
## `xform` maps the patch frame to the owner.
static func append_dome_triangles(points: PackedVector3Array, tuning: SnowTuning, xform: Transform3D, vertices: PackedVector3Array, normals: PackedVector3Array) -> void:
	var n: int = maxi(tuning.cap_segments, 2)
	var row: int = n + 1
	if points.size() != row * row:
		return
	var rim: float = tuning.cap_lift_m + EPS
	var local_normals: PackedVector3Array = PackedVector3Array()
	local_normals.resize(points.size())
	for j: int in range(row):
		for i: int in range(row):
			var left: Vector3 = points[j * row + maxi(i - 1, 0)]
			var right: Vector3 = points[j * row + mini(i + 1, n)]
			var down: Vector3 = points[maxi(j - 1, 0) * row + i]
			var up: Vector3 = points[mini(j + 1, n) * row + i]
			var normal: Vector3 = (up - down).cross(right - left)
			local_normals[j * row + i] = normal.normalized() if normal.length_squared() > EPS else Vector3.UP
	var basis: Basis = xform.basis
	var start: int = vertices.size()
	for j: int in range(n):
		for i: int in range(n):
			var a: int = j * row + i
			var b: int = a + 1
			var c: int = a + row + 1
			var d: int = a + row
			if points[a].y <= rim and points[b].y <= rim and points[c].y <= rim and points[d].y <= rim:
				continue
			# Front face: (b - a) x (c - a) points down, into the snow
			# (core/blocks/BlockMeshBuilder.gd, Bontago-xtq.5).
			vertices.append(points[a])
			vertices.append(points[b])
			vertices.append(points[c])
			vertices.append(points[a])
			vertices.append(points[c])
			vertices.append(points[d])
			normals.append(local_normals[a])
			normals.append(local_normals[b])
			normals.append(local_normals[c])
			normals.append(local_normals[a])
			normals.append(local_normals[c])
			normals.append(local_normals[d])
	if xform != Transform3D.IDENTITY:
		for k: int in range(start, vertices.size()):
			vertices[k] = xform * vertices[k]
			normals[k] = (basis * normals[k]).normalized()


## An ArrayMesh from triangle soup, or null when empty.
static func build_mesh(vertices: PackedVector3Array, normals: PackedVector3Array) -> ArrayMesh:
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- Patch frames ------------------------------------------------------------------

## Basis whose +Y is AXES[axis] (right-handed).
static func axis_basis(axis: int) -> Basis:
	var n: Vector3 = Vector3(AXES[clampi(axis, 0, AXES.size() - 1)])
	var u: Vector3 = Vector3(1.0, 0.0, 0.0) if absf(n.x) < 0.5 else Vector3(0.0, 0.0, 1.0)
	var w: Vector3 = u.cross(n)
	return Basis(u, n, w)


## Patch frame of the `axis` face of the cell centred at `cell_center`
## (block-local), for cubes of edge `cube_size`.
static func block_patch_transform(cell_center: Vector3, axis: int, cube_size: float) -> Transform3D:
	var basis: Basis = axis_basis(axis)
	return Transform3D(basis, cell_center + basis.y * (cube_size * 0.5))


## Index into AXES of the block-local axis closest to `local_up`, or -1 when
## even that one is more than acos(min_dot) away.
static func best_up_axis(local_up: Vector3, min_dot: float) -> int:
	var best: int = -1
	var best_dot: float = -INF
	var up: Vector3 = local_up.normalized()
	for index: int in range(AXES.size()):
		var d: float = Vector3(AXES[index]).dot(up)
		if d > best_dot:
			best_dot = d
			best = index
	return best if best_dot >= min_dot else -1


## Doubled integer key of a cell centre (so half-integer pivots stay exact).
static func cell_key(center: Vector3, cube_size: float) -> Vector3i:
	var scale: float = 2.0 / maxf(cube_size, EPS)
	return Vector3i(roundi(center.x * scale), roundi(center.y * scale), roundi(center.z * scale))


## Cell centres sorted into the canonical order both peers index by.
static func canonical_cells(centers: PackedVector3Array, cube_size: float) -> PackedVector3Array:
	var list: Array[Vector3] = []
	for c: Vector3 in centers:
		list.append(c)
	list.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		var ka: Vector3i = cell_key(a, cube_size)
		var kb: Vector3i = cell_key(b, cube_size)
		if ka.y != kb.y:
			return ka.y < kb.y
		if ka.x != kb.x:
			return ka.x < kb.x
		return ka.z < kb.z)
	var out: PackedVector3Array = PackedVector3Array()
	for c: Vector3 in list:
		out.append(c)
	return out


## Indices (into canonical `cells`) whose `axis` face is not covered by
## another cell of the same block, capped at `max_count`.
static func exposed_cells(cells: PackedVector3Array, axis: int, cube_size: float, max_count: int) -> PackedInt32Array:
	var keys: Dictionary = {}
	for c: Vector3 in cells:
		keys[cell_key(c, cube_size)] = true
	var step: Vector3i = AXES[axis] * 2
	var out: PackedInt32Array = PackedInt32Array()
	for index: int in range(cells.size()):
		if out.size() >= max_count or index > MAX_BLOCK_CELL_INDEX:
			break
		if not keys.has(cell_key(cells[index], cube_size) + step):
			out.append(index)
	return out


# --- Wire -----------------------------------------------------------------------------

## Appends one block record: net_id, axis, count, then (cell, level) pairs.
static func append_block_record(buffer: PackedInt32Array, net_id: int, axis: int, cells: PackedInt32Array, levels: PackedInt32Array) -> void:
	buffer.append(net_id)
	buffer.append(axis)
	buffer.append(cells.size())
	for index: int in range(cells.size()):
		buffer.append(cells[index])
		buffer.append(levels[index])


## The sanitized state, or {} for anything malformed: wrong types or keys,
## counts over the budget, levels out of range, unknown axes, repeated ids.
## Result: {"seed": int, "cover": int, "blocks": {net_id: [axis, cells,
## levels]}, "disc": {cell: level}}.
static func sanitize_state(raw: Variant, tuning: SnowTuning, max_cell_index: int) -> Dictionary:
	if not (raw is Dictionary):
		return {}
	var data: Dictionary = raw
	if data.size() != WIRE_KEYS.size():
		return {}
	for key: String in WIRE_KEYS:
		if not data.has(key):
			return {}
	if typeof(data["v"]) != TYPE_INT or int(data["v"]) != WIRE_VERSION or typeof(data["seed"]) != TYPE_INT:
		return {}
	if typeof(data["c"]) != TYPE_INT or int(data["c"]) < 0 or int(data["c"]) > tuning.depth_levels:
		return {}
	if typeof(data["b"]) != TYPE_PACKED_INT32_ARRAY or typeof(data["d"]) != TYPE_PACKED_INT32_ARRAY:
		return {}
	var b: PackedInt32Array = data["b"]
	var d: PackedInt32Array = data["d"]
	var blocks: Dictionary = {}
	var total: int = 0
	var i: int = 0
	while i < b.size():
		if i + 3 > b.size():
			return {}
		var net_id: int = b[i]
		var axis: int = b[i + 1]
		var count: int = b[i + 2]
		i += 3
		if not Quantize.is_wire_id(net_id) or blocks.has(net_id):
			return {}
		if axis < 0 or axis >= AXES.size() or count <= 0 or count > tuning.max_patches_per_block:
			return {}
		if i + count * 2 > b.size():
			return {}
		var cells: PackedInt32Array = PackedInt32Array()
		var levels: PackedInt32Array = PackedInt32Array()
		for _k: int in range(count):
			var cell: int = b[i]
			var level: int = b[i + 1]
			i += 2
			if cell < 0 or cell > MAX_BLOCK_CELL_INDEX or cells.has(cell):
				return {}
			if level < 1 or level > tuning.depth_levels:
				return {}
			cells.append(cell)
			levels.append(level)
		total += count
		blocks[net_id] = [axis, cells, levels]
	if total > tuning.max_block_patches:
		return {}
	if d.size() % 2 != 0 or d.size() / 2 > tuning.max_disc_patches:
		return {}
	var disc: Dictionary = {}
	for j: int in range(0, d.size(), 2):
		var cell_index: int = d[j]
		var disc_level: int = d[j + 1]
		if cell_index < 0 or cell_index > max_cell_index or disc.has(cell_index):
			return {}
		if disc_level < 1 or disc_level > tuning.depth_levels:
			return {}
		disc[cell_index] = disc_level
	return {"seed": int(data["seed"]), "cover": int(data["c"]), "blocks": blocks, "disc": disc}


static func make_state(seed_value: int, cover: int, blocks: PackedInt32Array, disc: PackedInt32Array) -> Dictionary:
	return {"v": WIRE_VERSION, "seed": seed_value, "c": cover, "b": blocks, "d": disc}
