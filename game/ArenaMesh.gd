class_name ArenaMesh
extends RefCounted
## The arena's generated SIDE surfaces (Bontago-mp0.150.1): the glowing chamfer,
## the metal side band and the bottom cap, appended as extra surfaces to the ONE
## ArrayMesh that game/TerritoryOverlay.gd draws the whole arena with (top =
## surface 0, territory shader). Formerly game/DiscBody.gd drew these as two
## separate MeshInstance3D children (Band, Chamfer) of a Node3D.
##
## Every vertex, UV, tangent, gradient colour, material and shader parameter is
## exactly what DiscBody produced; only the nodes are gone. The band and its
## bottom cap are generated as one smooth-shaded SurfaceTool mesh (so the seam
## normals are unchanged) and then split into two surfaces so the side and the
## bottom each carry their own material slot (the next package restyles them).
##
## Shape support (unchanged): ROUND and OVAL follow the analytic outline
## (field_radius in x, field_radius * oval_aspect in z); RING keeps the round
## outer edge; TWIN and CROSS get no side surfaces (they would float around
## empty space; DECISION Bontago-1pi.60).
##
## DECISION (game/ArenaMesh.gd): the side materials keep cull_mode
## CULL_DISABLED rather than hand-verified winding, as DiscBody did.

## GLOW is the emissive part of the alternative looks (ArenaSideStyle); the
## values of BAND/BOTTOM/GLOW match game/ArenaSideBuilder.gd's KIND_* constants.
enum Kind { TOP, CHAMFER, BAND, BOTTOM, GLOW }

const _CHAMFER_SHADER: Shader = preload("res://shaders/disc_rim.gdshader")
const _BAND_OVERLAY_SHADER: Shader = preload("res://shaders/disc_band_overlay.gdshader")

## Minimum segments for a degenerate/test MapDef (a triangle is the fewest a
## closed band can be built from).
const MIN_SEGMENTS: int = 3

## Fixed generation parameters of the procedural surface-texture normal map
## (only strength/frequency are tunables, DiscBodyVisuals).
const _NOISE_TEX_SIZE: int = 128
const _NOISE_SEED: int = 8302

## Vertices per quad / per cap triangle in the SurfaceTool's non-indexed output.
const _QUAD_VERTS: int = 6
const _CAP_TRI_VERTS: int = 3
## Floats per vertex in the tangent array (xyz + binormal sign).
const _TANGENT_STRIDE: int = 4
## Planar bottom-cap UV: centre of the unit square and the bounding-square factor.
const _CAP_UV_CENTER: Vector2 = Vector2(0.5, 0.5)
const _CAP_UV_SPAN: float = 2.0
const _CAP_EXTENT_MIN: float = 0.001
const _DIAMETER_FACTOR: float = 2.0

var visuals: DiscBodyVisuals = null
## Kind -> surface index in the target mesh (only kinds actually appended).
var _surface_of: Dictionary = {}
## Surface index -> Material for the appended surfaces.
var _materials: Dictionary = {}


## Surface index of `kind` in the mesh last built, or -1 when it has none.
func surface_index(kind: Kind) -> int:
	return int(_surface_of.get(kind, -1))


## Material of the surface at `surface`, or null.
func material_for_surface(surface: int) -> Material:
	return _materials.get(surface, null) as Material


## Surface index -> Material for every appended side surface.
func materials() -> Dictionary:
	return _materials


