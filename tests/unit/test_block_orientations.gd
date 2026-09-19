extends GutTest
## Rotation must never drift (spec 1.7, 2.5; M1 acceptance criterion). These
## tests cover the pure logic in core/blocks/BlockOrientations.gd.

const STEP_FUNCS: Array[StringName] = [
	&"step_yaw_ccw", &"step_yaw_cw",
	&"step_pitch_fwd", &"step_pitch_back",
	&"step_roll_left", &"step_roll_right",
]


func test_there_are_24_distinct_orientations() -> void:
	assert_eq(BlockOrientations.count(), 24, "The cube has exactly 24 axis-aligned orientations.")
	for i: int in range(24):
		for j: int in range(24):
			if i == j:
				continue
			var a: Basis = BlockOrientations.get_basis(i)
			var b: Basis = BlockOrientations.get_basis(j)
			var equal: bool = a[0].is_equal_approx(b[0]) and a[1].is_equal_approx(b[1]) and a[2].is_equal_approx(b[2])
			assert_false(equal, "Orientations %d and %d must be distinct." % [i, j])


func test_index_zero_is_identity() -> void:
	assert_eq(BlockOrientations.get_basis(0), Basis.IDENTITY)


func test_every_step_from_every_index_is_valid() -> void:
	for index: int in range(24):
		assert_between(BlockOrientations.step_yaw_ccw(index), 0, 23)
		assert_between(BlockOrientations.step_yaw_cw(index), 0, 23)
		assert_between(BlockOrientations.step_pitch_fwd(index), 0, 23)
		assert_between(BlockOrientations.step_pitch_back(index), 0, 23)
		assert_between(BlockOrientations.step_roll_left(index), 0, 23)
		assert_between(BlockOrientations.step_roll_right(index), 0, 23)


func test_four_yaw_steps_return_to_start() -> void:
	for index: int in range(24):
		var current: int = index
		for _i: int in range(4):
			current = BlockOrientations.step_yaw_ccw(current)
		assert_eq(current, index, "Four CCW yaw steps from %d must return to %d." % [index, index])

		current = index
		for _i: int in range(4):
			current = BlockOrientations.step_yaw_cw(current)
		assert_eq(current, index, "Four CW yaw steps from %d must return to %d." % [index, index])


func test_yaw_cw_undoes_yaw_ccw() -> void:
	for index: int in range(24):
		var forward: int = BlockOrientations.step_yaw_ccw(index)
		var back: int = BlockOrientations.step_yaw_cw(forward)
		assert_eq(back, index, "yaw_cw must undo yaw_ccw at index %d." % index)


func test_is_valid_index_accepts_exactly_the_24_table_indices() -> void:
	# get_basis() indexes the table directly: a negative index silently wraps
	# in GDScript (-1 is entry 23) and anything past the end is a script
	# error, so untrusted callers must ask this first (Beads Bontago-mv0.1.5).
	for index: int in range(BlockOrientations.ORIENTATION_COUNT):
		assert_true(BlockOrientations.is_valid_index(index), "Index %d is in the table." % index)
	for bad: int in [-1, -25, BlockOrientations.ORIENTATION_COUNT, 25, 1 << 40, -(1 << 40)]:
		assert_false(BlockOrientations.is_valid_index(bad), "Index %d is outside the table." % bad)


func test_valid_indices_still_map_to_the_same_bases() -> void:
	# The table is built by breadth-first closure from the identity with the
	# generators in yaw, pitch, roll order, so its first four entries are fixed
	# by construction; the guard above must not have changed how it is built.
	assert_eq(BlockOrientations.get_basis(0), Basis.IDENTITY)
	assert_true(BlockOrientations.get_basis(1).is_equal_approx(Basis(Vector3.UP, PI / 2.0)), "Entry 1 is the yaw generator.")
	assert_true(BlockOrientations.get_basis(2).is_equal_approx(Basis(Vector3.RIGHT, PI / 2.0)), "Entry 2 is the pitch generator.")
	assert_true(BlockOrientations.get_basis(3).is_equal_approx(Basis(Vector3.FORWARD, PI / 2.0)), "Entry 3 is the roll generator.")
	for index: int in range(BlockOrientations.ORIENTATION_COUNT):
		var basis: Basis = BlockOrientations.get_basis(index)
		assert_almost_eq(basis.determinant(), 1.0, 0.0001, "Entry %d is a proper rotation." % index)
		for axis: int in range(3):
			for component: int in range(3):
				var value: float = absf(basis[axis][component])
				assert_true(
					is_equal_approx(value, 0.0) or is_equal_approx(value, 1.0),
					"Entry %d is axis-aligned (all entries 0 or +-1)." % index
				)
		assert_eq(BlockOrientations.index_of(basis), index, "Entry %d round-trips through index_of." % index)


func test_reset_returns_to_identity_index() -> void:
	# Reset is PlayerController/GhostPreview policy ("set the index to 0"),
	# tested here at the data level: index 0 is always identity, regardless of
	# how far rotation had drifted.
	var index: int = 0
	for _i: int in range(7):
		index = BlockOrientations.step_pitch_fwd(index)
	assert_ne(index, 0, "Sanity check: several steps should move away from identity.")
	index = 0
	assert_eq(BlockOrientations.get_basis(index), Basis.IDENTITY, "Index 0 is always identity after reset.")
