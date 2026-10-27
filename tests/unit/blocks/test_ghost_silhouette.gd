extends GutTest
## GhostSilhouette: the pure footprint geometry of a held shape. build() turns block meshes at an
## offset and a rotation into outline loops (the shape's true top-down union, never its convex hull),
## wall pieces with their underside heights, and inside probes; rasterize_mask() fills the outer
## loops into an alpha mask.

const TUNING: PhysicsTuning = preload("res://config/physics/physics_tuning.tres")
const EDGE_TOLERANCE: float = 0.001
const AREA_TOLERANCE: float = 0.001
const UNDERSIDE_TOLERANCE: float = 0.015
const PROBE_NUDGE: float = 0.004
const PROBE_REACH: float = 0.05
const MASK_PPM: float = 8.0
const MASK_MAX: int = 96
const SOLID_ALPHA: float = 0.5


func _shape(shape_id: String) -> BlockShape:
	return load("res://config/blocks/%s.tres" % shape_id) as BlockShape


func _mesh(shape: BlockShape) -> Mesh:
	return BlockMeshBuilder.build_mesh(shape, TUNING.cube_size, TUNING.cube_margin)


func _build(shape_id: String, basis: Basis) -> GhostSilhouette.Result:
	var meshes: Array[Mesh] = [_mesh(_shape(shape_id))]
	return GhostSilhouette.build(meshes, PackedVector3Array([Vector3.ZERO]), basis)


func _columns(shape: BlockShape) -> int:
	var seen: Dictionary = {}
	for cell: Vector3i in shape.cells:
		seen[Vector2i(cell.x, cell.z)] = true
	return seen.size()


func _area(polygon: PackedVector2Array) -> float:
	var area: float = 0.0
	for i: int in range(polygon.size()):
		var next: Vector2 = polygon[(i + 1) % polygon.size()]
		area += polygon[i].x * next.y - next.x * polygon[i].y
	return absf(area) * 0.5


func _loops_area(loops: Array[PackedVector2Array]) -> float:
	var total: float = 0.0
	for loop: PackedVector2Array in loops:
		total += _area(loop)
	return total


func _perimeter(loops: Array[PackedVector2Array]) -> float:
	var total: float = 0.0
	for loop: PackedVector2Array in loops:
		for i: int in range(loop.size()):
			total += loop[i].distance_to(loop[(i + 1) % loop.size()])
	return total


func _bbox(loops: Array[PackedVector2Array]) -> Rect2:
	var low: Vector2 = Vector2(INF, INF)
	var high: Vector2 = Vector2(-INF, -INF)
	for loop: PackedVector2Array in loops:
		for point: Vector2 in loop:
			low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
			high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	return Rect2(low, high - low)


func _on_outline(point: Vector2, loops: Array[PackedVector2Array]) -> bool:
	for loop: PackedVector2Array in loops:
		for i: int in range(loop.size()):
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, loop[i], loop[(i + 1) % loop.size()])
			if closest.distance_to(point) < EDGE_TOLERANCE:
				return true
	return false


func _inside(point: Vector2, loops: Array[PackedVector2Array]) -> bool:
	for loop: PackedVector2Array in loops:
		if Geometry2D.is_point_in_polygon(point, loop):
			return true
	return false


func _wall_length(result: GhostSilhouette.Result) -> float:
	var total: float = 0.0
	for i: int in range(0, result.wall_segments.size(), 2):
		total += result.wall_segments[i].distance_to(result.wall_segments[i + 1])
	return total


## The lowest rotated mesh surface straight over `point` (INF when none covers it), own barycentric math.
func _underside_at(mesh: Mesh, basis: Basis, point: Vector2) -> float:
	var arrays: Array = mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lowest: float = INF
	for i: int in range(0, indices.size(), 3):
		var t0: Vector3 = basis * verts[indices[i]]
		var t1: Vector3 = basis * verts[indices[i + 1]]
		var t2: Vector3 = basis * verts[indices[i + 2]]
		var p0: Vector2 = Vector2(t0.x, t0.z)
		var e1: Vector2 = Vector2(t1.x, t1.z) - p0
		var e2: Vector2 = Vector2(t2.x, t2.z) - p0
		var denominator: float = e1.x * e2.y - e2.x * e1.y
		if absf(denominator) < 1e-8:
			continue
		var d: Vector2 = point - p0
		var w1: float = (d.x * e2.y - e2.x * d.y) / denominator
		var w2: float = (e1.x * d.y - d.x * e1.y) / denominator
		if w1 < 0.0 or w2 < 0.0 or w1 + w2 > 1.0:
			continue
		lowest = minf(lowest, t0.y + w1 * (t1.y - t0.y) + w2 * (t2.y - t0.y))
	return lowest


