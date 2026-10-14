class_name BotStability
extends RefCounted
## Bontago-1t5.72 (STATICS_DESIGN 2.3 and 3): does a candidate placement stand? The bot's one stability judgement,
## built from the owner's two centre-of-mass rules. A placement is stable iff `slack > 0`, where slack is the
## smallest (margin - required) over the piece's own cut (rule 1: its centre of mass against the contact patches
## under it) and every lower cut (rule 2: everything resting on a body as one object, down to the disc). BotStack
## holds the geometry (piece_cut, lower_cuts). Pure: reads a candidate, its orientation, the world view's stack
## snapshot and a Requirement; no scene tree.
##
## Disturbance (STATICS_DESIGN 3.1, 2.6; Bontago-1t5.72.6): the Storm's sustained push and the gift allowance raise
## the requirement only while weather or gifts are on; a tilted disc shifts every centre of mass exactly.

const SHIPPED_PHYSICS_TUNING: PhysicsTuning = preload("res://config/physics_tuning.tres")
## Result.binding: no cut was evaluated.
const BINDING_NONE: int = -2
## Result.binding: the piece's own cut (rule 1) is the tightest.
const BINDING_PIECE: int = -1
## PieceCut.owners value of an assumed (unsnapshotted) block.
const _OWNER_UNKNOWN: int = -2
## lower_cuts row fields (BotStack.LOWER_ROW floats per row): [body, margin_m, carried_mass, lever_m, top_y].
const _ROW_BODY: int = 0
const _ROW_MARGIN: int = 1
const _ROW_CARRIED: int = 2
const _ROW_LEVER: int = 3
const _ROW_TOP: int = 4
## Disc-local height of the disc surface (BotStackProbe.build: the shipped disc is field-local y = 0).
const _GROUND_Y: float = 0.0
const _HALF: float = 0.5
const _NO_SUPPORT: float = BotThink.NO_SUPPORT


## What a placement must clear; built once per think (requirement()).
class Requirement:
	extends RefCounted
	var aim_m: float = 0.0  # profile.aim_noise_m * aim_margin_share
	var tolerance_m: float = 0.0  # numeric_tolerance_m
	var probe_contact_m: float = 0.0  # BotTuning.stability_contact_tolerance_m (the one probe tolerance)
	var face_half_m: float = 0.0  # (cube_size - cube_margin) * 0.5
	var gift_m: float = 0.0  # disturbance package
	var wind_accel_ratio: float = 0.0  # disturbance package: storm max_accel * intensity / g
	var wind_tuning: StormTuning = null  # disturbance package: height_factor; null = calm
	var gravity_shift: Vector2 = Vector2.ZERO  # disturbance package: g_local.xz / -g_local.y


## The verdict for one candidate.
class Result:
	extends RefCounted
	var slack: float = INF  # min(margin - required); stable iff > 0
	var piece_margin: float = INF
	var binding: int = BINDING_NONE  # BINDING_PIECE or the binding lower cut's body index
	var plane_y: float = 0.0  # where the piece comes to rest, disc-local
	var known: bool = false  # false when an unsnapshotted block was assumed under the piece, or no snapshot


## The requirement of one think: the profile's aim error, the stack tuning's tolerance and the probe tolerance.
static func requirement(
	profile: BotDifficultyProfile, view: BotWorldView, t: BotStackTuning, probe_contact_m: float
) -> Requirement:
	var req: Requirement = Requirement.new()
	req.aim_m = profile.aim_noise_m * t.aim_margin_share
	req.tolerance_m = t.numeric_tolerance_m
	req.probe_contact_m = probe_contact_m
	req.face_half_m = (view.cube_size - SHIPPED_PHYSICS_TUNING.cube_margin) * _HALF
	if view.gifts_enabled:
		req.gift_m = t.gift_disturbance_m
	var g: float = view.gravity_local.length()
	if view.wind_tuning != null and view.weather_intensity > 0.0 and g > 0.0:
		req.wind_tuning = view.wind_tuning
		req.wind_accel_ratio = view.wind_tuning.max_accel * clampf(view.weather_intensity, 0.0, 1.0) / g
	# DECISION: a disc tilted past horizontal (g_local.y >= 0) has no static shift; the bot never places there.
	if view.gravity_local.y < 0.0:
		req.gravity_shift = Vector2(view.gravity_local.x, view.gravity_local.z) / -view.gravity_local.y
	return req


## Margin the piece's own cut needs (the aim error is already in the erosion of its patches).
static func required_piece(req: Requirement, lever_m: float, top_y: float) -> float:
	return req.tolerance_m + req.gift_m + _wind_m(req, lever_m, top_y)


## Margin a lower cut needs: the aim error moves the combined centre of mass by only piece_mass / carried_mass of it.
static func required_lower(
	req: Requirement, carried_mass: float, piece_mass: float, lever_m: float, top_y: float
) -> float:
	var share: float = piece_mass / carried_mass if carried_mass > 0.0 else 1.0
	return req.tolerance_m + req.aim_m * share + req.gift_m + _wind_m(req, lever_m, top_y)


## Storm allowance of a cut: its combined centre of mass acts lever * a/g downwind; the gust factor is taken at its
## peak of 1 and the height response at the cut's highest point (an upper bound); direction-free (covers the veer).
## Breeze gusts stay in breeze_tip (DECISION).
static func _wind_m(req: Requirement, lever_m: float, top_y: float) -> float:
	if req.wind_tuning == null:
		return 0.0
	return req.wind_accel_ratio * WindField.height_factor(top_y, req.wind_tuning) * maxf(lever_m, 0.0)


