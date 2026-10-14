class_name ArenaSideBuilder
extends RefCounted
## Generates the static side and underside geometry of the arena's alternative
## looks (Bontago-mp0.150.2; see config/territory/ArenaSideStyle.gd). Pure geometry, no
## scene tree: build() returns per-surface mesh arrays that game/field/ArenaMesh.gd
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
## Round 2 machined refinements (config/territory/ArenaSideStyle.gd).
const MIN_PANEL_SEGMENTS: int = 2
const DIAMETER_FACTOR_INT: int = 2
## Where the stylised underside's middle ring sits, as a share of the underside depth.
const UNDER_MID_DEPTH: float = 0.55
## Depth of the glowing core cone below the last detailed terrace, share of underside depth.
const CORE_DEPTH_SHARE: float = 0.12
## Vent slot rectangle inside its terrace cell (u along the segment, v across the terrace).
const VENT_U0: float = 0.3
const VENT_U1: float = 0.7
const VENT_V0: float = 0.2
const VENT_V1: float = 0.8
## Vent slots sit this share of the underside depth below the terrace so they read as recesses.
const VENT_DROP_SHARE: float = 0.004
## Thruster cone: hexagon base, centre of mass along its length.
const CONE_SIDES: int = 6
const CONE_INSIDE: float = 0.3
## Rivet pyramid base below / above the centre, in rivet half-widths.
const RIVET_LOW: float = 0.6
const RIVET_HIGH: float = 1.2
## Round 3 (sides that continue the top): outline segments per plate (a flat face
## then a narrow seam), the fewest plates around the rim, and the shortest plate.
const PLATE_SEGMENTS: int = 2
const PLATE_COUNT_MIN: int = 3
const PLATE_LENGTH_MIN: float = 0.1
## Narrowest ring of plates, in metres.
const RING_WIDTH_MIN: float = 0.1
## The slope of a tapered stratum never shrinks below this share of the radius.
const STRATUM_SPAN_MIN: float = 0.05


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
	## SHADER_DOME: when `shell` is set every vertex also carries UV.x = the radius
	## the top's plating pattern is read at (shaders/territory/arena_side_shell.gdshader):
	## a wall continues the top's rings outwards (radius + metres below `edge_y`),
	## an underside face reads its own radius.
	var shell: bool = false
	var edge_y: float = 0.0
	var uvs: PackedVector2Array = PackedVector2Array()

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
		if shell:
			for k: int in range(verts.size() - ArenaSideBuilder.TRI_VERTS, verts.size()):
				var v: Vector3 = verts[k]
				var radial: float = Vector2(v.x, v.z).length()
				if normal.y > ArenaSideBuilder.UNDERSIDE_NORMAL_Y:
					radial += edge_y - v.y
				uvs.append(Vector2(radial, 0.0))

	func is_empty() -> bool:
		return verts.is_empty()

	func arrays() -> Array:
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = verts
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_COLOR] = colors
		if shell:
			out[Mesh.ARRAY_TEX_UV] = uvs
		return out


var _outline: PackedVector2Array = PackedVector2Array()
var _radius: float = 0.0
var _body_side: Soup = null
var _body_under: Soup = null
var _glow: Soup = null
## Round 3: the slab's height (the gold lip wraps over its edge) and the plain
## evenly spaced circle the lip and its ledge are drawn on.
var _disk_height: float = 0.0
var _uniform: PackedVector2Array = PackedVector2Array()