## Appends the chamfer/band/bottom surfaces for `map_def` to `target`. `y_shift`
## is added to every vertex y (the overlay node sits at -disk_height/2, so the
## old world-space-at-origin coordinates become local with +disk_height/2).
## Returns the number of surfaces appended (0 for TWIN/CROSS).
func append_side_surfaces(
	target: ArrayMesh,
	map_def: MapDef,
	body_visuals: DiscBodyVisuals,
	segments: int,
	y_shift: float,
	side_style: ArenaSideStyle = null
) -> int:
	_surface_of.clear()
	_materials.clear()
	if map_def == null or body_visuals == null:
		return 0
	visuals = body_visuals
	if side_style != null and side_style.style != ArenaSideStyle.Style.CURRENT:
		return _append_style_surfaces(target, map_def, side_style, segments, y_shift)
	var circular_outline: bool = map_def.map_shape != MapDef.MapShape.TWIN and map_def.map_shape != MapDef.MapShape.CROSS
	if not circular_outline:
		return 0
	var true_points: PackedVector2Array = _outline_points(map_def, maxi(segments, MIN_SEGMENTS))
	var outer_points: PackedVector2Array = _scaled_points(true_points, visuals.band_radius_scale)
	var diameter: float = _DIAMETER_FACTOR * map_def.field_radius
	var band_height: float = maxf(diameter * visuals.band_height_fraction, 0.0)
	var chamfer_height: float = band_height * clampf(visuals.chamfer_height_fraction, 0.0, 1.0)
	# Same anchors as DiscBody: world y = 0 is the playing surface, the band spans
	# [-disk_height - band_height, -chamfer_height], the chamfer [-chamfer_height, 0].
	var band_bottom_y: float = -map_def.disk_height - band_height + y_shift
	var band_top_y: float = -chamfer_height + y_shift

	# The chamfer's TOP ring is the true disc edge (scale 1.0, y = 0), flush with the
	# top surface; its BOTTOM ring is the band's top ring. with_gradient paints
	# COLOR.r for shaders/disc_rim.gdshader.
	var chamfer_arrays: Array = _ring_arrays(true_points, outer_points, y_shift, band_top_y, false, true)
	_append(target, Kind.CHAMFER, chamfer_arrays, _chamfer_material())

	var band_arrays: Array = _ring_arrays(
		outer_points, outer_points, band_top_y, band_bottom_y, visuals.bottom_cap_enabled
	)
	var band_material: StandardMaterial3D = _band_material()
	var band_vertex_count: int = outer_points.size() * _QUAD_VERTS
	_append(target, Kind.BAND, _slice_arrays(band_arrays, 0, band_vertex_count), band_material)
	if visuals.bottom_cap_enabled:
		var total: int = (band_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		_append(target, Kind.BOTTOM, _slice_arrays(band_arrays, band_vertex_count, total), band_material)
	return _surface_of.size()


## The alternative looks (ArenaSideStyle): flat-shaded vertex-coloured body surfaces
## plus an unshaded glow surface, hanging from the slab's bottom edge.
func _append_style_surfaces(
	target: ArrayMesh, map_def: MapDef, side_style: ArenaSideStyle, segments: int, y_shift: float
) -> int:
	var builder: ArenaSideBuilder = ArenaSideBuilder.new()
	var built: Dictionary = builder.build(map_def, side_style, segments, y_shift - map_def.disk_height)
	var body_material: StandardMaterial3D = _style_body_material(side_style)
	var glow_material: StandardMaterial3D = _style_glow_material(side_style)
	for kind: Kind in [Kind.BAND, Kind.BOTTOM, Kind.GLOW]:
		if not built.has(int(kind)):
			continue
		_append(target, kind, built[int(kind)], glow_material if kind == Kind.GLOW else body_material)
	return _surface_of.size()


## Toon-shaded opaque body colour carried entirely by the vertex colours.
func _style_body_material(side_style: ArenaSideStyle) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	material.specular_mode = BaseMaterial3D.SPECULAR_TOON
	material.metallic = 0.0
	material.roughness = side_style.body_roughness
	return material


## Unshaded glow: vertex colour times a per-style energy (HDR, picked up by glow).
func _style_glow_material(side_style: ArenaSideStyle) -> StandardMaterial3D:
	var energy: float = 1.0
	match side_style.style:
		ArenaSideStyle.Style.LAYERED_PLATES:
			energy = side_style.layered_core_energy
		ArenaSideStyle.Style.ROCKY_ISLAND:
			energy = side_style.rock_crystal_energy
		ArenaSideStyle.Style.MACHINED_DISC:
			energy = side_style.machined_light_energy
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(energy, energy, energy, 1.0)
	return material


func _append(target: ArrayMesh, kind: Kind, arrays: Array, material: Material) -> void:
	target.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var index: int = target.get_surface_count() - 1
	_surface_of[kind] = index
	_materials[index] = material


## Copies vertices [from, to) of every per-vertex array (tangents hold 4 floats).
func _slice_arrays(arrays: Array, from: int, to: int) -> Array:
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).slice(from, to)
	out[Mesh.ARRAY_NORMAL] = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).slice(from, to)
	out[Mesh.ARRAY_TANGENT] = (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).slice(from * _TANGENT_STRIDE, to * _TANGENT_STRIDE)
	out[Mesh.ARRAY_TEX_UV] = (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).slice(from, to)
	if arrays[Mesh.ARRAY_COLOR] != null:
		out[Mesh.ARRAY_COLOR] = (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).slice(from, to)
	return out


## Disk-local (x, z) points around `map_def`'s outer boundary, evenly spaced
## by angle. See this file's own class doc for which shapes are exact.
func _outline_points(map_def: MapDef, segments: int) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	points.resize(segments)
	var z_scale: float = map_def.oval_aspect if map_def.map_shape == MapDef.MapShape.OVAL else 1.0
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		points[i] = Vector2(
			map_def.field_radius * cos(angle), map_def.field_radius * z_scale * sin(angle)
		)
	return points


