class_name GhostSilhouette
extends RefCounted
## Pure footprint geometry of a held shape: outline loops, wall segments and heights, and the
## collision probes, built from meshes and their offsets. No scene tree.

## The smallest projected (XZ) triangle area, in square meters, still unioned rather than dropped
## as degenerate: a triangle edge-on to straight-down (an unrotated shape's vertical side faces)
## projects to a zero-width sliver that would feed a near-empty or self-intersecting polygon into
## Geometry2D.merge_polygons.
const _MIN_TRIANGLE_AREA: float = 1e-6
## Geometric tolerances for the underside-hugging walls, in meters. Structural float tolerances,
## not look tunables: no value in these ranges changes the look, only whether rounding
## (merge_polygons' fixed-point output, ~1e-5 m) is absorbed.
## How far a split point may sit from an outline edge and still split it, and the shortest
## outline piece kept (a T-junction vertex ending exactly on the outline).
const _SPLIT_EPSILON: float = 1e-4
## How far _underside_heights() nudges its probe point off the outline, toward the interior, so
## point-in-triangle tests never land exactly on the outline. Two orders of magnitude above
## merge_polygons' own rounding, two below a cube.
const _PROBE_INSET: float = 1e-3
## How close two underside heights must be to count as the same level / the same slope.
const _CONTACT_EPSILON: float = 1e-4
## Indices of the probe point in _underside_heights()'s result.
const _HEIGHTS_PROBE_X: int = 2
const _HEIGHTS_PROBE_Y: int = 3
const _MIN_IMAGE_PIXELS: int = 2
## Vertices of a triangle, and the fewest points of a polygon.
const _TRIANGLE_VERTICES: int = 3


## What build() returns.
class Result extends RefCounted:
	## Footprint outline loops in the ground plane (x, z).
	var loops: Array[PackedVector2Array] = []
	## Consecutive (a, b) ghost-local XZ pairs, one per wall piece.
	var wall_segments: PackedVector2Array = PackedVector2Array()
	## Per wall piece, the shape's underside Y at a (x) and at b (y), relative to the ghost origin.
	var wall_heights: PackedVector2Array = PackedVector2Array()
	## One ghost-local XZ probe point per wall piece, nudged just inside the silhouette.
	var probes: PackedVector2Array = PackedVector2Array()


## The silhouette of `meshes[i]` moved by `offsets[i]` and turned by `basis`: its top-down union
## (the rendered shape's true outline, never the convex hull) plus the underside walls along it.
static func build(meshes: Array[Mesh], offsets: PackedVector3Array, basis: Basis) -> Result:
	var result: Result = Result.new()
	var triangles_3d: Array[PackedVector3Array] = _collect_rotated_triangles(meshes, offsets, basis)
	var triangles_2d: Array[PackedVector2Array] = []
	for triangle: PackedVector3Array in triangles_3d:
		triangles_2d.append(_flatten_triangle(triangle))
	var loops: Array[PackedVector2Array] = []
	for triangle: PackedVector2Array in triangles_2d:
		loops = _accumulate_union(loops, triangle)
	result.loops = loops
	_build_underside_walls(result, triangles_3d, triangles_2d)
	return result


## The loop with the largest absolute area (the outer outline; hole loops wind the other way).
static func largest_loop(loops: Array[PackedVector2Array]) -> PackedVector2Array:
	var best: PackedVector2Array = loops[0]
	var best_area: float = 0.0
	for loop: PackedVector2Array in loops:
		var area: float = 0.0
		for i: int in range(loop.size()):
			var next: Vector2 = loop[(i + 1) % loop.size()]
			area += loop[i].x * next.y - next.x * loop[i].y
		if absf(area) > best_area:
			best_area = absf(area)
			best = loop
	return best