## Per-surface arrays for `style` hanging from y = `y_top`: kind -> mesh arrays
## (only non-empty surfaces). `segments` is the outline resolution of the
## layered look; empty result for CURRENT.
func build(map_def: MapDef, style: ArenaSideStyle, segments: int, y_top: float) -> Dictionary:
	_body_side = Soup.new()
	_body_under = Soup.new()
	_glow = Soup.new()
	_radius = map_def.field_radius
	_disk_height = map_def.disk_height
	_uniform = outline_points(map_def, maxi(segments, MIN_SEGMENTS))
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
		ArenaSideStyle.Style.MACHINED_STYLISED:
			_outline = outline_points(map_def, maxi(style.stylised_panel_count, 1) * maxi(style.stylised_panel_segments, MIN_PANEL_SEGMENTS))
			_build_stylised(style, y_top)
		ArenaSideStyle.Style.MACHINED_DETAILED:
			_outline = outline_points(map_def, maxi(style.detailed_panel_count, 1) * maxi(style.detailed_panel_segments, MIN_PANEL_SEGMENTS))
			_build_detailed(style, y_top)
		ArenaSideStyle.Style.MACHINED_HEAVY:
			_outline = outline_points(map_def, maxi(style.heavy_panel_count, 1) * maxi(style.heavy_panel_segments, MIN_PANEL_SEGMENTS))
			_build_heavy(style, y_top)
		ArenaSideStyle.Style.MONOLITH:
			_build_monolith(style, y_top)
		ArenaSideStyle.Style.TAPERED_STRATA:
			_build_tapered(style, y_top)
		ArenaSideStyle.Style.PLATED_DOME:
			_build_dome(style, y_top)
		ArenaSideStyle.Style.SHADER_DOME:
			_build_shader_dome(style, y_top)
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


# --- Machined refinements (round 2): shared helpers ------------------------------

## Flush wall between two heights; `off_a` / `off_b` (metres, negative = inset)
## are the radial pushes at its top and bottom.
func _wall(y_a: float, y_b: float, off_a: float, off_b: float, color: Color, glow: bool = false) -> void:
	_sweep(_make_ring(1.0, y_a, off_a), _make_ring(1.0, y_b, off_b), color, glow)


## A wall of flat panels split by crisp recessed seams (the last outline segment
## of every `segs`), closed top and bottom by dark ledges so no gap shows.
func _seamed_wall(
	y_a: float, y_b: float, off: float, color: Color, seam_color: Color, seam_depth: float, segs: int
) -> void:
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	for i: int in range(_outline.size()):
		var is_seam: bool = i % segs == segs - 1
		offsets.append(-seam_depth if is_seam else 0.0)
		colors.append(seam_color if is_seam else color)
	var top: Ring = _make_ring(1.0, y_a, off, offsets)
	var bottom: Ring = _make_ring(1.0, y_b, off, offsets)
	_sweep(top, bottom, color, false, colors)
	_risers(top, bottom, seam_color)
	_sweep(_make_ring(1.0, y_a, off), top, seam_color)
	_sweep(bottom, _make_ring(1.0, y_b, off), seam_color)


## Triangle of a convex solid: the front faces away from the interior point `inside`.
func _solid_tri(soup: Soup, p0: Vector3, p1: Vector3, p2: Vector3, inside: Vector3, color: Color) -> void:
	soup.add_tri(p0, p1, p2, (p0 + p1 + p2) / float(TRI_VERTS) - inside, color)


## Colour per outline segment, alternating by whole panels.
func _wedge_colors(segs: int, color: Color, alt: Color) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	for i: int in range(_outline.size()):
		out.append(color if (i / segs) % ALTERNATE == 0 else alt)
	return out


## Glowing cone hanging below a flat hexagon of `radius` centred on `center`.
func _glow_cone(center: Vector3, radius: float, length: float, color: Color) -> void:
	var tip: Vector3 = center + Vector3.DOWN * length
	var inside: Vector3 = center + Vector3.DOWN * length * CONE_INSIDE
	for s: int in range(CONE_SIDES):
		var a0: float = TAU * float(s) / float(CONE_SIDES)
		var a1: float = TAU * float(s + 1) / float(CONE_SIDES)
		var p0: Vector3 = center + Vector3(cos(a0), 0.0, sin(a0)) * radius
		var p1: Vector3 = center + Vector3(cos(a1), 0.0, sin(a1)) * radius
		_solid_tri(_glow, p0, p1, tip, inside, color)