# --- outline loops ---------------------------------------------------------

func test_cube_is_one_unit_square_loop() -> void:
	var result: GhostSilhouette.Result = _build("cube", Basis.IDENTITY)
	assert_eq(result.loops.size(), 1, "a cube has one outline loop")
	assert_almost_eq(_loops_area(result.loops), TUNING.cube_size * TUNING.cube_size, AREA_TOLERANCE)
	var box: Rect2 = _bbox(result.loops)
	assert_almost_eq(box.size.x, TUNING.cube_size, EDGE_TOLERANCE)
	assert_almost_eq(box.size.y, TUNING.cube_size, EDGE_TOLERANCE)


func test_loops_follow_the_cell_union_not_the_convex_hull_for_every_yaw() -> void:
	for shape_id: String in ["L3", "plus5", "u5", "corner4", "arch5", "stair6", "T4", "S4"]:
		var shape: BlockShape = _shape(shape_id)
		var expected: float = float(_columns(shape)) * TUNING.cube_size * TUNING.cube_size
		for step: int in range(8):
			var basis: Basis = Basis(Vector3.UP, PI * 0.25 * step)
			var result: GhostSilhouette.Result = _build(shape_id, basis)
			assert_almost_eq(
				_loops_area(result.loops), expected, AREA_TOLERANCE,
				"%s yaw step %d: outline area is the union of the cell columns" % [shape_id, step]
			)


func test_concave_shapes_keep_one_hole_free_outer_loop() -> void:
	for shape_id: String in ["plus5", "u5", "L3"]:
		for step: int in range(4):
			var result: GhostSilhouette.Result = _build(shape_id, Basis(Vector3.UP, PI * 0.5 * step))
			assert_eq(result.loops.size(), 1, "%s yaw step %d: one loop, no hole, no fragments" % [shape_id, step])


func test_u5_notch_is_outside_every_loop() -> void:
	var result: GhostSilhouette.Result = _build("u5", Basis.IDENTITY)
	# u5 cells: (0,0,0) (2,0,0) (0,0,1) (1,0,1) (2,0,1); the notch is column (1,0,0).
	var shape: BlockShape = _shape("u5")
	var pivot: Vector3 = shape.bottom_center()
	var notch: Vector2 = Vector2((1.0 - pivot.x) * TUNING.cube_size, (0.0 - pivot.z) * TUNING.cube_size)
	var arm: Vector2 = Vector2((0.0 - pivot.x) * TUNING.cube_size, (0.0 - pivot.z) * TUNING.cube_size)
	assert_false(_inside(notch, result.loops), "the concave notch is not covered")
	assert_true(_inside(arm, result.loops), "an arm cell is covered")


func test_pitched_bar_is_still_a_single_outer_loop() -> void:
	var result: GhostSilhouette.Result = _build("bar4", Basis(Vector3.RIGHT, deg_to_rad(30.0)))
	assert_eq(result.loops.size(), 1, "overlapping rotated cell quads merge to one loop")


func test_rotation_about_yaw_keeps_area_and_turns_the_bounding_box() -> void:
	var flat: GhostSilhouette.Result = _build("bar4", Basis.IDENTITY)
	var turned: GhostSilhouette.Result = _build("bar4", Basis(Vector3.UP, PI * 0.5))
	var flat_box: Rect2 = _bbox(flat.loops)
	var turned_box: Rect2 = _bbox(turned.loops)
	assert_almost_eq(turned_box.size.x, flat_box.size.y, EDGE_TOLERANCE)
	assert_almost_eq(turned_box.size.y, flat_box.size.x, EDGE_TOLERANCE)
	assert_almost_eq(_loops_area(turned.loops), _loops_area(flat.loops), AREA_TOLERANCE)


