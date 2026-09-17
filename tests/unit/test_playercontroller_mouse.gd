extends GutTest
## PlayerController.gd: MMB is bound to both rotate_pitch_fwd (a tap) and
## camera_orbit_hold (a hold); CLAUDE.md requires the split to go through the
## Input Map ("All input goes through the Input Map. ... Never check raw
## keycodes in code"), so this exercises it with synthetic
## InputEventMouseButton presses/releases rather than a raw
## MOUSE_BUTTON_MIDDLE check in the source.


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


func _mmb_event(pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event


func test_quick_mmb_tap_rotates_pitch_forward() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_mmb_event(true))
	controller._unhandled_input(_mmb_event(false))

	assert_eq(
		controller._ghost.orientation_index,
		BlockOrientations.step_pitch_fwd(start_index),
		"A quick MMB tap should step rotate_pitch_fwd."
	)


func test_long_mmb_hold_does_not_rotate() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_mmb_event(true))
	# Simulate a hold longer than camera_tuning.mmb_tap_max_duration by
	# rewinding the recorded press time instead of a real sleep.
	controller._mmb_press_time -= controller.camera_tuning.mmb_tap_max_duration + 1.0
	controller._unhandled_input(_mmb_event(false))

	assert_eq(
		controller._ghost.orientation_index,
		start_index,
		"A long MMB hold (camera orbit) must not also rotate the block."
	)
