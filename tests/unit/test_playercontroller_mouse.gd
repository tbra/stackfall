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
## Bontago-mv0.22 (spec 2.5, [ORIGINAL] rows re-tested by the owner
## 2026-09-22): MMB gained a second, continuous job on top of rotate_snap's
## tap -- holding it and dragging spins the ghost's free rotation
## (rotate_drag) -- and RMB became camera_orbit, a second hold that does the
## same thing camera_mode (C) already does, plus lets the wheel zoom the rig
## instead of raising the ghost while either is held.
##
## Bontago-mv0.25 (docs/rotation-issue.png, owner test 2026-09-22): rotate_drag
## became full 3-DOF -- horizontal motion still yaws about world up, but
## vertical motion now pitches about the camera's current right axis instead
## of doing nothing.
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


# --- Bontago-mv0.17 item 5 (owner feel report: "the block's height changes
# ONLY via the wheel"): moving the cursor over a placed block must not raise
# the ghost; only the wheel does. --------------------------------------------

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


func test_the_wheel_still_raises_the_ghost_over_bare_disk() -> void:
	_make_field_for_controller()
	var controller: PlayerController = _make_controller()

	controller._update_ghost_transform()
	var height_before: float = controller._ghost.global_position.y

	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))
	controller._update_ghost_transform()
	var height_after: float = controller._ghost.global_position.y

	assert_gt(height_after, height_before, "the wheel must still raise the ghost.")


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

# --- Bontago-mv0.22: rotate_drag (MMB hold + drag), spec 2.5 "Rotate block
# (hold + drag)" [ORIGINAL, owner test 2026-09-22] ---------------------------

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


## Regression pin (coordinator fix, 2026-09-22): rotate_drag and rotate_snap
## used to share MMB, so a single press fired rotate_snap's tap AND started
## rotate_drag's spin -- every drag began with an unwanted extra 90 degree
## step. rotate_snap is gamepad-only now (RB); a bare MMB press plus drag
## must produce continuous free rotation with no discrete orientation_index
## step at all.
func test_mmb_press_plus_motion_does_not_also_fire_the_old_90_degree_snap() -> void:
	var controller: PlayerController = _make_controller()
	var start_index: int = controller._orientation_index()

	# The actual button-down event first (exercises the same code path a real
	# MMB press dispatches through, including the old rotate_snap tap branch,
	# which must no longer be reachable from this button).
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	controller._unhandled_input(press)

	# Input.action_press mirrors what the real Input singleton would report as
	# "held" for the rest of that same physical press, same as this file's
	# other hold+motion tests (e.g. rotate_drag/camera_mode above).
	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(20.0, 0.0)))
	Input.action_release(&"rotate_drag")

	assert_eq(
		controller._ghost.orientation_index, start_index,
		"MMB press + drag must never step the discrete orientation index (that was rotate_snap's old job)."
	)
	assert_ne(
		controller._ghost.free_quaternion, Quaternion.IDENTITY,
		"the drag should still spin the continuous free rotation."
	)


## Bontago-mv0.25 (spec 2.5, docs/rotation-issue.png, owner test 2026-09-22,
## "like the RMB orbit but for the block"): replaces the old
## test_rotate_drag_ignores_vertical_motion pin -- rotate_drag is full 3-DOF
## now, so vertical motion alone must pitch the block, not leave it untouched.
func test_rotate_drag_vertical_motion_pitches_about_the_cameras_right_axis() -> void:
	var controller: PlayerController = _make_controller()

	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(0.0, 100.0)))
	Input.action_release(&"rotate_drag")

	assert_ne(
		controller._ghost.free_quaternion, Quaternion.IDENTITY,
		"vertical motion should now pitch the held block continuously."
	)
	assert_almost_eq(
		controller._ghost.free_quaternion.length(), 1.0, 0.0001,
		"the composed free rotation must stay unit-length."
	)
	var axis: Vector3 = controller._ghost.free_quaternion.get_axis()
	# No CameraRig wired -> _camera_right_axis() falls back to yaw 0 -> world
	# +X (same fallback _camera_relative_dir() uses). A quaternion's axis-angle
	# form always normalizes to a positive angle, flipping the axis sign if
	# needed, so either +X or -X is a correct match here.
	assert_true(
		axis.is_equal_approx(Vector3.RIGHT) or axis.is_equal_approx(-Vector3.RIGHT),
		"pure vertical drag should pitch about the camera's right axis (world +X with no rig wired), got %s" % axis
	)


