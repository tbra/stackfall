class_name BotStack
extends RefCounted
## A pure, team-agnostic model of tower statics (Bontago-1t5.53a, docs/BOT_TOWER_PLAN.md B.3-B.5
## and C "1t5.53a"): a snapshot of the cubes near the bot's towers and the analysis of it.
##
## Frame: disk-local, y up. The disc's top surface is y == ground_y; a cube whose bottom face is
## within rest_tolerance_m of it rests on the disc. Cubes are squares of cube_size in XZ, turned by
## the body's basis (its x and z axes projected to the XZ plane); the XZ outline is what decides
## contact, so a tilted body's squares are only approximate (it is unsound anyway). Tilt is the smallest angle
## between any of the body's axes (either sign) and up, so a bar rolled 90 degrees is upright.
##
## What the analysis yields per body: the bodies it rests on, the convex support hull of its
## contacts (or of its bottom cubes when on the disc), the load above it (itself plus everything
## resting on it, directly or not) and its soundness. DECISION (deviates from the plan's "full load
## to every supporter"): the true split is statically indeterminate, and charging a bridge's whole
## load to each leg would flag every arch. A body's load therefore includes only the bodies it
## carries ALONE; a body with two or more supporters is tested against the union hull of its
## contacts and its load does not travel further down. DECISION: a body with no supporter and no disc contact (floating, or its support
## fell outside the snapshot) has no hull: it is unsound, but the margin walk skips it rather than
## forcing -INF. DECISION: the piece-on-support hull in load_margin is the convex hull of all cube
## squares of the supporting bodies (the piece's own contact patch is not known here).
##
## Usage: add_body() for each block, then call analyse_step() until it returns true (the contact
## pass is sliced; the load and soundness sweep runs in the last slice), then query.

const _MIN_HULL_POINTS: int = 3
const _HALF: float = 0.5
const _AXES: int = 3

var cube_size: float = 1.0
## Disc top surface height in the snapshot frame.
var ground_y: float = 0.0
var body_ids: PackedInt64Array = PackedInt64Array()
var body_team: PackedInt32Array = PackedInt32Array()
var body_mass: PackedFloat32Array = PackedFloat32Array()
var body_com: PackedVector3Array = PackedVector3Array()
var body_basis: Array[Basis] = []
var body_tilt_deg: PackedFloat32Array = PackedFloat32Array()
var body_settled: PackedByteArray = PackedByteArray()
## Disk-local cube centres and the index of the body each belongs to.
var cube_pos: PackedVector3Array = PackedVector3Array()
var cube_body: PackedInt32Array = PackedInt32Array()

# Per-body analysis results (valid once analyse_step has returned true).
var _supporters: Array[PackedInt32Array] = []
var _on_disc: PackedByteArray = PackedByteArray()
var _hull: Array[PackedVector2Array] = []
var _above: Array[PackedInt32Array] = []  # bodies resting on this one, directly
var _load_mass: PackedFloat32Array = PackedFloat32Array()
var _load_com: PackedVector3Array = PackedVector3Array()
var _sound: PackedByteArray = PackedByteArray()
var _index: Dictionary = {}  # body id -> index
var _cube_poly: Array[PackedVector2Array] = []
var _cube_cells: Dictionary = {}  # Vector2i -> PackedInt32Array of cube indices
var _debris_cells: Dictionary = {}  # Vector2i -> PackedInt32Array of unsound cube indices
var _body_cubes: Array[PackedInt32Array] = []
var _down_cache: Dictionary = {}  # support-set key -> PackedInt32Array (the closure down to the disc)
var _load_state: PackedByteArray = PackedByteArray()
var _degenerate_area: float = 0.0
var _hash_reach: int = 1  # set from the tuning in _prepare
var _prepared: bool = false
var _cursor: int = 0
var _done: bool = false


func body_count() -> int:
	return body_ids.size()


func is_analysed() -> bool:
	return _done


