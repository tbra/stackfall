extends GutTest
## Data checks for every BlockShape resource under config/blocks/ (spec 2.4).

const BLOCKS_DIR: String = "res://config/blocks/"

## id -> expected cube count, from the spec 2.4 table.
const EXPECTED_CELL_COUNTS: Dictionary = {
	&"cube": 1,
	&"domino": 2,
	&"bar3": 3,
	&"bar4": 4,
	&"L3": 3,
	&"L4": 4,
	&"T4": 4,
	&"S4": 4,
	&"square4": 4,
	&"slab6": 6,
	&"pillar": 3,
	&"wedge": 1,
}


func _all_shapes() -> Array[BlockShape]:
	var shapes: Array[BlockShape] = []
	var dir: DirAccess = DirAccess.open(BLOCKS_DIR)
	assert_not_null(dir, "config/blocks/ must exist.")
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var shape: BlockShape = load(BLOCKS_DIR + file_name)
			assert_not_null(shape, "%s failed to load as a BlockShape." % file_name)
			shapes.append(shape)
		file_name = dir.get_next()
	dir.list_dir_end()
	return shapes


func test_every_expected_shape_exists() -> void:
	var shapes: Array[BlockShape] = _all_shapes()
	var found_ids: Array[StringName] = []
	for shape: BlockShape in shapes:
		found_ids.append(shape.id)
	for id: StringName in EXPECTED_CELL_COUNTS:
		assert_true(found_ids.has(id), "Missing BlockShape resource for id %s." % id)


func test_cell_counts_match_the_spec_table() -> void:
	for shape: BlockShape in _all_shapes():
		if not EXPECTED_CELL_COUNTS.has(shape.id):
			continue
		assert_eq(
			shape.cells.size(),
			int(EXPECTED_CELL_COUNTS[shape.id]),
			"%s should have %s cubes." % [shape.id, EXPECTED_CELL_COUNTS[shape.id]]
		)


func test_no_duplicate_cells() -> void:
	for shape: BlockShape in _all_shapes():
		var seen: Dictionary = {}
		for cell: Vector3i in shape.cells:
			assert_false(seen.has(cell), "%s has a duplicate cell %s." % [shape.id, cell])
			seen[cell] = true


func test_weights_are_positive() -> void:
	for shape: BlockShape in _all_shapes():
		assert_gt(shape.weight, 0.0, "%s must have a positive feed weight." % shape.id)


func test_sloped_cells_are_a_subset_of_cells() -> void:
	for shape: BlockShape in _all_shapes():
		for cell: Vector3i in shape.sloped_cells:
			assert_true(shape.cells.has(cell), "%s sloped_cells must all be in cells." % shape.id)


func test_wedge_has_a_sloped_cell() -> void:
	for shape: BlockShape in _all_shapes():
		if shape.id == &"wedge":
			assert_gt(shape.sloped_cells.size(), 0, "wedge needs at least one sloped cell (spec 2.4).")


# --- Bontago-mv0.12: BlockShape.center() -------------------------------------

## center() must be the cells' bounding-box midpoint for every shape, not just
## the ones spot-checked below -- this is the generic version of those checks.
func test_center_is_the_bounding_box_midpoint_for_every_shape() -> void:
	for shape: BlockShape in _all_shapes():
		var min_cell: Vector3 = Vector3(shape.cells[0])
		var max_cell: Vector3 = Vector3(shape.cells[0])
		for cell: Vector3i in shape.cells:
			min_cell = Vector3(minf(min_cell.x, cell.x), minf(min_cell.y, cell.y), minf(min_cell.z, cell.z))
			max_cell = Vector3(maxf(max_cell.x, cell.x), maxf(max_cell.y, cell.y), maxf(max_cell.z, cell.z))
		var expected: Vector3 = (min_cell + max_cell) * 0.5
		assert_true(
			shape.center().is_equal_approx(expected),
			"%s.center() should be %s, got %s" % [shape.id, expected, shape.center()]
		)


## Spot checks against the spec 2.4 table's own cell layouts, so a future
## change to a specific shape's cells is caught by name, not just by the
## generic bounding-box check above.
func test_center_of_a_symmetric_shape_is_the_origin() -> void:
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	assert_eq(cube.center(), Vector3.ZERO)
	var square4: BlockShape = load("res://config/blocks/square4.tres")
	assert_true(square4.center().is_equal_approx(Vector3(0.5, 0.0, 0.5)))


func test_center_of_an_off_origin_shape_is_not_the_origin() -> void:
	var bar3: BlockShape = load("res://config/blocks/bar3.tres")
	assert_true(
		bar3.center().is_equal_approx(Vector3(1.0, 0.0, 0.0)),
		"bar3's cells run 0..2, so its true centre is its middle cube, not cell (0, 0, 0)."
	)
	var domino: BlockShape = load("res://config/blocks/domino.tres")
	assert_true(
		domino.center().is_equal_approx(Vector3(0.5, 0.0, 0.0)),
		"domino's two cells straddle x = 0.5, not either cell itself."
	)
