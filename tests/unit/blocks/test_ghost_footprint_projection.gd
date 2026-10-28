extends GutTest
## the landing projection (footprint quad outline + decal mask)
## follows the union of the cell footprints, never the convex hull, for concave
## shapes at every rotation.

const SHAPES: Array[String] = ["plus5", "u5", "corner4", "arch5", "stair6", "L3", "T4", "S4"]
const YAW_STEPS: int = 4


func _ghost_with(shape_id: String) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/%s.tres" % shape_id))
	return ghost


## Whether ghost-local XZ `point` lies inside the footprint outline (even-odd over the silhouette loops; only
## outer-wound loops fill, as in the footprint mesh).
func _footprint_contains(ghost: GhostPreview, point: Vector2) -> bool:
	var loops: Array[PackedVector2Array] = GhostParts.silhouette(ghost).loops
	if loops.is_empty():
		return false
	var largest: PackedVector2Array = loops[0]
	for loop: PackedVector2Array in loops:
		if _area(loop) > _area(largest):
			largest = loop
	var outer_clockwise: bool = Geometry2D.is_polygon_clockwise(largest)
	var crossings: int = 0
	for loop: PackedVector2Array in loops:
		if Geometry2D.is_polygon_clockwise(loop) == outer_clockwise and Geometry2D.is_point_in_polygon(point, loop):
			crossings += 1
	return crossings % 2 == 1


## Total area of the triangles of the (single) footprint quad's mesh.
func _footprint_mesh_area(ghost: GhostPreview) -> float:
	var quads: Array[MeshInstance3D] = GhostParts.footprint_quads(ghost)
	assert_eq(quads.size(), 1, "fixture: one footprint quad")
	var mesh: ArrayMesh = quads[0].mesh as ArrayMesh
	assert_not_null(mesh, "fixture: the footprint quad has a mesh")
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var total: float = 0.0
	for i: int in range(0, indices.size(), 3):
		var p0: Vector2 = Vector2(verts[indices[i]].x, verts[indices[i]].z)
		var p1: Vector2 = Vector2(verts[indices[i + 1]].x, verts[indices[i + 1]].z)
		var p2: Vector2 = Vector2(verts[indices[i + 2]].x, verts[indices[i + 2]].z)
		total += absf((p1 - p0).cross(p2 - p0)) * 0.5
	return total


func _column_key(ghost: GhostPreview, cell: Vector3) -> Vector2i:
	var pivot: Vector3 = ghost.get_shape().bottom_center()
	var rotated: Vector3 = ghost.basis * ((cell - pivot) * ghost.tuning.cube_size)
	return Vector2i(roundi(rotated.x / ghost.tuning.cube_size * 2.0), roundi(rotated.z / ghost.tuning.cube_size * 2.0))


func _check_footprint(ghost: GhostPreview, label: String) -> void:
	var shape: BlockShape = ghost.get_shape()
	var expected: Dictionary = {}
	for cell: Vector3i in shape.cells:
		expected[_column_key(ghost, Vector3(cell))] = true
	var pivot: Vector3 = shape.bottom_center()
	var cube: float = ghost.tuning.cube_size
	for x: int in range(-1, 4):
		for z: int in range(-1, 4):
			for y: int in range(0, 3):
				var cell: Vector3 = Vector3(x, y, z)
				var rotated: Vector3 = ghost.basis * ((cell - pivot) * cube)
				var key: Vector2i = _column_key(ghost, cell)
				var inside: bool = _footprint_contains(ghost, Vector2(rotated.x, rotated.z))
				if y == 0 or shape.cells.has(Vector3i(x, y, z)):
					# Only test columns that hold a cell at this height, and
					# empty columns at y == 0 (a cell above an empty column
					# elsewhere would alias with another key).
					if shape.cells.has(Vector3i(x, y, z)):
						assert_true(inside, "%s: cell %s column must be in the footprint" % [label, cell])
					elif not expected.has(key):
						assert_false(inside, "%s: empty column %s must not be in the footprint" % [label, cell])


func test_footprint_matches_cells_for_four_yaws() -> void:
	for shape_id: String in SHAPES:
		var ghost: GhostPreview = _ghost_with(shape_id)
		for step: int in range(YAW_STEPS):
			ghost.free_quaternion = Quaternion(Vector3.UP, PI * 0.5 * step)
			ghost.set_orientation_index(0)
			ghost.update_placement(Vector3.ZERO)
			_check_footprint(ghost, "%s yaw%d" % [shape_id, step])


func test_plus5_footprint_is_not_its_convex_hull() -> void:
	var ghost: GhostPreview = _ghost_with("plus5")
	ghost.update_placement(Vector3.ZERO)
	var quads: Array[MeshInstance3D] = GhostParts.footprint_quads(ghost)
	assert_eq(quads.size(), 1)
	var hull_area: float = _area(Geometry2D.convex_hull(GhostParts.quad_points_world(quads[0])))
	var loops_area: float = 0.0
	for loop: PackedVector2Array in GhostParts.silhouette(ghost).loops:
		loops_area += _area(loop)
	assert_gt(loops_area, 0.0, "fixture: the silhouette has area")
	assert_lt(loops_area, hull_area * 0.9, "plus footprint must be the five cells, not its octagonal hull")
	assert_lt(_footprint_mesh_area(ghost), hull_area * 0.9, "the footprint quad itself is the five cells, not their hull")
	assert_almost_eq(_footprint_mesh_area(ghost), loops_area, 0.01, "the quad covers the silhouette")


func test_decal_mask_is_transparent_in_the_concave_notch() -> void:
	var ghost: GhostPreview = _ghost_with("u5")
	ghost.update_placement(Vector3(0.0, 3.0, 0.0))
	var texture: ImageTexture = GhostParts.decal(ghost).texture_albedo as ImageTexture
	assert_not_null(texture)
	var image: Image = texture.get_image()
	var solid: int = 0
	var clear: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.5:
				solid += 1
			else:
				clear += 1
	assert_gt(solid, 0)
	assert_gt(clear, 0, "u5's notch must be clear in the decal mask, not a solid rectangle")


func _area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in range(polygon.size()):
		var next: Vector2 = polygon[(i + 1) % polygon.size()]
		area += polygon[i].x * next.y - next.x * polygon[i].y
	return absf(area) * 0.5


func test_walls_stop_on_a_block_under_the_ghost() -> void:
	var ghost: GhostPreview = _ghost_with("cube")
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var floor_box: BoxShape3D = BoxShape3D.new()
	floor_box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child_autofree(floor_body)
	var tower: StaticBody3D = StaticBody3D.new()
	var tower_shape: CollisionShape3D = CollisionShape3D.new()
	var tower_box: BoxShape3D = BoxShape3D.new()
	tower_box.size = Vector3(4.0, 2.0, 4.0)
	tower_shape.shape = tower_box
	tower.add_child(tower_shape)
	tower.position = Vector3(0.0, 1.0, 0.0)
	add_child_autofree(tower)
	await get_tree().physics_frame
	await get_tree().physics_frame
	ghost.update_placement(Vector3(0.0, 4.0, 0.0))
	var lowest: float = INF
	for vertex: Vector3 in GhostParts.prism_vertices(ghost):
		lowest = minf(lowest, vertex.y)
	assert_almost_eq(lowest, 2.0, 0.05, "wall bottoms on the tower top (y=2), not the disc")