func test_rotate_drag_horizontal_motion_yaws_about_world_up_only() -> void:
	var controller: PlayerController = _make_controller()

	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(100.0, 0.0)))
	Input.action_release(&"rotate_drag")

	var axis: Vector3 = controller._ghost.free_quaternion.get_axis()
	assert_true(
		axis.is_equal_approx(Vector3.UP) or axis.is_equal_approx(-Vector3.UP),
		"pure horizontal drag should yaw about world up only, got %s" % axis
	)
	assert_almost_eq(
		controller._ghost.free_quaternion.length(), 1.0, 0.0001,
		"the composed free rotation must stay unit-length."
	)


## Proves the pitch axis genuinely tracks the camera's current facing, not a
## hard-coded world axis -- yaw the rig 90 degrees first, so its right axis is
## no longer world +X, then check a vertical drag pitches about the rig's
## (rotated) right axis instead.
func test_rotate_drag_pitch_axis_follows_a_wired_cameras_current_yaw() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)

	Input.action_press(&"camera_mode")
	rig._unhandled_input(_motion(Vector2(-PI * 0.5 / rig.tuning.mouse_orbit_speed, 0.0)))
	Input.action_release(&"camera_mode")
	assert_almost_eq(rig.get_yaw(), PI * 0.5, 0.01, "fixture: the rig should now be yawed 90 degrees.")

	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(0.0, 100.0)))
	Input.action_release(&"rotate_drag")

	var expected_right: Vector3 = Vector3(0.0, 0.0, -1.0)  # world +X yawed 90 degrees (forward = (1,0,0) -> right = (0,0,-1))
	var axis: Vector3 = controller._ghost.free_quaternion.get_axis()
	assert_true(
		axis.is_equal_approx(expected_right) or axis.is_equal_approx(-expected_right),
		"vertical drag should pitch about the camera's current right axis, not a fixed world axis, got %s" % axis
	)


func test_motion_without_rotate_drag_held_moves_the_cursor_instead() -> void:
	var controller: PlayerController = _make_controller()

	controller._unhandled_input(_motion(Vector2(100.0, 0.0)))

	assert_eq(
		controller._ghost.free_quaternion, Quaternion.IDENTITY,
		"without rotate_drag held, motion should move the cursor, not spin the free rotation."
	)
	assert_gt(controller._cursor.x, 0.0)


# --- Bontago-mv0.22: camera_orbit (RMB hold + drag), spec 2.5 "Camera orbit
# (hold + drag)" [ORIGINAL, owner test 2026-09-22] ---------------------------

func test_camera_orbit_hold_plus_motion_orbits_instead_of_moving_the_block() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	var yaw_before: float = rig.get_yaw()

	Input.action_press(&"camera_orbit")
	var motion: InputEventMouseMotion = _motion(Vector2(100.0, 0.0))
	rig._unhandled_input(motion)
	controller._unhandled_input(motion)
	Input.action_release(&"camera_orbit")

	assert_ne(rig.get_yaw(), yaw_before, "camera_orbit + motion should orbit CameraRig, same as camera_mode.")
	assert_eq(controller._cursor, Vector3.ZERO, "camera_orbit must not also move the ghost's cursor.")


func test_wheel_while_camera_orbit_held_zooms_the_rig_not_the_ghost_height() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
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