func test_offsets_place_each_mesh_and_touching_meshes_merge() -> void:
	var cube: Mesh = _mesh(_shape("cube"))
	var meshes: Array[Mesh] = [cube, cube]
	var step: float = TUNING.cube_size
	var touching: GhostSilhouette.Result = GhostSilhouette.build(
		meshes, PackedVector3Array([Vector3.ZERO, Vector3(step, 0.0, 0.0)]), Basis.IDENTITY
	)
	assert_eq(touching.loops.size(), 1, "two cubes side by side are one outline")
	assert_almost_eq(_loops_area(touching.loops), 2.0 * step * step, AREA_TOLERANCE)
	assert_almost_eq(_bbox(touching.loops).size.x, 2.0 * step, EDGE_TOLERANCE)
	var apart: GhostSilhouette.Result = GhostSilhouette.build(
		meshes, PackedVector3Array([Vector3.ZERO, Vector3(5.0 * step, 0.0, 0.0)]), Basis.IDENTITY
	)
	assert_eq(apart.loops.size(), 2, "cubes with a gap stay two outlines")
	assert_almost_eq(_loops_area(apart.loops), 2.0 * step * step, AREA_TOLERANCE)


func test_unindexed_surface_uses_sequential_triangles() -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var result: GhostSilhouette.Result = _build_mesh(mesh)
	assert_eq(result.loops.size(), 1, "the unindexed triangle still yields an outline")
	assert_almost_eq(_loops_area(result.loops), 0.5, AREA_TOLERANCE)


func test_no_meshes_gives_an_empty_result() -> void:
	var meshes: Array[Mesh] = []
	var result: GhostSilhouette.Result = GhostSilhouette.build(meshes, PackedVector3Array(), Basis.IDENTITY)
	assert_not_null(result)
	assert_eq(result.loops.size(), 0)
	assert_eq(result.wall_segments.size(), 0)
	assert_eq(result.wall_heights.size(), 0)
	assert_eq(result.probes.size(), 0)


# --- wall pieces ------------------------------------------------------------

func test_wall_arrays_are_parallel_one_probe_and_height_pair_per_segment_pair() -> void:
	for shape_id: String in ["cube", "S4", "plus5"]:
		var result: GhostSilhouette.Result = _build(shape_id, Basis(Vector3.RIGHT, deg_to_rad(20.0)))
		assert_gt(result.wall_heights.size(), 0, "%s: has wall pieces" % shape_id)
		assert_eq(result.wall_segments.size(), result.wall_heights.size() * 2, "%s: two points per piece" % shape_id)
		assert_eq(result.probes.size(), result.wall_heights.size(), "%s: one probe per piece" % shape_id)


func test_cube_walls_tile_the_perimeter_at_the_cube_underside() -> void:
	var result: GhostSilhouette.Result = _build("cube", Basis.IDENTITY)
	assert_almost_eq(_wall_length(result), 4.0 * TUNING.cube_size, AREA_TOLERANCE, "walls cover the perimeter once")
	var underside: float = _mesh(_shape("cube")).get_aabb().position.y
	for heights: Vector2 in result.wall_heights:
		assert_almost_eq(heights.x, underside, EDGE_TOLERANCE, "flat underside at a")
		assert_almost_eq(heights.y, underside, EDGE_TOLERANCE, "flat underside at b")


func test_walls_lie_on_the_outline_and_cover_it_exactly_once() -> void:
	for shape_id: String in ["L3", "plus5", "S4", "bar4"]:
		for basis: Basis in [Basis.IDENTITY, Basis(Vector3.RIGHT, deg_to_rad(30.0)), Basis(Vector3.UP, deg_to_rad(45.0))]:
			var result: GhostSilhouette.Result = _build(shape_id, basis)
			for point: Vector2 in result.wall_segments:
				assert_true(_on_outline(point, result.loops), "%s: wall end %s is on the outline" % [shape_id, point])
			assert_almost_eq(
				_wall_length(result), _perimeter(result.loops), AREA_TOLERANCE,
				"%s: walls cover the outline perimeter once" % shape_id
			)


