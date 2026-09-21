extends GutTest
## CLAUDE.md / Hard Rules: verify gamepad input paths with synthetic
## InputEventJoypadButton/Motion events, since there's no physical pad here.
##
## Updated for M2 (docs/M2_PLAN.md P4): ghost_place is now intent-only (spec
## 3.4), so a press should send exactly one Match.request_place() call
## rather than spawn a block directly — see tests/unit/support/FakeMatch.gd.


func test_gamepad_button_places_a_block() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)
	ghost.global_position = Vector3(0.0, 5.0, 0.0)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.held_shapes[0] = cube_shape
	controller._match = fake_match

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_A
	button_event.pressed = true
	assert_true(
		button_event.is_action_pressed(&"ghost_place"),
		"JOY_BUTTON_A should map to ghost_place (tools/bootstrap_project.gd)."
	)

	controller._unhandled_input(button_event)

	assert_eq(
		fake_match.request_place_calls.size(), 1,
		"A synthetic gamepad ghost_place press should send exactly one placement intent."
	)
	assert_eq(fake_match.request_place_calls[0]["slot_id"], 0)
	assert_eq(fake_match.request_place_calls[0]["auto_drop"], false)


func test_gamepad_stick_moves_the_ghost_cursor() -> void:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)

	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 1.0
	assert_true(
		motion.is_action_pressed(&"ghost_move_right"),
		"Left stick +X should map to ghost_move_right (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()

	controller._update_gamepad_cursor(1.0)

	assert_true(controller._using_gamepad_cursor, "Pushing the left stick should switch input to the gamepad cursor.")
	# Bontago-mv0.14: renamed from _gamepad_cursor to _cursor -- mouse motion
	# moves the same field now (see test_playercontroller_mouse.gd).
	assert_gt(controller._cursor.x, 0.0, "ghost_move_right should move the cursor toward +X at camera yaw 0.")

	# Zero the synthetic axis (a fresh event — Godot warns if the same event
	# object is parsed twice in one frame) so it doesn't bleed into later tests.
	var release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	release.device = -1
	release.axis = JOY_AXIS_LEFT_X
	release.axis_value = 0.0
	Input.parse_input_event(release)
	Input.flush_buffered_events()


func test_gamepad_rotation_buttons_step_the_orientation_table() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_LEFT_SHOULDER
	button_event.pressed = true
	assert_true(
		button_event.is_action_pressed(&"rotate_yaw_ccw"),
		"LB should map to rotate_yaw_ccw (tools/bootstrap_project.gd)."
	)

	controller._unhandled_input(button_event)

	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_ccw(0))


## Bontago-mv0.14 (original tutorial: "while holding the rotation-mode key,
## the movement keys change the orientation of the block"): the gamepad's
## "movement keys" are the left stick (ghost_move_*), the same axes
## test_gamepad_stick_moves_the_ghost_cursor drives -- rotation_mode (right
## trigger) reroutes them into a 90 degree snap instead of moving the cursor.
func test_gamepad_rotation_mode_left_stick_snaps_orientation_instead_of_moving_the_cursor() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.device = -1
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	assert_true(
		trigger.is_action_pressed(&"rotation_mode"),
		"Right trigger should map to rotation_mode (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()

	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.device = -1
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()

	# pad_rotation_speed is "drag units per second at full deflection"; one
	# big delta stands in for enough frames to cross the 1.0 step threshold
	# (the same convention test_gamepad_stick_moves_the_ghost_cursor uses).
	var seconds_needed: float = 1.0 / controller.ghost_tuning.pad_rotation_speed
	controller._update_gamepad_cursor(seconds_needed + 0.05)

	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_cw(0), "full right-stick deflection should snap one CW yaw step.")
	assert_eq(controller._cursor, Vector3.ZERO, "rotation_mode must not also move the cursor.")

	# Release both synthetic axes so they don't bleed into later tests.
	var trigger_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger_release.device = -1
	trigger_release.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger_release.axis_value = 0.0
	Input.parse_input_event(trigger_release)
	Input.flush_buffered_events()

	var stick_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_release.device = -1
	stick_release.axis = JOY_AXIS_LEFT_X
	stick_release.axis_value = 0.0
	Input.parse_input_event(stick_release)
	Input.flush_buffered_events()