func _scaled_points(points: PackedVector2Array, scale: float) -> PackedVector2Array:
	var scaled: PackedVector2Array = PackedVector2Array()
	scaled.resize(points.size())
	for i: int in range(points.size()):
		scaled[i] = points[i] * scale
	return scaled


## A closed ring frustum between `top_points` at `top_y` and `bottom_points`
## at `bottom_y` (the two are the SAME array for a plain vertical band, or
## different-radius arrays for a sloped chamfer face), with an optional flat
## bottom cap. Smooth-shaded (st.generate_normals()), with generated UV/
## tangent data (U around the circumference, V from 0 at the top ring to 1 at
## the bottom) so both this mesh's own material (StandardMaterial3D or
## disc_rim.gdshader) can sample a shared procedural normal-map texture and
## drive anisotropic specular from real tangent data (Bontago-pt.12).
##
## `with_gradient` (Bontago-mp0.3.8) paints COLOR.r = 0.0 on every top-edge
## vertex and 1.0 on every bottom-edge vertex, so shaders/disc_rim.gdshader's
## rim material can tell, per vertex, which edge it is without a second
## uniform. Unused (false) by the band's own plain StandardMaterial3D.
func _ring_arrays(
	top_points: PackedVector2Array,
	bottom_points: PackedVector2Array,
	top_y: float,
	bottom_y: float,
	cap_bottom: bool,
	with_gradient: bool = false
) -> Array:
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = top_points.size()
	for i: int in range(count):
		var ta: Vector2 = top_points[i]
		var tb: Vector2 = top_points[(i + 1) % count]
		var ba: Vector2 = bottom_points[i]
		var bb: Vector2 = bottom_points[(i + 1) % count]
		var p0: Vector3 = Vector3(ta.x, top_y, ta.y)
		var p1: Vector3 = Vector3(tb.x, top_y, tb.y)
		var p2: Vector3 = Vector3(bb.x, bottom_y, bb.y)
		var p3: Vector3 = Vector3(ba.x, bottom_y, ba.y)
		var ua: float = float(i) / float(count)
		var ub: float = float(i + 1) / float(count)
		_add_quad(surface_tool, p0, p1, p2, p3, ua, ub, with_gradient)
	if cap_bottom:
		_add_bottom_cap(surface_tool, bottom_points, bottom_y)
	surface_tool.generate_normals()
	surface_tool.generate_tangents()
	var ring: ArrayMesh = surface_tool.commit()
	return ring.surface_get_arrays(0)


func _add_quad(
	surface_tool: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	ua: float,
	ub: float,
	with_gradient: bool = false
) -> void:
	# p0/p1 are this quad's top edge (COLOR.r = 0.0, V = 0.0), p2/p3 its
	# bottom edge (COLOR.r = 1.0, V = 1.0) -- see _ring_arrays()'s own
	# `with_gradient` doc.
	const TOP_COLOR: Color = Color(0.0, 0.0, 0.0, 1.0)
	const BOTTOM_COLOR: Color = Color(1.0, 0.0, 0.0, 1.0)
	if with_gradient:
		surface_tool.set_color(TOP_COLOR)
	surface_tool.set_uv(Vector2(ua, 0.0))
	surface_tool.add_vertex(p0)
	if with_gradient:
		surface_tool.set_color(TOP_COLOR)
	surface_tool.set_uv(Vector2(ub, 0.0))
	surface_tool.add_vertex(p1)
	if with_gradient:
		surface_tool.set_color(BOTTOM_COLOR)
	surface_tool.set_uv(Vector2(ub, 1.0))
	surface_tool.add_vertex(p2)
	if with_gradient:
		surface_tool.set_color(TOP_COLOR)
	surface_tool.set_uv(Vector2(ua, 0.0))
	surface_tool.add_vertex(p0)
	if with_gradient:
		surface_tool.set_color(BOTTOM_COLOR)
	surface_tool.set_uv(Vector2(ub, 1.0))
	surface_tool.add_vertex(p2)
	if with_gradient:
		surface_tool.set_color(BOTTOM_COLOR)
	surface_tool.set_uv(Vector2(ua, 1.0))
	surface_tool.add_vertex(p3)


