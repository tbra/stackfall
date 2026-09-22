extends GutTest
## core/blocks/BlockMeshBuilder.gd is pure geometry (no scene tree): checks
## interior-face culling, vertex bounds relative to BlockShape.bottom_center(),
## and the per-(shape, cube_size, cube_margin) cache (Bontago-xtq.3).

const CUBE_SIZE: float = 1.0
const CUBE_MARGIN: float = 0.02


func before_each() -> void:
	BlockMeshBuilder.clear_cache()


func _make_shape(cells: Array[Vector3i]) -> BlockShape:
	var shape: BlockShape = BlockShape.new()
	shape.id = &"test_shape"
	shape.cells = cells
	return shape


func _surface_arrays(mesh: ArrayMesh) -> Array:
	assert_eq(mesh.get_surface_count(), 1, "the builder should emit exactly one surface.")
	return mesh.surface_get_arrays(0)


func test_a_single_cube_has_six_quads() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0)])
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	assert_not_null(mesh)
	var arrays: Array = _surface_arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	# 6 faces * 4 verts, 6 faces * 2 tris * 3 indices.
	assert_eq(vertices.size(), 24, "a lone cube shows all 6 faces (no neighbour hides any of them).")
	assert_eq(indices.size(), 36)


func test_a_two_cell_bar_hides_the_two_shared_interior_faces() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0), Vector3i(1, 0, 0)])
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	var arrays: Array = _surface_arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 12 faces total minus the 2 that face each other = 10 quads = 40 verts.
	assert_eq(vertices.size(), 40)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 60)


func test_an_l_of_three_cells_hides_the_four_shared_interior_faces() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)])
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	var arrays: Array = _surface_arrays(mesh)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# 18 faces total; each of the 2 touching pairs hides 2 faces (1 each side).
	# No two of these three cells are neighbours of each other besides that
	# one adjacent pair each along X and Y from the corner cell, so 18 - 4 = 14
	# quads = 56 verts.
	assert_eq(vertices.size(), 56)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 84)


func test_vertices_lie_within_expected_bounds_relative_to_bottom_center() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 1, 0)])
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	var vertices: PackedVector3Array = (_surface_arrays(mesh)[Mesh.ARRAY_VERTEX] as PackedVector3Array)
	var pivot: Vector3 = shape.bottom_center()
	var half: float = CUBE_SIZE * 0.5
	# Every cell's own AABB, in the same (cell - pivot) * cube_size space the
	## builder works in, expanded by half a cube on every side.
	var expected_min: Vector3 = Vector3.INF
	var expected_max: Vector3 = -Vector3.INF
	for cell: Vector3i in shape.cells:
		var center: Vector3 = (Vector3(cell) - pivot) * CUBE_SIZE
		expected_min = expected_min.min(center - Vector3.ONE * half)
		expected_max = expected_max.max(center + Vector3.ONE * half)
	for vertex: Vector3 in vertices:
		assert_true(
			vertex.x >= expected_min.x - 0.0001 and vertex.x <= expected_max.x + 0.0001,
			"vertex %s out of expected X bounds [%s, %s]" % [vertex, expected_min.x, expected_max.x]
		)
		assert_true(
			vertex.y >= expected_min.y - 0.0001 and vertex.y <= expected_max.y + 0.0001,
			"vertex %s out of expected Y bounds [%s, %s]" % [vertex, expected_min.y, expected_max.y]
		)
		assert_true(
			vertex.z >= expected_min.z - 0.0001 and vertex.z <= expected_max.z + 0.0001,
			"vertex %s out of expected Z bounds [%s, %s]" % [vertex, expected_min.z, expected_max.z]
		)


func test_cache_returns_the_same_instance_for_the_same_shape_and_tuning() -> void:
	var shape: BlockShape = load("res://config/blocks/bar4.tres")
	var mesh_a: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	var mesh_b: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	assert_eq(mesh_a, mesh_b, "the same (shape, cube_size, cube_margin) should share one cached ArrayMesh.")


func test_a_different_cube_size_gets_its_own_cached_mesh() -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var mesh_a: ArrayMesh = BlockMeshBuilder.build_mesh(shape, 1.0, CUBE_MARGIN)
	var mesh_b: ArrayMesh = BlockMeshBuilder.build_mesh(shape, 2.0, CUBE_MARGIN)
	assert_ne(mesh_a, mesh_b)


func test_sloped_cells_fall_back_to_null_so_the_caller_can_use_its_own_path() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0)])
	shape.sloped_cells = [Vector3i(0, 0, 0)]
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	assert_null(mesh, "a sloped cell has no wedge face in this builder; the caller must fall back.")


func test_a_custom_shape_mesh_override_falls_back_to_null_too() -> void:
	var shape: BlockShape = _make_shape([Vector3i(0, 0, 0)])
	shape.mesh = BoxMesh.new()
	var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
	assert_null(mesh)
