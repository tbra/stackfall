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


## Bontago-xtq.5 (owner screenshot, docs/solid-blocks-issue.png: placed blocks
## render inside-out -- faces missing/looks hollow). Rather than trust the
## file's own comment claiming CCW-from-outside is Godot's front-face
## convention, derive the convention empirically from a Godot primitive
## (BoxMesh) and require every BlockMeshBuilder triangle to wind the same way.
func _box_mesh_front_face_sign() -> int:
	var box_mesh: BoxMesh = BoxMesh.new()
	var arrays: Array = box_mesh.get_mesh_arrays()
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var reference_sign: int = 0
	var tri_count: int = indices.size() / 3
	for t: int in range(tri_count):
		var ia: int = indices[t * 3]
		var ib: int = indices[t * 3 + 1]
		var ic: int = indices[t * 3 + 2]
		var a: Vector3 = vertices[ia]
		var b: Vector3 = vertices[ib]
		var c: Vector3 = vertices[ic]
		var stored_normal: Vector3 = normals[ia]
		var geom_normal: Vector3 = (b - a).cross(c - a)
		var this_sign: int = signi(geom_normal.dot(stored_normal))
		assert_ne(this_sign, 0, "BoxMesh triangle %d has a degenerate/zero geometric normal." % t)
		if reference_sign == 0:
			reference_sign = this_sign
		else:
			assert_eq(this_sign, reference_sign, "BoxMesh itself should wind every triangle the same way.")
	return reference_sign


## The cell's own centre in the same (cell - pivot) * cube_size space the
## builder works in, i.e. the same computation as
## test_vertices_lie_within_expected_bounds_relative_to_bottom_center() above.
func _cell_centers(shape: BlockShape) -> Array[Vector3]:
	var pivot: Vector3 = shape.bottom_center()
	var centers: Array[Vector3] = []
	for cell: Vector3i in shape.cells:
		centers.append((Vector3(cell) - pivot) * CUBE_SIZE)
	return centers


func test_triangle_winding_and_normal_direction_match_godot_convention_for_every_shipped_shape() -> void:
	var reference_sign: int = _box_mesh_front_face_sign()
	var shape_paths: Array[String] = [
		"res://config/blocks/cube.tres",
		"res://config/blocks/bar3.tres",
		"res://config/blocks/bar4.tres",
		"res://config/blocks/domino.tres",
		"res://config/blocks/L3.tres",
		"res://config/blocks/L4.tres",
		"res://config/blocks/pillar.tres",
		"res://config/blocks/S4.tres",
		"res://config/blocks/slab6.tres",
		"res://config/blocks/square4.tres",
		"res://config/blocks/T4.tres",
	]
	var half: float = CUBE_SIZE * 0.5
	var checked_triangles: int = 0
	var wrong_winding: int = 0
	var checked_quads: int = 0
	var wrong_normal_side: int = 0
	var first_wrong_winding_message: String = ""
	var first_wrong_normal_side_message: String = ""
	for path: String in shape_paths:
		var shape: BlockShape = load(path)
		var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, CUBE_SIZE, CUBE_MARGIN)
		assert_not_null(mesh, "%s should build a mesh (no sloped_cells/mesh override)." % path)
		var arrays: Array = _surface_arrays(mesh)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var cell_centers: Array[Vector3] = _cell_centers(shape)
		var tri_count: int = indices.size() / 3

		# (a) per triangle: geometric normal (b-a)x(c-a) must be parallel to
		# the stored vertex normal with the same sign as Godot's own BoxMesh
		# front-face convention.
		# DECISION (tests/unit/test_block_mesh_builder.gd): alignment is
		# checked by dot-product tolerance, not exact Vector3 equality.
		# Godot's ArrayMesh quantizes stored normals by default
		# (add_surface_from_arrays' normal compression), so a straight
		# axis-aligned normal like (1, 0, 0) reads back as e.g.
		# (1.0, 0.0, -0.000015) -- an exact-equality check flagged every
		# correctly-wound triangle as wrong. The 0.001 tolerance absorbs that
		# ~1e-5 quantization noise without masking an actual reversed winding
		# (whose alignment would be near -reference_sign, off by ~2.0).
		for t: int in range(tri_count):
			var ia: int = indices[t * 3]
			var ib: int = indices[t * 3 + 1]
			var ic: int = indices[t * 3 + 2]
			var a: Vector3 = vertices[ia]
			var b: Vector3 = vertices[ib]
			var c: Vector3 = vertices[ic]
			var stored_normal: Vector3 = normals[ia]
			var geom_normal: Vector3 = (b - a).cross(c - a)
			checked_triangles += 1

			var this_sign: int = signi(geom_normal.dot(stored_normal))
			var alignment: float = geom_normal.normalized().dot(stored_normal.normalized())
			var is_parallel: bool = absf(alignment - float(reference_sign)) < 0.001
			if this_sign != reference_sign or not is_parallel:
				wrong_winding += 1
				if first_wrong_winding_message == "":
					first_wrong_winding_message = "%s triangle %d winds opposite to Godot's own BoxMesh front-face convention (inside-out face)." % [path, t]

		# (b) per quad (_append_face's own doc comment: "one quad (4 vertices,
		# 2 triangles)" appended in order): the stored normal must point away
		# from the cell centre it belongs to, not into it.
		var quad_count: int = vertices.size() / 4
		for q: int in range(quad_count):
			var v0: Vector3 = vertices[q * 4]
			var v1: Vector3 = vertices[q * 4 + 1]
			var v2: Vector3 = vertices[q * 4 + 2]
			var v3: Vector3 = vertices[q * 4 + 3]
			var stored_normal: Vector3 = normals[q * 4]
			var quad_center: Vector3 = (v0 + v1 + v2 + v3) / 4.0
			var candidate_cell_center: Vector3 = quad_center - stored_normal * half
			var nearest_dist: float = INF
			for cell_center: Vector3 in cell_centers:
				nearest_dist = minf(nearest_dist, cell_center.distance_to(candidate_cell_center))
			assert_lt(nearest_dist, 0.001, "%s quad %d's face centre isn't half a cube from any cell centre along its own normal." % [path, q])
			checked_quads += 1
			if stored_normal.dot(quad_center - candidate_cell_center) <= 0.0:
				wrong_normal_side += 1
				if first_wrong_normal_side_message == "":
					first_wrong_normal_side_message = "%s quad %d has a stored normal pointing into its own cell." % [path, q]

	assert_gt(checked_triangles, 0, "sanity: shapes should produce triangles to check.")
	assert_eq(wrong_winding, 0, "%d/%d triangles wind opposite to Godot's front-face convention. First: %s" % [wrong_winding, checked_triangles, first_wrong_winding_message])
	assert_eq(wrong_normal_side, 0, "%d/%d quads have a stored normal pointing into their own cell. First: %s" % [wrong_normal_side, checked_quads, first_wrong_normal_side_message])
