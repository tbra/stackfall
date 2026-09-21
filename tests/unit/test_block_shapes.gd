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


# --- Bontago-mv0.17 item 3 (was Bontago-mv0.12): BlockShape.bottom_center() --

## bottom_center() must be the cells' bounding-box x/z midpoint, but the
## *bottom* face in y (half a cube below the lowest cell's own centre), for
## every shape, not just the ones spot-checked below -- this is the generic
## version of those checks.
func test_bottom_center_is_the_bounding_box_bottom_face_for_every_shape() -> void:
	for shape: BlockShape in _all_shapes():
		var min_cell: Vector3 = Vector3(shape.cells[0])
		var max_cell: Vector3 = Vector3(shape.cells[0])
		for cell: Vector3i in shape.cells:
			min_cell = Vector3(minf(min_cell.x, cell.x), minf(min_cell.y, cell.y), minf(min_cell.z, cell.z))
			max_cell = Vector3(maxf(max_cell.x, cell.x), maxf(max_cell.y, cell.y), maxf(max_cell.z, cell.z))
		var expected: Vector3 = Vector3((min_cell.x + max_cell.x) * 0.5, min_cell.y - 0.5, (min_cell.z + max_cell.z) * 0.5)
		assert_true(
			shape.bottom_center().is_equal_approx(expected),
			"%s.bottom_center() should be %s, got %s" % [shape.id, expected, shape.bottom_center()]
		)


## Spot checks against the spec 2.4 table's own cell layouts, so a future
## change to a specific shape's cells is caught by name, not just by the
## generic bounding-box check above.
func test_bottom_center_of_a_flat_symmetric_shape_is_below_the_origin() -> void:
	var cube: BlockShape = load("res://config/blocks/cube.tres")
	assert_true(cube.bottom_center().is_equal_approx(Vector3(0.0, -0.5, 0.0)))
	var square4: BlockShape = load("res://config/blocks/square4.tres")
	assert_true(square4.bottom_center().is_equal_approx(Vector3(0.5, -0.5, 0.5)))


func test_bottom_center_of_an_off_origin_shape_is_not_the_origin() -> void:
	var bar3: BlockShape = load("res://config/blocks/bar3.tres")
	assert_true(
		bar3.bottom_center().is_equal_approx(Vector3(1.0, -0.5, 0.0)),
		"bar3's cells run 0..2, so its x centre is its middle cube, not cell (0, 0, 0)."
	)
	var domino: BlockShape = load("res://config/blocks/domino.tres")
	assert_true(
		domino.bottom_center().is_equal_approx(Vector3(0.5, -0.5, 0.0)),
		"domino's two cells straddle x = 0.5, not either cell itself."
	)


## The shape that actually distinguishes bottom_center() from the old
## mv0.12 geometric centre: pillar stacks three cells in y (0..2), so its
## true vertical midpoint would be y = 1.0, but the bottom face of its lowest
## cell is y = -0.5.
func test_bottom_center_of_a_tall_shape_is_its_lowest_face_not_its_midpoint() -> void:
	var pillar: BlockShape = load("res://config/blocks/pillar.tres")
	assert_true(
		pillar.bottom_center().is_equal_approx(Vector3(0.0, -0.5, 0.0)),
		"pillar's cells run y = 0..2; bottom_center() must sit at the bottom face, not the y = 1.0 midpoint."
	)
