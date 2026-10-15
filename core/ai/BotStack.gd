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
## forcing -INF.
##
## Cut model (Bontago-1t5.72, the owner's two centre-of-mass rules): the CUT at a body b treats b plus everything
## resting on it (its up-closure U(b), through any number of carriers) as one object; its support region is the
## convex hull of every contact patch between U(b) and what is NOT in U(b) (the other carriers and the disc), its
## combined centre of mass is the mass-weighted mean over U(b). The margin is the signed distance of that centre
## inside the region. A new piece adds itself to the up-closure of every body that carries it (lower_cuts); its own
## cut (rule 1) is against its contact patches on the faces it rests on (piece_cut). DECISION: the region is the hull
## of the contact PATCHES (bottom faces of the carried object clipped to the top faces of its carriers), not the
## carriers' whole top surfaces: an inverted-T piece standing on its stem tips over the stem. Face outlines use the
## real collider half-width (add_body face_half) and are centred on the FACE, not the cube centre, for a tilted body.
##
## Support faces (Bontago-1t5.68): soundness describes a TOWER (every body down to the disc upright). Where a
## piece may REST is a separate, looser rule (is_flat_support, rest_margin): the faces under the piece lie flat
## against the disc within support_face_tolerance_deg, and the body and every carrier below it are settled with a
## known contact hull; a carrier may lean (debris), and whether the pile holds the piece is load_margin's call
## through every carrier down to the disc. DECISION: "flat against the disc" is measured in this snapshot's frame,
## which is disc-local: game/BotStackProbe converts cube centres with Field.to_local and bases with the inverse
## field basis, and Field (game/field/Field.gd _apply_tilt_transform) carries the tilt in its own transform, so local y
## IS the disc normal while the field tilts; world up never enters. The bot's real cube probes are cast along the
## same disc-local column (BotController._column_hit) and report field-local heights.
##
## Usage: add_body() for each block, then call analyse_step() until it returns true (the contact
## pass is sliced; the load and soundness sweep runs in the last slice), then query.

const _MIN_HULL_POINTS: int = 3
const _HALF: float = 0.5
const _AXES: int = 3
const _AXIS_EPS: float = 0.0001
## lower_cuts row layout: [body index, margin_m, carried_mass, lever_m, top_y].
const LOWER_ROW: int = 5
const _OWNER_DISC: int = -1
const _KEY_MUL: int = 1000003
const _SQUARE_CORNERS: int = 4
const _RECT_POINTS: int = 4


## The cut at one body (see the header): the up-closure U(b), its mass and centre, and its external support region.
class Cut:
	extends RefCounted
	var body: int = -1
	var members: PackedInt32Array = PackedInt32Array()  # U(b), b first
	var mask: PackedByteArray = PackedByteArray()  # per body index: 1 when in U(b)
	var mass: float = 0.0
	var com: Vector3 = Vector3.ZERO
	var top_y: float = 0.0
	var plane_y: float = 0.0  # b's lowest bottom face
	var hull: PackedVector2Array = PackedVector2Array()  # external contact patches of U(b)
	var planes: PackedFloat32Array = PackedFloat32Array()
	var margin: float = -INF  # the standing structure, no piece

	func has(b: int) -> bool:
		return b >= 0 and b < mask.size() and mask[b] == 1


