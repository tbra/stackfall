extends GutTest
## PlayerController.gd mouse-input coverage (original-style
## block-locked controls -- spec 1.5/2.5, docs/ORIGINAL_BONTAGO_NOTES.md
## "Controls"). Mouse motion moves a world-space cursor directly (no more
## screen-space raycast), the wheel is block height, holding rotation_mode
## turns motion into 90 degree orientation snaps, camera_mode hands motion to
## CameraRig instead, and lock_vertical ignores planar motion. CameraRig's
## follow-block mode is exercised here too, since PlayerController is what
## feeds it a position every frame (set_camera_rig()/set_follow_position()).
##
## replaced the old MMB tap/hold split
## (rotate_pitch_fwd/camera_orbit_hold) this file used to pin: MMB is now
## rotate_snap (a plain 90 degree yaw tap) and camera_mode moved to its own
## key (C), so those two tests -- and camera_tuning.mmb_tap_max_duration,
## which they were the only reader of -- are gone.
##
## spec 1.4, [ORIGINAL] rows re-tested by the owner
## : MMB gained a second, continuous job on top of rotate_snap's
## tap -- holding it and dragging spins the ghost's free rotation
## (rotate_drag) -- and RMB became camera_orbit, a second hold that does the
## same thing camera_mode (C) already does, plus lets the wheel zoom the rig
## instead of raising the ghost while either is held.
##
## Requirement: rotate_drag
## became full 3-DOF -- horizontal motion still yaws about world up, but
## vertical motion now pitches about the camera's current right axis instead
## of doing nothing.
##
## Also carries a regression pin (Part B, "the host cannot
## place"): the real root cause turned out to be ui/lobby/Lobby.gd sending
## hot_seat = true (see tests/unit/ui/test_lobby.gd's
## test_default_lobby_data_is_never_hot_seat), but PlayerController's own
## networked gating -- _acting_slot() reading Net.local_slot() rather than
## waiting on Events.turn_changed -- is the layer that would have hidden a
## reintroduced version of the same class of bug, so it gets its own direct
## pin here too.


func _make_controller() -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))

	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	return controller


func _motion(relative: Vector2) -> InputEventMouseMotion:
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.relative = relative
	return event


func _wheel(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


# --- Cursor movement (spec 1.5: "the mouse positions the block") -----------

func test_mouse_motion_moves_the_cursor_in_the_disk_plane() -> void:
	var controller: PlayerController = _make_controller()
	assert_eq(controller._cursor, Vector3.ZERO, "fixture: the cursor starts centered.")

	controller._unhandled_input(_motion(Vector2(100.0, 0.0)))

	assert_almost_eq(
		controller._cursor.x, 100.0 * controller.ghost_tuning.block_move_sensitivity, 0.001,
		"mouse X motion should move the cursor camera-relative (no rig wired -> yaw 0 -> world +X)."
	)
	assert_almost_eq(controller._cursor.z, 0.0, 0.001)


func test_mouse_motion_is_camera_relative_to_the_rigs_yaw() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/player/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)

	# Orbit the rig 90 degrees with camera_mode + motion so "world +X" stops
	# being the cursor's rightward direction.
	Input.action_press(&"camera_mode")
	rig._unhandled_input(_motion(Vector2(-PI * 0.5 / rig.tuning.mouse_orbit_speed, 0.0)))
	Input.action_release(&"camera_mode")
	assert_almost_eq(rig.get_yaw(), PI * 0.5, 0.01, "fixture: the rig should now be yawed 90 degrees.")

	controller._unhandled_input(_motion(Vector2(0.0, -100.0)))

	assert_almost_eq(controller._cursor.z, 0.0, 0.01, "camera-relative movement should follow the rotated yaw, not world +Z.")
	assert_ne(controller._cursor.x, 0.0, "at 90 degrees yaw, 'forward' motion should land on the X axis instead.")


# --- Wheel = block height (spec 1.5: "the mouse wheel raises and lowers the
# block") ---------------------------------------------------------------------

func test_wheel_up_raises_the_ghost_by_one_step() -> void:
	var controller: PlayerController = _make_controller()
	assert_eq(controller._ghost.manual_hover_offset, 0.0, "fixture: no manual hover yet.")

	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))

	assert_almost_eq(
		controller._ghost.manual_hover_offset, controller.ghost_tuning.hover_wheel_step, 0.001,
		"one wheel-up notch should raise the ghost by exactly one step (it's a momentary event, not held)."
	)


func _small_map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_pc_disk"
	map_def.field_radius = 10.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 16
	return map_def