func test_wheel_without_camera_orbit_held_still_raises_the_ghost() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	var distance_before: float = rig.get_distance()

	controller._unhandled_input(_wheel(MOUSE_BUTTON_WHEEL_UP))

	assert_almost_eq(rig.get_distance(), distance_before, 0.0001, "the wheel must not zoom the rig without a held orbit.")
	assert_almost_eq(
		controller._ghost.manual_hover_offset, controller.ghost_tuning.hover_wheel_step, 0.001,
		"the wheel must still raise the ghost as before (regression check)."
	)


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
	# The shipped follow_lag_seconds is 0 (owner-tuned, Bontago-mv0.21: the
	# camera snaps to the block like the original). This test is about the
	# smoothing path, so it sets a lag of its own on the shared tuning and
	# restores it afterwards.
	var saved_lag: float = rig.tuning.follow_lag_seconds
	rig.tuning.follow_lag_seconds = 0.2

	rig.set_follow_position(Vector3(10.0, 0.0, 0.0))
	rig._process(1.0 / 60.0)

	var after_one_frame: float = rig.get_target().distance_to(Vector3(10.0, 0.0, 0.0))
	assert_gt(after_one_frame, 0.0, "one frame with a lag > 0 should not be an instant snap.")
	assert_lt(after_one_frame, 10.0, "but it should have started closing the distance.")

	for _i: int in range(240):
		rig._process(1.0 / 60.0)
	assert_almost_eq(rig.get_target().x, 10.0, 0.05, "given enough time, the rig should have essentially caught up.")
	rig.tuning.follow_lag_seconds = saved_lag


## Bontago-mv0.28 (owner test 2026-09-22, "when rotating the block the camera
## adjusts; lock the camera to the center of the box without messing up the
## bottom center"): the camera's own follow target must track the ghost's
## rotated centre column (GhostPreview.rotated_center_world()), not its
## swinging node origin -- rotating in place must never drag the framing.
func test_rotate_drag_never_moves_the_cameras_follow_position_in_xz() -> void:
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = autofree(load("res://game/CameraRig.tscn").instantiate())
	add_child_autofree(rig)
	controller.set_camera_rig(rig)
	assert_almost_eq(rig.tuning.follow_lag_seconds, 0.0, 0.0001, "fixture: the shipped rig snaps to its follow target instantly.")

	controller._process(1.0 / 60.0)
	rig._process(1.0 / 60.0)
	var target_before: Vector3 = rig.get_target()
	assert_almost_eq(target_before.x, 0.0, 0.0001, "fixture: the cursor starts at the world origin.")
	assert_almost_eq(target_before.z, 0.0, 0.0001)

	Input.action_press(&"rotate_drag")
	controller._unhandled_input(_motion(Vector2(100.0, 50.0)))
	Input.action_release(&"rotate_drag")
	assert_ne(controller._ghost.free_quaternion, Quaternion.IDENTITY, "fixture: the drag should have rotated the held block.")

	controller._process(1.0 / 60.0)
	rig._process(1.0 / 60.0)
	var target_after: Vector3 = rig.get_target()

	assert_almost_eq(target_after.x, target_before.x, 0.0001, "rotating the held block must not drift the camera's framing in X.")
	assert_almost_eq(target_after.z, target_before.z, 0.0001, "rotating the held block must not drift the camera's framing in Z.")
	assert_true(
		target_after.is_equal_approx(controller._ghost.rotated_center_world()),
		"the rig's follow target should be exactly the ghost's rotated centre, got %s expected %s" % [target_after, controller._ghost.rotated_center_world()]
	)
	assert_true(
		not is_equal_approx(controller._ghost.global_position.x, target_after.x) or not is_equal_approx(controller._ghost.global_position.z, target_after.z),
		"fixture: the ghost's own node origin should have swung off-centre once rotated -- otherwise this isn't exercising the bug the owner reported."
	)


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
