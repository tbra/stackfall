class_name ParachuteMesh
extends RefCounted
## Procedural low-poly parachute for a falling gift crate (Bontago-mp0.139).
## Static builders only; every dimension comes from GiftConfig's "-- Parachute"
## section. Three small ArrayMeshes, all in a frame whose origin is the RISER
## point (where the suspension lines converge) with +Y up:
##
##   build_canopy()        a domed canopy of alternating-colour gores (panels)
##                         with a scalloped rim and an open vent at the top.
##                         One surface, vertex colours, flat per-face normals;
##                         meant for a double-sided material.
##   build_rim_lines()     thin lines from every gore seam on the rim down to
##                         the riser. Scales with the canopy while it inflates.
##   build_harness_lines() four short lines from the riser to the crate's top
##                         corners (the riser sits `chute_riser_height_m` above
##                         the crate top, so the corners are below the origin).
##
## Pure geometry: no scene tree, so tests can inspect the arrays directly.

## A line is a thin triangular prism: three sides, no end caps.
const PRISM_SIDES: int = 3
## Never build fewer panels than this (a canopy needs at least a triangle fan).
const MIN_GORES: int = 3
const MIN_RINGS: int = 1
## Keeps the vent open: a zero angle would collapse the top row to a point.
const MIN_VENT_ANGLE_RAD: float = 0.05
## Triangles thinner than this (squared cross-product length) are skipped.
const DEGENERATE_EPSILON: float = 0.0000001
## Harness corner count (a square).
const HARNESS_CORNERS: int = 4
## A line this close to vertical uses another reference axis for its cross-section.
const NEAR_VERTICAL_DOT: float = 0.9
## Vertices per triangle (float so it divides a centroid sum directly).
const TRI_VERTS: float = 3.0


## Number of gores the canopy is built with (even, so two colours alternate).
static func gore_count(config: GiftConfig) -> int:
	var count: int = maxi(config.chute_gore_count, MIN_GORES)
	return count + (count % 2)


static func ring_count(config: GiftConfig) -> int:
	return maxi(config.chute_ring_count, MIN_RINGS)


## The canopy mesh. Triangle count = gores * rings * 4.
static func build_canopy(config: GiftConfig) -> ArrayMesh:
	var gores: int = gore_count(config)
	var rings: int = ring_count(config)
	var vent: float = maxf(config.chute_vent_angle_rad, MIN_VENT_ANGLE_RAD)
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var centre: Vector3 = Vector3(0.0, config.chute_rim_height_m, 0.0)
	for gore: int in range(gores):
		var color: Color = config.chute_color_a if gore % 2 == 0 else config.chute_color_b
		var angles: PackedFloat32Array = PackedFloat32Array([
			TAU * float(gore) / float(gores),
			TAU * (float(gore) + 0.5) / float(gores),
			TAU * float(gore + 1) / float(gores),
		])
		# grid[ring][column]: column 0 and 2 are the seams, 1 the panel middle.
		var grid: Array[PackedVector3Array] = []
		for ring: int in range(rings + 1):
			var row: PackedVector3Array = PackedVector3Array()
			for column: int in range(angles.size()):
				row.append(_canopy_point(config, vent, ring, rings, angles[column], column == 1))
			grid.append(row)
		for ring: int in range(rings):
			for column: int in range(angles.size() - 1):
				var p00: Vector3 = grid[ring][column]
				var p01: Vector3 = grid[ring][column + 1]
				var p10: Vector3 = grid[ring + 1][column]
				var p11: Vector3 = grid[ring + 1][column + 1]
				_add_tri(verts, normals, colors, color, centre, p00, p10, p11)
				_add_tri(verts, normals, colors, color, centre, p00, p11, p01)
	return _commit(verts, normals, colors)


## One dome vertex. `ring` 0 is the vent edge, `rings` the rim. Seams sit on the
## true dome; a panel's middle bulges outward mid-way down (billow) and its rim
## edge is lifted (scallop), which gives the typical lobed lower edge.
static func _canopy_point(config: GiftConfig, vent: float, ring: int, rings: int,
		angle: float, is_middle: bool) -> Vector3:
	var along: float = float(ring) / float(rings)
	var polar: float = lerpf(vent, PI * 0.5, along)
	var radius: float = config.chute_radius_m * sin(polar)
	var height: float = config.chute_rim_height_m + config.chute_dome_height_m * cos(polar)
	if is_middle:
		radius *= 1.0 + config.chute_billow * sin(PI * along)
		if ring == rings:
			height += config.chute_scallop_depth_m
	return Vector3(cos(angle) * radius, height, sin(angle) * radius)


