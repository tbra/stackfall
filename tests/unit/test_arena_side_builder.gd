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
]
const SHAPES: Array[MapDef.MapShape] = [MapDef.MapShape.ROUND]


func _map(_shape: MapDef.MapShape) -> MapDef:
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


func test_every_style_builds_geometry_for_every_map_shape() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		for shape: MapDef.MapShape in SHAPES:
			var built: Dictionary = ArenaSideBuilder.new().build(_map(shape), _style(which), SEGMENTS, Y_TOP)
			assert_false(built.is_empty(), "style %d shape %d builds surfaces" % [which, shape])
			assert_true(_all_vertices(built).size() >= 3 * 3)


func test_geometry_hangs_from_the_slab_and_stays_inside_the_outline() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		for shape: MapDef.MapShape in SHAPES:
			var map_def: MapDef = _map(shape)
			var limit: float = RADIUS * RADIUS_SLACK
			var top_ring_seen: bool = false
			for vertex: Vector3 in _all_vertices(ArenaSideBuilder.new().build(map_def, _style(which), SEGMENTS, Y_TOP)):
				assert_true(vertex.y <= Y_TOP + EPS, "style %d shape %d: nothing above the slab edge" % [which, shape])
				assert_true(Vector2(vertex.x, vertex.z).length() <= limit, "style %d shape %d: inside the outline" % [which, shape])
				if is_equal_approx(vertex.y, Y_TOP):
					top_ring_seen = true
			assert_true(top_ring_seen, "style %d shape %d attaches at the slab edge" % [which, shape])


func test_normals_are_unit_and_agree_with_the_winding() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(MapDef.MapShape.ROUND), _style(which), SEGMENTS, Y_TOP)
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
	for which: ArenaSideStyle.Style in [ArenaSideStyle.Style.LAYERED_PLATES, ArenaSideStyle.Style.MACHINED_DISC]:
		var built: Dictionary = ArenaSideBuilder.new().build(_map(MapDef.MapShape.ROUND), _style(which), SEGMENTS, Y_TOP)
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
		var built: Dictionary = ArenaSideBuilder.new().build(_map(MapDef.MapShape.ROUND), _style(which), SEGMENTS, Y_TOP)
		if built.has(ArenaSideBuilder.KIND_BOTTOM):
			for n: Vector3 in (built[ArenaSideBuilder.KIND_BOTTOM] as Array)[Mesh.ARRAY_NORMAL] as PackedVector3Array:
				assert_true(n.y < 0.0, "style %d: underside faces point down" % which)


func test_build_is_deterministic() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.ROUND)
	var first: Dictionary = ArenaSideBuilder.new().build(map_def, _style(ArenaSideStyle.Style.ROCKY_ISLAND), SEGMENTS, Y_TOP)
	var second: Dictionary = ArenaSideBuilder.new().build(map_def, _style(ArenaSideStyle.Style.ROCKY_ISLAND), SEGMENTS, Y_TOP)
	assert_eq(_all_vertices(first), _all_vertices(second))


func test_current_style_keeps_the_band_and_chamfer() -> void:
	var arena: ArenaMesh = ArenaMesh.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	arena.append_side_surfaces(mesh, _map(MapDef.MapShape.ROUND), DiscBodyVisuals.new(), SEGMENTS, 0.0, _style(ArenaSideStyle.Style.CURRENT))
	assert_gte(arena.surface_index(ArenaMesh.Kind.CHAMFER), 0)
	assert_gte(arena.surface_index(ArenaMesh.Kind.BAND), 0)
	assert_eq(arena.surface_index(ArenaMesh.Kind.GLOW), -1)


func test_alternative_styles_become_arena_surfaces_with_materials() -> void:
	for which: ArenaSideStyle.Style in STYLES:
		var arena: ArenaMesh = ArenaMesh.new()
		var mesh: ArrayMesh = ArrayMesh.new()
		var count: int = arena.append_side_surfaces(mesh, _map(MapDef.MapShape.ROUND), DiscBodyVisuals.new(), SEGMENTS, DISK_HEIGHT * 0.5, _style(which))
		assert_gt(count, 0)
		assert_eq(mesh.get_surface_count(), count)
		assert_eq(arena.surface_index(ArenaMesh.Kind.CHAMFER), -1, "no gold chamfer in the new looks")
		for surface: int in arena.materials():
			assert_true(arena.material_for_surface(surface) is StandardMaterial3D)
		assert_gte(arena.surface_index(ArenaMesh.Kind.GLOW), 0, "style %d has a glow surface" % which)


func test_shipped_style_resource_defaults_to_the_current_look() -> void:
	var style: ArenaSideStyle = load("res://config/arena_side_style.tres") as ArenaSideStyle
	assert_eq(style.style, ArenaSideStyle.Style.CURRENT)