func _make_field_for_controller() -> Field:
	var field: Field = Field.new()
	field.map_def = _small_map()
	add_child_autofree(field)
	return field


func _make_stacked_block(field: Field, at: Vector3) -> RigidBody3D:
	var body: RigidBody3D = RigidBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3.ONE
	collision.shape = box
	body.add_child(collision)
	field.get_parent().add_child(body)
	autofree(body)
	body.global_position = at
	return body


func test_moving_the_cursor_over_a_block_does_not_change_the_ghost_height() -> void:
	var field: Field = _make_field_for_controller()
	var controller: PlayerController = _make_controller()
	_make_stacked_block(field, Vector3(0.0, 5.0, 0.0))

	controller._update_ghost_transform()
	var height_over_the_block: float = controller._ghost.global_position.y

	controller._cursor = Vector3(5.0, 0.0, 0.0)  # bare disk, well away from the block
	controller._update_ghost_transform()
	var height_over_bare_disk: float = controller._ghost.global_position.y

	assert_almost_eq(
		height_over_the_block, height_over_bare_disk, 0.05,
		"the ghost's height must come from the disk surface, never from whatever is stacked underneath the cursor."
	)


func test_rotation_mode_hold_plus_motion_snaps_yaw_by_90_degrees() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	Input.action_press(&"rotation_mode")
	# block_rotation_sensitivity is tuned so ~120px of drag crosses one step.
	controller._unhandled_input(_motion(Vector2(130.0, 0.0)))
	Input.action_release(&"rotation_mode")

	assert_eq(
		controller._ghost.orientation_index, BlockOrientations.step_yaw_cw(start_index),
		"enough rightward drag while rotation_mode is held should snap exactly one yaw step."
	)
	assert_eq(controller._cursor, Vector3.ZERO, "rotation_mode must not also move the cursor.")


func test_rotate_drag_hold_plus_motion_spins_the_ghosts_free_quaternion() -> void:
	var controller: PlayerController = _make_controller()
	assert_eq(controller._ghost.free_quaternion, Quaternion.IDENTITY, "fixture: no free rotation yet.")

	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(100.0, 0.0)))
	Input.action_release(&"rotate_drag")

	assert_ne(
		controller._ghost.free_quaternion, Quaternion.IDENTITY,
		"holding rotate_drag and moving the mouse should spin the ghost's free rotation continuously."
	)
	assert_eq(controller._cursor, Vector3.ZERO, "rotate_drag must not also move the cursor.")
	assert_eq(
		controller._ghost.orientation_index, 0,
		"rotate_drag drives the continuous free_quaternion, not the 90 degree orientation index."
	)


func _mmb(pressed: bool) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_MIDDLE
	event.pressed = pressed
	return event


func test_mmb_tap_with_no_motion_snaps_one_yaw_step_on_release() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_mmb(true))
	controller._unhandled_input(_mmb(false))

	assert_eq(
		controller._ghost.orientation_index, BlockOrientations.step_yaw_cw(start_index),
		"a bare MMB press+release with no motion at all must snap exactly one 90 degree yaw step."
	)
	assert_eq(
		controller._ghost.free_quaternion, Quaternion.IDENTITY,
		"a bare tap must never touch the continuous free rotation."
	)


func test_q_key_resets_rotation_same_as_home_and_f() -> void:
	var controller: PlayerController = _make_controller()
	controller._ghost.set_orientation_index(BlockOrientations.step_yaw_cw(0))
	controller._ghost.apply_free_rotation_delta(0.3, 0.0, Vector3.RIGHT)
	assert_ne(controller._ghost.orientation_index, 0, "fixture: the ghost must actually be rotated before resetting it.")
	assert_ne(controller._ghost.free_quaternion, Quaternion.IDENTITY, "fixture: the ghost must have some free rotation too.")

	var q_event: InputEventKey = InputEventKey.new()
	q_event.physical_keycode = KEY_Q
	q_event.pressed = true
	controller._unhandled_input(q_event)

	assert_eq(controller._ghost.orientation_index, 0, "Q must reset the 90 degree orientation index like Home/F.")
	assert_eq(controller._ghost.free_quaternion, Quaternion.IDENTITY, "Q must reset the continuous free rotation like Home/F.")


func test_wheel_while_camera_orbit_held_zooms_the_rig_not_the_ghost_height() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/player/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	var distance_before: float = rig.get_distance()

	Input.action_press(&"camera_orbit")
	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	Input.action_release(&"camera_orbit")

	assert_ne(rig.get_distance(), distance_before, "the wheel should zoom the rig while camera_orbit is held.")
	assert_eq(
		controller._ghost.manual_hover_offset, 0.0,
		"the wheel must not also raise the ghost while camera_orbit is held."
	)


