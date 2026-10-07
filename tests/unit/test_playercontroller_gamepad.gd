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


## Bontago (options package): Settings.stick_move_speed_scale() (Options
## menu's device-aware Controls-tab slider) scales the gamepad cursor's own
## max speed on top of the tuning Resource's gamepad_cursor_base_speed
## baseline -- independent of Settings.mouse_move_speed_scale().
func test_stick_move_speed_scale_increases_gamepad_cursor_motion() -> void:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = -1
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 1.0
	Input.parse_input_event(motion)
	Input.flush_buffered_events()

	var baseline: PlayerController = autofree(PlayerController.new())
	add_child_autofree(baseline)
	Settings.set_stick_move_speed_scale(1.0)
	# Bontago (options package): the cursor accelerates toward max_speed
	# rather than snapping to it (ghost_tuning.gamepad_cursor_acceleration),
	# so several frames are needed before the velocity actually saturates at
	# (scaled) max_speed -- one single short frame is acceleration-capped
	# identically regardless of the target speed and would not show a
	# difference at all.
	for _i: int in range(150):
		baseline._update_gamepad_cursor(1.0 / 60.0)

	var scaled: PlayerController = autofree(PlayerController.new())
	add_child_autofree(scaled)
	Settings.set_stick_move_speed_scale(2.0)
	for _i: int in range(150):
		scaled._update_gamepad_cursor(1.0 / 60.0)

	assert_gt(scaled._cursor_velocity.length(), baseline._cursor_velocity.length(), "a 2x stick speed scale should saturate the gamepad cursor's velocity higher than the 1x baseline.")
	assert_almost_eq(baseline._cursor_velocity.length(), baseline.ghost_tuning.gamepad_cursor_base_speed, 0.5)
	# Bontago-1pi.109: slider 100% now equals the former 120% (30 * 1.2).
	assert_almost_eq(baseline._cursor_velocity.length(), 30.0 * 1.2, 0.5)
	assert_almost_eq(scaled._cursor_velocity.length(), scaled.ghost_tuning.gamepad_cursor_base_speed * 2.0, 0.5)
	assert_eq(Settings.mouse_move_speed_scale(), 1.0, "the mouse scale must be untouched by the stick scale setter.")

	Settings.reset_move_speed_scales()
	var release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	release.device = -1
	release.axis = JOY_AXIS_LEFT_X
	release.axis_value = 0.0
	Input.parse_input_event(release)
	Input.flush_buffered_events()


## Bontago-mv0.14: rotate_yaw_ccw/cw are pad DEVICE_EXCEPTIONs (keyboard A/S
## only, tests/unit/test_project_setup.gd) -- B (rotate_snap) is the gamepad's
## own 90 degree yaw tap. Owner controller update (feedback/controller-update.md,
## re-confirmed 2026-09-28) reassigned the shoulder buttons to hover raise/
## lower (see test_gamepad_hover_raise_held_continuously_raises_the_ghost/
## test_gamepad_hover_lower_held_continuously_lowers_the_ghost below), so this
## exercises rotate_snap (B) instead of the shoulder-button binding this test
## used to check before that reassignment.
func test_gamepad_rotate_snap_button_steps_the_orientation_table() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

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


## Bontago-mv0.14 (original tutorial: "while holding the rotation-mode key,
## the movement keys change the orientation of the block"): the gamepad's
## "movement keys" are the left stick (ghost_move_*), the same axes
## test_gamepad_stick_moves_the_ghost_cursor drives -- rotation_mode reroutes
## them into a 90 degree snap instead of moving the cursor.
##
## Owner controller update (feedback/controller-update.md, re-confirmed
## 2026-09-28): rotation_mode's gamepad binding (the right trigger) moved to
## the new rotate_drag_pad action (free rotation, see
## test_gamepad_rotate_drag_pad_free_rotates_like_mmb_drag_and_freezes_the_cursor
## above) -- rotation_mode is keyboard-only now (R), so this drives the action
## directly with Input.action_press() rather than a synthetic trigger event,
## to keep covering PlayerController's own rotation_mode+stick handling
## without depending on which physical input the Input Map binds it to.
func test_gamepad_rotation_mode_left_stick_snaps_orientation_instead_of_moving_the_cursor() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

	Input.action_press(&"rotation_mode")

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

	assert_eq(ghost.orientation_index, BlockOrientations.step_yaw_cw(0), "full left-stick deflection should snap one CW yaw step.")
	assert_eq(controller._cursor, Vector3.ZERO, "rotation_mode must not also move the cursor.")

	# Release so it doesn't bleed into later tests.
	Input.action_release(&"rotation_mode")

	var stick_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_release.device = -1
	stick_release.axis = JOY_AXIS_LEFT_X
	stick_release.axis_value = 0.0
	Input.parse_input_event(stick_release)
	Input.flush_buffered_events()