## Small three-sided pyramid standing out of the wall at `center`, pointing along `normal`.
func _rivet(center: Vector3, normal: Vector3, half: float, height: float, color: Color) -> void:
	var tangent: Vector3 = Vector3.UP.cross(normal).normalized()
	var b0: Vector3 = center - tangent * half - Vector3.UP * half * RIVET_LOW
	var b1: Vector3 = center + tangent * half - Vector3.UP * half * RIVET_LOW
	var b2: Vector3 = center + Vector3.UP * half * RIVET_HIGH
	var tip: Vector3 = center + normal * height
	var inside: Vector3 = (b0 + b1 + b2) / float(TRI_VERTS) + normal * height * HALF * HALF
	_solid_tri(_body_side, b0, b1, tip, inside, color)
	_solid_tri(_body_side, b1, b2, tip, inside, color)
	_solid_tri(_body_side, b2, b0, tip, inside, color)


## Rivets at the first and last flat face of every panel on one row of height `y`.
func _rivet_row(y: float, segs: int, half: float, height: float, color: Color) -> void:
	var count: int = _outline.size()
	for panel: int in range(count / segs):
		for face: int in [0, segs - 2]:
			var i: int = panel * segs + face
			var a: Vector3 = _ring_point(i, 1.0, 0.0, PackedFloat32Array(), y)
			var b: Vector3 = _ring_point(i + 1, 1.0, 0.0, PackedFloat32Array(), y)
			var mid: Vector3 = (a + b) * HALF
			_rivet(mid, Vector3(mid.x, 0.0, mid.z).normalized(), half, height, color)


# --- MACHINED_STYLISED (M1) -------------------------------------------------------

func _build_stylised(style: ArenaSideStyle, y_top: float) -> void:
	var depth: float = DIAMETER_FACTOR * _radius * style.stylised_depth_fraction
	var seam: float = _radius * style.stylised_seam_depth_fraction
	var segs: int = maxi(style.stylised_panel_segments, MIN_PANEL_SEGMENTS)
	var y: float = y_top
	var rest: float = 1.0 - style.stylised_trim_share - style.stylised_upper_share - style.stylised_stripe_share - style.stylised_lower_trim_share
	var h: float = depth * style.stylised_trim_share
	_wall(y, y - h, 0.0, 0.0, style.stylised_gold_color, true)
	y -= h
	h = depth * style.stylised_upper_share
	_seamed_wall(y, y - h, 0.0, style.stylised_upper_color, style.stylised_seam_color, seam, segs)
	y -= h
	h = depth * style.stylised_stripe_share
	_wall(y, y - h, 0.0, 0.0, style.stylised_stripe_color)
	y -= h
	h = depth * maxf(rest, 0.0)
	_seamed_wall(y, y - h, 0.0, style.stylised_lower_color, style.stylised_seam_color, seam, segs)
	y -= h
	h = depth * style.stylised_lower_trim_share
	_wall(y, y - h, 0.0, 0.0, style.stylised_gold_color, true)
	y -= h
	# Underside: two cone steps in alternating wedge colours, then a glowing core.
	var under: float = depth * style.stylised_underside_ratio
	var wedge: PackedColorArray = _wedge_colors(segs, style.stylised_underside_color, style.stylised_underside_alt_color)
	var previous: Ring = _make_ring(1.0, y)
	var mid: Ring = _make_ring(lerpf(1.0, style.stylised_keel_scale, HALF), y - under * UNDER_MID_DEPTH)
	_sweep(previous, mid, style.stylised_underside_color, false, wedge)
	var keel: Ring = _make_ring(style.stylised_keel_scale, y - under)
	_sweep(mid, keel, style.stylised_underside_color, false, wedge)
	var core_depth: float = under * style.stylised_core_height_fraction
	_sweep(keel, _make_ring(0.0, y - under - core_depth), style.stylised_core_color, true)


# --- MACHINED_DETAILED (M2) -------------------------------------------------------