## Alpha mask of `loops` over `origin` .. `origin + extent`; width and height are each
## ceil(extent * pixels_per_meter) clamped to 2 .. max_pixels. Scanline fill of the outer loops
## (even-odd, hole loops skipped) with one fill_rect per covered span, no per-pixel polygon tests.
static func rasterize_mask(
	loops: Array[PackedVector2Array], origin: Vector2, extent: Vector2,
	pixels_per_meter: float, max_pixels: int
) -> Image:
	var width: int = clampi(ceili(extent.x * pixels_per_meter), _MIN_IMAGE_PIXELS, max_pixels)
	var height: int = clampi(ceili(extent.y * pixels_per_meter), _MIN_IMAGE_PIXELS, max_pixels)
	var image: Image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(Color.WHITE, 0.0))
	if loops.is_empty():
		return image
	var outer_clockwise: bool = Geometry2D.is_polygon_clockwise(largest_loop(loops))
	var edges: PackedVector2Array = PackedVector2Array()
	for loop: PackedVector2Array in loops:
		if Geometry2D.is_polygon_clockwise(loop) != outer_clockwise:
			continue
		for i: int in range(loop.size()):
			edges.append(loop[i])
			edges.append(loop[(i + 1) % loop.size()])
	var crossings: PackedFloat64Array = PackedFloat64Array()
	for row: int in range(height):
		var v: float = origin.y + (row + 0.5) / height * extent.y
		crossings.clear()
		for e: int in range(0, edges.size(), 2):
			var a: Vector2 = edges[e]
			var b: Vector2 = edges[e + 1]
			if (a.y <= v) != (b.y <= v):
				crossings.append(a.x + (v - a.y) / (b.y - a.y) * (b.x - a.x))
		crossings.sort()
		for k: int in range(0, crossings.size() - 1, 2):
			var x0: int = clampi(ceili((crossings[k] - origin.x) / extent.x * width - 0.5), 0, width)
			var x1: int = clampi(ceili((crossings[k + 1] - origin.x) / extent.x * width - 0.5), 0, width)
			if x1 > x0:
				image.fill_rect(Rect2i(x0, row, x1 - x0, 1), Color.WHITE)
	return image


## Every triangle of every mesh (each moved by its offset), each vertex turned by `basis`, in
## ghost-local 3D (each Y is a height relative to the ghost origin). Triangles whose XZ
## projection is degenerate are dropped: they have no well-defined plane height over XZ.
static func _collect_rotated_triangles(
	meshes: Array[Mesh], offsets: PackedVector3Array, basis: Basis
) -> Array[PackedVector3Array]:
	var triangles: Array[PackedVector3Array] = []
	for m: int in range(meshes.size()):
		var mesh: Mesh = meshes[m]
		if mesh == null:
			continue
		var local_offset: Vector3 = offsets[m]
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			# An unindexed surface stores null here, which cannot be cast to a packed array.
			var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
			var indices: PackedInt32Array = (
					_sequential_indices(verts.size()) if index_data == null else index_data
			)
			for i: int in range(0, indices.size() - 2, _TRIANGLE_VERTICES):
				var triangle: PackedVector3Array = PackedVector3Array([
					basis * (local_offset + verts[indices[i]]),
					basis * (local_offset + verts[indices[i + 1]]),
					basis * (local_offset + verts[indices[i + 2]]),
				])
				if _triangle_area(_flatten_triangle(triangle)) >= _MIN_TRIANGLE_AREA:
					triangles.append(triangle)
	return triangles


## A ghost-local 3D triangle dropped straight down onto XZ (x, z).
static func _flatten_triangle(triangle: PackedVector3Array) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(triangle[0].x, triangle[0].z),
		Vector2(triangle[1].x, triangle[1].z),
		Vector2(triangle[2].x, triangle[2].z),
	])


## Fallback index buffer (0, 1, 2, 3, ...) for a surface with no ARRAY_INDEX at all.
static func _sequential_indices(vertex_count: int) -> PackedInt32Array:
	var indices: PackedInt32Array = PackedInt32Array()
	indices.resize(vertex_count)
	for i: int in range(vertex_count):
		indices[i] = i
	return indices


