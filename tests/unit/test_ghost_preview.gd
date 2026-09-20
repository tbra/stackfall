extends GutTest
## GhostPreview must apply the orientation-index + free-quaternion rotation
## correctly and never drift on reset (spec 1.7, 2.5 — M1 acceptance).


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func test_default_orientation_is_identity() -> void:
	var ghost: GhostPreview = _make_ghost()
	assert_eq(ghost.orientation_index, 0)
	assert_eq(ghost.basis, Basis.IDENTITY)


func test_orientation_step_matches_table() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_ccw(0))
	assert_eq(ghost.basis, BlockOrientations.get_basis(ghost.orientation_index))


func test_set_orientation_index_wraps() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(-1)
	assert_eq(ghost.orientation_index, 23)
	ghost.set_orientation_index(24)
	assert_eq(ghost.orientation_index, 0)


func test_free_rotation_layers_on_top_of_index() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(0))
	ghost.apply_free_rotation_delta(0.3, 0.1)
	assert_ne(ghost.free_quaternion, Quaternion.IDENTITY)
	var expected: Basis = Basis(ghost.free_quaternion) * BlockOrientations.get_basis(ghost.orientation_index)
	assert_true(ghost.basis.is_equal_approx(expected))


func test_reset_clears_free_rotation_and_index() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.set_orientation_index(5)
	ghost.apply_free_rotation_delta(1.2, 0.7)
	ghost.reset_rotation()
	assert_eq(ghost.orientation_index, 0)
	assert_eq(ghost.free_quaternion, Quaternion.IDENTITY)
	assert_eq(ghost.basis, Basis.IDENTITY)


## Bontago-mv0.10 (spec 2.4/2.5 "[ORIGINAL target]" cadence): "A distinct
## timer-locked state must remain visible even at a legal location."
func test_set_locked_overrides_the_validity_tint() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)

	ghost.set_locked(true)

	assert_eq(ghost.current_state(), GhostPreview.STATE_LOCKED)
	assert_true(
		ghost.current_tint_color().is_equal_approx(ghost.ghost_tuning.locked_tint_color),
		"the locked tint must win over the (still legal) validity tint."
	)

	ghost.set_locked(false)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID, "unlocking restores whatever validity last said.")


func test_many_random_steps_then_reset_never_drifts() -> void:
	var ghost: GhostPreview = _make_ghost()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 42
	for _i: int in range(200):
		match rng.randi_range(0, 5):
			0: ghost.set_orientation_index(BlockOrientations.step_yaw_ccw(ghost.orientation_index))
			1: ghost.set_orientation_index(BlockOrientations.step_yaw_cw(ghost.orientation_index))
			2: ghost.set_orientation_index(BlockOrientations.step_pitch_fwd(ghost.orientation_index))
			3: ghost.set_orientation_index(BlockOrientations.step_pitch_back(ghost.orientation_index))
			4: ghost.set_orientation_index(BlockOrientations.step_roll_left(ghost.orientation_index))
			5: ghost.set_orientation_index(BlockOrientations.step_roll_right(ghost.orientation_index))
		ghost.apply_free_rotation_delta(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5))
	ghost.reset_rotation()
	assert_eq(ghost.basis, Basis.IDENTITY, "However far rotation drifted, reset must land exactly on identity.")