## Judges candidate `c` (orientation `info`) against the view's stack snapshot (probe-only fallback without one).
## `c` must carry its probes (probe_points, cell_support, support_bodies, support_height).
static func evaluate(
	c: BotCandidate, info: BotStatics.OrientationInfo, view: BotWorldView, req: Requirement
) -> Result:
	var result: Result = Result.new()
	var cube: float = view.cube_size
	var bottom: PackedVector2Array = PackedVector2Array()
	for offset: Vector2 in info.contact:
		bottom.append(c.origin + offset * cube)
	var lever: float = info.com_height * cube
	var com_xz: Vector2 = c.origin + info.com * cube
	var stack: BotStack = view.stack
	var snapshot: bool = stack != null and stack.is_analysed()
	var points: PackedVector2Array = PackedVector2Array()
	var pc: BotStack.PieceCut = null
	if snapshot:
		pc = _snapshot_patches(c, bottom, stack, req, result)
		points = pc.points
		result.plane_y = pc.plane_y
		if not pc.flat:
			result.piece_margin = -INF
			result.slack = -INF
			result.binding = BINDING_PIECE
			return result
	else:
		result.plane_y = c.support_height
		points = _probe_patches(c, bottom, req)
	result.piece_margin = BotGeom2D.signed_inside_hull(BotGeom2D.hull(points), com_xz + req.gravity_shift * lever)
	result.binding = BINDING_PIECE
	result.slack = result.piece_margin - required_piece(req, lever, result.plane_y + info.height * cube)
	if not snapshot:
		return result
	var piece_mass: float = SHIPPED_PHYSICS_TUNING.cube_mass * float(info.cubes.size())
	var piece_com: Vector3 = Vector3(com_xz.x, result.plane_y + lever, com_xz.y)
	var rows: PackedFloat32Array = stack.lower_cuts(pc, piece_com, piece_mass, req.gravity_shift)
	var i: int = 0
	while i < rows.size():
		var slack: float = rows[i + _ROW_MARGIN] - required_lower(
			req, rows[i + _ROW_CARRIED], piece_mass, rows[i + _ROW_LEVER], rows[i + _ROW_TOP]
		)
		if slack < result.slack:
			result.slack = slack
			result.binding = int(rows[i + _ROW_BODY])
		i += BotStack.LOWER_ROW
	return result


## The piece's patches from the snapshot (BotStack.piece_cut) plus an assumed patch under every cube whose probe hit
## a block that is not in the snapshot; sets result.known.
static func _snapshot_patches(
	c: BotCandidate, bottom: PackedVector2Array, stack: BotStack, req: Requirement, result: Result
) -> BotStack.PieceCut:
	var disc_ok: PackedByteArray = PackedByteArray()
	var probe_of: PackedInt32Array = _probe_index(c, bottom)
	for j: int in bottom.size():
		var p: int = probe_of[j]
		disc_ok.append(1 if p < 0 or (c.support_bodies[p] < 0 and c.cell_support[p] != _NO_SUPPORT) else 0)
	var pc: BotStack.PieceCut = stack.piece_cut(bottom, req.face_half_m, c.support_height, req.aim_m, disc_ok)
	result.known = true
	for j: int in bottom.size():
		var p: int = probe_of[j]
		if p < 0 or c.support_bodies[p] < 0 or stack.index_of(c.support_bodies[p]) >= 0:
			continue
		if absf(c.cell_support[p] - pc.plane_y) > req.probe_contact_m:
			continue
		# DECISION: an unknown block is assumed to cover the probed square (as BotStatics does), shrunk by the aim error.
		result.known = false
		for corner: Vector2 in _shrunk_square(bottom[j], req.face_half_m, req.aim_m):
			pc.points.append(corner)
			pc.owners.append(_OWNER_UNKNOWN)
	return pc


## Probe-only fallback (no snapshot): every bottom cube that is not probed as a hole or below the resting plane
## counts as supported, on the disc with its full square, on a block shrunk by the aim error.
static func _probe_patches(c: BotCandidate, bottom: PackedVector2Array, req: Requirement) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	var on_disc: bool = absf(c.support_height - _GROUND_Y) <= req.probe_contact_m
	var probe_of: PackedInt32Array = _probe_index(c, bottom)
	for j: int in bottom.size():
		var p: int = probe_of[j]
		if p >= 0 and (
			c.cell_support[p] == _NO_SUPPORT or absf(c.cell_support[p] - c.support_height) > req.probe_contact_m
		):
			continue
		var shrink: float = 0.0 if on_disc else req.aim_m
		points.append_array(_shrunk_square(bottom[j], req.face_half_m, shrink))
	return points


## Per bottom square: index of the probe measured under it (BotStatics.MATCH_EPSILON_M), -1 when it was not probed.
static func _probe_index(c: BotCandidate, bottom: PackedVector2Array) -> PackedInt32Array:
	var probed: int = mini(c.probe_points.size(), mini(c.cell_support.size(), c.support_bodies.size()))
	var out: PackedInt32Array = PackedInt32Array()
	for point: Vector2 in bottom:
		var found: int = -1
		for i: int in probed:
			if c.probe_points[i].distance_to(point) <= BotStatics.MATCH_EPSILON_M:
				found = i
				break
		out.append(found)
	return out


## The axis-aligned square around `centre` with half-width `half` shrunk by `shrink`; empty when nothing is left.
static func _shrunk_square(centre: Vector2, half: float, shrink: float) -> PackedVector2Array:
	var h: float = half - shrink
	if h <= 0.0:
		return PackedVector2Array()
	return BotGeom2D.square(centre, Vector2(h, 0.0), Vector2(0.0, h))