## Area of a triangle (half the absolute shoelace sum).
static func _triangle_area(triangle: PackedVector2Array) -> float:
	var a: Vector2 = triangle[0]
	var b: Vector2 = triangle[1]
	var c: Vector2 = triangle[2]
	return absf((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) * 0.5


## Folds `addition` into `existing` (already-mutually-disjoint outline loops) via
## Geometry2D.merge_polygons, growing one candidate polygon against every existing loop it
## touches in turn (so a single new triangle can bridge two previously separate loops). A pair
## that doesn't overlap or touch stays two loops, correct for a rotation that genuinely splits
## the silhouette.
static func _accumulate_union(
	existing: Array[PackedVector2Array], addition: PackedVector2Array
) -> Array[PackedVector2Array]:
	var candidate: PackedVector2Array = addition
	var remainder: Array[PackedVector2Array] = []
	for polygon: PackedVector2Array in existing:
		var merge_result: Array = Geometry2D.merge_polygons(polygon, candidate)
		if merge_result.size() == 1:
			candidate = merge_result[0]
		else:
			remainder.append(polygon)
	remainder.append(candidate)
	return remainder


## Fills the wall arrays of `result` from its loops and the rotated triangles that produced them.
## Step 1: every outline edge a->b is split at every parameter where a projected triangle edge
## crosses it or where a projected triangle vertex lies on it (within _SPLIT_EPSILON: a
## T-junction, e.g. per-cell bottom-face seams ending on the outline, which a crossing test alone
## can miss by float rounding). Between two consecutive split parameters no triangle boundary
## crosses the edge, so the lowest triangle over the piece is one fixed triangle. Step 2
## (_underside_heights()): that triangle's plane at the piece's two endpoints is the shape's
## underside there. Pieces shorter than the epsilon, or with no triangle on either side, are
## dropped.
static func _build_underside_walls(
	result: Result, triangles_3d: Array[PackedVector3Array], triangles_2d: Array[PackedVector2Array]
) -> void:
	for loop: PackedVector2Array in result.loops:
		var edge_count: int = loop.size()
		if edge_count < _TRIANGLE_VERTICES:
			continue
		for i: int in range(edge_count):
			var a: Vector2 = loop[i]
			var b: Vector2 = loop[(i + 1) % edge_count]
			var edge_length: float = a.distance_to(b)
			if edge_length <= _SPLIT_EPSILON:
				continue
			var params: PackedFloat64Array = _edge_split_params(a, b, triangles_2d)
			var previous: float = params[0]
			# Index of the last piece kept on *this* edge, or -1: a piece that just continues
			# the previous one's plane extends it instead of adding a redundant quad.
			var last_piece: int = -1
			for k: int in range(1, params.size()):
				var current: float = params[k]
				if (current - previous) * edge_length <= _SPLIT_EPSILON:
					continue
				var piece_a: Vector2 = a.lerp(b, previous)
				var piece_b: Vector2 = a.lerp(b, current)
				previous = current
				var heights: PackedFloat64Array = _underside_heights(piece_a, piece_b, triangles_3d, triangles_2d)
				if heights.is_empty():
					last_piece = -1
					continue
				if last_piece >= 0 and _continues_piece(result, last_piece, piece_a, piece_b, heights):
					result.wall_segments[last_piece * 2 + 1] = piece_b
					var extended: Vector2 = result.wall_heights[last_piece]
					result.wall_heights[last_piece] = Vector2(extended.x, heights[1])
					continue
				result.wall_segments.append(piece_a)
				result.wall_segments.append(piece_b)
				result.wall_heights.append(Vector2(heights[0], heights[1]))
				result.probes.append(Vector2(heights[_HEIGHTS_PROBE_X], heights[_HEIGHTS_PROBE_Y]))
				last_piece = result.wall_heights.size() - 1


## Whether new piece piece_a->piece_b (underside `heights` at its ends) lies on the same straight
## underside line as piece `index` of `result` on the same outline edge: it starts where that one
## ends, at the same height, with the same slope, so one quad can cover both exactly.
static func _continues_piece(
	result: Result, index: int, piece_a: Vector2, piece_b: Vector2, heights: PackedFloat64Array
) -> bool:
	var prev_a: Vector2 = result.wall_segments[index * 2]
	var prev_b: Vector2 = result.wall_segments[index * 2 + 1]
	var prev_heights: Vector2 = result.wall_heights[index]
	if prev_b.distance_to(piece_a) > _SPLIT_EPSILON:
		return false
	if absf(prev_heights.y - heights[0]) > _CONTACT_EPSILON:
		return false
	var prev_slope: float = (prev_heights.y - prev_heights.x) / prev_a.distance_to(prev_b)
	var slope: float = (heights[1] - heights[0]) / piece_a.distance_to(piece_b)
	return absf(prev_slope - slope) <= _CONTACT_EPSILON


## Sorted split parameters (always including 0.0 and 1.0) along outline edge a->b. Near-duplicates
## are left in; the caller skips any piece shorter than _SPLIT_EPSILON.
static func _edge_split_params(
	a: Vector2, b: Vector2, triangles_2d: Array[PackedVector2Array]
) -> PackedFloat64Array:
	var params: PackedFloat64Array = PackedFloat64Array([0.0, 1.0])
	var edge: Vector2 = b - a
	var length_squared: float = edge.length_squared()
	for triangle: PackedVector2Array in triangles_2d:
		for k: int in range(_TRIANGLE_VERTICES):
			var p: Vector2 = triangle[k]
			var q: Vector2 = triangle[(k + 1) % _TRIANGLE_VERTICES]
			var crossing: Variant = Geometry2D.segment_intersects_segment(a, b, p, q)
			if crossing != null:
				params.append(clampf(((crossing as Vector2) - a).dot(edge) / length_squared, 0.0, 1.0))
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(p, a, b)
			if closest.distance_to(p) <= _SPLIT_EPSILON:
				params.append(clampf((closest - a).dot(edge) / length_squared, 0.0, 1.0))
	params.sort()
	return params


## The shape's underside height (relative to the ghost origin) at the two endpoints of outline
## piece a->b, as [height_at_a, height_at_b, probe_x, probe_y] -- or empty when neither side of the
## piece has any triangle over it. Probes the piece's midpoint nudged _PROBE_INSET off the outline
## (left side first, then right: which side is "inside" depends on the loop's winding), picks the
## triangle with the lowest plane Y there (a closed shell's lowest surface is its underside), and
## evaluates that triangle's plane at the real, un-nudged endpoints.
static func _underside_heights(
	a: Vector2, b: Vector2,
	triangles_3d: Array[PackedVector3Array], triangles_2d: Array[PackedVector2Array]
) -> PackedFloat64Array:
	var midpoint: Vector2 = (a + b) * 0.5
	var direction: Vector2 = (b - a).normalized()
	var left: Vector2 = Vector2(-direction.y, direction.x)
	for side: float in [1.0, -1.0]:
		var probe: Vector2 = midpoint + left * (side * _PROBE_INSET)
		var best_index: int = -1
		var best_y: float = INF
		for j: int in range(triangles_2d.size()):
			var flat: PackedVector2Array = triangles_2d[j]
			if not Geometry2D.point_is_inside_triangle(probe, flat[0], flat[1], flat[2]):
				continue
			var y: float = _triangle_plane_y(triangles_3d[j], flat, probe)
			if y < best_y:
				best_y = y
				best_index = j
		if best_index >= 0:
			var triangle: PackedVector3Array = triangles_3d[best_index]
			var triangle_flat: PackedVector2Array = triangles_2d[best_index]
			return PackedFloat64Array([
				_triangle_plane_y(triangle, triangle_flat, a),
				_triangle_plane_y(triangle, triangle_flat, b),
				probe.x, probe.y,
			])
	return PackedFloat64Array()


## The Y of `triangle`'s plane over XZ point `point` (barycentric weights from its XZ projection
## `flat`, extrapolated outside it). `flat` is never degenerate: _collect_rotated_triangles()
## dropped every triangle under _MIN_TRIANGLE_AREA.
static func _triangle_plane_y(triangle: PackedVector3Array, flat: PackedVector2Array, point: Vector2) -> float:
	var e1: Vector2 = flat[1] - flat[0]
	var e2: Vector2 = flat[2] - flat[0]
	var d: Vector2 = point - flat[0]
	var denominator: float = e1.x * e2.y - e2.x * e1.y
	var weight_1: float = (d.x * e2.y - e2.x * d.y) / denominator
	var weight_2: float = (e1.x * d.y - d.x * e1.y) / denominator
	return triangle[0].y + weight_1 * (triangle[1].y - triangle[0].y) + weight_2 * (triangle[2].y - triangle[0].y)
