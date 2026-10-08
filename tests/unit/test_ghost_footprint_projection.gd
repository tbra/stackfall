extends GutTest
## Bontago-1pi.132: the landing projection (footprint quad outline + decal mask)
## follows the union of the cell footprints, never the convex hull, for concave
## shapes at every rotation.

const SHAPES: Array[String] = ["plus5", "u5", "corner4", "arch5", "stair6", "L3", "T4", "S4"]
const YAW_STEPS: int = 4


func _ghost_with(shape_id: String) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/%s.tres" % shape_id))
	return ghost


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
				var inside: bool = ghost.footprint_contains_local(Vector2(rotated.x, rotated.z))
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
			ghost.update_placement(Vector3.ZERO, Vector3.UP)
			_check_footprint(ghost, "%s yaw%d" % [shape_id, step])


func test_footprint_matches_cells_after_pitch_flip() -> void:
	for shape_id: String in SHAPES:
		var ghost: GhostPreview = _ghost_with(shape_id)
		ghost.free_quaternion = Quaternion(Vector3.RIGHT, PI)
		ghost.set_orientation_index(0)
		ghost.update_placement(Vector3.ZERO, Vector3.UP)
		_check_footprint(ghost, "%s pitch flip" % shape_id)


func test_plus5_footprint_is_not_its_convex_hull() -> void:
	var ghost: GhostPreview = _ghost_with("plus5")
	ghost.update_placement(Vector3.ZERO, Vector3.UP)
	var hull_area: float = _area(ghost.footprint_polygon_world(0))
	var loops_area: float = 0.0
	for loop: PackedVector2Array in ghost.footprint_loops_local():
		loops_area += _area(loop)
	assert_lt(loops_area, hull_area * 0.9, "plus footprint must be the five cells, not its octagonal hull")
	var mesh: ArrayMesh = ghost._footprint_quads[0].mesh as ArrayMesh
	assert_not_null(mesh)


func test_decal_mask_is_transparent_in_the_concave_notch() -> void:
	var ghost: GhostPreview = _ghost_with("u5")
	ghost.update_placement(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	ghost.global_position.y = 3.0
	ghost._update_footprint()
	var texture: ImageTexture = ghost._block_projection_decal.texture_albedo as ImageTexture
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
	ghost.global_position = Vector3(0.0, 5.0, 0.0)
	ghost._update_footprint()
	var lowest: float = INF
	for vertex: Vector3 in ghost.projection_mesh_vertices_world():
		lowest = minf(lowest, vertex.y)
	assert_almost_eq(lowest, 2.0, 0.05, "wall bottoms on the tower top (y=2), not the disc")
