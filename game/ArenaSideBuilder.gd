class_name ArenaSideBuilder
extends RefCounted
## Generates the static side and underside geometry of the arena's alternative
## looks (Bontago-mp0.150.2; see config/ArenaSideStyle.gd). Pure geometry, no
## scene tree: build() returns per-surface mesh arrays that game/ArenaMesh.gd
## appends to the one arena ArrayMesh.
##
## Every look hangs from the ring at the bottom edge of the territory slab
## (y = y_top) and follows the map's outline: the analytic circle. Shading is
## flat per triangle (cel look) with the colour carried per vertex; faces are
## wound from an explicit outward hint, so normals always point away from the
## solid. Triangles are routed to three surfaces: BAND (side), BOTTOM
## (facing down) and GLOW (emissive parts).

## Surface kinds this builder fills (values match ArenaMesh.Kind).
const KIND_BAND: int = 2
const KIND_BOTTOM: int = 3
const KIND_GLOW: int = 4

## A face whose outward direction points down by more than this is "underside".
const UNDERSIDE_NORMAL_Y: float = -0.5
## Triangles smaller than this (squared cross-product length) are dropped.
const AREA_MIN: float = 0.0000001
## Points closer than this count as the same point when finding steps.
const POINT_EPS: float = 0.0001
## Minimum segments for a degenerate/test MapDef.
const MIN_SEGMENTS: int = 3
## Outline segments per machined panel: face, face, face, recessed seam.
const PANEL_SEGMENTS: int = 4
## Segments of one machined rib (crest) / valley run.
const RIB_SEGMENTS: int = 2
## Rings of the machined cone underside (excluding the shoulder).
const MACHINED_CONE_RINGS: int = 3
## Shoulder inset of the machined underside as a fraction of the radius.
const MACHINED_SHOULDER_SCALE: float = 0.96
## Corners of a crystal's base ring.
const CRYSTAL_SIDES: int = 4
## Crystals sit between these fractions of the rock depth.
const CRYSTAL_T_MIN: float = 0.35
const CRYSTAL_T_SPAN: float = 0.4
## Crystal base is lifted this fraction of its length into the rock.
const CRYSTAL_EMBED: float = 0.15
## How much darker the underside of a plate ledge is than its plate.
const LEDGE_DARKEN: float = 0.25
const HALF: float = 0.5
## Vertices per triangle.
const TRI_VERTS: int = 3
const DIAMETER_FACTOR: float = 2.0
## Every second stratum / rib run uses the alternate colour / height.
const ALTERNATE: int = 2


## One closed loop of per-segment edge points: segment i spans starts[i]..ends[i].
## Continuous rings have ends[i] == starts[i + 1]; stepped rings do not.
class Ring:
	extends RefCounted
	var starts: PackedVector3Array = PackedVector3Array()
	var ends: PackedVector3Array = PackedVector3Array()


## Triangle soup with a flat normal and a colour per vertex.
class Soup:
	extends RefCounted
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()

	func add_tri(p0: Vector3, p1: Vector3, p2: Vector3, front: Vector3, color: Color) -> void:
		var facing: Vector3 = (p1 - p0).cross(p2 - p0)
		if facing.length_squared() <= ArenaSideBuilder.AREA_MIN:
			return
		var normal: Vector3 = facing.normalized()
		# Godot's front face is clockwise: the right-hand cross of a front-facing
		# triangle points away from `front`, so reorder when it points along it.
		if facing.dot(front) > 0.0:
			verts.append_array(PackedVector3Array([p0, p2, p1]))
		else:
			verts.append_array(PackedVector3Array([p0, p1, p2]))
			normal = -normal
		for _i: int in range(ArenaSideBuilder.TRI_VERTS):
			normals.append(normal)
			colors.append(color)

	func is_empty() -> bool:
		return verts.is_empty()

	func arrays() -> Array:
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colors
		return out


var _outline: PackedVector2Array = PackedVector2Array()
var _radius: float = 0.0
var _body_side: Soup = null
var _body_under: Soup = null
var _glow: Soup = null


## Per-surface arrays for `style` hanging from y = `y_top`: kind -> mesh arrays
## (only non-empty surfaces). `segments` is the outline resolution of the
## layered look; empty result for CURRENT.
func build(map_def: MapDef, style: ArenaSideStyle, segments: int, y_top: float) -> Dictionary:
	_body_side = Soup.new()
	_body_under = Soup.new()
	_glow = Soup.new()
	_radius = map_def.field_radius
	match style.style:
		ArenaSideStyle.Style.LAYERED_PLATES:
			_outline = outline_points(map_def, maxi(segments, MIN_SEGMENTS))
			_build_layered(style, y_top)
		ArenaSideStyle.Style.ROCKY_ISLAND:
			_outline = outline_points(map_def, maxi(style.rock_segments, MIN_SEGMENTS))
			_build_rock(style, y_top)
		ArenaSideStyle.Style.MACHINED_DISC:
			_outline = outline_points(map_def, maxi(style.machined_panel_count, 1) * PANEL_SEGMENTS)
			_build_machined(style, y_top)
	var out: Dictionary = {}
	if not _body_side.is_empty():
		out[KIND_BAND] = _body_side.arrays()
	if not _body_under.is_empty():
		out[KIND_BOTTOM] = _body_under.arrays()
	if not _glow.is_empty():
		out[KIND_GLOW] = _glow.arrays()
	return out


