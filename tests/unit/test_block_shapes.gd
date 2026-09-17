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