## A triangle fan from the disk-local origin, closing the band's underside.
## Rarely seen (only from a low, distant angle looking up under the disc),
## so a simple planar UV (centered, spanning the bounding square) is enough
## to keep the shared surface-texture material from sampling a degenerate
## coordinate here.
func _add_bottom_cap(
	surface_tool: SurfaceTool, points: PackedVector2Array, y: float
) -> void:
	var center: Vector3 = Vector3(0.0, y, 0.0)
	var count: int = points.size()
	var extent: float = _CAP_EXTENT_MIN
	for point: Vector2 in points:
		extent = maxf(extent, maxf(absf(point.x), absf(point.y)))
	for i: int in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		surface_tool.set_uv(_CAP_UV_CENTER)
		surface_tool.add_vertex(center)
		surface_tool.set_uv((a / (_CAP_UV_SPAN * extent)) + _CAP_UV_CENTER)
		surface_tool.add_vertex(Vector3(a.x, y, a.y))
		surface_tool.set_uv((b / (_CAP_UV_SPAN * extent)) + _CAP_UV_CENTER)
		surface_tool.add_vertex(Vector3(b.x, y, b.y))


## Bontago-pt.12: procedurally generated (FastNoiseLite-backed, no
## third-party asset) tangent-space normal map, shared by the band's own
## StandardMaterial3D and the chamfer's ShaderMaterial so both disc surfaces
## this package owns carry the same fine-grained "brushed metal" micro-
## texture -- the owner's "it lacks the texture ... visible where it
## interacts with the sun" report. Regenerated on every rebuild() (a rare,
## map-change-driven call, not a per-frame one) rather than cached, keeping
## this file's own state simple; NoiseTexture2D generation is cheap at
## _NOISE_TEX_SIZE and runs off the render thread.
func _surface_noise_texture() -> NoiseTexture2D:
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = _NOISE_SEED
	noise.frequency = visuals.surface_noise_frequency
	var texture: NoiseTexture2D = NoiseTexture2D.new()
	texture.width = _NOISE_TEX_SIZE
	texture.height = _NOISE_TEX_SIZE
	texture.seamless = true
	texture.as_normal_map = true
	texture.noise = noise
	return texture


func _band_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = visuals.band_color
	material.metallic = visuals.band_metallic
	material.roughness = visuals.band_roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.anisotropy_enabled = visuals.surface_anisotropy > 0.0
	material.anisotropy = visuals.surface_anisotropy
	material.normal_enabled = visuals.surface_noise_strength > 0.0
	material.normal_texture = _surface_noise_texture()
	material.normal_scale = visuals.surface_noise_strength
	material.next_pass = _band_overlay_material()
	return material


## Bontago-adt.2: additive banded-wall overlay (inlay line, lower line, cool
## fresnel sheen) chained after the band's StandardMaterial3D.
func _band_overlay_material() -> ShaderMaterial:
	var overlay: ShaderMaterial = ShaderMaterial.new()
	overlay.shader = _BAND_OVERLAY_SHADER
	overlay.set_shader_parameter(&"inlay_color", visuals.band_inlay_color)
	overlay.set_shader_parameter(&"inlay_energy", visuals.band_inlay_energy)
	overlay.set_shader_parameter(&"inlay_position", visuals.band_inlay_position)
	overlay.set_shader_parameter(&"inlay_width", visuals.band_inlay_width)
	overlay.set_shader_parameter(&"lower_line_strength", visuals.band_lower_line_strength)
	overlay.set_shader_parameter(&"sheen_color", visuals.band_sheen_color)
	overlay.set_shader_parameter(&"sheen_strength", visuals.band_sheen_strength)
	overlay.set_shader_parameter(&"sheen_power", visuals.band_sheen_power)
	return overlay


## Bontago-mp0.3.8: a ShaderMaterial (shaders/disc_rim.gdshader) rather than
## the band's own plain StandardMaterial3D -- the dashing-at-distance fix
## needs a vertex shader that reads this mesh's own gradient vertex colors
## (see _ring_arrays()'s `with_gradient`) to push its bottom edge down by
## a camera-distance-proportional amount, which a fixed material cannot do.
func _chamfer_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = _CHAMFER_SHADER
	material.set_shader_parameter(&"rim_color", visuals.chamfer_glow_color)
	material.set_shader_parameter(&"rim_emission_energy", visuals.chamfer_glow_energy)
	material.set_shader_parameter(&"band_color", visuals.band_color)
	material.set_shader_parameter(
		&"min_screen_width_factor", visuals.chamfer_screen_min_width_factor
	)
	material.set_shader_parameter(&"surface_noise", _surface_noise_texture())
	material.set_shader_parameter(&"surface_noise_strength", visuals.surface_noise_strength)
	material.set_shader_parameter(&"surface_anisotropy", visuals.surface_anisotropy)
	return material