## Where a candidate piece rests (piece_cut): the contact patches on the faces under it.
class PieceCut:
	extends RefCounted
	var plane_y: float = 0.0
	var on_disc: bool = false
	var flat: bool = true  # every support is_flat_support (Bontago-1t5.68)
	var supports: PackedInt32Array = PackedInt32Array()  # snapshot body indices
	var points: PackedVector2Array = PackedVector2Array()  # patch vertices (block patches eroded by aim)
	var owners: PackedInt32Array = PackedInt32Array()  # per point: body index, -1 disc, -2 unknown block

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
## Per body: half-width of its cube faces (metres), the real collider box half-extent.
var body_face_half: PackedFloat32Array = PackedFloat32Array()
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
## Bontago-1t5.68: 1 when the body and every body carrying it (down to the disc) are settled with a known hull.
var _known_chain: PackedByteArray = PackedByteArray()
var _face_tolerance_deg: float = 0.0  # set from the tuning in _prepare
var _contact_tolerance: float = 0.0  # set from the tuning in _prepare
var _index: Dictionary = {}  # body id -> index
var _top_poly: Array[PackedVector2Array] = []  # per cube: outline of its top face, centred on the face
var _top_lo: PackedVector2Array = PackedVector2Array()  # per cube: bounds of the top outline
var _top_hi: PackedVector2Array = PackedVector2Array()
var _bot_lo: PackedVector2Array = PackedVector2Array()  # per cube: bounds of the bottom outline
var _bot_hi: PackedVector2Array = PackedVector2Array()
var _erode_memo: Dictionary = {}  # Vector2(cube, aim) -> eroded top Vector4; see _eroded_top
var _axis_aligned: PackedByteArray = PackedByteArray()  # per cube: 1 when its outlines are axis-aligned rectangles
var _bot_poly: Array[PackedVector2Array] = []  # per cube: outline of its bottom face
var _patch_owner: Array[PackedInt32Array] = []  # per body: supporter index (or -1 disc) of each contact patch
var _patch_pts: Array[Array] = []  # per body: PackedVector2Array of each contact patch, parallel to _patch_owner
var _cuts: Array[Cut] = []  # lazy, per body
var _cube_cells: Dictionary = {}  # Vector2i -> PackedInt32Array of cube indices
var _body_cubes: Array[PackedInt32Array] = []
var _down_cache: Dictionary = {}  # int key of a sorted support set -> [sorted set, closure down to the disc]
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
## of mass is the cube mean). `face_half` is the half-width of the cube faces (the collider box half-extent); a
## negative value means cube_size * 0.5. Invalidates any earlier analysis.
func add_body(
	id: int,
	team: int,
	basis: Basis,
	cubes: PackedVector3Array,
	mass: float,
	settled: bool,
	face_half: float = -1.0
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
	body_face_half.append(face_half if face_half > 0.0 else cube_size * _HALF)
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


## Bontago-1t5.70: sound bodies of `team` with no SOUND body resting on them, tallest first. Unlike sound_tops an
## unsound block lying on the tower (a leaning top piece, a stray) does not take the tower below it out of the
## list: the tower still stands, the plan keeps following it. DECISION: unsound bodies above are ignored here
## only; is_usable_top (the site filter) still refuses a top that carries one.
func standing_tops(team: int) -> PackedInt32Array:
	var tops: Array[int] = []
	if not _done:
		return PackedInt32Array()
	for i: int in body_ids.size():
		if body_team[i] != team or _sound[i] != 1:
			continue
		var carries_sound: bool = false
		for u: int in _above[i]:
			if _sound[u] == 1:
				carries_sound = true
				break
		if not carries_sound:
			tops.append(i)
	tops.sort_custom(
		func(a: int, b: int) -> bool:
			var ha: float = top_height(a)
			var hb: float = top_height(b)
			return a < b if is_equal_approx(ha, hb) else ha > hb
	)
	return PackedInt32Array(tops)


## Bontago-1t5.70: true when `body` or any body carrying it down to the disc has its centre of mass within `radius`
## of `point` (disk-local XZ): the body belongs to the tower rooted there, however far its own top has wandered.
func rooted_near(body: int, point: Vector2, radius: float) -> bool:
	for b: int in down_set(PackedInt32Array([body])):
		if com_xz(b).distance_to(point) <= radius:
			return true
	return false


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


## The smallest signed distance (metres, positive inside) by which the centre of mass of the load stays inside the
## support region of the piece and of every body from `support_ids` down to the disc, with a piece of `piece_mass`
## centred at `piece_com` added on top (the cut model, header). INF when no support id is known (no block support).
## The piece is taken as one cube square centred under `piece_com`; its patch on the supports' top faces is the first
## region (rule 1), each lower region is that body's external contact hull (rule 2).
func load_margin(support_ids: PackedInt64Array, piece_com: Vector3, piece_mass: float) -> float:
	var supports: PackedInt32Array = PackedInt32Array()
	for id: int in support_ids:
		var i: int = index_of(id)
		if i >= 0:
			supports.append(i)
	if supports.is_empty() or not _done:
		return INF
	var bottom: PackedVector2Array = PackedVector2Array([Vector2(piece_com.x, piece_com.z)])
	var pc: PieceCut = _piece_cut(bottom, cube_size * _HALF, ground_y, 0.0, PackedByteArray(), supports)
	return _margin_with(pc, supports, piece_com, piece_mass)


## Bontago-1t5.68: true when a piece may rest on `body`'s top faces: they lie within support_face_tolerance_deg
## of the disc plane (the body's tilt against the disc normal), and the body and every body carrying it are
## settled with a known contact hull. A carrier may lean or be unsound (fallen debris): whether the pile holds
## the piece is the load margin's call (rest_margin). A body with an unknown hull below it (floating in the
## snapshot, its support out of range) cannot be checked, so it is not a support.
func is_flat_support(body: int) -> bool:
	if not _done or body < 0 or body >= _known_chain.size():
		return false
	return _known_chain[body] == 1 and body_tilt_deg[body] <= _face_tolerance_deg


## Bontago-1t5.68: index of the body whose top face is highest above disk-local `point` (the first one a probe
## down the disc-normal column hits), -1 when the column holds only the disc.
func surface_at(point: Vector2) -> int:
	var ci: int = _top_cube_at(point)
	return cube_body[ci] if ci >= 0 else -1


## Bontago-1t5.68: how a piece would rest with its bottom cubes over the disk-local `points` (the columns the
## bot's cube probes fire down). The highest face under them is the resting plane (the host lifts the piece onto
## it); the bodies whose faces lie on it within rest_tolerance_m carry the piece. INF when only the disc carries
## it (no block support, as load_margin); -INF when a carrying face is not a flat support (is_flat_support:
## tilted against the disc, unsettled or unverifiable); else the cut-model margin (load_margin) for a piece of
## `piece_mass` centred at `piece_com_xz`, whose bottom is one cube square under each of `points`. Negative: the
## pile would not hold the piece.
func rest_margin(points: PackedVector2Array, piece_com_xz: Vector2, piece_mass: float) -> float:
	if not _done:
		return INF
	var hits: PackedInt32Array = PackedInt32Array()
	var plane: float = ground_y
	for p: Vector2 in points:
		var ci: int = _top_cube_at(p)
		hits.append(ci)
		if ci >= 0:
			plane = maxf(plane, _cube_top(ci))
	var supports: PackedInt32Array = PackedInt32Array()
	for ci: int in hits:
		# DECISION: rest_tolerance_m (the stack's own contact tolerance) decides which faces touch the plane; a
		# lower face is under an overhang, which the patch hull of the piece covers.
		if ci < 0 or plane - _cube_top(ci) > _contact_tolerance:
			continue
		var b: int = cube_body[ci]
		if not is_flat_support(b):
			return -INF
		if not supports.has(b):
			supports.append(b)
	if supports.is_empty():
		return INF
	var disc_ok: PackedByteArray = PackedByteArray()
	for ci: int in hits:
		disc_ok.append(1 if ci < 0 else 0)
	var pc: PieceCut = _piece_cut(points, cube_size * _HALF, plane, 0.0, disc_ok, PackedInt32Array())
	if not pc.flat:
		return -INF
	# DECISION: the margin is measured in the disc plane only, so the piece's height does not enter it; its
	# centre is put half a cube above the resting plane.
	var com: Vector3 = Vector3(piece_com_xz.x, plane + cube_size * _HALF, piece_com_xz.y)
	return _margin_with(pc, supports, com, piece_mass)


# --- cut model ----------------------------------------------------------------------------------


## The cut at `body` (header): memoised per analysis, built the first time a candidate's down-set reaches it. Null
## before the analysis is finished or for an unknown body.
func cut_of(body: int) -> Cut:
	if not _done or body < 0 or body >= body_ids.size():
		return null
	var cached: Cut = _cuts[body]
	if cached != null:
		return cached
	var n: int = body_ids.size()
	var cut: Cut = Cut.new()
	cut.body = body
	cut.mask.resize(n)
	cut.members.append(body)
	cut.mask[body] = 1
	var head: int = 0
	while head < cut.members.size():
		var x: int = cut.members[head]
		head += 1
		for u: int in _above[x]:
			if cut.mask[u] == 0:
				cut.mask[u] = 1
				cut.members.append(u)
	var moment: Vector3 = Vector3.ZERO
	var top: float = -INF
	var pts: PackedVector2Array = PackedVector2Array()
	for x: int in cut.members:
		cut.mass += body_mass[x]
		moment += body_com[x] * body_mass[x]
		top = maxf(top, top_height(x))
		var owners: PackedInt32Array = _patch_owner[x]
		for i: int in owners.size():
			var o: int = owners[i]
			if o < 0 or cut.mask[o] == 0:
				pts.append_array(_patch_pts[x][i] as PackedVector2Array)
	cut.com = moment / cut.mass if cut.mass > 0.0 else body_com[body]
	cut.top_y = top
	cut.plane_y = _lowest_y(body) - cube_size * _HALF
	cut.hull = BotGeom2D.hull(pts)
	cut.planes = BotGeom2D.half_planes(cut.hull)
	cut.margin = BotGeom2D.signed_inside(cut.planes, cut.hull, Vector2(cut.com.x, cut.com.z))
	_cuts[body] = cut
	return cut


## The bodies from `supports` down through every supporter (cached per support set, keyed by an int hash of the
## sorted set with the set kept to rule out collisions).
func down_set(supports: PackedInt32Array) -> PackedInt32Array:
	var sorted: PackedInt32Array = supports
	if supports.size() > 1:
		sorted = supports.duplicate()
		sorted.sort()
	var key: int = 0
	for s: int in sorted:
		key = key * _KEY_MUL + s + 1
	var entry: Array = _down_cache.get(key, []) as Array
	if not entry.is_empty() and entry[0] == sorted:
		return entry[1] as PackedInt32Array
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
	if entry.is_empty():
		_down_cache[key] = [sorted, out]
	return out


## Where a piece with bottom cubes centred at the disk-local `bottom` points (square faces of half-width `half`) would
## rest: the resting plane is the highest face overlapping any of them (the host lifts the piece onto it), but not
## below `min_plane`; the faces on that plane within rest_tolerance_m carry it. Each carrier's top face is shrunk by
## `aim` (the aim error moves the piece, not the carrier, so this is a lower bound on every outcome of it); the
## disc is never shrunk: `disc_ok[j]` (empty: all) says square j may rest on the disc. See STATICS_DESIGN 2.3.
func piece_cut(
	bottom: PackedVector2Array, half: float, min_plane: float, aim: float, disc_ok: PackedByteArray
) -> PieceCut:
	return _piece_cut(bottom, half, min_plane, aim, disc_ok, PackedInt32Array())


## For every body that carries the piece (down_set of pc.supports): one row of LOWER_ROW floats
## [body, margin_m, carried_mass, lever_m, top_y] with the piece added to its up-closure. `margin_m` is the signed
## distance of the combined centre of mass (shifted along gravity by `gravity_shift` * lever) inside the body's
## external contact hull, extended by the piece's patches on carriers outside the up-closure (a bridge to another
## column); INF for a body with no known hull. `top_y` is the higher of the cut's top and the piece's centre plus
## half a cube (the piece's own top is not known here).
func lower_cuts(
	pc: PieceCut, piece_com: Vector3, piece_mass: float, gravity_shift: Vector2
) -> PackedFloat32Array:
	var rows: PackedFloat32Array = PackedFloat32Array()
	if not _done or pc.supports.is_empty():
		return rows
	for b: int in down_set(pc.supports):
		var cut: Cut = cut_of(b)
		var total: float = cut.mass + piece_mass
		var com: Vector3 = cut.com
		if total > 0.0:
			com = (cut.com * cut.mass + piece_com * piece_mass) / total
		var lever: float = com.y - cut.plane_y
		var hull: PackedVector2Array = cut.hull
		var planes: PackedFloat32Array = cut.planes
		var extra: PackedVector2Array = PackedVector2Array()
		for i: int in pc.owners.size():
			if not cut.has(pc.owners[i]):
				extra.append(pc.points[i])
		if not extra.is_empty() and not cut.hull.is_empty():
			var joined: PackedVector2Array = cut.hull.duplicate()
			joined.append_array(extra)
			hull = BotGeom2D.hull(joined)
			planes = BotGeom2D.half_planes(hull)
		var margin: float = INF
		if not hull.is_empty():
			var at: Vector2 = Vector2(com.x, com.z) + gravity_shift * lever
			margin = BotGeom2D.signed_inside(planes, hull, at)
		rows.append(float(b))
		rows.append(margin)
		rows.append(total)
		rows.append(lever)
		rows.append(maxf(cut.top_y, piece_com.y + cube_size * _HALF))
	return rows


## min(the piece's own margin, every lower cut's margin) for `pc`; when the piece has no patch the margin falls back to
## the supports' footprint (a finite, negative number for a piece beside them).
func _margin_with(pc: PieceCut, supports: PackedInt32Array, piece_com: Vector3, piece_mass: float) -> float:
	var piece_xz: Vector2 = Vector2(piece_com.x, piece_com.z)
	var region: PackedVector2Array = BotGeom2D.hull(pc.points)
	var carrying: PieceCut = pc
	if region.is_empty():
		region = _footprint_hull(supports)
		carrying = PieceCut.new()
		carrying.supports = supports
	var margin: float = BotGeom2D.signed_inside_hull(region, piece_xz)
	var rows: PackedFloat32Array = lower_cuts(carrying, piece_com, piece_mass, Vector2.ZERO)
	var i: int = 0
	while i < rows.size():
		margin = minf(margin, rows[i + 1])
		i += LOWER_ROW
	return margin


func _piece_cut(
	bottom: PackedVector2Array,
	half: float,
	min_plane: float,
	aim: float,
	disc_ok: PackedByteArray,
	only: PackedInt32Array
) -> PieceCut:
	var pc: PieceCut = PieceCut.new()
	pc.plane_y = min_plane
	if not _done:
		return pc
	var reach: Vector2 = Vector2(half, half)
	# Pass 1: every (square, cube) pair whose faces overlap enough; the highest such top face is the plane.
	var pair_j: PackedInt32Array = PackedInt32Array()
	var pair_k: PackedInt32Array = PackedInt32Array()
	var plane: float = min_plane
	for j: int in bottom.size():
		var centre: Vector2 = bottom[j]
		var cell: Vector2i = _cell_of(centre)
		for dx: int in range(-_hash_reach, _hash_reach + 1):
			for dz: int in range(-_hash_reach, _hash_reach + 1):
				var list: PackedInt32Array = _cube_cells.get(cell + Vector2i(dx, dz), PackedInt32Array())
				for k: int in list:
					if not only.is_empty() and not only.has(cube_body[k]):
						continue
					# DECISION: a body tilted past the face tolerance only sets the plane when the square's centre is
					# on its top outline (a probe would hit it, rest_margin rejects it); beside a leaning cube the
					# piece rests on the disc (Bontago-1t5.68), and the projected outline of a tilted top is only
					# an approximation of where the host would lift the piece.
					if body_tilt_deg[cube_body[k]] > _face_tolerance_deg:
						if BotGeom2D.signed_inside_hull(_top_poly[k], centre) < 0.0:
							continue
					# DECISION (Bontago-1t5.72.10): ANY positive overlap sets the plane and carries the piece. The host lifts
					# a placement onto every box it intersects (MatchPlacement._lift_pose_clear, no minimum overlap), and
					# Jolt stands a piece on a 9 cm strip (statics Jolt case F), so dropping slivers below
					# min_contact_overlap_m called a piece resting on a sliver "on the lower plane / on the disc". The
					# strip joins the support hull, so the verdict is the physical one either way.
					var overlap: PackedVector2Array = _patch_of(k, centre - reach, centre + reach, 0.0)
					if overlap.is_empty():
						continue
					pair_j.append(j)
					pair_k.append(k)
					plane = maxf(plane, _cube_top(k))
	pc.plane_y = plane
	pc.on_disc = absf(plane - ground_y) <= _contact_tolerance
	# Pass 2: the cubes on the plane carry the piece.
	for i: int in pair_j.size():
		var k: int = pair_k[i]
		if absf(_cube_top(k) - plane) > _contact_tolerance:
			continue
		var b: int = cube_body[k]
		if not pc.supports.has(b):
			pc.supports.append(b)
			if not is_flat_support(b):
				pc.flat = false
		var centre: Vector2 = bottom[pair_j[i]]
		var patch: PackedVector2Array = _patch_of(k, centre - reach, centre + reach, aim)
		for p: Vector2 in patch:
			pc.points.append(p)
			pc.owners.append(b)
	if pc.on_disc:
		for j: int in bottom.size():
			if not disc_ok.is_empty() and (j >= disc_ok.size() or disc_ok[j] == 0):
				continue
			var c: Vector2 = bottom[j]
			pc.points.append(c + Vector2(-half, -half))
			pc.points.append(c + Vector2(half, -half))
			pc.points.append(c + Vector2(half, half))
			pc.points.append(c + Vector2(-half, half))
			for _corner: int in _SQUARE_CORNERS:
				pc.owners.append(_OWNER_DISC)
	return pc


## The overlap of the axis-aligned box lo..hi (a piece's bottom face) with cube `k`'s top face eroded by `aim`.
## DECISION (Bontago-1t5.72.10): the aim error erodes the merged support REGION once, not each cube top: an edge that
## abuts a coplanar top across the seam is interior to the region and is not eroded (see _eroded_top).
func _patch_of(k: int, lo: Vector2, hi: Vector2, aim: float) -> PackedVector2Array:
	if _axis_aligned[k] == 1:
		var r: Vector4 = _eroded_top(k, aim)
		return BotGeom2D.rect_overlap(lo, hi, Vector2(r.x, r.y), Vector2(r.z, r.w))
	var box: PackedVector2Array = PackedVector2Array([lo, Vector2(hi.x, lo.y), hi, Vector2(lo.x, hi.y)])
	return BotGeom2D.clip_convex(box, BotGeom2D.erode(_top_poly[k], aim))


## Cube `k`'s top rectangle (lo.x, lo.y, hi.x, hi.y) eroded by `aim` on its exposed edges only. An edge is shared (not
## eroded) when the coplanar flat tops of other cubes abut it across the seam and cover its whole length; for
## axis-aligned faces this equals eroding the rectilinear union of the coplanar tops. Memoised per (cube, aim).
func _eroded_top(k: int, aim: float) -> Vector4:
	var lo: Vector2 = _top_lo[k]
	var hi: Vector2 = _top_hi[k]
	if aim <= 0.0:
		return Vector4(lo.x, lo.y, hi.x, hi.y)
	var key: Vector2 = Vector2(float(k), aim)
	if _erode_memo.has(key):
		return _erode_memo[key]
	var s: Vector4 = Vector4(aim, aim, aim, aim)
	if body_tilt_deg[cube_body[k]] <= _face_tolerance_deg:
		if _side_shared(k, 0, -1.0):
			s.x = 0.0
		if _side_shared(k, 1, -1.0):
			s.y = 0.0
		if _side_shared(k, 0, 1.0):
			s.z = 0.0
		if _side_shared(k, 1, 1.0):
			s.w = 0.0
	var out: Vector4 = Vector4(lo.x + s.x, lo.y + s.y, hi.x - s.z, hi.y - s.w)
	_erode_memo[key] = out
	return out


## Whether the side of cube `k`'s top at `axis` (0 x, 1 z), direction `dir` (+1 / -1) is entirely covered by flat
## coplanar tops of other cubes across a seam no wider than the cube pitch leaves plus rest_tolerance_m.
func _side_shared(k: int, axis: int, dir: float) -> bool:
	var lo: Vector2 = _top_lo[k]
	var hi: Vector2 = _top_hi[k]
	var other: int = 1 - axis
	var seam: float = maxf(cube_size - (hi[axis] - lo[axis]), 0.0) + _contact_tolerance
	var seam_other: float = maxf(cube_size - (hi[other] - lo[other]), 0.0) + _contact_tolerance
	var edge: float = hi[axis] if dir > 0.0 else lo[axis]
	var top_y: float = _cube_top(k)
	var starts: Array[float] = []
	var ends: Array[float] = []
	var cell: Vector2i = _cell_of((lo + hi) * 0.5)
	for dx: int in range(-_hash_reach, _hash_reach + 1):
		for dz: int in range(-_hash_reach, _hash_reach + 1):
			for k2: int in _cube_cells.get(cell + Vector2i(dx, dz), PackedInt32Array()):
				if k2 == k or _axis_aligned[k2] != 1 or body_tilt_deg[cube_body[k2]] > _face_tolerance_deg:
					continue
				if absf(_cube_top(k2) - top_y) > _contact_tolerance:
					continue
				var gap: float = (_top_lo[k2][axis] - edge) if dir > 0.0 else (edge - _top_hi[k2][axis])
				if gap < -_contact_tolerance or gap > seam:
					continue
				starts.append(_top_lo[k2][other])
				ends.append(_top_hi[k2][other])
	var cur: float = lo[other]
	var target: float = hi[other]
	var progressed: bool = true
	while progressed and cur < target - _contact_tolerance:
		progressed = false
		for i: int in starts.size():
			if starts[i] <= cur + seam_other and ends[i] > cur:
				cur = ends[i]
				progressed = true
	return cur >= target - _contact_tolerance


# --- analysis -----------------------------------------------------------------------------------


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / cube_size)), int(floor(p.y / cube_size)))


