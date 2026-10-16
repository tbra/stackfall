extends GutTest
## game/field/ArenaSideBuilder.gd + the ArenaSideStyle switch in game/field/ArenaMesh.gd
## : every alternative side/underside look is static CPU
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


