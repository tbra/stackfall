class_name DiscBody
extends Node3D
## The play disc's visible THICKNESS (Bontago-mp0.3.2, owner feedback: "The
## disc is just a thin mirror currently, the mockup has a much thicker
## metallic disc with a soft glowing border going round the rim."). A dark
## polished-metal side band, topped with a sloped, glowing CHAMFER face
## around its top edge, hanging directly below game/TerritoryOverlay.gd's own
## thin (MapDef.disk_height) surface disc so the two read as one continuous,
## much thicker edge.
##
## Chamfer redesign (Bontago-pt.12, owner: "the glowing strip currently sits
## slightly outside the disc as its own separate element; in the mockup the
## disc has sort of a chamfered edge that makes up the glowing strip"). The
## old design (Bontago-mp0.3.2/mp0.3.8) built the glow as a second, separate
## vertical strip offset in both radius (rim_radius_scale) and height
## (rim_lift) from the band -- correct to avoid a z-fighting/dashing bug, but
## visibly disconnected from the disc's own edge. The chamfer below instead
## is a single sloped ring frustum whose TOP ring sits exactly at the true
## disc edge (radius scale 1.0, y = 0, flush with game/TerritoryOverlay.gd's
## own CylinderMesh top-face boundary -- no offset, no gap) and whose BOTTOM
## ring meets the band's own top ring (both at band_radius_scale) -- a real,
## watertight, beveled edge whose sloped face carries the emissive glow, not
## a floating second element. The two meshes only ever share a zero-width
## edge (never a coincident area), so the mp0.3.8 z-fighting bug does not
## recur -- see shaders/disc_rim.gdshader's own header comment for why.
##
## Surface texture (Bontago-pt.12, owner: "the disc looks close to the
## mockup but it lacks the texture ... especially visible ... where it
## interacts with the sun"): both the band's StandardMaterial3D and the
## chamfer's ShaderMaterial sample a shared, procedurally-generated
## (FastNoiseLite-backed NoiseTexture2D, no third-party asset) tangent-space
## normal map for a subtle brushed-metal micro-texture, plus anisotropic
## specular (StandardMaterial3D.anisotropy / the chamfer shader's own
## ANISOTROPY output) that runs circumferentially thanks to this file's own
## generated UV (U around the circumference) and SurfaceTool.generate_
## tangents(). This package owns only the band + chamfer surfaces; the flat
## mirrored TOP of the disc is game/TerritoryOverlay.gd's own CylinderMesh
## (config/TerritoryVisuals.gd), a different package's ownership -- the
## broad sun-sheen texture the owner also described on that flat surface is
## out of this package's scope.
##
## Purely visual: this node carries no collision, no shape owner, and never
## reads or writes anything under game/Field.gd's own disk trimesh/hole
## machinery (that file's own class doc: "Field decides nothing" about a
## hole; the same holds here -- this package's ownership rule keeps
## disk_height, collision walls and hole punching exactly as they already
## are). It hangs at world Y = -MapDef.disk_height and below, entirely
## beneath the collision trimesh's own top face (y = 0) and its
## disk_height-deep rim/hole walls, so it can never occlude or interfere with
## anything a block's physics reads. The chamfer's own top ring reaches up to
## y = 0 (flush with the true playing surface) but, like the rest of this
## node, carries no collision.
##
## **Shape support** (this package's own brief: "the rim/band must follow
## the actual outer edge of the disc shape for every variant"). ROUND and
## OVAL are exact: _outline_points() below walks the same analytic
## circle/ellipse boundary MapDef.shape_contains() tests membership against
## (field_radius in x, field_radius * oval_aspect in z for OVAL -- spec
## 2.1's map_shape). RING/TWIN/CROSS fall back to the same plain round
## bounding circle game/TerritoryOverlay.gd's own rebuild_disk_mesh() always
## draws for every shape today (that file builds one CylinderMesh with
## top_radius == bottom_radius == field_radius regardless of map_shape), so
## this band never drifts from the top surface it visually extends -- it
## does not attempt any shape's own holes/arms/gap silhouette (a ring's
## central hole, a cross's missing corners, a twin's gap between its two
## sub-disks all stay exactly as invisible on this band as they already are
## on the existing top surface; see this package's own handback report).
##
## DECISION (game/DiscBody.gd): both meshes below use cull_mode
## CULL_DISABLED rather than hand-verified triangle winding -- a small,
## purely cosmetic mesh rendered from every camera angle a life-sized arena
## never needs backface culling to look right, and skipping that
## verification was worth the render-order simplicity here (contrast
## game/DiscMirror.gd's own mirror_transform() DECISION, where getting
## winding exactly right was load-bearing for a *reflected* camera's
## rasterizer).