func _prepare(t: BotStackTuning) -> void:
	_degenerate_area = t.degenerate_area_m2
	_hash_reach = t.hash_reach_cells
	_face_tolerance_deg = t.support_face_tolerance_deg
	_contact_tolerance = t.rest_tolerance_m
	var n: int = body_ids.size()
	_supporters.clear()
	_hull.clear()
	_above.clear()
	_top_poly.clear()
	_bot_poly.clear()
	_top_lo = PackedVector2Array()
	_top_hi = PackedVector2Array()
	_bot_lo = PackedVector2Array()
	_bot_hi = PackedVector2Array()
	_axis_aligned = PackedByteArray()
	_patch_owner.clear()
	_patch_pts.clear()
	_cuts.clear()
	_erode_memo.clear()
	_cube_cells.clear()
	_on_disc = PackedByteArray()
	_on_disc.resize(n)
	_sound = PackedByteArray()
	_sound.resize(n)
	_known_chain = PackedByteArray()
	_known_chain.resize(n)
	_load_mass = PackedFloat32Array()
	_load_mass.resize(n)
	_load_com = PackedVector3Array()
	_load_com.resize(n)
	for i: int in n:
		_supporters.append(PackedInt32Array())
		_hull.append(PackedVector2Array())
		_above.append(PackedInt32Array())
		_patch_owner.append(PackedInt32Array())
		_patch_pts.append([])
		_cuts.append(null)
	for ci: int in cube_pos.size():
		var p: Vector3 = cube_pos[ci]
		_add_outlines(p, body_basis[cube_body[ci]], body_face_half[cube_body[ci]])
		var key: Vector2i = _cell_of(Vector2(p.x, p.z))
		var list: PackedInt32Array = _cube_cells.get(key, PackedInt32Array())
		list.append(ci)
		_cube_cells[key] = list
	_prepared = true


