class_name DiscBody
extends Node3D
## The play disc's visible THICKNESS (Bontago-mp0.3.2, owner feedback: "The
## disc is just a thin mirror currently, the mockup has a much thicker
## metallic disc with a soft glowing border going round the rim."). A dark
## polished-metal side band, capped with a soft glowing rim line around its
## top edge, hanging directly below game/TerritoryOverlay.gd's own thin
## (MapDef.disk_height) surface disc so the two read as one continuous, much
## thicker edge.
##
## Purely visual: this node carries no collision, no shape owner, and never
## reads or writes anything under game/Field.gd's own disk trimesh/hole
## machinery (that file's own class doc: "Field decides nothing" about a
## hole; the same holds here -- this package's ownership rule keeps
## disk_height, collision walls and hole punching exactly as they already
## are). It hangs at world Y = -MapDef.disk_height and below, entirely
## beneath the collision trimesh's own top face (y = 0) and its
## disk_height-deep rim/hole walls, so it can never occlude or interfere with
## anything a block's physics reads.
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

## Minimum segments for a degenerate/test MapDef (a triangle is the fewest a
## closed band can be built from); production maps use
## TerritoryVisuals.disk_mesh_segments (96 by default), passed in by whoever
## configures this node.
const MIN_SEGMENTS: int = 3

var _band: MeshInstance3D = null
var _rim: MeshInstance3D = null
var _map_def: MapDef = null


## Builds (or rebuilds) the band + rim meshes for `map_def`. `segments`
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
	var points: PackedVector2Array = _outline_points(_map_def, maxi(segments, MIN_SEGMENTS))
	var diameter: float = 2.0 * _map_def.field_radius
	var band_height: float = maxf(diameter * visuals.band_height_fraction, 0.0)
	# Bontago-mp0.3.2 review pass 3 (owner: "the glowing gold line sits
	# partway down the band rather than on the top lip edge -- put it exactly
	# at the top outer edge"): top_y is the true playing surface (y = 0), not
	# -disk_height. game/TerritoryOverlay.gd's own CylinderMesh is a real
	# cylinder disk_height tall, so it carries its own (non-emissive,
	# territory-shaded) side wall from y = 0 down to y = -disk_height --
	# anchoring this band at -disk_height left that thin sliver of the
	# overlay's own wall sitting ABOVE the glowing rim, reading as the glow
	# starting short of the actual top edge. bottom_y keeps the same anchor
	# as before (band_height below -disk_height), so the band simply grows
	# taller by disk_height to close that gap rather than the whole disc
	# getting thinner.
	var top_y: float = 0.0
	var bottom_y: float = -_map_def.disk_height - band_height
	var band_points: PackedVector2Array = _scaled_points(points, visuals.band_radius_scale)

	_band = _mesh_instance(_band, &"Band")
	_band.mesh = _build_band_mesh(band_points, top_y, bottom_y, visuals.bottom_cap_enabled)
	_band.material_override = _band_material()

	var rim_height: float = band_height * clampf(visuals.rim_height_fraction, 0.0, 1.0)
	var rim_points: PackedVector2Array = _scaled_points(points, visuals.rim_radius_scale)
	_rim = _mesh_instance(_rim, &"Rim")
	_rim.mesh = _build_band_mesh(rim_points, top_y, top_y - rim_height, false)
	_rim.material_override = _rim_material()


func band_mesh_instance() -> MeshInstance3D:
	return _band


func rim_mesh_instance() -> MeshInstance3D:
	return _rim


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


## A closed vertical band between `points` at `top_y` and `bottom_y`, with an
## optional flat bottom cap. Smooth-shaded (st.generate_normals()), the same
## look Godot's own CylinderMesh gives the top surface's side wall.
func _build_band_mesh(
	points: PackedVector2Array, top_y: float, bottom_y: float, cap_bottom: bool
) -> ArrayMesh:
	var surface_tool: SurfaceTool = SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = points.size()
	for i: int in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		var p0: Vector3 = Vector3(a.x, top_y, a.y)
		var p1: Vector3 = Vector3(b.x, top_y, b.y)
		var p2: Vector3 = Vector3(b.x, bottom_y, b.y)
		var p3: Vector3 = Vector3(a.x, bottom_y, a.y)
		_add_quad(surface_tool, p0, p1, p2, p3)
	if cap_bottom:
		_add_bottom_cap(surface_tool, points, bottom_y)
	surface_tool.generate_normals()
	return surface_tool.commit()


func _add_quad(
	surface_tool: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3
) -> void:
	surface_tool.add_vertex(p0)
	surface_tool.add_vertex(p1)
	surface_tool.add_vertex(p2)
	surface_tool.add_vertex(p0)
	surface_tool.add_vertex(p2)
	surface_tool.add_vertex(p3)


## A triangle fan from the disk-local origin, closing the band's underside.
func _add_bottom_cap(
	surface_tool: SurfaceTool, points: PackedVector2Array, y: float
) -> void:
	var center: Vector3 = Vector3(0.0, y, 0.0)
	var count: int = points.size()
	for i: int in range(count):
		var a: Vector2 = points[i]
		var b: Vector2 = points[(i + 1) % count]
		surface_tool.add_vertex(center)
		surface_tool.add_vertex(Vector3(a.x, y, a.y))
		surface_tool.add_vertex(Vector3(b.x, y, b.y))


func _band_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = visuals.band_color
	material.metallic = visuals.band_metallic
	material.roughness = visuals.band_roughness
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _rim_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = visuals.rim_color
	material.emission_enabled = true
	material.emission = visuals.rim_color
	material.emission_energy_multiplier = visuals.rim_emission_energy
	material.metallic = 0.0
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