## Bontago-mv0.17 item 5 (owner feel report: "the block's height changes ONLY
## via the wheel"): the gamepad's hover_raise/hover_lower bindings are the
## "wheel" for a gamepad player and must keep working exactly as before --
## held continuously, unlike the mouse wheel's one-notch-per-press.
## Owner controller update (feedback/controller-update.md, re-confirmed
## 2026-09-28: "RB = hover raise, LB = hover lower (held)") moved these off
## RS click/X onto the shoulder buttons.
func test_gamepad_hover_raise_held_continuously_raises_the_ghost() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

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
	controller._handle_hover_adjust(1.0)

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


# Bontago-59o.5: the held path already ramps (hover_hold_acceleration); pin
# that a longer hold moves further per second than the first second.
func test_gamepad_hover_raise_held_longer_accelerates() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_RIGHT_SHOULDER
	button_event.pressed = true
	Input.parse_input_event(button_event)
	Input.flush_buffered_events()

	controller._handle_hover_adjust(1.0)
	var first_second: float = ghost.manual_hover_offset
	controller._handle_hover_adjust(1.0)
	var second_second: float = ghost.manual_hover_offset - first_second
	assert_gt(second_second, first_second, "holding RB longer should raise faster per second.")

	var release: InputEventJoypadButton = button_event.duplicate() as InputEventJoypadButton
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()
	controller._handle_hover_adjust(0.1)
	assert_eq(controller._hover_hold_seconds, 0.0, "releasing resets the ramp.")