## Appends the top and bottom face outlines (and their bounds) of the cube centred at `c`.
func _add_outlines(c: Vector3, basis: Basis, face_half: float) -> void:
	# Blocks use the 24 axis-aligned rotations: the footprint comes from the two axes that are most horizontal,
	# whichever local axis points up (a lying bar is rolled 90 degrees).
	var up_axis: int = _vertical_index(basis)
	var up: Vector3 = _basis_axis(basis, up_axis)
	if up.y < 0.0:
		up = -up
	var u_axis: Vector3 = _basis_axis(basis, (up_axis + 1) % _AXES)
	var v_axis: Vector3 = _basis_axis(basis, (up_axis + 2) % _AXES)
	var u: Vector2 = Vector2(u_axis.x, u_axis.z) * face_half
	var v: Vector2 = Vector2(v_axis.x, v_axis.z) * face_half
	# Bontago-1t5.72: a tilted body's faces are centred on the FACE centres, not on the cube centre.
	var lift: Vector2 = Vector2(up.x, up.z) * face_half
	var centre: Vector2 = Vector2(c.x, c.z)
	var top: PackedVector2Array = BotGeom2D.square(centre + lift, u, v)
	var bot: PackedVector2Array = BotGeom2D.square(centre - lift, u, v)
	if absf(BotGeom2D.area(top)) < _degenerate_area:
		top = PackedVector2Array()
		bot = PackedVector2Array()
	_top_poly.append(top)
	_bot_poly.append(bot)
	_axis_aligned.append(1 if _is_rect(top) else 0)
	_top_lo.append(_bounds(top, true))
	_top_hi.append(_bounds(top, false))
	_bot_lo.append(_bounds(bot, true))
	_bot_hi.append(_bounds(bot, false))


