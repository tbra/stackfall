extends GutTest
## GiftCrateTouch: separating-axis overlap between a block's rotated cells and the world-aligned
## gift crate box. Pure maths through the public statics. The held-cell margin is added by the
## caller into `cell_half`, so these tests pass it in the same way.

const CELL_HALF: float = 0.5
const CRATE_HALF: Vector3 = Vector3(0.5, 0.5, 0.5)
const EDGE_ONLY_AXIS: Vector3 = Vector3(1.0, 1.0, 0.0)


func _hit(offset: Vector3, basis: Basis = Basis.IDENTITY, half: float = CELL_HALF) -> bool:
	return GiftCrateTouch.cell_overlaps_crate(Vector3.ZERO, basis, half, offset, CRATE_HALF)


func test_axis_aligned_overlap_and_miss_on_each_axis() -> void:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3.LEFT, Vector3.DOWN, Vector3.FORWARD]:
		assert_true(_hit(axis * 0.9), "overlap %s" % axis)
		assert_false(_hit(axis * 1.1), "miss %s" % axis)


func test_coincident_centres_overlap() -> void:
	assert_true(_hit(Vector3.ZERO))


func test_touching_faces_count_as_overlap() -> void:
	assert_true(_hit(Vector3(1.0, 0.0, 0.0)), "faces exactly touching")


func test_overlap_is_symmetric_in_sign() -> void:
	assert_eq(_hit(Vector3(1.05, 0.2, -0.3)), _hit(Vector3(-1.05, -0.2, 0.3)))


func test_rotated_45_degrees_reaches_further_along_its_corner() -> void:
	var diamond: Basis = Basis(Vector3.UP, deg_to_rad(45.0))
	# A cube turned 45 degrees about Y has a corner 0.7071 out along X: reach 0.5 + 0.7071.
	assert_true(_hit(Vector3(1.2, 0.0, 0.0), diamond), "inside the corner reach")
	assert_false(_hit(Vector3(1.22, 0.0, 0.0), diamond), "beyond the corner reach")
	assert_false(_hit(Vector3(1.1, 0.0, 0.0)), "the same offset misses axis-aligned")
	assert_true(_hit(Vector3(0.0, 0.9, 0.0), diamond), "Y extent unchanged by a Y turn")
	assert_false(_hit(Vector3(0.0, 1.1, 0.0), diamond))


func test_diagonal_corner_to_corner_miss_and_hit() -> void:
	var diamond: Basis = Basis(Vector3.BACK, deg_to_rad(45.0))
	assert_false(_hit(Vector3(1.0, 1.0, 0.0), diamond), "bounds overlap but the diamond corner clears")
	assert_true(_hit(Vector3(0.8, 0.8, 0.0), diamond), "closer along the diagonal overlaps")


func test_edge_edge_separation_found_by_cross_axes() -> void:
	# Face axes of both boxes cannot separate this pair; only an edge-edge axis does.
	var tilted: Basis = Basis(EDGE_ONLY_AXIS.normalized(), deg_to_rad(45.0))
	assert_false(_hit(Vector3(0.0, 0.65, 1.35), tilted), "edge-only separation is a miss")
	assert_true(_hit(Vector3(0.0, 0.65, 1.25), tilted), "slightly closer overlaps")


func test_larger_cell_half_reaches_further() -> void:
	var offset: Vector3 = Vector3(1.05, 0.0, 0.0)
	assert_false(_hit(offset, Basis.IDENTITY, 0.5))
	assert_true(_hit(offset, Basis.IDENTITY, 0.58), "the caller's margin widens the cell")


func test_crate_half_extents_are_per_axis() -> void:
	var flat: Vector3 = Vector3(2.0, 0.25, 0.5)
	assert_true(GiftCrateTouch.cell_overlaps_crate(Vector3.ZERO, Basis.IDENTITY, CELL_HALF, Vector3(2.4, 0, 0), flat))
	assert_false(GiftCrateTouch.cell_overlaps_crate(Vector3.ZERO, Basis.IDENTITY, CELL_HALF, Vector3(0, 0.8, 0), flat))


func test_cell_centre_offset_is_relative_to_the_crate() -> void:
	var cell: Vector3 = Vector3(10.0, 5.0, -3.0)
	assert_true(GiftCrateTouch.cell_overlaps_crate(cell, Basis.IDENTITY, CELL_HALF, cell + Vector3(0.9, 0, 0), CRATE_HALF))
	assert_false(GiftCrateTouch.cell_overlaps_crate(cell, Basis.IDENTITY, CELL_HALF, cell + Vector3(1.1, 0, 0), CRATE_HALF))


func _row(count: int) -> Array[Vector3i]:
	var cells: Array[Vector3i] = []
	for i: int in range(count):
		cells.append(Vector3i(i, 0, 0))
	return cells


func _shape_hit(cells: Array[Vector3i], crate: Vector3, basis: Basis = Basis.IDENTITY,
		pivot: Vector3 = Vector3.ZERO, origin: Vector3 = Vector3.ZERO, cube: float = 1.0) -> bool:
	return GiftCrateTouch.shape_overlaps_crate(cells, pivot, origin, basis, cube, CELL_HALF, crate, CRATE_HALF)


func test_shape_hit_by_a_far_cell_only() -> void:
	assert_true(_shape_hit(_row(3), Vector3(2.0, 0, 0)), "only the third cell reaches")
	assert_true(_shape_hit(_row(3), Vector3(2.9, 0, 0)))
	assert_false(_shape_hit(_row(3), Vector3(3.2, 0, 0)))
	assert_false(_shape_hit(_row(1), Vector3(2.0, 0, 0)), "a single cell does not reach")


func test_shape_miss_beside_the_row() -> void:
	assert_false(_shape_hit(_row(3), Vector3(1.0, 1.2, 0)))
	assert_true(_shape_hit(_row(3), Vector3(1.0, 0.9, 0)))


func test_empty_cell_list_never_overlaps() -> void:
	var none: Array[Vector3i] = []
	assert_false(_shape_hit(none, Vector3.ZERO))


func test_shape_pivot_origin_and_cube_size_place_the_cells() -> void:
	assert_true(_shape_hit(_row(3), Vector3(0.0, 0, 0), Basis.IDENTITY, Vector3(2, 0, 0)), "pivot cell at the origin")
	assert_true(_shape_hit(_row(3), Vector3(-1.0, 0, 0), Basis.IDENTITY, Vector3(2, 0, 0)))
	assert_false(_shape_hit(_row(3), Vector3(5.0, 0, 0), Basis.IDENTITY, Vector3(2, 0, 0)))
	assert_true(_shape_hit(_row(3), Vector3(10.0, 0, 0), Basis.IDENTITY, Vector3.ZERO, Vector3(8, 0, 0)), "origin offsets all cells")
	assert_true(_shape_hit(_row(3), Vector3(4.0, 0, 0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, 2.0), "cube size scales spacing")
	assert_false(_shape_hit(_row(3), Vector3(7.0, 0, 0), Basis.IDENTITY, Vector3.ZERO, Vector3.ZERO, 2.0))


func test_shape_basis_swings_the_whole_row() -> void:
	var quarter: Basis = Basis(Vector3.UP, deg_to_rad(90.0))
	# Rotating +90 degrees about Y turns +X cells towards -Z.
	assert_true(_shape_hit(_row(3), Vector3(0, 0, -2.0), quarter))
	assert_false(_shape_hit(_row(3), Vector3(2.0, 0, 0), quarter), "no longer along X")