## "the mmb rotation issue persists, can the camera
## just be locked in place while mmb is pressed?" -- feedback/rotation-issue.png:
## The rotated-centre follow target still made the camera visibly move
## *during* a drag -- only the settled end state ever matched the ghost's
## rotated centre exactly, not every frame in between (rotated_center_offset()'s
## own doc comment: a pitch component tips the vertical origin-to-centre
## offset sideways progressively as the drag accumulates). This pins the
## reported complaint: the rig must not move at all, frame to frame, for
## as long as rotate_drag stays held, and must resume immediately once it's
## released.
func test_rotate_drag_freezes_the_camera_rig_for_the_whole_drag_then_resumes_on_release() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/player/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	assert_almost_eq(rig.tuning.follow_lag_seconds, 0.0, 0.0001, "fixture: the shipped rig snaps to its follow target instantly.")

	controller._process(1.0 / 60.0)
	rig._process(1.0 / 60.0)
	var target_before: Vector3 = rig.get_target()
	var transform_before: Transform3D = rig.get_camera().global_transform

	Input.action_press(&"rotate_drag")
	for i: int in range(6):
		controller._unhandled_input(_motion(Vector2(15.0, 10.0)))
		controller._process(1.0 / 60.0)
		rig._process(1.0 / 60.0)
		assert_true(
			rig.get_target().is_equal_approx(target_before),
			"frame %d: the rig's follow target must not move while rotate_drag is held." % i
		)
		assert_true(
			rig.get_camera().global_transform.is_equal_approx(transform_before),
			"frame %d: global_transform must be bit-for-bit unchanged for the whole drag." % i
		)
	Input.action_release(&"rotate_drag")
	assert_ne(controller._ghost.free_quaternion, Quaternion.IDENTITY, "fixture: the drag should have rotated the held block.")

	controller._process(1.0 / 60.0)
	rig._process(1.0 / 60.0)

	# Bontago-pt-4 (coordinator follow-up, shape-independent camera follow
	# anchor): only X/Z resume tracking the ghost's rotated centre -- Y now
	# comes from PlayerController._camera_follow_anchor()'s shape-independent
	# hover height instead (see that method's own doc comment), so it is
	# deliberately not part of this "resumes following" check any more.
	var target_after_release: Vector3 = rig.get_target()
	assert_almost_eq(
		target_after_release.x, controller._ghost.rotated_center_world().x, 0.0001,
		"after release, the rig should resume following the ghost's rotated centre in X."
	)
	assert_almost_eq(
		target_after_release.z, controller._ghost.rotated_center_world().z, 0.0001,
		"after release, the rig should resume following the ghost's rotated centre in Z."
	)
	# Bontago-pt-4: no longer asserts the target actually *moved* once resumed
	# -- this fixture's rotation-only drag (no cursor motion, no hover change)
	# now legitimately produces zero camera movement end to end, which is the
	# whole point of the shape-independent anchor (see
	# tests/unit/player/test_camera_drop_continuity.gd for that coverage). The frozen
	# loop above (assert_true at every held frame) already pins "did not move
	# while held"; free_quaternion's own assert_ne above already pins "the
	# drag really did rotate the block".


func test_continuous_wheel_scroll_ramps_the_step_and_resets_after_a_gap() -> void:
	var controller: PlayerController = _make_controller()
	var tuning: GhostTuning = controller.ghost_tuning
	var step: float = tuning.hover_wheel_step

	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(controller._ghost.manual_hover_offset, step, 0.001, "first notch is a plain step.")

	# Scroll on, one notch per short frame, past the ramp time.
	var frame: float = tuning.hover_wheel_gap_seconds * 0.5
	var elapsed: float = 0.0
	while elapsed < tuning.hover_wheel_ramp_seconds + frame:
		controller._tick_wheel_ramp(frame)
		controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
		elapsed += frame
	var before: float = controller._ghost.manual_hover_offset
	controller._tick_wheel_ramp(frame)
	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(
		controller._ghost.manual_hover_offset - before, step * tuning.hover_wheel_max_multiplier, 0.001,
		"after the ramp time of continuous scrolling the notch uses the max multiplier."
	)

	# A pause longer than the gap resets to a plain step.
	controller._tick_wheel_ramp(tuning.hover_wheel_gap_seconds + 0.1)
	before = controller._ghost.manual_hover_offset
	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	assert_almost_eq(controller._ghost.manual_hover_offset - before, step, 0.001, "the ramp resets after a gap.")