func test_wall_heights_follow_the_shapes_own_underside() -> void:
	for roll: float in [0.0, 30.0]:
		var basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(roll))
		for shape_id: String in ["bar4", "S4"]:
			var result: GhostSilhouette.Result = _build(shape_id, basis)
			var mesh: Mesh = _mesh(_shape(shape_id))
			assert_gt(result.wall_heights.size(), 0)
			for i: int in range(result.wall_heights.size()):
				var a: Vector2 = result.wall_segments[i * 2]
				var b: Vector2 = result.wall_segments[i * 2 + 1]
				if a.distance_to(b) < 0.01:
					continue
				var side: Vector2 = (b - a).normalized().orthogonal()
				for t: float in [0.25, 0.5, 0.75]:
					var point: Vector2 = a.lerp(b, t)
					var expected: float = _underside_at(mesh, basis, point + side * PROBE_NUDGE)
					if expected == INF:
						expected = _underside_at(mesh, basis, point - side * PROBE_NUDGE)
					assert_true(expected != INF, "%s roll %.0f: shape covers wall point %s" % [shape_id, roll, point])
					var actual: float = lerpf(result.wall_heights[i].x, result.wall_heights[i].y, t)
					assert_almost_eq(actual, expected, UNDERSIDE_TOLERANCE, "%s roll %.0f piece %d t=%.2f" % [shape_id, roll, i, t])


func test_s4_overhang_end_is_higher_than_the_lower_row_end() -> void:
	var result: GhostSilhouette.Result = _build("S4", Basis.IDENTITY)
	var box: Rect2 = _bbox(result.loops)
	var left_top: float = INF
	var right_top: float = INF
	for i: int in range(result.wall_heights.size()):
		for k: int in range(2):
			var end: Vector2 = result.wall_segments[i * 2 + k]
			var height: float = result.wall_heights[i].x if k == 0 else result.wall_heights[i].y
			if absf(end.x - box.position.x) < EDGE_TOLERANCE:
				left_top = minf(left_top, height)
			if absf(end.x - box.end.x) < EDGE_TOLERANCE:
				right_top = minf(right_top, height)
	assert_almost_eq(left_top - right_top, TUNING.cube_size, EDGE_TOLERANCE, "the overhang's wall starts one cube above the lower row's")


func test_probes_sit_just_inside_the_silhouette_next_to_their_piece() -> void:
	for shape_id: String in ["cube", "L3", "u5"]:
		var result: GhostSilhouette.Result = _build(shape_id, Basis(Vector3.UP, deg_to_rad(30.0)))
		assert_gt(result.probes.size(), 0)
		for i: int in range(result.probes.size()):
			var a: Vector2 = result.wall_segments[i * 2]
			var b: Vector2 = result.wall_segments[i * 2 + 1]
			var near: Vector2 = Geometry2D.get_closest_point_to_segment(result.probes[i], a, b)
			assert_lt(near.distance_to(result.probes[i]), PROBE_REACH, "%s piece %d: probe is beside its wall" % [shape_id, i])
			assert_true(_inside(result.probes[i], result.loops), "%s piece %d: probe is inside the outline" % [shape_id, i])


# --- hand-built meshes ------------------------------------------------------

## An indexed mesh of the given quads (each an array of four Vector3 corners in order), two triangles each.
func _quad_mesh(quads: Array) -> Mesh:
	var verts: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for quad: Array in quads:
		var base: int = verts.size()
		for corner: Vector3 in quad:
			verts.append(corner)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	return _mesh_of(verts, indices)


func _mesh_of(verts: PackedVector3Array, indices: PackedInt32Array) -> Mesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Quad over x0..x1, z 0..1 whose underside is y0 at x0 and y1 at x1.
func _slab(x0: float, x1: float, y0: float, y1: float) -> Array:
	return [Vector3(x0, y0, 0.0), Vector3(x1, y1, 0.0), Vector3(x1, y1, 1.0), Vector3(x0, y0, 1.0)]


func _build_mesh(mesh: Mesh) -> GhostSilhouette.Result:
	var meshes: Array[Mesh] = [mesh]
	return GhostSilhouette.build(meshes, PackedVector3Array([Vector3.ZERO]), Basis.IDENTITY)