static func build_rim_lines(config: GiftConfig) -> ArrayMesh:
	var gores: int = gore_count(config)
	var verts: PackedVector3Array = PackedVector3Array()
	for seam: int in range(gores):
		var angle: float = TAU * float(seam) / float(gores)
		var rim: Vector3 = Vector3(cos(angle) * config.chute_radius_m, config.chute_rim_height_m,
			sin(angle) * config.chute_radius_m)
		_add_line(verts, rim, Vector3.ZERO, config.chute_line_thickness_m)
	return _commit(verts, PackedVector3Array(), PackedColorArray())


## Crate-top corner attachment points, relative to the riser (below the origin).
static func harness_corners(config: GiftConfig) -> PackedVector3Array:
	var corners: PackedVector3Array = PackedVector3Array()
	var half: float = config.chute_attach_half_extent_m
	var drop: float = -config.chute_riser_height_m
	for index: int in range(HARNESS_CORNERS):
		var x_sign: float = 1.0 if index % 2 == 0 else -1.0
		var z_sign: float = 1.0 if index < 2 else -1.0
		corners.append(Vector3(x_sign * half, drop, z_sign * half))
	return corners


static func build_harness_lines(config: GiftConfig) -> ArrayMesh:
	var verts: PackedVector3Array = PackedVector3Array()
	for corner: Vector3 in harness_corners(config):
		_add_line(verts, Vector3.ZERO, corner, config.chute_line_thickness_m)
	return _commit(verts, PackedVector3Array(), PackedColorArray())


## The canopy's material: vertex colours, lit, double-sided (back faces get a
## flipped normal), roughness 1 like every other gift prop (GiftCrate).
static func canopy_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


## Lines are unshaded so a 1.6 cm prism still reads as a clean thread.
static func line_material(config: GiftConfig) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = config.chute_line_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


# --- geometry helpers -------------------------------------------------------

## Appends one triangle wound so its front face (clockwise in Godot, which is
## the side the cross product points away from) looks outward from `centre`,
## with a matching flat normal. Skips degenerate triangles.
static func _add_tri(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, color: Color, centre: Vector3,
		p0: Vector3, p1: Vector3, p2: Vector3) -> void:
	var facing: Vector3 = (p1 - p0).cross(p2 - p0)
	if facing.length_squared() < DEGENERATE_EPSILON:
		return
	var outward: Vector3 = (p0 + p1 + p2) / TRI_VERTS - centre
	if facing.dot(outward) > 0.0:
		verts.append_array(PackedVector3Array([p0, p2, p1]))
		facing = -facing
	else:
		verts.append_array(PackedVector3Array([p0, p1, p2]))
	var normal: Vector3 = -facing.normalized()
	for _i: int in range(int(TRI_VERTS)):
		normals.append(normal)
		colors.append(color)


## A thin triangular prism from `a` to `b` (three quads, no caps).
static func _add_line(verts: PackedVector3Array, a: Vector3, b: Vector3, thickness: float) -> void:
	var axis: Vector3 = (b - a).normalized()
	var reference: Vector3 = Vector3.RIGHT if absf(axis.dot(Vector3.UP)) > NEAR_VERTICAL_DOT else Vector3.UP
	var side: Vector3 = axis.cross(reference).normalized()
	var up: Vector3 = axis.cross(side)
	var radius: float = thickness * 0.5
	var offsets: PackedVector3Array = PackedVector3Array()
	for corner: int in range(PRISM_SIDES):
		var angle: float = TAU * float(corner) / float(PRISM_SIDES)
		offsets.append((side * cos(angle) + up * sin(angle)) * radius)
	for corner: int in range(PRISM_SIDES):
		var next: int = (corner + 1) % PRISM_SIDES
		verts.append_array(PackedVector3Array([
			a + offsets[corner], b + offsets[corner], b + offsets[next],
			a + offsets[corner], b + offsets[next], a + offsets[next],
		]))


static func _commit(verts: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> ArrayMesh:
	var mesh: ArrayMesh = ArrayMesh.new()
	if verts.is_empty():
		return mesh
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	if not normals.is_empty():
		arrays[Mesh.ARRAY_NORMAL] = normals
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