## Disk-local (x, z) outline of `map_def`, evenly spaced by angle. The
## round disc is the analytic circle.
static func outline_points(map_def: MapDef, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(segments)
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var radius: float = map_def.field_radius
		points[i] = Vector2(direction.x * radius, direction.y * radius)
	return points


# --- Ring helpers ---------------------------------------------------------------

## A ring at height `y`: each outline point scaled by `scale`, then pushed
## `off` (+ per-segment `off_seg`, + per-vertex `jitter`) metres along its radial
## direction; `dy_seg` adds a per-segment height. A point pushed through the axis
## collapses to the axis.
func _make_ring(
	scale: float,
	y: float,
	off: float = 0.0,
	off_seg: PackedFloat32Array = PackedFloat32Array(),
	dy_seg: PackedFloat32Array = PackedFloat32Array(),
	jitter: PackedFloat32Array = PackedFloat32Array()
) -> Ring:
	var ring: Ring = Ring.new()
	var count: int = _outline.size()
	for i: int in range(count):
		var seg_off: float = off + (off_seg[i] if not off_seg.is_empty() else 0.0)
		var seg_y: float = y + (dy_seg[i] if not dy_seg.is_empty() else 0.0)
		ring.starts.append(_ring_point(i, scale, seg_off, jitter, seg_y))
		ring.ends.append(_ring_point(i + 1, scale, seg_off, jitter, seg_y))
	return ring


func _ring_point(
	index: int, scale: float, off: float, jitter: PackedFloat32Array, y: float
) -> Vector3:
	var wrapped: int = index % _outline.size()
	var base: Vector2 = _outline[wrapped]
	var push: float = off + (jitter[wrapped] if not jitter.is_empty() else 0.0)
	var direction: Vector2 = base.normalized()
	var point: Vector2 = base * scale + direction * push
	if scale <= 0.0 or point.dot(direction) < 0.0:
		point = Vector2.ZERO
	return Vector3(point.x, y, point.y)


## Quads between two rings, wound so the front faces the outward profile normal
## (derived from how the profile moves in radius and height going from `a` to `b`).
func _sweep(
	a: Ring, b: Ring, color: Color, glow: bool = false, colors: PackedColorArray = PackedColorArray()
) -> void:
	for i: int in range(a.starts.size()):
		var p0: Vector3 = a.starts[i]
		var p1: Vector3 = a.ends[i]
		var p2: Vector3 = b.ends[i]
		var p3: Vector3 = b.starts[i]
		var tint: Color = color if colors.is_empty() else colors[i]
		_add_quad(p0, p1, p2, p3, _profile_front(p0, p1, p2, p3), tint, glow)


func _profile_front(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Vector3:
	var mid_a: Vector3 = (p0 + p1) * HALF
	var mid_b: Vector3 = (p2 + p3) * HALF
	var radial: Vector3 = Vector3((mid_a.x + mid_b.x) * HALF, 0.0, (mid_a.z + mid_b.z) * HALF)
	if radial.length_squared() <= AREA_MIN:
		radial = Vector3(mid_a.x, 0.0, mid_a.z)
	radial = radial.normalized()
	var radius_a: float = Vector2(mid_a.x, mid_a.z).length()
	var radius_b: float = Vector2(mid_b.x, mid_b.z).length()
	return radial * (mid_a.y - mid_b.y) + Vector3.UP * (radius_b - radius_a)


## Steps where neighbouring segments of ring `a` or `b` do not meet: the exposed
## wall of the protruding segment, spanning from ring `a` down to ring `b`.
func _risers(a: Ring, b: Ring, color: Color) -> void:
	var count: int = a.starts.size()
	for i: int in range(count):
		var prev: int = (i + count - 1) % count
		var stepped: Ring = a
		if a.ends[prev].distance_to(a.starts[i]) <= POINT_EPS:
			stepped = b
			if b.ends[prev].distance_to(b.starts[i]) <= POINT_EPS:
				continue
		var end_prev: Vector3 = stepped.ends[prev]
		var start_next: Vector3 = stepped.starts[i]
		var radius_diff: float = Vector2(start_next.x, start_next.z).length() - Vector2(end_prev.x, end_prev.z).length()
		var toward_next: bool = radius_diff < 0.0 if absf(radius_diff) > POINT_EPS else start_next.y > end_prev.y
		var tangent: Vector2 = _outline[(i + 1) % count] - _outline[prev]
		var front: Vector3 = Vector3(tangent.x, 0.0, tangent.y).normalized()
		if not toward_next:
			front = -front
		_add_quad(a.ends[prev], a.starts[i], b.starts[i], b.ends[prev], front, color, false)


func _add_quad(
	p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, front: Vector3, color: Color, glow: bool
) -> void:
	var soup: Soup = _glow
	if not glow:
		soup = _body_under if front.normalized().y < UNDERSIDE_NORMAL_Y else _body_side
	soup.add_tri(p0, p1, p2, front, color)
	soup.add_tri(p0, p2, p3, front, color)


# --- LAYERED_PLATES -------------------------------------------------------------

func _build_layered(style: ArenaSideStyle, y_top: float) -> void:
	var depth: float = DIAMETER_FACTOR * _radius * style.layered_depth_fraction
	var plates: int = maxi(style.layered_plate_count, 1)
	var plate_depth: float = depth * style.layered_plate_share / float(plates)
	var step: float = _radius * style.layered_inset_fraction
	var y: float = y_top
	var off: float = 0.0
	var bottom: Ring = null
	for j: int in range(plates):
		var color: Color = _cycle_color(style.layered_plate_colors, j)
		var top_ring: Ring = _make_ring(1.0, y, off)
		bottom = _make_ring(1.0, y - plate_depth, off)
		_sweep(top_ring, bottom, color)
		y -= plate_depth
		if j < plates - 1:
			off -= step
			_sweep(bottom, _make_ring(1.0, y, off), color.darkened(LEDGE_DARKEN))
			bottom = _make_ring(1.0, y, off)
	var taper_depth: float = depth * (1.0 - style.layered_plate_share)
	var core_height: float = taper_depth * style.layered_core_height_fraction
	var keel_scale: float = style.layered_keel_radius_fraction
	var keel: Ring = _make_ring(keel_scale, y - (taper_depth - core_height))
	_sweep(bottom, keel, style.layered_underside_color)
	_sweep(keel, _make_ring(0.0, y - taper_depth), style.layered_core_color, true)


func _cycle_color(colors: PackedColorArray, index: int) -> Color:
	if colors.is_empty():
		return Color.GRAY
	return colors[index % colors.size()]


# --- ROCKY_ISLAND ---------------------------------------------------------------

func _build_rock(style: ArenaSideStyle, y_top: float) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = style.rock_seed
	var depth: float = DIAMETER_FACTOR * _radius * style.rock_depth_fraction
	var strata: int = maxi(style.rock_strata_count, 1)
	var amplitude: float = _radius * style.rock_roughness_fraction
	var jitters: Array[PackedFloat32Array] = []
	var scales: PackedFloat32Array = PackedFloat32Array()
	for k: int in range(strata + 1):
		var t: float = float(k) / float(strata)
		var scale: float = 1.0 - pow(t, style.rock_taper_exponent)
		scales.append(scale)
		var jitter: PackedFloat32Array = PackedFloat32Array()
		for _i: int in range(_outline.size()):
			jitter.append(rng.randf_range(-amplitude, amplitude) * scale)
		jitters.append(jitter)
	# The first ring meets the slab edge exactly (no wobble).
	jitters[0] = PackedFloat32Array()
	var none: PackedFloat32Array = PackedFloat32Array()
	for k: int in range(strata):
		var y_a: float = y_top - depth * float(k) / float(strata)
		var y_b: float = y_top - depth * float(k + 1) / float(strata)
		var scale_mid: float = lerpf(scales[k], scales[k + 1], style.rock_wall_slope)
		var upper: Ring = _make_ring(scales[k], y_a, 0.0, none, none, jitters[k])
		var wall_end: Ring = _make_ring(scale_mid, y_b, 0.0, none, none, jitters[k])
		var next_top: Ring = _make_ring(scales[k + 1], y_b, 0.0, none, none, jitters[k + 1])
		var wall_color: Color = style.rock_wall_color if k % ALTERNATE == 0 else style.rock_alt_color
		_sweep(upper, wall_end, wall_color)
		_sweep(wall_end, next_top, style.rock_ledge_color)
	for _c: int in range(style.rock_crystal_count):
		_add_crystal(style, rng, y_top, depth)


func _add_crystal(style: ArenaSideStyle, rng: RandomNumberGenerator, y_top: float, depth: float) -> void:
	var index: int = rng.randi() % _outline.size()
	var t: float = CRYSTAL_T_MIN + rng.randf() * CRYSTAL_T_SPAN
	var scale: float = 1.0 - pow(t, style.rock_taper_exponent)
	var center: Vector2 = _outline[index] * scale
	var length: float = depth * style.rock_crystal_length_fraction
	var half_width: float = _radius * style.rock_crystal_size_fraction
	var y_base: float = y_top - depth * t + length * CRYSTAL_EMBED
	var tip: Vector3 = Vector3(center.x, y_base - length, center.y)
	var base: Array[Vector3] = []
	for s: int in range(CRYSTAL_SIDES):
		var angle: float = TAU * float(s) / float(CRYSTAL_SIDES)
		base.append(Vector3(center.x + cos(angle) * half_width, y_base, center.y + sin(angle) * half_width))
	for s: int in range(CRYSTAL_SIDES):
		var p0: Vector3 = base[s]
		var p1: Vector3 = base[(s + 1) % CRYSTAL_SIDES]
		var mid: Vector3 = (p0 + p1) * HALF
		var out: Vector3 = Vector3(mid.x - center.x, 0.0, mid.z - center.y)
		var front: Vector3 = out.normalized() * length + Vector3.DOWN * half_width
		_glow.add_tri(p0, p1, tip, front, style.rock_crystal_color)


# --- MACHINED_DISC --------------------------------------------------------------

func _build_machined(style: ArenaSideStyle, y_top: float) -> void:
	var depth: float = DIAMETER_FACTOR * _radius * style.machined_depth_fraction
	var seam: float = _radius * style.machined_seam_depth_fraction
	var recess: float = _radius * style.machined_strip_recess_fraction
	var count: int = _outline.size()
	var none: PackedFloat32Array = PackedFloat32Array()
	var seam_offsets: PackedFloat32Array = PackedFloat32Array()
	var seg_colors: PackedColorArray = PackedColorArray()
	for i: int in range(count):
		var is_seam: bool = i % PANEL_SEGMENTS == PANEL_SEGMENTS - 1
		seam_offsets.append(-seam if is_seam else 0.0)
		seg_colors.append(style.machined_seam_color if is_seam else style.machined_panel_color)
	var y_strip_top: float = y_top - depth * style.machined_strip_position
	var y_strip_bottom: float = y_strip_top - depth * style.machined_strip_height_fraction
	var y_side_bottom: float = y_top - depth * style.machined_side_share
	var side_top: Ring = _make_ring(1.0, y_top, 0.0, seam_offsets)
	var upper_bottom: Ring = _make_ring(1.0, y_strip_top, 0.0, seam_offsets)
	_sweep(side_top, upper_bottom, style.machined_panel_color, false, seg_colors)
	_risers(side_top, upper_bottom, style.machined_seam_color)
	var strip_top: Ring = _make_ring(1.0, y_strip_top, -recess)
	var strip_bottom: Ring = _make_ring(1.0, y_strip_bottom, -recess)
	_sweep(upper_bottom, strip_top, style.machined_panel_color)
	_sweep(strip_top, strip_bottom, style.machined_light_color, true)
	var lower_top: Ring = _make_ring(1.0, y_strip_bottom, 0.0, seam_offsets)
	var lower_bottom: Ring = _make_ring(1.0, y_side_bottom, 0.0, seam_offsets)
	_sweep(strip_bottom, lower_top, style.machined_panel_color)
	_sweep(lower_top, lower_bottom, style.machined_panel_color, false, seg_colors)
	_risers(lower_top, lower_bottom, style.machined_seam_color)
	# Ribbed underside: a shoulder, then a cone whose alternate runs hang lower.
	var cone_depth: float = depth * (1.0 - style.machined_side_share)
	var rib_height: float = depth * style.machined_rib_height_fraction
	var previous: Ring = _make_ring(MACHINED_SHOULDER_SCALE, y_side_bottom)
	_sweep(lower_bottom, previous, style.machined_underside_color)
	for k: int in range(1, MACHINED_CONE_RINGS + 1):
		var fraction: float = float(k) / float(MACHINED_CONE_RINGS)
		var ring_scale: float = lerpf(MACHINED_SHOULDER_SCALE, style.machined_emitter_radius_fraction, fraction)
		var last: bool = k == MACHINED_CONE_RINGS
		var drops: PackedFloat32Array = PackedFloat32Array()
		for i: int in range(count):
			var crest: bool = (i / RIB_SEGMENTS) % ALTERNATE == 0
			drops.append(-rib_height * ring_scale if crest and not last else 0.0)
		var ring: Ring = _make_ring(ring_scale, y_side_bottom - cone_depth * fraction, 0.0, none, drops)
		_sweep(previous, ring, style.machined_underside_color)
		_risers(previous, ring, style.machined_underside_color)
		previous = ring
	var center: Ring = _make_ring(0.0, previous.starts[0].y)
	_sweep(previous, center, style.machined_light_color, true)