func test_gamepad_hover_lower_held_continuously_lowers_the_ghost() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.manual_hover_offset = 5.0

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost

	var button_event: InputEventJoypadButton = InputEventJoypadButton.new()
	button_event.device = -1
	button_event.button_index = JOY_BUTTON_LEFT_SHOULDER
	button_event.pressed = true
	assert_true(
		button_event.is_action_pressed(&"hover_lower"),
		"LB should map to hover_lower (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(button_event)
	Input.flush_buffered_events()

	var before: float = ghost.manual_hover_offset
	controller._handle_hover_adjust(1.0)

	assert_almost_eq(
		ghost.manual_hover_offset, before - controller.ghost_tuning.hover_manual_adjust_speed, 0.001,
		"holding the gamepad's hover_lower button should lower the ghost continuously, at hover_manual_adjust_speed per second."
	)

	# Release so it doesn't bleed into later tests.
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = JOY_BUTTON_LEFT_SHOULDER
	release.pressed = false
	Input.parse_input_event(release)
	Input.flush_buffered_events()


## Owner controller update (feedback/controller-update.md, re-confirmed
## 2026-09-28): "RT held + left stick = continuous free rotation of the held
## block exactly like holding MMB and moving the mouse ... NOT the current
## rotation_mode 90-degree snap grid". Drives free_quaternion (not the
## orientation_index snap table), same direction convention rotate_drag's own
## mouse-motion branch uses (test_playercontroller_mouse.gd), and must not
## move the cursor while held.
func test_gamepad_rotate_drag_pad_free_rotates_like_mmb_drag_and_freezes_the_cursor() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	var cursor_before: Vector3 = controller._cursor

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

	controller._update_gamepad_cursor(1.0)

	# Mirrors rotate_drag's own mouse-motion branch: +X input yaws the same
	# direction a +X mouse-relative drag does (both negate the raw input
	# before scaling), so free_quaternion must actually have changed, not
	# just be non-identity by construction.
	assert_ne(
		ghost.free_quaternion, Quaternion.IDENTITY,
		"holding rotate_drag_pad (RT) with stick deflection must free-rotate the ghost."
	)
	assert_eq(ghost.orientation_index, 0, "rotate_drag_pad must not touch the 90-degree snap table, only free_quaternion.")
	assert_eq(controller._cursor, cursor_before, "rotate_drag_pad must not move the cursor while held.")

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


## Owner controller update: "LT held + left stick up/down = zoom camera in
## (stick up) / out (stick down), continuous"; "Triggers alone must NEVER
## zoom"; "While either trigger modifier is held, the ghost cursor must not
## move".
func test_gamepad_camera_zoom_modifier_zooms_with_stick_not_trigger_alone_and_freezes_the_cursor() -> void:
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	rig.set_process(false)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller.set_camera_rig(rig)
	var cursor_before: Vector3 = controller._cursor

	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.device = -1
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	assert_true(
		trigger.is_action_pressed(&"camera_zoom_modifier"),
		"Left trigger should map to camera_zoom_modifier (tools/bootstrap_project.gd)."
	)
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()

	# Trigger alone (no stick deflection): distance must not change at all.
	var distance_before: float = rig.get_distance()
	controller._update_gamepad_cursor(1.0)
	assert_almost_eq(rig.get_distance(), distance_before, 0.0001, "the trigger alone must never zoom.")
	assert_eq(controller._cursor, cursor_before, "camera_zoom_modifier must not move the cursor while held, even with no stick input.")

	var stick_up: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_up.device = -1
	stick_up.axis = JOY_AXIS_LEFT_Y
	stick_up.axis_value = -1.0  # stick pushed up.
	Input.parse_input_event(stick_up)
	Input.flush_buffered_events()

	controller._update_gamepad_cursor(1.0)

	assert_lt(rig.get_distance(), distance_before, "stick up while LT is held must zoom in (decrease distance).")
	assert_eq(controller._cursor, cursor_before, "camera_zoom_modifier must not move the cursor while held.")

	var closer_distance: float = rig.get_distance()
	var stick_down: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_down.device = -1
	stick_down.axis = JOY_AXIS_LEFT_Y
	stick_down.axis_value = 1.0  # stick pushed down.
	Input.parse_input_event(stick_down)
	Input.flush_buffered_events()

	controller._update_gamepad_cursor(1.0)

	assert_gt(rig.get_distance(), closer_distance, "stick down while LT is held must zoom out (increase distance).")

	var trigger_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger_release.device = -1
	trigger_release.axis = JOY_AXIS_TRIGGER_LEFT
	trigger_release.axis_value = 0.0
	Input.parse_input_event(trigger_release)
	Input.flush_buffered_events()

	var stick_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	stick_release.device = -1
	stick_release.axis = JOY_AXIS_LEFT_Y
	stick_release.axis_value = 0.0
	Input.parse_input_event(stick_release)
	Input.flush_buffered_events()


## Bontago-1pi.85.29: throwing no longer uses LT (no hold-to-aim state), so LT + stick zoom
## applies to every held piece, throwables included, and LT alone never throws or places.
func test_gamepad_camera_zoom_modifier_never_starts_a_throw_on_a_held_special() -> void:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0

	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.held_shapes[0] = cube_shape
	fake_match.held_special_by_slot[0] = &"bomb"
	controller._match = fake_match

	var trigger: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger.device = -1
	trigger.axis = JOY_AXIS_TRIGGER_LEFT
	trigger.axis_value = 1.0
	Input.parse_input_event(trigger)
	Input.flush_buffered_events()

	controller._update_throw_aim(1.0 / 60.0)

	assert_eq(fake_match.request_throw_calls.size(), 0, "LT alone throws nothing")
	assert_eq(fake_match.request_place_calls.size(), 0, "LT alone places nothing")

	var trigger_release: InputEventJoypadMotion = InputEventJoypadMotion.new()
	trigger_release.device = -1
	trigger_release.axis = JOY_AXIS_TRIGGER_LEFT
	trigger_release.axis_value = 0.0
	Input.parse_input_event(trigger_release)
	Input.flush_buffered_events()