## The wall pieces lying on the z = 0 outline edge as [x_low, x_high, height_at_low, height_at_high], by x.
func _front_pieces(result: GhostSilhouette.Result) -> Array[Array]:
	var pieces: Array[Array] = []
	for i: int in range(result.wall_heights.size()):
		var a: Vector2 = result.wall_segments[i * 2]
		var b: Vector2 = result.wall_segments[i * 2 + 1]
		if absf(a.y) > EDGE_TOLERANCE or absf(b.y) > EDGE_TOLERANCE:
			continue
		if a.x <= b.x:
			pieces.append([a.x, b.x, result.wall_heights[i].x, result.wall_heights[i].y])
		else:
			pieces.append([b.x, a.x, result.wall_heights[i].y, result.wall_heights[i].x])
	pieces.sort_custom(func(l: Array, r: Array) -> bool: return l[0] < r[0])
	return pieces


func test_single_triangle_gets_walls_on_all_three_edges() -> void:
	var mesh: Mesh = _mesh_of(
		PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)]), PackedInt32Array([0, 1, 2])
	)
	var result: GhostSilhouette.Result = _build_mesh(mesh)
	assert_eq(result.loops.size(), 1)
	assert_eq(result.loops[0].size(), 3)
	assert_almost_eq(_wall_length(result), 2.0 + sqrt(2.0), AREA_TOLERANCE, "a three-vertex outline still gets walls")


func test_flat_then_sloped_underside_keeps_the_kink_as_two_pieces() -> void:
	var result: GhostSilhouette.Result = _build_mesh(_quad_mesh([_slab(0.0, 1.0, 0.0, 0.0), _slab(1.0, 2.0, 0.0, 1.0)]))
	var pieces: Array[Array] = _front_pieces(result)
	assert_eq(pieces.size(), 2, "different slopes from the same height are not one quad")
	if pieces.size() != 2:
		return
	assert_almost_eq(float(pieces[0][2]), 0.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[0][3]), 0.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[1][2]), 0.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[1][3]), 1.0, EDGE_TOLERANCE)


func test_equal_slope_run_is_one_wall_piece() -> void:
	var result: GhostSilhouette.Result = _build_mesh(_quad_mesh([
		_slab(0.0, 1.0, 0.0, 0.0), _slab(1.0, 1.5, 0.0, 0.5), _slab(1.5, 2.0, 0.5, 1.0),
	]))
	var pieces: Array[Array] = _front_pieces(result)
	assert_eq(pieces.size(), 2, "the two collinear slope pieces share one quad")
	if pieces.size() != 2:
		return
	assert_almost_eq(float(pieces[1][0]), 1.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[1][1]), 2.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[1][3]), 1.0, EDGE_TOLERANCE, "the merged quad reaches the far end's height")


func test_height_step_at_a_seam_is_two_pieces() -> void:
	var result: GhostSilhouette.Result = _build_mesh(_quad_mesh([_slab(0.0, 1.0, 0.0, 0.0), _slab(1.0, 2.0, 0.5, 0.5)]))
	var pieces: Array[Array] = _front_pieces(result)
	assert_eq(pieces.size(), 2, "a vertical step is not bridged")
	if pieces.size() != 2:
		return
	assert_almost_eq(float(pieces[0][3]), 0.0, EDGE_TOLERANCE)
	assert_almost_eq(float(pieces[1][2]), 0.5, EDGE_TOLERANCE)


func test_touching_cubes_in_a_row_share_one_wall_per_long_edge() -> void:
	var cube: Mesh = _mesh(_shape("cube"))
	var step: float = TUNING.cube_size
	for turn: int in range(4):
		var meshes: Array[Mesh] = [cube, cube, cube]
		var offsets: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3(step, 0.0, 0.0), Vector3(2.0 * step, 0.0, 0.0)])
		var result: GhostSilhouette.Result = GhostSilhouette.build(meshes, offsets, Basis(Vector3.UP, PI * 0.5 * turn))
		assert_eq(result.wall_heights.size(), 4, "turn %d: a flat 3x1 slab has four walls" % turn)