func _build_detailed(style: ArenaSideStyle, y_top: float) -> void:
	var depth: float = DIAMETER_FACTOR * _radius * style.detailed_depth_fraction
	var seam: float = _radius * style.detailed_seam_depth_fraction
	var recess: float = _radius * style.detailed_strip_recess_fraction
	var segs: int = maxi(style.detailed_panel_segments, MIN_PANEL_SEGMENTS)
	var rest: float = 1.0 - style.detailed_trim_share - style.detailed_upper_share - style.detailed_strip_share - style.detailed_lip_share
	var y: float = y_top
	var h: float = depth * style.detailed_trim_share
	_wall(y, y - h, 0.0, 0.0, style.detailed_gold_color, true)
	y -= h
	h = depth * style.detailed_upper_share
	_seamed_wall(y, y - h, 0.0, style.detailed_panel_color, style.detailed_seam_color, seam, segs)
	var rivet_half: float = _radius * style.detailed_rivet_size_fraction
	var rivet_height: float = _radius * style.detailed_rivet_height_fraction
	_rivet_row(y - h * HALF, segs, rivet_half, rivet_height, style.detailed_rivet_color)
	y -= h
	# Recessed warm light strip between two bevels.
	h = depth * style.detailed_strip_share
	var strip_top: Ring = _make_ring(1.0, y, -recess)
	var strip_bottom: Ring = _make_ring(1.0, y - h, -recess)
	_sweep(_make_ring(1.0, y), strip_top, style.detailed_seam_color)
	_sweep(strip_top, strip_bottom, style.detailed_strip_color, true)
	_sweep(strip_bottom, _make_ring(1.0, y - h), style.detailed_seam_color)
	y -= h
	h = depth * maxf(rest, 0.0)
	_seamed_wall(y, y - h, 0.0, style.detailed_lower_color, style.detailed_seam_color, seam, segs)
	_rivet_row(y - h * HALF, segs, rivet_half, rivet_height, style.detailed_rivet_color)
	y -= h
	h = depth * style.detailed_lip_share
	_wall(y, y - h, 0.0, 0.0, style.detailed_lip_color)
	y -= h
	_build_detailed_underside(style, y, depth, segs)


## Concentric stepped terraces (annulus then dark groove riser), dark vent slots
## on one terrace, glowing thruster cones on another, glowing core in the middle.
func _build_detailed_underside(style: ArenaSideStyle, y_edge: float, depth: float, segs: int) -> void:
	var under: float = depth * style.detailed_underside_ratio
	var rings: int = maxi(style.detailed_ring_count, 1)
	var groove: float = under * style.detailed_groove_share
	var slope: float = under / float(rings) - groove
	var previous: Ring = _make_ring(1.0, y_edge)
	var y: float = y_edge
	var wedge: PackedColorArray = _wedge_colors(segs, style.detailed_underside_color, style.detailed_underside_alt_color)
	var annuli: Array[Ring] = []
	var annulus_tops: Array[Ring] = []
	for k: int in range(1, rings + 1):
		var scale: float = lerpf(1.0, style.detailed_keel_scale, float(k) / float(rings))
		var top: Ring = _make_ring(scale, y - slope)
		_sweep(previous, top, style.detailed_underside_color, false, wedge)
		annuli.append(previous)
		annulus_tops.append(top)
		y -= slope + groove
		var bottom: Ring = _make_ring(scale, y)
		_sweep(top, bottom, style.detailed_groove_color)
		previous = bottom
	var ring_index: int = clampi(style.detailed_vent_ring, 1, rings) - 1
	_vents(style, annuli[ring_index], annulus_tops[ring_index], under)
	ring_index = clampi(style.detailed_thruster_ring, 1, rings) - 1
	_thrusters(style, annuli[ring_index], annulus_tops[ring_index], under)
	var core: float = under * CORE_DEPTH_SHARE
	_sweep(previous, _make_ring(0.0, y - core), style.detailed_core_color, true)


## Dark rectangles, set slightly below one terrace, evenly spaced around it.
func _vents(style: ArenaSideStyle, outer: Ring, inner: Ring, under: float) -> void:
	var count: int = _outline.size()
	var lift: Vector3 = Vector3.DOWN * under * VENT_DROP_SHARE
	for v: int in range(style.detailed_vent_count):
		var i: int = (v * count / maxi(style.detailed_vent_count, 1)) % count
		var corners: Array[Vector3] = []
		for pair: Vector2 in [Vector2(VENT_U0, VENT_V0), Vector2(VENT_U1, VENT_V0), Vector2(VENT_U1, VENT_V1), Vector2(VENT_U0, VENT_V1)]:
			var edge_o: Vector3 = outer.starts[i].lerp(outer.ends[i], pair.x)
			var edge_i: Vector3 = inner.starts[i].lerp(inner.ends[i], pair.x)
			corners.append(edge_o.lerp(edge_i, pair.y) + lift)
		_add_quad(corners[0], corners[1], corners[2], corners.back(), Vector3.DOWN, style.detailed_vent_color, false)


