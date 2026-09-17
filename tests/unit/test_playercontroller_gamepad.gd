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
	assert_gt(controller._gamepad_cursor.x, 0.0, "ghost_move_right should move the cursor toward +X at camera yaw 0.")

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