@export var visuals: DiscBodyVisuals = preload("res://config/disc_body_visuals.tres")

## Bontago-mp0.3.8: the chamfer's own screen-space-minimum-width shader --
## see shaders/disc_rim.gdshader's own class-doc-equivalent header comment.
const _CHAMFER_SHADER: Shader = preload("res://shaders/disc_rim.gdshader")
const _BAND_OVERLAY_SHADER: Shader = preload("res://shaders/disc_band_overlay.gdshader")

## Minimum segments for a degenerate/test MapDef (a triangle is the fewest a
## closed band can be built from); production maps use
## TerritoryVisuals.disk_mesh_segments (96 by default), passed in by whoever
## configures this node.
const MIN_SEGMENTS: int = 3

## Bontago-pt.12: fixed generation parameters for the procedural surface-
## texture normal map -- only the perceptual knobs (strength, frequency) are
## tunables (DiscBodyVisuals.surface_noise_strength/_frequency); the raw
## texture resolution and RNG seed are implementation detail, not something
## an F4 tuning pass needs to reach.
const _NOISE_TEX_SIZE: int = 128
const _NOISE_SEED: int = 8302

var _band: MeshInstance3D = null
var _chamfer: MeshInstance3D = null
var _map_def: MapDef = null


## Builds (or rebuilds) the band + chamfer meshes for `map_def`. `segments`
## mirrors whatever radial segment count the overlay's own disk mesh is
## currently using (TerritoryVisuals.disk_mesh_segments), so the band's own
## polygon facets line up with the top surface's.
func configure(map_def: MapDef, body_visuals: DiscBodyVisuals, segments: int) -> void:
	_map_def = map_def
	if body_visuals != null:
		visuals = body_visuals
	rebuild(maxi(segments, MIN_SEGMENTS))


func rebuild(segments: int) -> void:
	if _map_def == null or visuals == null:
		return
	var true_points: PackedVector2Array = _outline_points(_map_def, maxi(segments, MIN_SEGMENTS))
	var outer_points: PackedVector2Array = _scaled_points(true_points, visuals.band_radius_scale)
	var diameter: float = 2.0 * _map_def.field_radius
	var band_height: float = maxf(diameter * visuals.band_height_fraction, 0.0)
	var chamfer_height: float = band_height * clampf(visuals.chamfer_height_fraction, 0.0, 1.0)
	# Bontago-mp0.3.2 review pass 3 (owner: "the glowing gold line sits
	# partway down the band rather than on the top lip edge -- put it exactly
	# at the top outer edge"): the true playing surface (y = 0) is the disc's
	# real top -- game/TerritoryOverlay.gd's own CylinderMesh is a real
	# cylinder disk_height tall, carrying its own (non-emissive,
	# territory-shaded) side wall from y = 0 down to y = -disk_height.
	# band_bottom_y keeps the same anchor as before this package
	# (band_height below -disk_height, so the combined band+disk_height drop
	# from y = 0 is unchanged). Bontago-pt.12: band_top_y is now
	# -chamfer_height rather than a flat 0.0 -- the chamfer above the band
	# occupies the top chamfer_height slice of that same combined
	# (band_height + disk_height) budget rather than adding on top of it, so
	# the disc's overall silhouette height is unchanged by this package.
	var band_bottom_y: float = -_map_def.disk_height - band_height
	var band_top_y: float = -chamfer_height

	_band = _mesh_instance(_band, &"Band")
	_band.mesh = _build_ring_mesh(
		outer_points, outer_points, band_top_y, band_bottom_y, visuals.bottom_cap_enabled
	)
	_band.material_override = _band_material()

	# Bontago-pt.12: the chamfer's own TOP ring uses `true_points` (radius
	# scale 1.0, y = 0) -- exactly the true disc edge, flush with game/
	# TerritoryOverlay.gd's own CylinderMesh top-face boundary, no offset. Its
	# BOTTOM ring uses `outer_points` (band_radius_scale) at band_top_y --
	# exactly the band's own top ring, a watertight, seamless join. See this
	# file's own class doc for why sharing that top edge does not reproduce
	# the mp0.3.8 z-fighting bug.
	_chamfer = _mesh_instance(_chamfer, &"Chamfer")
	# Bontago-mp0.3.8: with_gradient = true paints COLOR.r = 0.0/1.0 on the
	# top/bottom edges -- shaders/disc_rim.gdshader's own vertex() reads that
	# to know which edge it may push down for its screen-space minimum width,
	# and its fragment() to fade EMISSION from the top edge down.
	_chamfer.mesh = _build_ring_mesh(true_points, outer_points, 0.0, band_top_y, false, true)
	_chamfer.material_override = _chamfer_material()
	# DECISION (Bontago-1pi.60): the band/chamfer are circular outlines; for TWIN
	# and CROSS they would float around empty space, so hide them there. RING's
	# outer edge is the circle, so it keeps them.
	var circular_outline: bool = _map_def.map_shape != MapDef.MapShape.TWIN and _map_def.map_shape != MapDef.MapShape.CROSS
	_band.visible = circular_outline
	_chamfer.visible = circular_outline