## Glowing nozzles hanging from the middle of one terrace.
func _thrusters(style: ArenaSideStyle, outer: Ring, inner: Ring, under: float) -> void:
	var count: int = _outline.size()
	for t: int in range(style.detailed_thruster_count):
		var i: int = (t * count + count / DIAMETER_FACTOR_INT) / maxi(style.detailed_thruster_count, 1) % count
		var centre: Vector3 = (outer.starts[i] + outer.ends[i] + inner.starts[i] + inner.ends[i]) * HALF * HALF
		_glow_cone(centre, _radius * style.detailed_thruster_size_fraction, under * style.detailed_thruster_length_share, style.detailed_thruster_color)


# --- MACHINED_HEAVY (M3) ----------------------------------------------------------

func _build_heavy(style: ArenaSideStyle, y_top: float) -> void:
	var depth: float = DIAMETER_FACTOR * _radius * style.heavy_depth_fraction
	var seam: float = _radius * style.heavy_seam_depth_fraction
	var segs: int = maxi(style.heavy_panel_segments, MIN_PANEL_SEGMENTS)
	var steps: int = maxi(style.heavy_step_count, 1)
	var y: float = y_top
	var h: float = depth * style.heavy_trim_share
	_wall(y, y - h, 0.0, 0.0, style.heavy_gold_color, true)
	y -= h
	h = depth * style.heavy_rim_share
	_seamed_wall(y, y - h, 0.0, style.heavy_rim_color, style.heavy_seam_color, seam, segs)
	y -= h
	var off: float = -_radius * style.heavy_bevel_inset_fraction
	h = depth * style.heavy_bevel_share
	_wall(y, y - h, 0.0, off, style.heavy_bevel_color)
	y -= h
	var terrace_share: float = 1.0 - style.heavy_trim_share - style.heavy_rim_share - style.heavy_bevel_share
	var trim: float = depth * style.heavy_step_trim_share
	var wall_h: float = maxf(depth * terrace_share / float(steps) - trim, 0.0)
	var step_in: float = _radius * style.heavy_step_inset_fraction
	for k: int in range(steps):
		_sweep(_make_ring(1.0, y, off), _make_ring(1.0, y, off - step_in), style.heavy_ledge_color)
		off -= step_in
		_wall(y, y - trim, off, off, style.heavy_gold_color, true)
		y -= trim
		var wall_color: Color = style.heavy_wall_color if k % ALTERNATE == 0 else style.heavy_wall_alt_color
		_wall(y, y - wall_h, off, off, wall_color)
		y -= wall_h
	# Keel: taper to a flat cap with a glowing core.
	var keel_y: float = y - depth * style.heavy_keel_ratio
	var wall_bottom: Ring = _make_ring(1.0, y, off)
	var keel: Ring = _make_ring(style.heavy_keel_scale, keel_y)
	_sweep(wall_bottom, keel, style.heavy_keel_color)
	var core: Ring = _make_ring(style.heavy_core_scale, keel_y)
	_sweep(keel, core, style.heavy_keel_color)
	_sweep(core, _make_ring(0.0, keel_y), style.heavy_core_color, true)


# --- Round 3: sides that continue the top -----------------------------------------
# The top is dark navy plating (hub, rings of ~5 m plates, hairline seams, small
# rivets) under a gold edge. These looks wrap that over the edge and carry it down
# and underneath: the same plates, seams, rivets and gold, one shade darker below.

