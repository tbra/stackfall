extends GutTest
## CLAUDE.md / Hard Rules: verify gamepad input paths with synthetic
## InputEventJoypadButton/Motion events, since there's no physical pad here.
##
## ghost_place is now intent-only (spec
## 3.4), so a press should send exactly one submit_place() intent through the
## match context rather than spawn a block directly — see
## tests/support/FakeMatchContext.gd.


## The controller finds its ghost through the exported ghost_path, as LocalPlayer.tscn
## wires it: a sibling "Ghost" under one holder. `context` (when given) is installed on
## match_context before add_child, the way LocalPlayer injects the port.
func _make_controller(ghost: GhostPreview, context: MatchContext = null) -> PlayerController:
	var holder: Node = Node.new()
	add_child_autofree(holder)
	ghost.name = &"Ghost"
	holder.add_child(ghost)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.ghost_path = NodePath("../Ghost")
	if context != null:
		controller.match_context = context
	holder.add_child(controller)
	return controller


func _make_ghost() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	return ghost


## Where the cursor aims, read off the ghost: the rotated shape's centre sits over the cursor.
func _cursor_xz(ghost: GhostPreview) -> Vector2:
	var centre: Vector3 = ghost.rotated_center_world()
	return Vector2(centre.x, centre.z)


func test_gamepad_button_places_a_block() -> void:
	var ghost: GhostPreview = _make_ghost()
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	var context: FakeMatchContext = FakeMatchContext.new()
	context.held_shape_by_slot[0] = cube_shape
	var controller: PlayerController = _make_controller(ghost, context)
	ghost.set_shape(cube_shape)
	ghost.global_position = Vector3(0.0, 5.0, 0.0)
	controller.set_acting_slot(0)

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
		context.submit_place_calls.size(), 1,
		"A synthetic gamepad ghost_place press should send exactly one placement intent."
	)
	assert_eq(context.submit_place_calls[0]["slot_id"], 0)
	assert_eq(context.submit_place_calls[0]["auto_drop"], false)
	assert_eq(
		context.submit_place_calls[0]["origin"], ghost.global_position,
		"the intent carries the pose the ghost shows."
	)


func test_gamepad_stick_moves_the_ghost_cursor() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = _make_controller(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	controller._process(1.0)
	var before: Vector2 = _cursor_xz(ghost)

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

	controller._process(1.0)

	# The cursor is the one both devices move (see test_playercontroller_mouse.gd); the
	# ghost sits over it.
	assert_gt(_cursor_xz(ghost).x, before.x, "ghost_move_right should move the cursor toward +X at camera yaw 0.")
	assert_almost_eq(_cursor_xz(ghost).y, before.y, 0.001, "and not sideways.")

	# Zero the synthetic axis (a fresh event — Godot warns if the same event
	# object is parsed twice in one frame) so it doesn't bleed into later tests.
	var release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	release.device = -1
	release.axis = JOY_AXIS_LEFT_X
	release.axis_value = 0.0
	Input.parse_input_event(release)
	Input.flush_buffered_events()


## rotate_yaw_ccw/cw are pad DEVICE_EXCEPTIONs (keyboard A/S
## only, tests/unit/main/test_project_setup.gd) -- B (rotate_snap) is the gamepad's
## own 90 degree yaw tap. Controller update (re-confirmed)
## reassigned the shoulder buttons to hover raise/
## lower (see test_gamepad_hover_raise_held_continuously_raises_the_ghost/
## test_gamepad_hover_lower_held_continuously_lowers_the_ghost below), so this
## exercises rotate_snap (B) instead of the shoulder-button binding this test
## used to check before that reassignment.
func test_gamepad_rotate_snap_button_steps_the_orientation_table() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = _make_controller(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_B
	button_event.pressed = true
	assert_true(
		button_event.is_action_pressed(&"rotate_snap"),
		"B should map to rotate_snap (tools/bootstrap_project.gd)."
	)

	controller._unhandled_input(button_event)

	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_cw(0))


## Requirement: "the block's height changes ONLY
## via the wheel"): the gamepad's hover_raise/hover_lower bindings are the
## "wheel" for a gamepad player and must keep working exactly as before --
## held continuously, unlike the mouse wheel's one-notch-per-press.
## Controller update (re-confirmed
## "RB = hover raise, LB = hover lower (held)") moved these off
## RS click/X onto the shoulder buttons.
func test_gamepad_hover_raise_held_continuously_raises_the_ghost() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = _make_controller(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	button_event.pressed = true
	assert_true(
		button_event.is_action_pressed(&"hover_raise"),
		"RB should map to hover_raise (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(button_event)
	Input.flush_buffered_events()

	var before: float = ghost.manual_hover_offset
	controller._process(1.0)

	assert_almost_eq(
		ghost.manual_hover_offset, before + controller.ghost_tuning.hover_manual_adjust_speed, 0.001,
		"holding the gamepad's hover_raise button should raise the ghost continuously, at hover_manual_adjust_speed per second."
	)

	# Release so it doesn't bleed into later tests.
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = JOY_BUTTON_RIGHT_SHOULDER
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


## Controller update: "RT held + left stick = continuous free rotation of the held
## block exactly like holding MMB and moving the mouse ... NOT the current
## rotation_mode 90-degree snap grid". Drives free_quaternion (not the
## orientation_index snap table), same direction convention rotate_drag's own
## mouse-motion branch uses (test_playercontroller_mouse.gd), and must not
## move the cursor while held.
func test_gamepad_rotate_drag_pad_free_rotates_like_mmb_drag_and_freezes_the_cursor() -> void:
	var ghost: GhostPreview = _make_ghost()
	var controller: PlayerController = _make_controller(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	controller._process(1.0)
	var cursor_before: Vector2 = _cursor_xz(ghost)

	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.device = -1
	trigger.axis = JOY_AXIS_TRIGGER_RIGHT
	trigger.axis_value = 1.0
	assert_true(
		trigger.is_action_pressed(&"rotate_drag_pad"),
		"Right trigger should map to rotate_drag_pad (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()

	var stick: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick.device = -1
	stick.axis = JOY_AXIS_LEFT_X
	stick.axis_value = 1.0
	Input.parse_input_event(stick)
	Input.flush_buffered_events()

	controller._process(1.0)

	# Mirrors rotate_drag's own mouse-motion branch: +X input yaws the same
	# direction a +X mouse-relative drag does (both negate the raw input
	# before scaling), so free_quaternion must actually have changed, not
	# just be non-identity by construction.
	assert_ne(
		ghost.free_quaternion, Quaternion.IDENTITY,
		"holding rotate_drag_pad (RT) with stick deflection must free-rotate the ghost."
	)
	assert_eq(ghost.orientation_index, 0, "rotate_drag_pad must not touch the 90-degree snap table, only free_quaternion.")
	assert_almost_eq(_cursor_xz(ghost), cursor_before, Vector2(0.001, 0.001), "rotate_drag_pad must not move the cursor while held.")

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