## Adds one rigid body. `cubes` are its cube centres in the disk-local frame; `basis` is its
## orientation (its y axis gives the tilt). Mass is spread evenly over the cubes (the body's centre
## of mass is the cube mean). Invalidates any earlier analysis.
func add_body(
	id: int, team: int, basis: Basis, cubes: PackedVector3Array, mass: float, settled: bool
) -> void:
	if cubes.is_empty():
		return
	var idx: int = body_ids.size()
	var sum: Vector3 = Vector3.ZERO
	var own: PackedInt32Array = PackedInt32Array()
	for p: Vector3 in cubes:
		sum += p
		own.append(cube_pos.size())
		cube_pos.append(p)
		cube_body.append(idx)
	body_ids.append(id)
	body_team.append(team)
	body_mass.append(mass)
	body_com.append(sum / float(cubes.size()))
	body_basis.append(basis)
	var vertical: Vector3 = _basis_axis(basis, _vertical_index(basis))
	body_tilt_deg.append(rad_to_deg(acos(clampf(absf(vertical.normalized().y), 0.0, 1.0))))
	body_settled.append(1 if settled else 0)
	_body_cubes.append(own)
	_index[id] = idx
	_prepared = false
	_done = false
	_cursor = 0
	_down_cache.clear()


func index_of(body_id: int) -> int:
	return int(_index.get(body_id, -1))


## Runs up to `max_bodies` bodies of the contact pass; true when the whole analysis is finished.
func analyse_step(max_bodies: int, t: BotStackTuning) -> bool:
	if _done:
		return true
	if not _prepared:
		_prepare(t)
	var n: int = body_ids.size()
	var stop: int = mini(n, _cursor + maxi(max_bodies, 1))
	while _cursor < stop:
		_analyse_contacts(_cursor, t)
		_cursor += 1
	if _cursor >= n:
		_finish(t)
		_done = true
	return _done


func is_sound(body: int) -> bool:
	return _done and body >= 0 and body < _sound.size() and _sound[body] == 1


## Top face height of the body's highest cube.
func top_height(body: int) -> float:
	var top: float = -INF
	for ci: int in _body_cubes[body]:
		top = maxf(top, cube_pos[ci].y)
	return top + cube_size * _HALF


## Sound bodies of `team` with nothing resting on them, tallest first.
func sound_tops(team: int) -> PackedInt32Array:
	var tops: Array[int] = []
	if not _done:
		return PackedInt32Array()
	for i: int in body_ids.size():
		if body_team[i] == team and _sound[i] == 1 and _above[i].is_empty():
			tops.append(i)
	tops.sort_custom(
		func(a: int, b: int) -> bool:
			var ha: float = top_height(a)
			var hb: float = top_height(b)
			return a < b if is_equal_approx(ha, hb) else ha > hb
	)
	return PackedInt32Array(tops)


## Bontago-1t5.54: the body whose centre of mass lies within `radius` of `point` (disk-local XZ) and
## whose top face is nearest `top` (a circle's own top height decides between the bodies of a column);
## -1 when none. Circles carry no body id, so this is how a circle finds its body.
func body_near(point: Vector2, radius: float, top: float) -> int:
	var best: int = -1
	var best_dy: float = INF
	for i: int in body_ids.size():
		var com: Vector3 = body_com[i]
		if Vector2(com.x, com.z).distance_to(point) > radius:
			continue
		var dy: float = absf(top_height(i) - top)
		if dy < best_dy:
			best_dy = dy
			best = i
	return best


## True when `body` is sound and carries nothing unsound (a tower top a piece may still be added to).
func is_usable_top(body: int) -> bool:
	if not is_sound(body):
		return false
	for u: int in _above[body]:
		if _sound[u] != 1:
			return false
	return true


## Number of snapshotted bodies of `team`.
func team_body_count(team: int) -> int:
	var count: int = 0
	for t: int in body_team:
		if t == team:
			count += 1
	return count


## True when a body of `team` has not settled yet (a block still falling or sliding).
func has_unsettled(team: int) -> bool:
	for i: int in body_ids.size():
		if body_team[i] == team and body_settled[i] == 0:
			return true
	return false


## Disk-local XZ of the body's centre of mass.
func com_xz(body: int) -> Vector2:
	return Vector2(body_com[body].x, body_com[body].z)


## True when any cube of an unsound body lies within `radius` of `point` (disk-local XZ).
func debris_near(point: Vector2, radius: float) -> bool:
	if not _done:
		return false
	var reach: int = int(ceil(radius / cube_size)) + _hash_reach
	var cell: Vector2i = _cell_of(point)
	for dx: int in range(-reach, reach + 1):
		for dz: int in range(-reach, reach + 1):
			var list: PackedInt32Array = _debris_cells.get(cell + Vector2i(dx, dz), PackedInt32Array())
			for ci: int in list:
				var p: Vector3 = cube_pos[ci]
				if Vector2(p.x, p.z).distance_to(point) <= radius:
					return true
	return false