func test_pitched_bar_long_edges_are_one_wall_each() -> void:
	var result: GhostSilhouette.Result = _build("bar4", Basis(Vector3.RIGHT, deg_to_rad(30.0)))
	var long_pieces: int = 0
	for i: int in range(result.wall_heights.size()):
		var length: float = result.wall_segments[i * 2].distance_to(result.wall_segments[i * 2 + 1])
		if length > TUNING.cube_size * 1.5:
			long_pieces += 1
			assert_almost_eq(length, 4.0 * TUNING.cube_size, EDGE_TOLERANCE, "a long edge is not split per cell")
	assert_eq(long_pieces, 2, "one wall on each long edge")


# --- largest_loop -----------------------------------------------------------

func test_largest_loop_picks_by_area_wherever_the_loops_sit() -> void:
	var big: PackedVector2Array = PackedVector2Array([Vector2(2, 2), Vector2(0, 2), Vector2(0, 0), Vector2(2, 0)])
	var small: PackedVector2Array = _square(Vector2.ZERO, Vector2(1.5, 1.5), false)
	var loops: Array[PackedVector2Array] = [big, small]
	assert_eq(GhostSilhouette.largest_loop(loops), big)
	var swapped: Array[PackedVector2Array] = [small, big]
	assert_eq(GhostSilhouette.largest_loop(swapped), big)
	var clockwise_big: PackedVector2Array = big.duplicate()
	clockwise_big.reverse()
	var mixed: Array[PackedVector2Array] = [small, clockwise_big]
	assert_eq(GhostSilhouette.largest_loop(mixed), clockwise_big, "winding does not matter")


func test_largest_loop_of_equal_areas_is_the_first() -> void:
	var first: PackedVector2Array = _square(Vector2.ZERO, Vector2.ONE, false)
	var second: PackedVector2Array = _square(Vector2(5.0, 5.0), Vector2(6.0, 6.0), false)
	var loops: Array[PackedVector2Array] = [first, second]
	assert_eq(GhostSilhouette.largest_loop(loops), first)


# --- mask raster ------------------------------------------------------------

func _square(low: Vector2, high: Vector2, clockwise: bool) -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array([
		low, Vector2(high.x, low.y), high, Vector2(low.x, high.y),
	])
	if clockwise != Geometry2D.is_polygon_clockwise(points):
		points.reverse()
	return points


func _mask(loops: Array[PackedVector2Array], origin: Vector2, extent: Vector2) -> Image:
	return GhostSilhouette.rasterize_mask(loops, origin, extent, MASK_PPM, MASK_MAX)


func _solid(image: Image, x: int, y: int) -> bool:
	return image.get_pixel(x, y).a > SOLID_ALPHA


func _solid_count(image: Image) -> int:
	var count: int = 0
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if _solid(image, x, y):
				count += 1
	return count


func test_mask_size_is_extent_times_density_clamped() -> void:
	var loops: Array[PackedVector2Array] = [_square(Vector2.ZERO, Vector2.ONE, false)]
	var normal: Image = _mask(loops, Vector2.ZERO, Vector2(2.0, 1.5))
	if normal == null:
		fail_test("rasterize_mask returned no image")
		return
	assert_eq(normal.get_width(), 16)
	assert_eq(normal.get_height(), 12)
	var tiny: Image = _mask(loops, Vector2.ZERO, Vector2(0.01, 0.01))
	assert_eq(tiny.get_width(), 2, "never below 2 pixels")
	assert_eq(tiny.get_height(), 2)
	var huge: Image = _mask(loops, Vector2.ZERO, Vector2(100.0, 50.0))
	assert_eq(huge.get_width(), MASK_MAX, "never above the cap")
	assert_eq(huge.get_height(), MASK_MAX)


