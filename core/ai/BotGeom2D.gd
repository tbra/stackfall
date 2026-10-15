class_name BotGeom2D
extends RefCounted
## Pure 2D geometry for the bot's statics (docs: STATICS_DESIGN 7.2): convex polygons in the disc
## plane, counter-clockwise (cross > 0 turns), as PackedVector2Array. No scene tree.

const _MIN_POINTS: int = 3
const _PLANE_STRIDE: int = 3
const _HALF: float = 0.5
## Strictly positive area below which a clipped polygon counts as empty.
const _EMPTY_AREA: float = 1.0e-9


## Convex hull, counter-clockwise, without the closing duplicate Geometry2D adds. Fewer than 3 distinct points are
## returned as they are.
static func hull(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < _MIN_POINTS:
		return points
	var out: PackedVector2Array = Geometry2D.convex_hull(points)
	if out.size() > 1 and out[0] == out[out.size() - 1]:
		out.remove_at(out.size() - 1)
	if out.size() >= _MIN_POINTS and area(out) < 0.0:
		out.reverse()
	return out


## One row (nx, nz, d) per hull edge: unit outward normal n and offset d, a point p is inside when n.p <= d.
static func half_planes(hull_pts: PackedVector2Array) -> PackedFloat32Array:
	var planes: PackedFloat32Array = PackedFloat32Array()
	if hull_pts.size() < _MIN_POINTS:
		return planes
	for i: int in hull_pts.size():
		var a: Vector2 = hull_pts[i]
		var edge: Vector2 = hull_pts[(i + 1) % hull_pts.size()] - a
		var length: float = edge.length()
		if length <= 0.0:
			continue
		var n: Vector2 = Vector2(edge.y, -edge.x) / length
		planes.append(n.x)
		planes.append(n.y)
		planes.append(n.dot(a))
	return planes


## Signed distance (metres, positive inside) from `p` to the hull boundary, through its precomputed half-planes. A
## hull of fewer than 3 points is all boundary (negative distance to it); an empty one is -INF.
static func signed_inside(planes: PackedFloat32Array, hull_pts: PackedVector2Array, p: Vector2) -> float:
	if hull_pts.size() < _MIN_POINTS or planes.is_empty():
		return _degenerate_inside(hull_pts, p)
	var best: float = INF
	var i: int = 0
	while i < planes.size():
		best = minf(best, planes[i + 2] - (planes[i] * p.x + planes[i + 1] * p.y))
		i += _PLANE_STRIDE
	return best


static func signed_inside_hull(hull_pts: PackedVector2Array, p: Vector2) -> float:
	return signed_inside(half_planes(hull_pts), hull_pts, p)


static func _degenerate_inside(hull_pts: PackedVector2Array, p: Vector2) -> float:
	if hull_pts.is_empty():
		return -INF
	var nearest: float = INF
	for i: int in hull_pts.size():
		var a: Vector2 = hull_pts[i]
		var b: Vector2 = hull_pts[mini(i + 1, hull_pts.size() - 1)]
		nearest = minf(nearest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return -nearest


## A square (or rectangle) with half-axes `u` and `v` around `centre`, counter-clockwise.
static func square(centre: Vector2, u: Vector2, v: Vector2) -> PackedVector2Array:
	var poly: PackedVector2Array = PackedVector2Array([centre + u + v, centre - u + v, centre - u - v, centre + u - v])
	if area(poly) < 0.0:
		poly.reverse()
	return poly


static func area(poly: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * _HALF


## Sutherland-Hodgman: the part of convex CCW polygon `subject` inside convex CCW polygon `clip`.
static func clip_convex(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	if subject.is_empty() or clip.is_empty():
		return PackedVector2Array()
	var out: PackedVector2Array = subject
	for i: int in clip.size():
		var a: Vector2 = clip[i]
		var b: Vector2 = clip[(i + 1) % clip.size()]
		out = _clip_side(out, a, b - a, 0.0)
		if out.is_empty():
			break
	return out


## `poly` shrunk inward by `d` on every edge (convex CCW input); empty once nothing is left.
static func erode(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	if d <= 0.0 or poly.size() < _MIN_POINTS:
		return poly
	var out: PackedVector2Array = poly
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var edge: Vector2 = poly[(i + 1) % poly.size()] - a
		var length: float = edge.length()
		if length <= 0.0:
			continue
		out = _clip_side(out, a, edge, d * length)
		if out.is_empty():
			return out
	return out if absf(area(out)) > _EMPTY_AREA else PackedVector2Array()


## Keeps the part of `input` whose edge.cross(p - a) >= offset (offset = distance * |edge|).
static func _clip_side(input: PackedVector2Array, a: Vector2, edge: Vector2, offset: float) -> PackedVector2Array:
	var out: PackedVector2Array = PackedVector2Array()
	if input.is_empty():
		return out
	var prev: Vector2 = input[input.size() - 1]
	var d_prev: float = edge.cross(prev - a) - offset
	for cur: Vector2 in input:
		var d_cur: float = edge.cross(cur - a) - offset
		if (d_cur >= 0.0) != (d_prev >= 0.0):
			out.append(prev + (cur - prev) * (d_prev / (d_prev - d_cur)))
		if d_cur >= 0.0:
			out.append(cur)
		prev = cur
		d_prev = d_cur
	return out


## Overlap of two axis-aligned boxes (lo/hi corners) as a CCW rectangle; empty when they do not overlap.
static func rect_overlap(a_lo: Vector2, a_hi: Vector2, b_lo: Vector2, b_hi: Vector2) -> PackedVector2Array:
	var lo: Vector2 = Vector2(maxf(a_lo.x, b_lo.x), maxf(a_lo.y, b_lo.y))
	var hi: Vector2 = Vector2(minf(a_hi.x, b_hi.x), minf(a_hi.y, b_hi.y))
	if hi.x <= lo.x or hi.y <= lo.y:
		return PackedVector2Array()
	return PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])


## The smaller side of the axis-aligned bounds of `pts` (0 when fewer than 3 points).
static func min_extent(points: PackedVector2Array) -> float:
	if points.size() < _MIN_POINTS:
		return 0.0
	var lo: Vector2 = points[0]
	var hi: Vector2 = points[0]
	for p: Vector2 in points:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return minf(hi.x - lo.x, hi.y - lo.y)
