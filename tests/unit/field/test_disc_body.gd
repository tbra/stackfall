extends GutTest
## game/field/ArenaMesh.gd: the disc's purely-visual thickness ("The disc is
## just a thin mirror currently, the mockup has a much thicker metallic disc
## with a soft glowing border going round the rim.") plus its chamfer/texture
## redesign ("the glowing strip currently sits slightly outside the disc as its
## own separate element ... the disc has a chamfered edge that makes up the
## glowing strip", "it lacks the texture ... visible where it interacts with
## the sun"). These tests pin the band/chamfer mesh geometry -- height,
## footprint and the chamfer's flush no-gap seam with the true disc edge --
## without needing a live Field or a renderer (ArrayMesh geometry is plain CPU
## data, readable headless).

const SEGMENTS: int = 24


func _map(radius: float = 10.0) -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_disc_body"
	map_def.field_radius = radius
	map_def.disk_height = 0.2
	return map_def


func _default_visuals() -> DiscBodyVisuals:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	# Footprint assertions below want an exact field_radius circle/ellipse;
	# band_radius_scale's hair's-width z-fighting nudge (config/
	# DiscBodyVisuals.gd's own DECISION) is covered by its own dedicated
	# assertion, not these. Zeroing the chamfer keeps the band's own AABB
	# spanning the full band_height budget for these footprint-only checks.
	visuals.band_radius_scale = 1.0
	visuals.chamfer_height_fraction = 0.0
	return visuals


## One side surface of the merged arena mesh re-wrapped as its own single-surface
## mesh + material, so the per-part geometry assertions below read the same data
## the old separate Band/Chamfer MeshInstance3D nodes exposed.
class Part:
	extends RefCounted
	var mesh: ArrayMesh = null
	var material_override: Material = null
	var name: String = ""


class Body:
	extends RefCounted
	var arena: ArenaMesh = null
	var merged: ArrayMesh = null
	var _parts: Dictionary = {}

	func part(kind: ArenaMesh.Kind, part_name: String) -> Part:
		if _parts.has(kind):
			return _parts[kind]
		var out: Part = Part.new()
		out.name = part_name
		var index: int = int(arena._surface_of.get(kind, -1))
		out.mesh = ArrayMesh.new()
		out.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, merged.surface_get_arrays(index))
		out.material_override = arena.material_for_surface(index)
		_parts[kind] = out
		return out

	func band_mesh_instance() -> Part:
		return part(ArenaMesh.Kind.BAND, "Band")

	func chamfer_mesh_instance() -> Part:
		return part(ArenaMesh.Kind.CHAMFER, "Chamfer")


func _make_body(map_def: MapDef, visuals: DiscBodyVisuals = null, y_shift: float = 0.0) -> Body:
	var body: Body = Body.new()
	body.arena = ArenaMesh.new()
	body.merged = ArrayMesh.new()
	body.arena.append_side_surfaces(
		body.merged, map_def, visuals if visuals != null else _default_visuals(), SEGMENTS, y_shift
	)
	return body


func test_configure_builds_a_band_and_chamfer_mesh() -> void:
	var body: Body = _make_body(_map())
	assert_not_null(body.band_mesh_instance())
	assert_not_null(body.band_mesh_instance().mesh)
	assert_not_null(body.chamfer_mesh_instance())
	assert_not_null(body.chamfer_mesh_instance().mesh)


func test_band_height_matches_the_configured_fraction_of_diameter() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_height_fraction = 0.05
	visuals.chamfer_height_fraction = 0.0
	var map_def: MapDef = _map(10.0)
	var body: Body = _make_body(map_def, visuals)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	# diameter 20 * 0.05 == 1.0 m of band_height_fraction, plus disk_height
	# (0.2 m) since the band's own top now sits flush at the true playing
	# surface (y = 0) whenever the chamfer above it is zeroed out -- see
	# game/field/ArenaMesh.gd's own rebuild().
	assert_almost_eq(aabb.size.y, 1.2, 0.01)
	assert_almost_eq(aabb.position.y, -1.2, 0.01)
	assert_almost_eq(aabb.position.y + aabb.size.y, 0.0, 0.01)


func test_round_band_footprint_is_the_field_radius_circle() -> void:
	var map_def: MapDef = _map(12.0)
	var body: Body = _make_body(map_def)

	var aabb: AABB = body.band_mesh_instance().mesh.get_aabb()
	assert_almost_eq(aabb.size.x, 24.0, 0.05, "x footprint spans 2 * field_radius.")
	assert_almost_eq(aabb.size.z, 24.0, 0.05, "z footprint spans 2 * field_radius (round).")


## The chamfer redesign ("the glowing strip currently sits slightly outside
## the disc as its own separate element ... the disc has a chamfered edge
## that makes up the glowing strip"). The chamfer's own TOP ring must sit
## exactly at the true field_radius edge -- not band_radius_scale's proud
## lip -- so there is no floating gap between the disc's true boundary and
## the glow, unlike the old separate rim mesh this package replaces.
func test_chamfer_top_ring_is_flush_with_the_true_field_radius_edge() -> void:
	var visuals: DiscBodyVisuals = DiscBodyVisuals.new()
	visuals.band_radius_scale = 1.1
	visuals.chamfer_height_fraction = 0.5
	visuals.band_height_fraction = 0.05
	var map_def: MapDef = _map(10.0)
	var body: Body = _make_body(map_def, visuals)

	var mesh: ArrayMesh = body.chamfer_mesh_instance().mesh as ArrayMesh
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var saw_top_vertex: bool = false
	for vertex: Vector3 in verts:
		if is_equal_approx(vertex.y, 0.0):
			saw_top_vertex = true
			var radius: float = Vector2(vertex.x, vertex.z).length()
			assert_almost_eq(radius, 10.0, 0.02,
				"the chamfer's own top ring must sit exactly at field_radius, flush with the overlay's own top-face boundary -- no proud/offset gap.")
	assert_true(saw_top_vertex, "fixture: the chamfer mesh must carry at least one true top-edge (y == 0) vertex.")