func test_mask_fills_the_loop_and_leaves_the_rest_clear() -> void:
	var loops: Array[PackedVector2Array] = [_square(Vector2(-0.5, -0.5), Vector2(0.5, 0.5), false)]
	var image: Image = _mask(loops, Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	assert_eq(image.get_width(), 16)
	assert_eq(_solid_count(image), 64, "the unit square covers 8x8 of the 16x16 pixels")
	assert_true(_solid(image, 8, 8), "centre is solid")
	assert_false(_solid(image, 1, 1), "corner is clear")
	assert_false(_solid(image, 14, 14), "far corner is clear")


func test_mask_columns_follow_x_and_rows_follow_y() -> void:
	var loops: Array[PackedVector2Array] = [_square(Vector2.ZERO, Vector2(1.0, 0.5), false)]
	var image: Image = _mask(loops, Vector2.ZERO, Vector2.ONE)
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	assert_true(_solid(image, 4, 1), "small y, any x is inside")
	assert_false(_solid(image, 4, 6), "large y is outside")
	var tall: Array[PackedVector2Array] = [_square(Vector2.ZERO, Vector2(0.5, 1.0), false)]
	var tall_image: Image = _mask(tall, Vector2.ZERO, Vector2.ONE)
	assert_true(_solid(tall_image, 1, 4), "small x is inside")
	assert_false(_solid(tall_image, 6, 4), "large x is outside")


func test_mask_leaves_a_concave_notch_clear() -> void:
	var u_shape: PackedVector2Array = PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(3.0, 0.0), Vector2(3.0, 2.0), Vector2(2.0, 2.0),
		Vector2(2.0, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 2.0), Vector2(0.0, 2.0),
	])
	var loops: Array[PackedVector2Array] = [u_shape]
	var image: Image = _mask(loops, Vector2.ZERO, Vector2(3.0, 2.0))
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	assert_eq(image.get_width(), 24)
	assert_eq(image.get_height(), 16)
	assert_true(_solid(image, 4, 12), "the left arm is solid")
	assert_true(_solid(image, 12, 4), "the base is solid")
	assert_false(_solid(image, 12, 12), "the notch is clear")


func test_mask_fills_every_disjoint_outer_loop() -> void:
	var loops: Array[PackedVector2Array] = [
		_square(Vector2.ZERO, Vector2(1.0, 1.0), false), _square(Vector2(2.0, 0.0), Vector2(3.0, 1.0), false),
	]
	var image: Image = _mask(loops, Vector2.ZERO, Vector2(3.0, 1.0))
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	assert_true(_solid(image, 4, 4), "first loop")
	assert_true(_solid(image, 20, 4), "second loop")
	assert_false(_solid(image, 12, 4), "the gap between them is clear")


func test_mask_skips_a_hole_wound_against_the_outer_loop() -> void:
	var loops: Array[PackedVector2Array] = [
		_square(Vector2.ZERO, Vector2(3.0, 3.0), false), _square(Vector2(1.0, 1.0), Vector2(2.0, 2.0), true),
	]
	var image: Image = _mask(loops, Vector2.ZERO, Vector2(3.0, 3.0))
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	assert_true(_solid(image, 12, 12), "an opposite-wound loop is not carved out of the mask")
	assert_eq(_solid_count(image), 24 * 24)


func test_mask_of_real_silhouette_matches_footprint_area() -> void:
	var result: GhostSilhouette.Result = _build("plus5", Basis.IDENTITY)
	assert_gt(result.loops.size(), 0)
	var box: Rect2 = _bbox(result.loops)
	var image: Image = _mask(result.loops, box.position, box.size)
	if not is_instance_valid(image):
		fail_test("rasterize_mask returned no image")
		return
	var pixel_area: float = (box.size.x / image.get_width()) * (box.size.y / image.get_height())
	var covered: float = float(_solid_count(image)) * pixel_area
	var expected: float = _loops_area(result.loops)
	assert_gt(expected, 0.0)
	assert_almost_eq(covered, expected, expected * 0.1, "covered pixel area is within 10% of the outline area")
	assert_lt(covered, box.size.x * box.size.y * 0.9, "a plus is not its bounding box")


func test_mask_ignores_a_loop_wholly_left_of_the_origin() -> void:
	var loops: Array[PackedVector2Array] = [_square(Vector2(-2.0, 0.0), Vector2(-1.0, 1.0), false)]
	var image: Image = _mask(loops, Vector2.ZERO, Vector2.ONE)
	assert_eq(_solid_count(image), 0, "nothing of it lies inside the mask window")
