extends GutTest
## Bontago-1pi.60: every shipped map must build its own visible mesh and
## collider, not the default disc. Compares Field's collision trimesh, the
## TerritoryOverlay's visible mesh and the MapDef's cell coverage.

const FIELD_SCENE: PackedScene = preload("res://game/Field.tscn")
const SHAPES: Array[int] = [0, 1, 2, 3, 4]
const SIZES: Array[int] = [0, 1, 2]
## Slack (m) on AABB comparisons: one cell plus float noise.
const AABB_SLACK: float = 0.01


func _field_for(map_def: MapDef) -> Field:
	var field: Field = FIELD_SCENE.instantiate() as Field
	add_child_autofree(field)
	field.rebuild_for_map(map_def)
	return field


func _top_cell_aabb(map_def: MapDef) -> Rect2:
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	var rect: Rect2 = Rect2()
	var first: bool = true
	for cell: int in grid.in_disk_cells():
		var c: Vector2i = grid.cell_coords(cell)
		var lo: Vector2 = Vector2(c) * grid.cell_size - Vector2(grid.half_extent, grid.half_extent)
		var r: Rect2 = Rect2(lo, Vector2(grid.cell_size, grid.cell_size))
		rect = r if first else rect.merge(r)
		first = false
	return rect


func test_collision_and_visible_mesh_match_map_def_for_every_shipped_map() -> void:
	for shape: int in SHAPES:
		for size: int in SIZES:
			var map_def: MapDef = MapDef.for_variant_and_size(shape, size as MapDef.MapSize)
			var label: String = "%s/%d" % [str(map_def.id), size]
			var field: Field = _field_for(map_def)
			var expected: Rect2 = _top_cell_aabb(map_def)

			var faces: PackedVector3Array = field._disk_shape.get_faces()
			assert_gt(faces.size(), 0, "%s: collider has faces" % label)
			var lo: Vector2 = Vector2(INF, INF)
			var hi: Vector2 = Vector2(-INF, -INF)
			for v: Vector3 in faces:
				lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
				hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
			assert_almost_eq(lo.x, expected.position.x, AABB_SLACK, "%s collider min x" % label)
			assert_almost_eq(hi.y, expected.end.y, AABB_SLACK, "%s collider max z" % label)
			assert_eq(field.cell_count(), field.grid().in_disk_cell_count(), "%s cells" % label)

			var mesh: Mesh = field.overlay().mesh
			assert_not_null(mesh, "%s: overlay mesh" % label)
			var box: AABB = mesh.get_aabb()
			if DiskShapeMesh.needs_cell_mesh(map_def):
				assert_almost_eq(box.position.x, expected.position.x, AABB_SLACK, "%s visible min x" % label)
				assert_almost_eq(box.end.z, expected.end.y, AABB_SLACK, "%s visible max z" % label)
				assert_almost_eq(box.size.y, map_def.disk_height, AABB_SLACK, "%s visible height" % label)
				# Top faces: two triangles per cell, so the visible mesh is not a disc.
				var tris: int = (mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() / 3
				assert_gte(tris, 2 * field.cell_count(), "%s visible triangles cover every cell" % label)
			else:
				assert_true(mesh is CylinderMesh, "%s: round/oval keep the cylinder" % label)


func test_ring_visible_mesh_has_no_top_face_over_the_hole() -> void:
	var map_def: MapDef = MapDef.for_variant_and_size(MapDef.MapShape.RING, MapDef.MapSize.MEDIUM)
	var mesh: ArrayMesh = DiskShapeMesh.build(map_def, map_def.disk_height)
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var top_y: float = map_def.disk_height * 0.5
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size, map_def.shape_test())
	for i: int in range(0, verts.size(), 3):
		if not (is_equal_approx(verts[i].y, top_y) and is_equal_approx(verts[i + 1].y, top_y) and is_equal_approx(verts[i + 2].y, top_y)):
			continue
		var centroid: Vector3 = (verts[i] + verts[i + 1] + verts[i + 2]) / 3.0
		var cell: Vector2i = grid.world_to_cell(Vector2(centroid.x, centroid.z))
		assert_true(grid.is_in_disk(cell.x, cell.y), "top triangle sits on an in-shape cell")
	# Winding: every top triangle faces up.
	var checked: int = 0
	for i: int in range(0, verts.size(), 3):
		if is_equal_approx(verts[i].y, top_y) and is_equal_approx(verts[i + 1].y, top_y) and is_equal_approx(verts[i + 2].y, top_y):
			var n: Vector3 = (verts[i + 2] - verts[i]).cross(verts[i + 1] - verts[i])
			assert_gt(n.y, 0.0, "top triangle winds clockwise from above (front face up)")
			checked += 1
	assert_gt(checked, 0)