## True for a 4-point polygon whose edges all run along an axis.
static func _is_rect(poly: PackedVector2Array) -> bool:
	if poly.size() != _RECT_POINTS:
		return false
	for i: int in _RECT_POINTS:
		var e: Vector2 = poly[(i + 1) % _RECT_POINTS] - poly[i]
		if absf(e.x) > _AXIS_EPS and absf(e.y) > _AXIS_EPS:
			return false
	return true


static func _bounds(poly: PackedVector2Array, low: bool) -> Vector2:
	if poly.is_empty():
		return Vector2.ZERO
	var out: Vector2 = poly[0]
	for p: Vector2 in poly:
		out = Vector2(minf(out.x, p.x), minf(out.y, p.y)) if low else Vector2(maxf(out.x, p.x), maxf(out.y, p.y))
	return out


func _analyse_contacts(b: int, t: BotStackTuning) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	var supporters: PackedInt32Array = PackedInt32Array()
	var owners: PackedInt32Array = PackedInt32Array()
	var patches: Array = []
	var max_dy: float = cube_size + t.rest_tolerance_m
	var disc_top: float = ground_y + cube_size * _HALF + t.rest_tolerance_m
	for ci: int in _body_cubes[b]:
		var p: Vector3 = cube_pos[ci]
		if p.y <= disc_top:
			_on_disc[b] = 1
			pts.append_array(_bot_poly[ci])
			owners.append(_OWNER_DISC)
			patches.append(_bot_poly[ci])
		var cell: Vector2i = _cell_of(Vector2(p.x, p.z))
		for dx: int in range(-_hash_reach, _hash_reach + 1):
			for dz: int in range(-_hash_reach, _hash_reach + 1):
				var list: PackedInt32Array = _cube_cells.get(cell + Vector2i(dx, dz), PackedInt32Array())
				for cj: int in list:
					var other: int = cube_body[cj]
					var dy: float = p.y - cube_pos[cj].y
					if other == b or dy <= 0.0 or dy > max_dy:
						continue
					var poly: PackedVector2Array = _contact_patch(ci, cj)
					if BotGeom2D.min_extent(poly) < t.min_contact_overlap_m:
						continue
					pts.append_array(poly)
					owners.append(other)
					patches.append(poly)
					if not supporters.has(other):
						supporters.append(other)
	_supporters[b] = supporters
	_hull[b] = BotGeom2D.hull(pts)
	_patch_owner[b] = owners
	_patch_pts[b] = patches