func _build_monolith(style: ArenaSideStyle, y_top: float) -> void:
	var rng: RandomNumberGenerator = _top_rng(style)
	var depth: float = DIAMETER_FACTOR * _radius * style.monolith_depth_fraction
	var bevel_h: float = depth * style.monolith_bevel_share
	var wall_h: float = depth - bevel_h
	var plates: PackedVector2Array = _plate_outline(style)
	var y: float = _top_lip(style, y_top)
	_outline = plates
	_band(style, rng, y, 1.0, y - wall_h, 1.0, style.top_plate_color, true, 0.0)
	_plate_rivets(style, y, y - wall_h)
	y -= wall_h
	var s_in: float = 1.0 - style.monolith_bevel_inset_fraction
	_band(style, rng, y, 1.0, y - bevel_h, s_in, style.top_plate_color, false, 0.0)
	y -= bevel_h
	_ring_stack(style, rng, y, 0.0, s_in, false)


func _build_tapered(style: ArenaSideStyle, y_top: float) -> void:
	var rng: RandomNumberGenerator = _top_rng(style)
	var diameter: float = DIAMETER_FACTOR * _radius
	var wall_h: float = diameter * style.tapered_wall_fraction
	var y: float = _top_lip(style, y_top)
	_outline = _plate_outline(style)
	_band(style, rng, y, 1.0, y - wall_h, 1.0, style.top_plate_color, true, style.top_seam_width_m)
	_plate_rivets(style, y, y - wall_h)
	y -= wall_h
	var strata: int = maxi(style.tapered_strata_count, 1)
	var inset: float = style.tapered_step_inset_fraction
	var slope_total: float = maxf(1.0 - style.tapered_bowl_scale - inset * float(strata - 1), STRATUM_SPAN_MIN)
	var span: float = slope_total / float(strata)
	var stratum_h: float = diameter * style.tapered_bowl_fraction / float(strata)
	var scale: float = 1.0
	for k: int in range(strata):
		if k > 0:
			_sweep(_make_ring(scale, y), _make_ring(scale - inset, y), style.top_ledge_color)
			scale -= inset
		var color: Color = _cycle_color(style.tapered_strata_colors, k)
		_band(style, rng, y, scale, y - stratum_h, scale - span, color, true, style.top_seam_width_m)
		scale -= span
		y -= stratum_h
	_sweep(_make_ring(scale, y), _make_ring(0.0, y), style.top_hub_color)


func _build_dome(style: ArenaSideStyle, y_top: float) -> void:
	var rng: RandomNumberGenerator = _top_rng(style)
	var diameter: float = DIAMETER_FACTOR * _radius
	var course_h: float = diameter * style.dome_course_fraction
	var y: float = _top_lip(style, y_top)
	_outline = _plate_outline(style)
	for _course: int in range(maxi(style.dome_course_count, 1)):
		_band(style, rng, y, 1.0, y - course_h, 1.0, style.top_plate_color, true, style.top_seam_width_m)
		_plate_rivets(style, y, y - course_h)
		y -= course_h
	_ring_stack(style, rng, y, diameter * style.dome_depth_fraction, 1.0, true)


func _top_rng(style: ArenaSideStyle) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = style.top_seed
	return rng


## Plates around the rim: as many as fit at the top's own plate length.
func _plate_count(style: ArenaSideStyle) -> int:
	return maxi(roundi(TAU * _radius / maxf(style.top_plate_length_m, PLATE_LENGTH_MIN)), PLATE_COUNT_MIN)


## Angular width of one plate's flat face (the plate minus its hairline seam).
func _face_angle(style: ArenaSideStyle) -> float:
	var step: float = TAU / float(_plate_count(style))
	return step - minf(style.top_seam_width_m / maxf(_radius, POINT_EPS), step * HALF)


## Outline of the plates: segment 2p is plate p's flat face, 2p + 1 its seam.
func _plate_outline(style: ArenaSideStyle) -> PackedVector2Array:
	var count: int = _plate_count(style)
	var step: float = TAU / float(count)
	var face: float = _face_angle(style)
	var points: PackedVector2Array = PackedVector2Array()
	for p: int in range(count):
		var a0: float = step * float(p)
		var a1: float = a0 + face
		points.append(Vector2(cos(a0), sin(a0)) * _radius)
		points.append(Vector2(cos(a1), sin(a1)) * _radius)
	return points


## Brightness factor of one plate (the top's proc_tone_variation).
func _tone(style: ArenaSideStyle, rng: RandomNumberGenerator) -> float:
	return 1.0 + style.top_tone_variation * (rng.randf() * DIAMETER_FACTOR - 1.0)