## The smallest signed distance (metres, positive inside) by which the centre of mass of the load
## stays inside the support hull of every body from `support_ids` down to the disc, with a piece of
## `piece_mass` centred at `piece_com` added on top. INF when no support id is known (no block
## support). The first hull is the supports' own footprint (the piece rests on it); each lower hull
## is that body's contact hull against what carries it.
func load_margin(support_ids: PackedInt64Array, piece_com: Vector3, piece_mass: float) -> float:
	var supports: PackedInt32Array = PackedInt32Array()
	for id: int in support_ids:
		var i: int = index_of(id)
		if i >= 0:
			supports.append(i)
	if supports.is_empty() or not _done:
		return INF
	var piece_xz: Vector2 = Vector2(piece_com.x, piece_com.z)
	var margin: float = _signed_inside(_footprint_hull(supports), piece_xz)
	# The piece loads a lone support and the chain of lone supporters below it; with several
	# supports the union footprint above is the whole check.
	var carried: Dictionary = {}
	if supports.size() == 1:
		var cur: int = supports[0]
		while not carried.has(cur):
			carried[cur] = true
			if _carriers(cur) != 1 or _on_disc[cur] == 1:
				break
			cur = _supporters[cur][0]
	for b: int in _down_set(supports):
		var hull: PackedVector2Array = _hull[b]
		if hull.is_empty():
			continue
		var m: float = _load_mass[b]
		var com: Vector3 = _load_com[b]
		if carried.has(b):
			com = (com * m + piece_com * piece_mass) / (m + piece_mass)
		margin = minf(margin, _signed_inside(hull, Vector2(com.x, com.z)))
	return margin


# --- analysis -----------------------------------------------------------------------------------


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / cube_size)), int(floor(p.y / cube_size)))


func _prepare(t: BotStackTuning) -> void:
	_degenerate_area = t.degenerate_area_m2
	_hash_reach = t.hash_reach_cells
	var n: int = body_ids.size()
	_supporters.clear()
	_hull.clear()
	_above.clear()
	_cube_poly.clear()
	_cube_cells.clear()
	_debris_cells.clear()
	_on_disc = PackedByteArray()
	_on_disc.resize(n)
	_sound = PackedByteArray()
	_sound.resize(n)
	_load_mass = PackedFloat32Array()
	_load_mass.resize(n)
	_load_com = PackedVector3Array()
	_load_com.resize(n)
	for i: int in n:
		_supporters.append(PackedInt32Array())
		_hull.append(PackedVector2Array())
		_above.append(PackedInt32Array())
	for ci: int in cube_pos.size():
		var p: Vector3 = cube_pos[ci]
		_cube_poly.append(_square(p, body_basis[cube_body[ci]]))
		var key: Vector2i = _cell_of(Vector2(p.x, p.z))
		var list: PackedInt32Array = _cube_cells.get(key, PackedInt32Array())
		list.append(ci)
		_cube_cells[key] = list
	_prepared = true


func _analyse_contacts(b: int, t: BotStackTuning) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var supporters: PackedInt32Array = PackedInt32Array()
	var max_dy: float = cube_size + t.rest_tolerance_m
	var disc_top: float = ground_y + cube_size * _HALF + t.rest_tolerance_m
	for ci: int in _body_cubes[b]:
		var p: Vector3 = cube_pos[ci]
		if p.y <= disc_top:
			_on_disc[b] = 1
			pts.append_array(_cube_poly[ci])
		var cell: Vector2i = _cell_of(Vector2(p.x, p.z))
		for dx: int in range(-_hash_reach, _hash_reach + 1):
			for dz: int in range(-_hash_reach, _hash_reach + 1):
				var list: PackedInt32Array = _cube_cells.get(cell + Vector2i(dx, dz), PackedInt32Array())
				for cj: int in list:
					var other: int = cube_body[cj]
					var dy: float = p.y - cube_pos[cj].y
					if other == b or dy <= 0.0 or dy > max_dy:
						continue
					var poly: PackedVector2Array = _clip(_cube_poly[ci], _cube_poly[cj])
					if _extent_min(poly) < t.min_contact_overlap_m:
						continue
					pts.append_array(poly)
					if not supporters.has(other):
						supporters.append(other)
	_supporters[b] = supporters
	_hull[b] = _convex_hull(pts)