## The patch where cube `ci`'s bottom face rests on cube `cj`'s top face.
func _contact_patch(ci: int, cj: int) -> PackedVector2Array:
	if _axis_aligned[ci] == 1 and _axis_aligned[cj] == 1:
		return BotGeom2D.rect_overlap(_bot_lo[ci], _bot_hi[ci], _top_lo[cj], _top_hi[cj])
	return BotGeom2D.clip_convex(_bot_poly[ci], _top_poly[cj])


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
			ok = BotGeom2D.signed_inside_hull(_hull[b], Vector2(com.x, com.z)) >= 0.0
		for s: int in _supporters[b]:
			ok = ok and _sound[s] == 1
		_sound[b] = 1 if ok else 0
		# Bontago-1t5.68: the carrier chain a support face needs (tilt and centre of mass are not part of it).
		var known: bool = body_settled[b] == 1 and not _hull[b].is_empty()
		for s: int in _supporters[b]:
			known = known and _known_chain[s] == 1
		_known_chain[b] = 1 if known else 0


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


## The cube whose top face is highest over `point` (its XZ square contains the point), -1 for none; the first
## found wins a tie (the hash walk is deterministic).
func _top_cube_at(point: Vector2) -> int:
	var best: int = -1
	var best_top: float = -INF
	var cell: Vector2i = _cell_of(point)
	for dx: int in range(-_hash_reach, _hash_reach + 1):
		for dz: int in range(-_hash_reach, _hash_reach + 1):
			var list: PackedInt32Array = _cube_cells.get(cell + Vector2i(dx, dz), PackedInt32Array())
			for ci: int in list:
				var poly: PackedVector2Array = _top_poly[ci]
				if poly.size() < _MIN_HULL_POINTS or BotGeom2D.signed_inside_hull(poly, point) < 0.0:
					continue
				var top: float = _cube_top(ci)
				if top > best_top:
					best_top = top
					best = ci
	return best


## Top face height of cube `ci` (its centre plus half a cube; approximate for a tilted body).
func _cube_top(ci: int) -> float:
	return cube_pos[ci].y + cube_size * _HALF


func _footprint_hull(bodies: PackedInt32Array) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for b: int in bodies:
		for ci: int in _body_cubes[b]:
			pts.append_array(_top_poly[ci])
	return BotGeom2D.hull(pts)


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