func _toned(color: Color, tone: float) -> Color:
	return Color(color.r * tone, color.g * tone, color.b * tone, 1.0)


## The gold lip wrapping over the playing surface's edge (flush with it, bevelled
## out, then a short drop) and its dark ledge back to the wall. Returns the height
## where the wall starts. Drawn on the plain circle; the ledge reaches in past the
## flat plate faces so the plates tuck under it with no gap.
func _top_lip(style: ArenaSideStyle, y_top: float, smooth: bool = false) -> float:
	_outline = _uniform
	var y_edge: float = y_top + _disk_height
	var y_end: float = y_top - DIAMETER_FACTOR * _radius * style.top_lip_below_fraction
	var y_bevel: float = lerpf(y_edge, y_end, style.top_lip_bevel_share)
	var out: float = _radius * style.top_lip_out_fraction
	_sweep(_make_ring(1.0, y_edge), _make_ring(1.0, y_bevel, out), style.top_lip_color, true)
	_sweep(_make_ring(1.0, y_bevel, out), _make_ring(1.0, y_end, out), style.top_lip_shade_color, true)
	# SHADER_DOME has a smooth wall (no flat plate faces), and its dark ledge goes to
	# the unshaded surface so the shader-lit underside never shows it.
	var reach: float = 1.0 - POINT_EPS if smooth else cos(_face_angle(style) * HALF) - POINT_EPS
	_sweep(_make_ring(1.0, y_end, out), _make_ring(reach, y_end), style.top_ledge_color, smooth)
	return y_end


## A band of plating on the current outline between two heights and radius scales
## (equal scales = a vertical wall, equal heights = a flat annulus): flat plate faces
## with hairline recessed seams, a brightness per plate, and an optional seam-coloured
## strip along its lower edge `strip_m` metres wide.
func _band(
	style: ArenaSideStyle, rng: RandomNumberGenerator, y_a: float, s_a: float, y_b: float, s_b: float,
	color: Color, seams: bool, strip_m: float
) -> void:
	var recess: float = _radius * style.top_seam_depth_fraction
	var offsets: PackedFloat32Array = PackedFloat32Array()
	var colors: PackedColorArray = PackedColorArray()
	var tone: float = _tone(style, rng)
	for i: int in range(_outline.size()):
		var is_seam: bool = seams and i % PLATE_SEGMENTS == PLATE_SEGMENTS - 1
		if seams and i % PLATE_SEGMENTS == 0:
			tone = _tone(style, rng)
		offsets.append(-recess if is_seam else 0.0)
		colors.append(style.top_seam_color if is_seam else _toned(color, tone))
	var length: float = Vector2(_radius * (s_a - s_b), y_a - y_b).length()
	var strip: float = clampf(strip_m / maxf(length, POINT_EPS), 0.0, HALF) if strip_m > 0.0 else 0.0
	var top: Ring = _make_ring(s_a, y_a, 0.0, offsets)
	var bottom: Ring = _make_ring(s_b, y_b, 0.0, offsets)
	var mid: Ring = bottom
	if strip > 0.0:
		mid = _make_ring(lerpf(s_a, s_b, 1.0 - strip), lerpf(y_a, y_b, 1.0 - strip), 0.0, offsets)
	_sweep(top, mid, color, false, colors)
	_risers(top, mid, style.top_seam_color)
	if strip > 0.0:
		_sweep(mid, bottom, style.top_seam_color)
		_risers(mid, bottom, style.top_seam_color)
	_sweep(_make_ring(s_a, y_a), top, style.top_seam_color)
	_sweep(bottom, _make_ring(s_b, y_b), style.top_seam_color)