func _finish(t: BotStackTuning) -> void:
	var n: int = body_ids.size()
	for b: int in n:
		for s: int in _supporters[b]:
			_above[s].append(b)
	# Load above each body: itself plus everything it carries alone (memoised recursion).
	_load_state = PackedByteArray()
	_load_state.resize(n)
	for b: int in n:
		_load_of(b)
	# Soundness, lowest bodies first so supporters are decided before what rests on them.
	var order: Array[int] = _support_order()
	for b: int in order:
		var ok: bool = body_tilt_deg[b] <= t.max_tilt_deg and body_settled[b] == 1
		ok = ok and not _hull[b].is_empty()
		if ok:
			var com: Vector3 = _load_com[b]
			ok = _signed_inside(_hull[b], Vector2(com.x, com.z)) >= 0.0
		for s: int in _supporters[b]:
			ok = ok and _sound[s] == 1
		_sound[b] = 1 if ok else 0
	for b: int in n:
		if _sound[b] == 1:
			continue
		for ci: int in _body_cubes[b]:
			var key: Vector2i = _cell_of(Vector2(cube_pos[ci].x, cube_pos[ci].z))
			var list: PackedInt32Array = _debris_cells.get(key, PackedInt32Array())
			list.append(ci)
			_debris_cells[key] = list


## Bodies (and the disc) carrying `b`: a body that also touches the disc is carried by the disc too.
func _carriers(b: int) -> int:
	return _supporters[b].size() + int(_on_disc[b])


func _load_of(b: int) -> void:
	if _load_state[b] != 0:
		return
	_load_state[b] = 1  # in progress (guards interlocked bodies)
	var mass_sum: float = body_mass[b]
	var moment: Vector3 = body_com[b] * body_mass[b]
	for u: int in _above[b]:
		if _carriers(u) != 1 or _load_state[u] == 1:
			continue
		_load_of(u)
		mass_sum += _load_mass[u]
		moment += _load_com[u] * _load_mass[u]
	_load_mass[b] = mass_sum
	_load_com[b] = moment / mass_sum if mass_sum > 0.0 else body_com[b]
	_load_state[b] = 2


## Bodies in support order (Kahn): every body after all its supporters. Bodies caught in a support
## cycle follow, lowest first.
func _support_order() -> Array[int]:
	var n: int = body_ids.size()
	var pending: PackedInt32Array = PackedInt32Array()
	var order: Array[int] = []
	var queue: Array[int] = []
	for b: int in n:
		pending.append(_supporters[b].size())
		if pending[b] == 0:
			queue.append(b)
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		order.append(cur)
		for u: int in _above[cur]:
			pending[u] -= 1
			if pending[u] == 0:
				queue.append(u)
	if order.size() < n:
		var rest: Array[int] = []
		for b: int in n:
			if pending[b] > 0:
				rest.append(b)
		rest.sort_custom(func(a: int, c: int) -> bool: return _lowest_y(a) < _lowest_y(c))
		order.append_array(rest)
	return order


func _lowest_y(b: int) -> float:
	var low: float = INF
	for ci: int in _body_cubes[b]:
		low = minf(low, cube_pos[ci].y)
	return low


## The bodies from `supports` down through every supporter (cached per support set).
func _down_set(supports: PackedInt32Array) -> PackedInt32Array:
	var sorted: Array[int] = []
	for s: int in supports:
		sorted.append(s)
	sorted.sort()
	var key: String = ",".join(PackedStringArray(sorted.map(func(v: int) -> String: return str(v))))
	if _down_cache.has(key):
		return _down_cache[key]
	var seen: Dictionary = {}
	var queue: Array[int] = []
	for s: int in sorted:
		seen[s] = true
		queue.append(s)
	var out: PackedInt32Array = PackedInt32Array()
	while not queue.is_empty():
		var cur: int = queue.pop_back()
		out.append(cur)
		for below: int in _supporters[cur]:
			if not seen.has(below):
				seen[below] = true
				queue.append(below)
	_down_cache[key] = out
	return out


func _footprint_hull(bodies: PackedInt32Array) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for b: int in bodies:
		for ci: int in _body_cubes[b]:
			pts.append_array(_cube_poly[ci])
	return _convex_hull(pts)


# --- 2D geometry --------------------------------------------------------------------------------


## The XZ outline of a cube centred at `c` in a body with `basis`, counter-clockwise.
func _square(c: Vector3, basis: Basis) -> PackedVector2Array:
	var half: float = cube_size * _HALF
	# Blocks use the 24 axis-aligned rotations: the footprint comes from the two axes that are
	# most horizontal, whichever local axis points up (a lying bar is rolled 90 degrees).
	var up_axis: int = _vertical_index(basis)
	var u_axis: Vector3 = _basis_axis(basis, (up_axis + 1) % _AXES)
	var v_axis: Vector3 = _basis_axis(basis, (up_axis + 2) % _AXES)
	var u: Vector2 = Vector2(u_axis.x, u_axis.z) * half
	var v: Vector2 = Vector2(v_axis.x, v_axis.z) * half
	var centre: Vector2 = Vector2(c.x, c.z)
	var poly: PackedVector2Array = PackedVector2Array(
		[centre + u + v, centre - u + v, centre - u - v, centre + u - v]
	)
	var area: float = _area(poly)
	if absf(area) < _degenerate_area:
		return PackedVector2Array()
	if area < 0.0:
		poly.reverse()
	return poly


