extends GutTest
## Data checks for every BlockShape resource under config/blocks/ (spec 1.4).

const BLOCKS_DIR: String = "res://config/blocks/"

## id -> expected cube count, from the spec 1.4 table.
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
	&"bar5": 5,
	&"plus5": 5,
	&"u5": 5,
	&"corner4": 4,
	&"stair6": 6,
	&"arch5": 5,
	&"cube8": 8,
	&"plate9": 9,
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


# --- item 3 (was): BlockShape.bottom_center() --

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


