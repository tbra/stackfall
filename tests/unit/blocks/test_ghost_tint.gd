extends GutTest
## Spec 1.5/2.5: the ghost is tinted in the player's colour when the spot is
## valid, red when outside territory/contested/off the disk, and hatched over
## a hole (the owner's colour when Match.preview_placement returns VALID, red
## for OUTSIDE_TERRITORY/CONTESTED/OFF_DISK, hatched over HOLE).

const PLAYER_COLOR: Color = Color(0.25, 0.55, 0.95, 1.0)


## Every tint colour's own stored
## alpha channel is now dead weight -- game/player/GhostPreview.gd's
## _apply_validity_material() always overrides it with ghost_tuning.
## ghost_opacity -- so a test that used to compare a live tint straight
## against one of GhostTuning's own Color constants needs this helper to
## build the *actually expected* colour (that constant's RGB, ghost_opacity's
## alpha) instead.
func _with_ghost_opacity(ghost: GhostPreview, color: Color) -> Color:
	return Color(color.r, color.g, color.b, ghost.ghost_tuning.ghost_opacity)


## The ghost_tuning resource is the same process-wide preloaded singleton
## every GhostPreview's own @export field resolves to (test_tuning_panel.gd's
## own class doc explains why) -- test_ghost_opacity_is_the_alpha_of_every_
## tint_state() below mutates its ghost_opacity, so it must be restored here
## rather than leaking a non-default value into every test file that runs
## afterward in the same process.
var _saved_ghost_opacity: float


func before_each() -> void:
	var tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
	_saved_ghost_opacity = tuning.ghost_opacity


func after_each() -> void:
	var tuning: GhostTuning = preload("res://config/blocks/tuning/ghost_tuning.tres")
	tuning.ghost_opacity = _saved_ghost_opacity


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.set_player_color(PLAYER_COLOR)
	return ghost


func _body_tint(ghost: GhostPreview) -> Color:
	return ghost._material.get_shader_parameter(&"albedo_color") as Color


func test_valid_result_tints_player_color() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.VALID)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)
	var tint: Color = _body_tint(ghost)
	assert_almost_eq(tint.r, PLAYER_COLOR.r, 0.001)
	assert_almost_eq(tint.g, PLAYER_COLOR.g, 0.001)
	assert_almost_eq(tint.b, PLAYER_COLOR.b, 0.001)


func test_outside_territory_is_invalid_red() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.OUTSIDE_TERRITORY)
	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)
	assert_true(_body_tint(ghost).is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.invalid_tint_color)))


func test_hole_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.HOLE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_true(_body_tint(ghost).is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.hole_tint_color)))


## Territory v2: a goal flag's no-build
## zone reads the same as a legacy hole — hatched, hole_tint_color — since the
## spec's "hatched pattern when over a hole" visual language already means
## "can't build here" for either reason.
func test_goal_zone_is_hatched() -> void:
	var ghost: GhostPreview = _make_ghost()
	ghost.apply_validity(PlacementRules.Result.GOAL_ZONE)
	assert_eq(ghost.current_state(), GhostPreview.STATE_HOLE)
	assert_true(_body_tint(ghost).is_equal_approx(_with_ghost_opacity(ghost, ghost.ghost_tuning.hole_tint_color)))


# --- Controller wiring: the ghost tint follows the context's preview_placement -----


func test_controller_applies_preview_result_to_ghost_every_frame() -> void:
	var holder: Node = Node.new()
	add_child_autofree(holder)
	var ghost: GhostPreview = _make_ghost()
	ghost.name = &"Ghost"
	ghost.get_parent().remove_child(ghost)
	holder.add_child(ghost)

	var context: FakeMatchContext = FakeMatchContext.new()
	context.preview_placement_value = PlacementRules.Result.CONTESTED
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = NodePath("../Ghost")
	controller.match_context = context
	holder.add_child(controller)
	controller.set_acting_slot(0)

	controller._process(1.0 / 60.0)

	assert_eq(ghost.current_state(), GhostPreview.STATE_INVALID)

	context.preview_placement_value = PlacementRules.Result.VALID
	controller._process(1.0 / 60.0)
	assert_eq(ghost.current_state(), GhostPreview.STATE_VALID)

	context.release_locked_by_slot[0] = true
	controller._process(1.0 / 60.0)
	assert_eq(ghost.current_state(), GhostPreview.STATE_LOCKED, "a release-locked slot overrides the legal-spot tint.")