static func _basis_axis(basis: Basis, index: int) -> Vector3:
	return basis.x if index == 0 else (basis.y if index == 1 else basis.z)


## Index (0 x, 1 y, 2 z) of the local axis closest to vertical, sign ignored.
static func _vertical_index(basis: Basis) -> int:
	var best: int = 0
	var best_y: float = -1.0
	for i: int in _AXES:
		var ay: float = absf(_basis_axis(basis, i).y)
		if ay > best_y:
			best_y = ay
			best = i
	return best


static func _area(poly: PackedVector2Array) -> float:
	var sum: float = 0.0
	for i: int in poly.size():
		var a: Vector2 = poly[i]
		var b: Vector2 = poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return sum * _HALF


## Sutherland-Hodgman: the part of convex CCW polygon `subject` inside convex CCW polygon `clip`.
static func _clip(subject: PackedVector2Array, clip: PackedVector2Array) -> PackedVector2Array:
	if subject.is_empty() or clip.is_empty():
		return PackedVector2Array()
	var out: PackedVector2Array = subject
	for i: int in clip.size():
		var a: Vector2 = clip[i]
		var b: Vector2 = clip[(i + 1) % clip.size()]
		var input: PackedVector2Array = out
		out = PackedVector2Array()
		if input.is_empty():
			break
		var prev: Vector2 = input[input.size() - 1]
		var prev_in: bool = (b - a).cross(prev - a) >= 0.0
		for cur: Vector2 in input:
			var cur_in: bool = (b - a).cross(cur - a) >= 0.0
			if cur_in != prev_in:
				var d1: float = (b - a).cross(prev - a)
				var d2: float = (b - a).cross(cur - a)
				out.append(prev + (cur - prev) * (d1 / (d1 - d2)))
			if cur_in:
				out.append(cur)
			prev = cur
			prev_in = cur_in
	return out


## The smaller side of the axis-aligned bounds of `pts` (0 when empty).
static func _extent_min(pts: PackedVector2Array) -> float:
	if pts.size() < _MIN_HULL_POINTS:
		return 0.0
	var lo: Vector2 = pts[0]
	var hi: Vector2 = pts[0]
	for p: Vector2 in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return minf(hi.x - lo.x, hi.y - lo.y)


## Andrew's monotone chain; the hull is counter-clockwise. Fewer than 3 distinct points give the
## points as they are.
static func _convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	var pts: Array[Vector2] = []
	for p: Vector2 in points:
		pts.append(p)
	pts.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if pts.size() < _MIN_HULL_POINTS:
		return PackedVector2Array(pts)
	var hull: Array[Vector2] = []
	for _pass: int in 2:
		var start: int = hull.size()
		for p: Vector2 in pts:
			while hull.size() >= start + 2:
				var last: Vector2 = hull[hull.size() - 1]
				var before: Vector2 = hull[hull.size() - 2]
				if (last - before).cross(p - before) > 0.0:
					break
				hull.pop_back()
			hull.append(p)
		hull.pop_back()
		pts.reverse()
	return PackedVector2Array(hull)


## Signed distance from `p` to the boundary of a CCW convex hull: positive inside, negative outside.
## A hull of fewer than 3 points is all boundary: the (negative) distance to it.
static func _signed_inside(hull: PackedVector2Array, p: Vector2) -> float:
	if hull.size() < _MIN_HULL_POINTS:
		if hull.is_empty():
			return -INF
		var nearest: float = INF
		for i: int in hull.size():
			var a: Vector2 = hull[i]
			var b: Vector2 = hull[mini(i + 1, hull.size() - 1)]
			nearest = minf(nearest, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
		return -nearest
	var best: float = INF
	for i: int in hull.size():
		var a: Vector2 = hull[i]
		var b: Vector2 = hull[(i + 1) % hull.size()]
		var edge: Vector2 = b - a
		var edge_len: float = edge.length()
		if edge_len > 0.0:
			best = minf(best, edge.cross(p - a) / edge_len)
	return best
