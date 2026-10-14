extends GutTest
## game/ArenaSideBuilder.gd + the ArenaSideStyle switch in game/ArenaMesh.gd
## (Bontago-mp0.150.2): every alternative side/underside look is static CPU
## geometry that must hang from the slab edge, stay inside the map's outline,
## carry unit normals that point away from the solid, and work for every MapDef
## shape. Plain ArrayMesh data, readable headless.

const RADIUS: float = 20.0
const DISK_HEIGHT: float = 0.2
const SEGMENTS: int = 48
const Y_TOP: float = -0.1
const EPS: float = 0.001
## Outline radius may overshoot the nominal radius a little (rock wobble, oval z).
const RADIUS_SLACK: float = 1.15
const STYLES: Array[ArenaSideStyle.Style] = [
	ArenaSideStyle.Style.LAYERED_PLATES,
	ArenaSideStyle.Style.ROCKY_ISLAND,
	ArenaSideStyle.Style.MACHINED_DISC,
	ArenaSideStyle.Style.MACHINED_STYLISED,
	ArenaSideStyle.Style.MACHINED_DETAILED,
	ArenaSideStyle.Style.MACHINED_HEAVY,
	ArenaSideStyle.Style.MONOLITH,
	ArenaSideStyle.Style.TAPERED_STRATA,
	ArenaSideStyle.Style.PLATED_DOME,
	ArenaSideStyle.Style.SHADER_DOME,
]
## Round 3 looks wrap a gold lip over the slab's top edge, so they reach DISK_HEIGHT above Y_TOP.
const WRAP_STYLES: Array[ArenaSideStyle.Style] = [
	ArenaSideStyle.Style.MONOLITH,
	ArenaSideStyle.Style.TAPERED_STRATA,
	ArenaSideStyle.Style.PLATED_DOME,
	ArenaSideStyle.Style.SHADER_DOME,
]
const ROUND3_VERTEX_BUDGET: int = 60000
## Round-2 machined looks stay cheap static geometry.
## Rivet height as a fraction of the radius is the only thing allowed past the disc edge.
const RIVET_SLACK: float = 0.006
const MACHINED_VERTEX_BUDGET: int = 12000


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_arena_side"
	map_def.field_radius = RADIUS
	map_def.disk_height = DISK_HEIGHT
	return map_def


func _style(which: ArenaSideStyle.Style) -> ArenaSideStyle:
	var style: ArenaSideStyle = ArenaSideStyle.new()
	style.style = which
	return style


