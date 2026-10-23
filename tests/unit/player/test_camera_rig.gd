extends GutTest
## game/player/CameraRig.gd's own coverage (previously only exercised indirectly
## through test_playercontroller_mouse.gd's follow-block tests).
##
## Requirement: "on match start the follow
## camera's yaw must look from the player's home flag toward the disk
## centre"): CameraRig.set_home_view() is what PlayerController.
## set_home_position() calls once a controller binds to a real slot
## (game/main/LocalPlayer.gd's bind_local_slot(), game/sandbox/Sandbox.gd's own turn-changed
## handler) — see those files' own DECISION comments for who calls this and
## why.


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


func test_set_home_view_points_the_rig_from_home_toward_the_center() -> void:
	var rig: CameraRig = _make_rig()

	var home: Vector3 = Vector3(0.0, 0.0, 20.0)
	rig.set_home_view(home)

	var expected_yaw: float = atan2(home.x, home.z)
	assert_almost_eq(rig.get_yaw(), expected_yaw, 0.001)
	assert_almost_eq(rig.get_target().x, home.x, 0.001)
	assert_almost_eq(rig.get_target().z, home.z, 0.001)


func _make_ghost_with_shape() -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	return ghost


func test_camera_target_matches_the_ghost_position_the_same_frame_it_moves() -> void:
	# Same order as game/main/LocalPlayer.tscn: the rig exists first,
	# the controller (and its ghost) are added afterward.
	var rig: CameraRig = _make_rig()
	var ghost: GhostPreview = _make_ghost_with_shape()
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller.set_camera_rig(rig)
	# DECISION (tests/unit/player/test_camera_rig.gd): a rig-local tuning duplicate
	# with ghost_collision disabled -- this test is isolating the CameraRig/
	# PlayerController process-order question only.'s swept
	# collision test (_clamp_cursor_collision()) queries the live
	# PhysicsDirectSpaceState3D every _process(), which only reflects whatever
	# the physics server has actually stepped so far; with no Field/physics
	# ticks driving this bare test tree, that lags render frames unevenly and
	# introduces its own frame-to-frame variance unrelated to the camera bug
	# under test here (see test_ghost_collision.gd for that feature's own
	# coverage).
	controller.ghost_tuning = controller.ghost_tuning.duplicate() as GhostTuning
	controller.ghost_tuning.ghost_collision_enabled = false

	# A newly add_child()'d node's first _process() call can land one
	# process_frame signal later than the frame it was actually added on
	# (Godot's own scheduling, nothing to do with this bug) -- let that
	# one-time startup transient pass before the constant-motion loop below,
	# so it measures steady-state behaviour, not this test fixture's own
	# warm-up frame.
	await get_tree().process_frame
	await get_tree().process_frame

	var previous_ghost_x: float = ghost.global_position.x
	var previous_displacement: float = 0.0
	for i: int in range(60):
		# A fixed per-iteration cursor step, independent of the real engine's
		# (possibly uneven, headless) frame delta -- isolates "does the camera
		# see the same frame's ghost position" from unrelated frame-timing
		# noise, and gives a displacement that can only be non-constant if
		# something in the ghost/camera pipeline itself introduces variance.
		controller._cursor += Vector3(0.1, 0.0, 0.0)
		await get_tree().process_frame

		var displacement: float = ghost.global_position.x - previous_ghost_x
		if i > 0:
			assert_almost_eq(
				displacement, previous_displacement, 0.0001,
				"frame %d: the ghost's per-frame displacement must stay constant under constant input." % i
			)
		previous_ghost_x = ghost.global_position.x
		previous_displacement = displacement

		assert_almost_eq(
			rig.get_target().x, ghost.global_position.x, 0.0001,
			"frame %d: the camera target must equal the ghost position from this same frame, not one frame stale." % i
		)


func test_process_freezes_target_yaw_pitch_and_distance_while_rotate_drag_is_held() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate() as CameraTuning
	rig.set_home_view(Vector3(5.0, 0.0, 10.0))
	rig._process(1.0 / 60.0)

	var target_before: Vector3 = rig.get_target()
	var yaw_before: float = rig.get_yaw()
	var pitch_before: float = rig.get_pitch()
	var distance_before: float = rig.get_distance()
	var transform_before: Transform3D = rig.get_camera().global_transform

	Input.action_press(&"rotate_drag")
	# A moving follow target -- the ghost's rotated centre sliding during the
	# drag, an earlier regression -- must not move the camera while frozen,
	# and neither should the gamepad's always-on right-stick orbit strength
	# left at zero here (asserted separately by the RMB+MMB test below).
	for i: int in range(5):
		rig.set_follow_position(Vector3(5.0 + float(i), 1.0, 10.0 - float(i)))
		rig._process(1.0 / 60.0)
		assert_true(
			rig.get_target().is_equal_approx(target_before),
			"frame %d: target must not move while rotate_drag is held." % i
		)
	Input.action_release(&"rotate_drag")

	assert_almost_eq(rig.get_yaw(), yaw_before, 0.0001, "yaw must be untouched by the frozen frames.")
	assert_almost_eq(rig.get_pitch(), pitch_before, 0.0001, "pitch must be untouched by the frozen frames.")
	assert_almost_eq(rig.get_distance(), distance_before, 0.0001, "distance must be untouched by the frozen frames.")
	assert_true(
		rig.get_camera().global_transform.is_equal_approx(transform_before),
		"global_transform must be bit-for-bit unchanged for the whole drag."
	)

	# MMB release -> follows again (follow_lag_seconds == 0 here, an instant
	# snap to the latest set_follow_position(), same as any other frame).
	rig._process(1.0 / 60.0)
	assert_true(
		rig.get_target().is_equal_approx(Vector3(9.0, 1.0, 6.0)),
		"after release, the rig must resume following the latest follow position."
	)


func _key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	return event


func _disturb(rig: CameraRig) -> void:
	rig._yaw += 1.0
	rig._pitch = deg_to_rad(-70.0)
	rig._distance = rig.tuning.zoom_min
	rig._update_transform()


## camera_reset (V / pad Back) restores the match-start pose.
func test_camera_reset_key_restores_the_recorded_start_pose() -> void:
	var rig: CameraRig = _make_rig()
	rig.tuning = rig.tuning.duplicate()
	rig.tuning.snap_enabled = false
	rig._has_start_pose = true
	rig._start_yaw = 0.4
	rig._start_pitch = deg_to_rad(-20.0)
	rig._start_distance = 12.0
	_disturb(rig)
	rig._unhandled_input(_key_event(KEY_V))
	assert_almost_eq(rig.get_yaw(), 0.4, 0.0001)
	assert_almost_eq(rig.get_pitch(), deg_to_rad(-20.0), 0.0001)
	assert_almost_eq(rig.get_distance(), 12.0, 0.0001)

