extends GutTest
## BlockShape.cell_centres: the one statement of (cell - pivot) * cube_size, checked against
## hand-worked shapes, the shipped shapes and BlockFactory's non-gift overlap probe.

const EPS: float = 0.0001

var _tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")


func _shape(cells: Array[Vector3i]) -> BlockShape:
	var shape: BlockShape = BlockShape.new()
	shape.cells = cells
	return shape


func _assert_centres(actual: Array[Vector3], expected: Array[Vector3], label: String) -> void:
	assert_eq(actual.size(), expected.size(), "%s: one centre per cell." % label)
	if actual.size() != expected.size():
		return
	for i: int in actual.size():
		assert_true(actual[i].is_equal_approx(expected[i]), "%s: centre %d is %s, expected %s." % [label, i, actual[i], expected[i]])


func test_single_cube_sits_half_a_cell_above_the_pivot() -> void:
	var centres: Array[Vector3] = _shape([Vector3i(0, 0, 0)]).cell_centres(2.0)
	_assert_centres(centres, [Vector3(0.0, 1.0, 0.0)], "cube")


func test_domino_is_centred_in_x_and_stands_on_the_pivot_plane() -> void:
	var centres: Array[Vector3] = _shape([Vector3i(0, 0, 0), Vector3i(1, 0, 0)]).cell_centres(1.0)
	_assert_centres(centres, [Vector3(-0.5, 0.5, 0.0), Vector3(0.5, 0.5, 0.0)], "domino")


func test_pivot_is_bottom_of_lowest_cell_for_a_tall_shape() -> void:
	var centres: Array[Vector3] = _shape([Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(0, 2, 0)]).cell_centres(1.0)
	_assert_centres(centres, [Vector3(0, 0.5, 0), Vector3(0, 1.5, 0), Vector3(0, 2.5, 0)], "pillar")


func test_offset_cells_are_measured_from_the_bounds_centre_not_the_origin() -> void:
	# Bounds x 2..4, y 3..3, z -1..1: pivot (3, 2.5, 0).
	var centres: Array[Vector3] = _shape([Vector3i(2, 3, -1), Vector3i(4, 3, 1)]).cell_centres(1.0)
	_assert_centres(centres, [Vector3(-1.0, 0.5, -1.0), Vector3(1.0, 0.5, 1.0)], "offset")


func test_centres_scale_linearly_with_cube_size() -> void:
	var shape: BlockShape = _shape([Vector3i(0, 0, 0), Vector3i(1, 1, 0)])
	var unit: Array[Vector3] = shape.cell_centres(1.0)
	var big: Array[Vector3] = shape.cell_centres(3.0)
	for i: int in unit.size():
		assert_true(big[i].is_equal_approx(unit[i] * 3.0), "Centre %d scales by the cube size." % i)


func test_zero_cube_size_collapses_every_centre_to_the_pivot() -> void:
	for centre: Vector3 in _shape([Vector3i(0, 0, 0), Vector3i(1, 0, 0)]).cell_centres(0.0):
		assert_eq(centre, Vector3.ZERO)


func test_empty_shape_has_no_centres() -> void:
	assert_eq(_shape([]).cell_centres(1.0).size(), 0)


func test_centres_follow_cells_order() -> void:
	var shape: BlockShape = _shape([Vector3i(1, 0, 0), Vector3i(0, 0, 0)])
	_assert_centres(shape.cell_centres(1.0), [Vector3(0.5, 0.5, 0.0), Vector3(-0.5, 0.5, 0.0)], "reversed")


func test_result_is_a_fresh_array_each_call() -> void:
	var shape: BlockShape = _shape([Vector3i(0, 0, 0)])
	var first: Array[Vector3] = shape.cell_centres(1.0)
	first[0] = Vector3(9.0, 9.0, 9.0)
	first.append(Vector3.ONE)
	_assert_centres(shape.cell_centres(1.0), [Vector3(0.0, 0.5, 0.0)], "second call")


func test_every_shipped_shape_matches_the_cell_minus_pivot_formula() -> void:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	assert_gt(shapes.size(), 0, "Shipped shapes load.")
	for shape: BlockShape in shapes:
		var pivot: Vector3 = shape.bottom_center()
		var expected: Array[Vector3] = []
		for cell: Vector3i in shape.cells:
			expected.append((Vector3(cell) - pivot) * _tuning.cube_size)
		_assert_centres(shape.cell_centres(_tuning.cube_size), expected, String(shape.id))


func test_every_shipped_shape_matches_the_factory_overlap_probe() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		_assert_centres(shape.cell_centres(_tuning.cube_size), BlockFactory.overlap_probe_centers(shape, _tuning, &""), "probe " + String(shape.id))


func test_every_shipped_shape_is_centred_in_xz_and_rests_on_the_pivot_plane() -> void:
	for shape: BlockShape in BlockShape.load_all_shapes():
		var centres: Array[Vector3] = shape.cell_centres(_tuning.cube_size)
		var lo: Vector3 = Vector3(INF, INF, INF)
		var hi: Vector3 = Vector3(-INF, -INF, -INF)
		for centre: Vector3 in centres:
			lo = lo.min(centre)
			hi = hi.max(centre)
		assert_almost_eq(lo.x + hi.x, 0.0, EPS, "%s centred in x." % shape.id)
		assert_almost_eq(lo.z + hi.z, 0.0, EPS, "%s centred in z." % shape.id)
		assert_almost_eq(lo.y, _tuning.cube_size * 0.5, EPS, "%s lowest cell centre is half a cube up." % shape.id)


func test_rotated_center_offset_is_the_rotated_bounds_centre_of_the_cell_centres() -> void:
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(90.0))
	for shape: BlockShape in BlockShape.load_all_shapes():
		var lo: Vector3 = Vector3(INF, INF, INF)
		var hi: Vector3 = Vector3(-INF, -INF, -INF)
		for centre: Vector3 in shape.cell_centres(_tuning.cube_size):
			lo = lo.min(centre)
			hi = hi.max(centre)
		var expected: Vector3 = basis * ((lo + hi) * 0.5)
		assert_true(shape.rotated_center_offset(basis, _tuning.cube_size).is_equal_approx(expected), "%s rotated offset." % shape.id)


func test_rotated_center_offset_of_an_empty_shape_is_zero() -> void:
	assert_eq(_shape([]).rotated_center_offset(Basis.IDENTITY, 1.0), Vector3.ZERO)
