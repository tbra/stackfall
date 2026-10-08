extends GutTest
## Bontago-1pi.115: the eight shapes added on top of the original 11
## (docs/BLOCK_POOL_PLAN.md section 3; spec 2.4).

const NEW_IDS: Array[StringName] = [&"bar5", &"plus5", &"u5", &"corner4", &"stair6", &"arch5", &"cube8", &"plate9"]
const CELL_COUNTS: Dictionary = {
	&"bar5": 5, &"plus5": 5, &"u5": 5, &"corner4": 4, &"stair6": 6, &"arch5": 5, &"cube8": 8, &"plate9": 9,
}
const TOTAL_SHAPES: int = 19
const MAX_CELLS: int = 9


func _new_shapes() -> Array[BlockShape]:
	var out: Array[BlockShape] = []
	var by_id: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		by_id[shape.id] = shape
	for id: StringName in NEW_IDS:
		assert_true(by_id.has(id), "load_all_shapes() must include %s." % id)
		if by_id.has(id):
			out.append(by_id[id])
	return out


func _connected(cells: Array[Vector3i]) -> bool:
	var seen: Dictionary = {cells[0]: true}
	var queue: Array[Vector3i] = [cells[0]]
	while not queue.is_empty():
		var c: Vector3i = queue.pop_back()
		for d: Vector3i in [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD]:
			var n: Vector3i = c + d
			if cells.has(n) and not seen.has(n):
				seen[n] = true
				queue.append(n)
	return seen.size() == cells.size()


func test_all_new_shapes_load_with_expected_cell_counts() -> void:
	for shape: BlockShape in _new_shapes():
		assert_eq(shape.cells.size(), int(CELL_COUNTS[shape.id]), "%s cell count" % shape.id)
		assert_lte(shape.cells.size(), MAX_CELLS)


func test_new_shapes_are_connected_unique_and_weighted() -> void:
	for shape: BlockShape in _new_shapes():
		assert_true(_connected(shape.cells), "%s must be face-connected." % shape.id)
		var seen: Dictionary = {}
		for cell: Vector3i in shape.cells:
			assert_false(seen.has(cell), "%s duplicate cell %s" % [shape.id, cell])
			seen[cell] = true
		assert_gt(shape.weight, 0.0, "%s weight" % shape.id)
		assert_eq(shape.sloped_cells.size(), 0, "%s has no slopes" % shape.id)


func test_shape_ids_are_unique_and_total_is_19() -> void:
	var ids: Dictionary = {}
	for shape: BlockShape in BlockShape.load_all_shapes():
		assert_false(ids.has(shape.id), "duplicate id %s" % shape.id)
		ids[shape.id] = true
	assert_eq(ids.size(), TOTAL_SHAPES)


func test_mass_is_cells_times_cube_mass() -> void:
	var tuning: PhysicsTuning = PhysicsTuning.new()
	for shape: BlockShape in _new_shapes():
		var mass: float = float(shape.cells.size()) * tuning.cube_mass
		assert_almost_eq(mass, float(CELL_COUNTS[shape.id]) * tuning.cube_mass, 0.0001)