## Rivets near both ends of every plate face, on two rows of a vertical wall.
func _plate_rivets(style: ArenaSideStyle, y_a: float, y_b: float) -> void:
	var half: float = _radius * style.top_rivet_size_fraction
	var height: float = _radius * style.top_rivet_height_fraction
	var inset: float = (y_a - y_b) * style.top_rivet_row_inset
	var none: PackedFloat32Array = PackedFloat32Array()
	for p: int in range(_outline.size() / PLATE_SEGMENTS):
		var i: int = p * PLATE_SEGMENTS
		var face_mid: Vector3 = (_ring_point(i, 1.0, 0.0, none, 0.0) + _ring_point(i + 1, 1.0, 0.0, none, 0.0)) * HALF
		var normal: Vector3 = Vector3(face_mid.x, 0.0, face_mid.z).normalized()
		for row_y: float in [y_a - inset, y_b + inset]:
			var a: Vector3 = _ring_point(i, 1.0, 0.0, none, row_y)
			var b: Vector3 = _ring_point(i + 1, 1.0, 0.0, none, row_y)
			for u: float in [style.top_rivet_end_inset, 1.0 - style.top_rivet_end_inset]:
				_rivet(a.lerp(b, u), normal, half, height, style.top_rivet_color)


## Concentric plate rings from the rim inwards (like the top's rings), hanging
## in a shallow dome `sag` deep at the middle (0 = flat), then the darker hub.
func _ring_stack(
	style: ArenaSideStyle, rng: RandomNumberGenerator, y_rim: float, sag: float, s_rim: float, seams: bool
) -> void:
	var hub: float = clampf(style.top_hub_radius_m / maxf(_radius, POINT_EPS), 0.0, s_rim * HALF)
	var width: float = maxf(style.top_ring_width_m, RING_WIDTH_MIN)
	var rings: int = maxi(roundi((_radius * s_rim - style.top_hub_radius_m) / width), 1)
	var s_a: float = s_rim
	var y_a: float = y_rim
	for k: int in range(rings):
		var s_b: float = lerpf(s_rim, hub, float(k + 1) / float(rings))
		var y_b: float = y_rim - sag * (1.0 - pow(s_b / s_rim, DIAMETER_FACTOR))
		_band(style, rng, y_a, s_a, y_b, s_b, style.top_under_color, seams, style.top_seam_width_m)
		s_a = s_b
		y_a = y_b
	_sweep(_make_ring(s_a, y_a), _make_ring(0.0, y_a), style.top_hub_color)


# --- Round 4: SHADER_DOME -----------------------------------------------------------
# PLATED_DOME's silhouette (a tall wall of plate courses, then a shallow dome of
# plate rings) with no modelled detail: smooth surfaces whose plating, seams and
# rivets are drawn by shaders/territory/arena_side_shell.gdshader, the top's own plating code.

func _build_shader_dome(style: ArenaSideStyle, y_top: float) -> void:
	_body_side.shell = true
	_body_under.shell = true
	_body_side.edge_y = y_top + _disk_height
	_body_under.edge_y = _body_side.edge_y
	_uniform = outline_points_for_radius(_radius, maxi(style.shell_segments, MIN_SEGMENTS))
	_outline = _uniform
	var diameter: float = DIAMETER_FACTOR * _radius
	var wall_h: float = diameter * style.dome_course_fraction * float(maxi(style.dome_course_count, 1))
	var y: float = _top_lip(style, y_top, true)
	_wall(y, y - wall_h, 0.0, 0.0, style.top_plate_color)
	y -= wall_h
	var sag: float = diameter * style.dome_depth_fraction
	var hub: float = clampf(style.top_hub_radius_m / maxf(_radius, POINT_EPS), 0.0, HALF)
	var width: float = maxf(style.top_ring_width_m, RING_WIDTH_MIN)
	var rings: int = maxi(roundi((_radius - style.top_hub_radius_m) / width), 1)
	var s_a: float = 1.0
	var y_a: float = y
	for k: int in range(rings):
		var s_b: float = lerpf(1.0, hub, float(k + 1) / float(rings))
		var y_b: float = y - sag * (1.0 - s_b * s_b)
		_sweep(_make_ring(s_a, y_a), _make_ring(s_b, y_b), style.top_under_color)
		s_a = s_b
		y_a = y_b
	_sweep(_make_ring(s_a, y_a), _make_ring(0.0, y_a), style.top_hub_color)


## The analytic circle of `radius` with `segments` evenly spaced points.
static func outline_points_for_radius(radius: float, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(segments)
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points[i] = Vector2(cos(angle), sin(angle)) * radius
	return points
