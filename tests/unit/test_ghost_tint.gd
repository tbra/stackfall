extends GutTest
## Spec 2.2/2.5: the ghost is tinted in the player's colour when the spot is
## valid, red when outside territory/contested/off the disk, and hatched over
## a hole. docs/M2_PLAN.md P4: "the ghost is the owner's color when
## Match.preview_placement returns VALID, red for
## OUTSIDE_TERRITORY/CONTESTED/OFF_DISK, hatched over HOLE."

const PLAYER_COLOR: Color = Color(0.25, 0.55, 0.95, 1.0)


## Bontago-xtq.13 (owner playtest 2026-09-23): every tint colour's own stored
## alpha channel is now dead weight -- game/GhostPreview.gd's
## _apply_validity_material() always overrides it with ghost_tuning.
## ghost_opacity -- so a test that used to compare a live tint straight
## against one of GhostTuning's own Color constants needs this helper to
## build the *actually expected* colour (that constant's RGB, ghost_opacity's
## alpha) instead.
func _with_ghost_opacity(ghost: GhostPreview, color: Color) -> Color:
	return Color(color.r, color.g, color.b, ghost.ghost_tuning.ghost_opacity)


## Bontago-xtq.13: ghost_tuning is the same process-wide preloaded singleton
## every GhostPreview's own @export field resolves to (test_tuning_panel.gd's
## own class doc explains why) -- test_ghost_opacity_is_the_alpha_of_every_
## tint_state() below mutates its ghost_opacity, so it must be restored here
## rather than leaking a non-default value into every test file that runs
## afterward in the same process.
var _saved_ghost_opacity: float


func before_each() -> void:
	var tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
	_saved_ghost_opacity = tuning.ghost_opacity


func after_each() -> void:
	var tuning: GhostTuning = preload("res://config/ghost_tuning.tres")
	tuning.ghost_opacity = _saved_ghost_opacity


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
	assert_true(ghost.current_tint_color().is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.invalid_tint_color)))


func test_contested_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.CONTESTED)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_true(ghost.current_tint_color().is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.invalid_tint_color)))


func test_off_disk_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.OFF_DISK)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_true(ghost.current_tint_color().is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.invalid_tint_color)))


func test_empty_footprint_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.EMPTY)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)


func test_hole_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.HOLE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_true(ghost.current_tint_color().is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.hole_tint_color)))


## Territory v2 (docs/TERRITORY_V2_PLAN.md package C): a goal flag's no-build
## zone reads the same as a legacy hole — hatched, hole_tint_color — since the
## spec's "hatched pattern when over a hole" visual language already means
## "can't build here" for either reason.
func test_goal_zone_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.GOAL_ZONE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_true(ghost.current_tint_color().is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.hole_tint_color)))


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


# --- Bontago-xtq.13 (owner playtest 2026-09-23, "ghost block should still be
# less transparent -> add a slider for it in the F4 menu") ------------------

## Must fail against the pre-xtq.13 code (every state's alpha came from that
## colour's own stored channel -- 0.75 for every one of these -- not one
## shared, owner-tunable slider) and pass once every state's own alpha is
## exactly ghost_tuning.ghost_opacity, including a non-default value.
func test_ghost_opacity_is_the_alpha_of_every_tint_state() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.ghost_tuning.ghost_opacity = 0.42

	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_almost_eq(ghost.current_tint_color().a, 0.42, 0.001, "valid tint alpha must equal ghost_opacity.")

	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_almost_eq(ghost.current_tint_color().a, 0.42, 0.001, "invalid tint alpha must equal ghost_opacity.")

	ghost.apply_validity(PlacementRules.Result.HOLE)
	assert_almost_eq(ghost.current_tint_color().a, 0.42, 0.001, "hole tint alpha must equal ghost_opacity.")

	ghost.set_locked(true)
	assert_almost_eq(ghost.current_tint_color().a, 0.42, 0.001, "locked tint alpha must equal ghost_opacity.")
	ghost.set_locked(false)

	ghost.show_throw_hint(true)
	assert_almost_eq(ghost.current_tint_color().a, 0.42, 0.001, "throw-aim tint alpha must equal ghost_opacity.")


func test_ghost_opacity_default_value() -> void:
	var fresh: GhostTuning = GhostTuning.new()
	assert_almost_eq(fresh.ghost_opacity, 0.9, 0.0001)
