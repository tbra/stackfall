extends GutTest
## PlayerController.gd camera-aimed gift release (Bontago-1pi.85.29, owner: "throwable gifts ...
## use the camera as the base of the trajectory, tied directly to the gift so it automatically
## activates when held (no LT required)"). Supersedes the M4 P2d hold-and-drag throw aim.
## Fixture family of test_playercontroller_mouse.gd/test_playercontroller_gamepad.gd.


func after_each() -> void:
	# Synthetic gamepad presses flip Settings' active device; restore it for later scripts.
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _mouse_press(button: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


func _make_controller(fake: FakeMatch) -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0
	controller._match = fake
	return controller


func _fake_match_with(special_id: StringName) -> FakeMatch:
	var fake: FakeMatch = FakeMatch.new()
	if special_id != &"":
		fake.held_special_by_slot[0] = special_id
	return fake


func test_lmb_press_over_a_held_throwable_throws_along_the_camera_forward_with_no_lt() -> void:
	var fake: FakeMatch = _fake_match_with(&"bomb")
	var controller: PlayerController = _make_controller(fake)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(fake.request_place_calls.size(), 0, "a throwable is thrown, not placed")
	assert_eq(fake.request_throw_calls.size(), 1, "one plain click throws (no hold, no drag, no LT)")
	var sent: Vector3 = fake.request_throw_calls[0]["velocity"]
	assert_almost_eq(sent.length(), 1.0, 0.001, "the intent carries only the unit camera forward")
	assert_true(sent.is_equal_approx(controller._camera_forward()))


func test_synthetic_gamepad_a_press_throws_exactly_like_the_mouse() -> void:
	var mouse_fake: FakeMatch = _fake_match_with(&"bomb")
	var pad_fake: FakeMatch = _fake_match_with(&"bomb")
	var mouse_controller: PlayerController = _make_controller(mouse_fake)
	var pad_controller: PlayerController = _make_controller(pad_fake)

	mouse_controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))
	pad_controller._unhandled_input(_pad_button(JOY_BUTTON_A))

	assert_eq(pad_fake.request_place_calls.size(), 0)
	assert_eq(pad_fake.request_throw_calls.size(), 1, "A (ghost_place) throws a held throwable; LT is not needed")
	var mouse_v: Vector3 = mouse_fake.request_throw_calls[0]["velocity"]
	var pad_v: Vector3 = pad_fake.request_throw_calls[0]["velocity"]
	assert_true(mouse_v.is_equal_approx(pad_v))


func test_an_ordinary_block_still_places_on_press() -> void:
	var fake: FakeMatch = _fake_match_with(&"")
	var controller: PlayerController = _make_controller(fake)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(fake.request_place_calls.size(), 1)
	assert_eq(fake.request_throw_calls.size(), 0)


func test_a_non_throwable_gift_still_places() -> void:
	var fake: FakeMatch = _fake_match_with(&"anvil")
	var controller: PlayerController = _make_controller(fake)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(fake.request_throw_calls.size(), 0)
	assert_eq(fake.request_place_calls.size(), 1)


func test_throw_preview_uses_the_host_throw_velocity_and_spawn_point() -> void:
	var controller: PlayerController = _make_controller(_fake_match_with(&"bomb"))
	var preview: Dictionary = controller.gift_launch_preview()
	var forward: Vector3 = controller._camera_forward()
	var tuning: SpecialTuning = controller.special_tuning
	assert_false(preview.is_empty(), "a held throwable always has a preview, no LT/drag")
	assert_true((preview["velocity"] as Vector3).is_equal_approx(GiftAim.throw_velocity(forward, tuning)), "parity with the host")
	assert_eq(preview["gravity_scale"], 1.0, "a thrown block arcs under gravity")
	var ghost_pos: Vector3 = controller._ghost.global_position
	assert_true((preview["origin"] as Vector3).is_equal_approx(GiftAim.spawn_point(ghost_pos, forward, ghost_pos.y, tuning)))


func test_rocket_preview_is_a_straight_gravity_free_line() -> void:
	var controller: PlayerController = _make_controller(_fake_match_with(&"rocket"))
	var preview: Dictionary = controller.gift_launch_preview()
	assert_eq(preview["gravity_scale"], 0.0)
	var velocity: Vector3 = preview["velocity"]
	assert_true(velocity.normalized().is_equal_approx(controller._camera_forward().normalized()))


func test_preview_origin_is_the_ghost_pose_and_the_camera_yaw_rotates_the_velocity() -> void:
	var controller: PlayerController = _make_controller(_fake_match_with(&"bomb"))
	controller._ghost.global_position = Vector3(2.0, 9.0, 3.0)
	var first: Dictionary = controller.gift_launch_preview()
	var clamped: Vector3 = Vector3(2.0, 9.0 + controller.special_tuning.gift_aim_min_height_m, 3.0)
	# No field behind the fake match: surface_y is the ghost height, so only the min-height clamp lifts it.
	assert_true((first["origin"] as Vector3).is_equal_approx(clamped), "arc starts at the held gift")
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	rig._yaw = PI * 0.5
	controller._camera_rig = rig
	var second: Dictionary = controller.gift_launch_preview()
	assert_true((second["origin"] as Vector3).is_equal_approx(clamped), "origin independent of camera")
	assert_false((first["velocity"] as Vector3).is_equal_approx(second["velocity"] as Vector3), "yaw rotates the aim")


func test_rocket_and_paintball_are_not_previewable() -> void:
	for id: StringName in [&"rocket", &"paintball"]:
		var controller: PlayerController = _make_controller(_fake_match_with(id))
		assert_false(GiftThrow.shows_preview(controller._held_gift_mode()), "%s" % id)
	assert_true(GiftThrow.shows_preview(_make_controller(_fake_match_with(&"bomb"))._held_gift_mode()))


func test_no_preview_for_an_ordinary_piece_or_a_placed_gift() -> void:
	assert_true(_make_controller(_fake_match_with(&"")).gift_launch_preview().is_empty())
	assert_true(_make_controller(_fake_match_with(&"anvil")).gift_launch_preview().is_empty())


func test_the_hold_to_aim_state_machine_is_gone() -> void:
	var controller: PlayerController = _make_controller(_fake_match_with(&"bomb"))
	assert_false(controller.has_method(&"is_aiming_throw"), "LT/drag aiming no longer exists")
	assert_false(controller.has_method(&"_commit_throw_aim"))