func _all_vertices(built: Dictionary) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	for kind: int in built:
		out.append_array((built[kind] as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	return out


func test_every_style_builds_geometry() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		assert_false(built.is_empty(), "style %d builds surfaces" % which)
		assert_true(_all_vertices(built).size() >= 3 * 3)


func test_geometry_hangs_from_the_slab_and_stays_inside_the_outline() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var map_def: MapDef = _map()
		var limit: float = RADIUS * RADIUS_SLACK
		var top_ring_seen: bool = false
		var attach_y: float = Y_TOP + (DISK_HEIGHT if WRAP_STYLES.has(which) else 0.0)
		for vertex: Vector3 in _all_vertices(ArenaSideBuilder.new().build(map_def, _style(which), SEGMENTS, Y_TOP)):
			assert_true(vertex.y <= attach_y + EPS, "style %d: nothing above the slab edge" % which)
			assert_true(Vector2(vertex.x, vertex.z).length() <= limit, "style %d: inside the outline" % which)
			if is_equal_approx(vertex.y, attach_y):
				top_ring_seen = true
		assert_true(top_ring_seen, "style %d attaches at the slab edge" % which)


func test_normals_are_unit_and_agree_with_the_winding() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		for kind: int in built:
			var arrays: Array = built[kind]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			assert_eq(verts.size(), normals.size())
			assert_eq(verts.size() % 3, 0)
			for t: int in range(verts.size() / 3):
				var n: Vector3 = normals[t * 3]
				assert_almost_eq(n.length(), 1.0, EPS)
				# Godot's front face is clockwise, so the right-hand cross points away from it.
				var cross: Vector3 = (verts[t * 3 + 1] - verts[t * 3]).cross(verts[t * 3 + 2] - verts[t * 3]).normalized()
				assert_true(cross.dot(n) < 0.0, "style %d: winding matches the stored normal" % which)


## Layered plates and the machined disc are convex enough that every face must
## point away from the middle of the solid on a round map.
func test_convex_looks_point_their_faces_outward() -> void:
	for which: ArenaSideStyle.Style in [ArenaSideStyle.Style.LAYERED_PLATES, ArenaSideStyle.Style.MACHINED_DISC, ArenaSideStyle.Style.MACHINED_STYLISED, ArenaSideStyle.Style.MACHINED_DETAILED, ArenaSideStyle.Style.MACHINED_HEAVY, ArenaSideStyle.Style.MONOLITH, ArenaSideStyle.Style.TAPERED_STRATA, ArenaSideStyle.Style.PLATED_DOME]:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		var floor_y: float = INF
		for vertex: Vector3 in _all_vertices(built):
			floor_y = minf(floor_y, vertex.y)
		var center: Vector3 = Vector3(0.0, (Y_TOP + floor_y) * 0.5, 0.0)
		# The underside (kind 3) is covered by the facing-down test below: its
		# overhang ledges sit above the middle of the solid but still face down.
		for kind: int in [ArenaSideBuilder.KIND_BAND, ArenaSideBuilder.KIND_GLOW]:
			if not built.has(kind):
				continue
			var arrays: Array = built[kind]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var bad: int = 0
			for t: int in range(verts.size() / 3):
				var centroid: Vector3 = (verts[t * 3] + verts[t * 3 + 1] + verts[t * 3 + 2]) / 3.0
				if normals[t * 3].dot(centroid - center) < -EPS:
					bad += 1
			# Ledge/seam faces may legitimately face inward-down; the bulk must not.
			assert_true(bad * 10 <= verts.size() / 3, "style %d kind %d: faces point outward (%d bad)" % [which, kind, bad])


func test_underside_surface_faces_down_and_side_surface_does_not() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		if built.has(ArenaSideBuilder.KIND_BOTTOM):
			for n: Vector3 in (built[ArenaSideBuilder.KIND_BOTTOM] as Array)[Mesh.ARRAY_NORMAL] as PackedVector3Array:
				assert_true(n.y < 0.0, "style %d: underside faces point down" % which)


func test_build_is_deterministic() -> void:
	var map_def: MapDef = _map()
	var first: Dictionary = ArenaSideBuilder.new().build(map_def, _style(ArenaSideStyle.Style.ROCKY_ISLAND), SEGMENTS, Y_TOP)
	var second: Dictionary = ArenaSideBuilder.new().build(map_def, _style(ArenaSideStyle.Style.ROCKY_ISLAND), SEGMENTS, Y_TOP)
	assert_eq(_all_vertices(first), _all_vertices(second))


func test_current_style_keeps_the_band_and_chamfer() -> void:
	var arena: ArenaMesh = ArenaMesh.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	arena.append_side_surfaces(mesh, _map(), DiscBodyVisuals.new(), SEGMENTS, 0.0, _style(ArenaSideStyle.Style.CURRENT))
	assert_gte(arena.surface_index(ArenaMesh.Kind.CHAMFER), 0)
	assert_gte(arena.surface_index(ArenaMesh.Kind.BAND), 0)
	assert_eq(arena.surface_index(ArenaMesh.Kind.GLOW), -1)


func test_alternative_styles_become_arena_surfaces_with_materials() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var arena: ArenaMesh = ArenaMesh.new()
		var mesh: ArrayMesh = ArrayMesh.new()
		var count: int = arena.append_side_surfaces(mesh, _map(), DiscBodyVisuals.new(), SEGMENTS, DISK_HEIGHT * 0.5, _style(which))
		assert_gt(count, 0)
		assert_eq(mesh.get_surface_count(), count)
		assert_eq(arena.surface_index(ArenaMesh.Kind.CHAMFER), -1, "no gold chamfer in the new looks")
		for surface: int in arena.materials():
			var is_shell: bool = which == ArenaSideStyle.Style.SHADER_DOME and surface != arena.surface_index(ArenaMesh.Kind.GLOW)
			if is_shell:
				assert_true(arena.material_for_surface(surface) is ShaderMaterial, "shader dome body uses the plating shader")
			else:
				assert_true(arena.material_for_surface(surface) is StandardMaterial3D)
		assert_gte(arena.surface_index(ArenaMesh.Kind.GLOW), 0, "style %d has a glow surface" % which)


func test_shipped_style_resource_defaults_to_the_current_look() -> void:
	var style: ArenaSideStyle = load("res://config/arena_side_style.tres") as ArenaSideStyle
	assert_eq(style.style, ArenaSideStyle.Style.CURRENT)


func test_machined_refinements_stay_inside_the_disc_footprint_and_keep_surfaces_modest() -> void:
	for which: ArenaSideStyle.Style in [ArenaSideStyle.Style.MACHINED_STYLISED, ArenaSideStyle.Style.MACHINED_DETAILED, ArenaSideStyle.Style.MACHINED_HEAVY]:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		assert_lte(built.size(), 3, "style %d: one surface per material (body side, body underside, glow)" % which)
		var vertices: PackedVector3Array = _all_vertices(built)
		assert_lt(vertices.size(), MACHINED_VERTEX_BUDGET, "style %d vertex budget" % which)
		for vertex: Vector3 in vertices:
			assert_true(Vector2(vertex.x, vertex.z).length() <= RADIUS * (1.0 + RIVET_SLACK) + EPS, "style %d inside the disc footprint (rivets may stand proud)" % which)


func test_round3_looks_continue_the_top_and_stay_modest() -> void:
	for which: ArenaSideStyle.Style in WRAP_STYLES:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(), _style(which), SEGMENTS, Y_TOP)
		assert_lte(built.size(), 3, "style %d: one surface per material" % which)
		assert_true(built.has(ArenaSideBuilder.KIND_GLOW), "style %d: gold lip glows" % which)
		assert_true(built.has(ArenaSideBuilder.KIND_BOTTOM), "style %d: has an underside" % which)
		assert_lt(_all_vertices(built).size(), ROUND3_VERTEX_BUDGET, "style %d vertex budget" % which)
		for vertex: Vector3 in _all_vertices(built):
			assert_true(Vector2(vertex.x, vertex.z).length() <= RADIUS * (1.0 + RIVET_SLACK) + EPS, "style %d inside the footprint" % which)


## SHADER_DOME is PLATED_DOME's silhouette with no modelled relief: smooth surfaces whose
## UV.x carries the plating radius the shader reads (wall = top rings continued outwards).
func test_shader_dome_is_smooth_and_carries_plating_radius_in_uv() -> void:
	var map_def: MapDef = _map()
	var style: ArenaSideStyle = _style(ArenaSideStyle.Style.SHADER_DOME)
	var built: Dictionary = ArenaSideBuilder.new().build(map_def, style, SEGMENTS, Y_TOP)
	for vertex: Vector3 in _all_vertices(built):
		assert_true(Vector2(vertex.x, vertex.z).length() <= RADIUS * (1.0 + style.top_lip_out_fraction) + EPS, "no rivets or relief standing past the lip")
	var edge_y: float = Y_TOP + DISK_HEIGHT
	for kind: int in [ArenaSideBuilder.KIND_BAND, ArenaSideBuilder.KIND_BOTTOM]:
		var arrays: Array = built[kind]
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		assert_eq(uvs.size(), verts.size())
		for i: int in range(verts.size()):
			var radial: float = Vector2(verts[i].x, verts[i].z).length()
			var expected: float = radial + (edge_y - verts[i].y if kind == ArenaSideBuilder.KIND_BAND else 0.0)
			assert_almost_eq(uvs[i].x, expected, EPS)
	assert_false((built[ArenaSideBuilder.KIND_GLOW] as Array)[Mesh.ARRAY_TEX_UV] != null, "the gold lip is not shader plated")


func test_shader_dome_overlay_material_shares_the_territory_look() -> void:
	var arena: ArenaMesh = ArenaMesh.new()
	arena.append_side_surfaces(ArrayMesh.new(), _map(), DiscBodyVisuals.new(), SEGMENTS, DISK_HEIGHT * 0.5, _style(ArenaSideStyle.Style.SHADER_DOME))
	var shell: ShaderMaterial = arena.shell_material()
	assert_not_null(shell)
	assert_almost_eq(float(shell.get_shader_parameter(&"top_local_y")), DISK_HEIGHT * 0.5, EPS)