func band_mesh_instance() -> MeshInstance3D:
	return _band


func chamfer_mesh_instance() -> MeshInstance3D:
	return _chamfer


func _mesh_instance(existing: MeshInstance3D, node_name: StringName) -> MeshInstance3D:
	if existing != null:
		return existing
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = node_name
	# Bontago-mp0.3.2 review pass 3 (decisive finding): game/DiscMirror.gd's
	# own mirror Camera3D sits reflected BELOW the disc, looking back up at
	# the blocks/sky it needs to capture -- exactly where this node's own
	# band/bottom-cap geometry hangs. Left on the default render layer, that
	# solid, opaque, dark mesh sat directly in the mirror camera's own line
	# of sight, so mirror_tex came back a near-featureless dark image no
	# matter how strong mirror_strength/mirror_center_fraction were pushed
	# (confirmed: even mirror_strength = mirror_center_fraction = 1.0 showed
	# no block silhouettes). game/TerritoryOverlay.gd's own disc mesh solves
	# the identical problem the identical way (see DiscMirror.gd's own
	# DECISION on `overlay.layers = DISC_LAYER_BIT`) -- this reuses that same
	# bit rather than inventing a second one, so both disc-owned meshes are
	# invisible to the one camera that must never see them nested inside
	# their own reflection, while staying on every other camera's default
	# cull_mask (CameraRig, every screenshot tool) exactly like the overlay.
	instance.layers = DiscMirror.DISC_LAYER_BIT
	add_child(instance)
	return instance


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
func _build_ring_mesh(
	top_points: PackedVector2Array,
	bottom_points: PackedVector2Array,
	top_y: float,
	bottom_y: float,
	cap_bottom: bool,
	with_gradient: bool = false
) -> ArrayMesh:
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
	return surface_tool.commit()


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
	# bottom edge (COLOR.r = 1.0, V = 1.0) -- see _build_ring_mesh()'s own
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
	var extent: float = 0.001
	for point: Vector2 in points:
		extent = maxf(extent, maxf(absf(point.x), absf(point.y)))
	for i: int in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		surface_tool.set_uv(Vector2(0.5, 0.5))
		surface_tool.add_vertex(center)
		surface_tool.set_uv((a / (2.0 * extent)) + Vector2(0.5, 0.5))
		surface_tool.add_vertex(Vector3(a.x, y, a.y))
		surface_tool.set_uv((b / (2.0 * extent)) + Vector2(0.5, 0.5))
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
## (see _build_ring_mesh()'s `with_gradient`) to push its bottom edge down by
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
