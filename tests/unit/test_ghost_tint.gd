extends GutTest
## Spec 2.2/2.5: the ghost is tinted in the player's colour when the spot is
## valid, red when outside territory/contested/off the disk, and hatched over
## a hole. docs/M2_PLAN.md P4: "the ghost is the owner's color when
## Match.preview_placement returns VALID, red for
## OUTSIDE_TERRITORY/CONTESTED/OFF_DISK, hatched over HOLE."

const PLAYER_COLOR: Color = Color(0.25, 0.55, 0.95, 1.0)


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.set_player_color(PLAYER_COLOR)
	return ghost


func test_valid_result_tints_player_color() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)
	var tint: Color = ghost.current_tint_color()
	assert_almost_eq(tint.r, PLAYER_COLOR.r, 0.001)
	assert_almost_eq(tint.g, PLAYER_COLOR.g, 0.001)
	assert_almost_eq(tint.b, PLAYER_COLOR.b, 0.001)


func test_outside_territory_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_eq(ghost.current_tint_color(), ghost.ghost_tuning.invalid_tint_color)


func test_contested_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.CONTESTED)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_eq(ghost.current_tint_color(), ghost.ghost_tuning.invalid_tint_color)


func test_off_disk_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.OFF_DISK)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_eq(ghost.current_tint_color(), ghost.ghost_tuning.invalid_tint_color)


func test_empty_footprint_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.EMPTY)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)


func test_hole_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.HOLE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_eq(ghost.current_tint_color(), ghost.ghost_tuning.hole_tint_color)


## Territory v2 (docs/TERRITORY_V2_PLAN.md package C): a goal flag's no-build
## zone reads the same as a legacy hole — hatched, hole_tint_color — since the
## spec's "hatched pattern when over a hole" visual language already means
## "can't build here" for either reason.
func test_goal_zone_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.GOAL_ZONE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_eq(ghost.current_tint_color(), ghost.ghost_tuning.hole_tint_color)


func test_switching_back_to_valid_restores_player_color() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.CONTESTED)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)
	assert_almost_eq(ghost.current_tint_color().r, PLAYER_COLOR.r, 0.001)


func test_set_player_color_live_updates_a_currently_valid_ghost() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)
	var other_color: Color = Color(0.95, 0.55, 0.2, 1.0)
	ghost.set_player_color(other_color)
	assert_almost_eq(ghost.current_tint_color().r, other_color.r, 0.001)
	assert_almost_eq(ghost.current_tint_color().g, other_color.g, 0.001)


func test_set_player_color_does_not_override_an_invalid_tint() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.HOLE)
	ghost.set_player_color(Color.BLACK)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE, "A colour change shouldn't clear an active reject/hole tint.")


# --- Controller wiring: the ghost tint follows Match.preview_placement -----


func test_controller_applies_preview_result_to_ghost_every_frame() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.next_preview_result = PlacementRules.Result.CONTESTED
	controller._match = fake_match

	controller._update_ghost_tint()

	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_eq(fake_match.preview_placement_calls.size(), 1)

	fake_match.next_preview_result = PlacementRules.Result.VALID
	controller._update_ghost_tint()
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)


func test_controller_skips_preview_when_no_active_slot() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = -1

	var fake_match: FakeMatch = FakeMatch.new()
	controller._match = fake_match

	controller._update_ghost_tint()

	assert_eq(fake_match.preview_placement_calls.size(), 0, "No hot-seat turn yet, so nothing should be previewed.")


# --- Bontago-xtq.9 (owner test 2026-09-23, "the ghost block should be a bit
# more opaque") --------------------------------------------------------------

## Must fail against the old ~0.55-0.65 GhostTuning defaults and pass once
## every valid/state tint's own alpha is raised to ~0.75.
func test_every_tint_state_alpha_is_at_least_the_new_more_opaque_default() -> void:
	var ghost: GhostPreview = _make_ghost()
	var minimum_alpha: float = 0.75

	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_true(
		ghost.current_tint_color().a >= minimum_alpha - 0.001,
		"valid tint alpha %.3f should be >= %.3f" % [ghost.current_tint_color().a, minimum_alpha]
	)

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_true(
		ghost.current_tint_color().a >= minimum_alpha - 0.001,
		"invalid tint alpha %.3f should be >= %.3f" % [ghost.current_tint_color().a, minimum_alpha]
	)

	ghost.apply_validity(PlacementRules.Result.HOLE)
	assert_true(
		ghost.current_tint_color().a >= minimum_alpha - 0.001,
		"hole tint alpha %.3f should be >= %.3f" % [ghost.current_tint_color().a, minimum_alpha]
	)

	ghost.set_locked(true)
	assert_true(
		ghost.current_tint_color().a >= minimum_alpha - 0.001,
		"locked tint alpha %.3f should be >= %.3f" % [ghost.current_tint_color().a, minimum_alpha]
	)
