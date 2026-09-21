extends GutTest
## PlayerController.gd mouse-input coverage (Bontago-mv0.14: original-style
## block-locked controls -- spec 1.5/2.5, docs/ORIGINAL_BONTAGO_NOTES.md
## "Controls"). Mouse motion moves a world-space cursor directly (no more
## screen-space raycast), the wheel is block height, holding rotation_mode
## turns motion into 90 degree orientation snaps, camera_mode hands motion to
## CameraRig instead, and lock_vertical ignores planar motion. CameraRig's
## follow-block mode is exercised here too, since PlayerController is what
## feeds it a position every frame (set_camera_rig()/set_follow_position()).
##
## Bontago-mv0.14 replaced the old MMB tap/hold split
## (rotate_pitch_fwd/camera_orbit_hold) this file used to pin: MMB is now
## rotate_snap (a plain 90 degree yaw tap) and camera_mode moved to its own
## key (C), so those two tests -- and camera_tuning.mmb_tap_max_duration,
## which they were the only reader of -- are gone.
##
## Also carries a Bontago-mv0.7 regression pin (Part B, "the host cannot
## place"): the real root cause turned out to be ui/Lobby.gd sending
## hot_seat = true (see tests/unit/test_lobby.gd's
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
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
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


func test_wheel_down_lowers_the_ghost_and_clamps_at_zero() -> void:
	var controller: PlayerController = _make_controller()

	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_DOWN))

	assert_almost_eq(controller._ghost.manual_hover_offset, 0.0, 0.001, "hover cannot go below zero.")


# --- Rotation mode (original tutorial: "while holding the rotation-mode key,
# the movement keys change the orientation of the block") ---------------------

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


func test_motion_moves_the_cursor_instead_of_rotating_without_the_hold() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	controller._unhandled_input(_motion(Vector2(130.0, 0.0)))

	assert_eq(controller._ghost.orientation_index, start_index, "without rotation_mode, motion should move the cursor, not rotate.")
	assert_gt(controller._cursor.x, 0.0)


# --- Lock vertical (original tutorial: "Locks block to vertical movement
# only") -------------------------------------------------------------------

func test_lock_vertical_hold_ignores_planar_mouse_motion() -> void:
	var controller: PlayerController = _make_controller()

	Input.action_press(&"lock_vertical")
	controller._unhandled_input(_motion(Vector2(100.0, 100.0)))
	Input.action_release(&"lock_vertical")

	assert_eq(controller._cursor, Vector3.ZERO, "lock_vertical should ignore XZ motion entirely; only the wheel changes height while held.")


# --- Camera mode (original tutorial: "while holding the camera-mode key,
# movement keys change where the camera is facing") ---------------------------

func test_camera_mode_hold_plus_motion_orbits_instead_of_moving_the_block() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	var yaw_before: float = rig.get_yaw()

	Input.action_press(&"camera_mode")
	var motion: InputEventMouseMotion = _motion(Vector2(100.0, 0.0))
	rig._unhandled_input(motion)
	controller._unhandled_input(motion)
	Input.action_release(&"camera_mode")

	assert_ne(rig.get_yaw(), yaw_before, "camera_mode + motion should orbit CameraRig.")
	assert_eq(controller._cursor, Vector3.ZERO, "camera_mode must not also move the ghost's cursor.")


# --- CameraRig follow-block mode (spec 1.5: "the camera is attached to the
# held block") --------------------------------------------------------------

func test_camera_rig_follows_the_ghost_smoothly_within_its_lag() -> void:
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	assert_true(rig.tuning.follow_block, "fixture: follow_block defaults to true.")

	rig.set_follow_position(Vector3(10.0, 0.0, 0.0))
	rig._process(1.0 / 60.0)

	var after_one_frame: float = rig.get_target().distance_to(Vector3(10.0, 0.0, 0.0))
	assert_gt(after_one_frame, 0.0, "one frame with a lag > 0 should not be an instant snap.")
	assert_lt(after_one_frame, 10.0, "but it should have started closing the distance.")

	for _i: int in range(240):
		rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().x, 10.0, 0.05, "given enough time, the rig should have essentially caught up.")


func test_follow_block_false_pins_the_legacy_free_orbit_camera() -> void:
	# A dedicated CameraTuning instance, not the shared preloaded resource:
	# CameraRig's @export tuning defaults to a preload()'d singleton, so
	# mutating that shared resource here would leak into every other test
	# that uses the default tuning.
	var legacy_tuning: CameraTuning = CameraTuning.new()
	legacy_tuning.follow_block = false
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	rig.tuning = legacy_tuning

	rig.set_follow_position(Vector3(50.0, 0.0, 0.0))
	for _i: int in range(120):
		rig._process(1.0 / 60.0)

	assert_eq(
		rig.get_target(), Vector3.ZERO,
		"follow_block = false must ignore set_follow_position entirely (the pre-mv0.14 behaviour, pinned deliberately)."
	)


# --- Bontago-mv0.7 Part B regression pin -------------------------------------

func _fake_match_with_slots() -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	fake.slots_by_id[0] = PlayerSlot.new(0, 0, "P1", Color(0.9, 0.2, 0.2))
	fake.slots_by_id[1] = PlayerSlot.new(1, 1, "P2", Color(0.2, 0.4, 0.9))
	return fake


func _make_networked_controller(session: FakeNet, fake_match: FakeMatch) -> PlayerController:
	var scene: PackedScene = load("res://game/HotSeat.tscn")
	var hot_seat: HotSeat = autofree(scene.instantiate())
	add_child_autofree(hot_seat)
	var controller: PlayerController = hot_seat.controller()
	controller._match = fake_match
	controller.set_session_provider(session)
	return controller


## A host-local slot, hot_seat = false (real-time networked play), must be
## placeable from nothing but the feed-issued shape and Net.local_slot() --
## exactly what a genuine networked match does. Events.turn_changed is never
## emitted here at all (Match's own hot-seat mechanism), so a regression that
## makes the ghost's shape/tint or _acting_slot() depend on it again fails
## this test first, before it ever reaches a windowed repro.
func test_a_networked_hosts_own_slot_places_without_any_turn_changed() -> void:
	var fake_match: FakeMatch = _fake_match_with_slots()
	var controller: PlayerController = _make_networked_controller(FakeNet.host({1: 0}, [0]), fake_match)

	Events.feed_block_issued.emit(0, &"cube", &"")
	controller._place_ghost_block()

	assert_eq(fake_match.request_place_calls.size(), 1, "the ghost must be armed and the click must reach Match")
	assert_eq(
		fake_match.request_place_calls[0]["slot_id"], 0,
		"the host's own instance always acts for its own slot, not whoever Match's hot-seat names"
	)
