extends GutTest
## PlayerController.gd camera-aimed gift release (requirement: "throwable gifts ...
## use the camera as the base of the trajectory, tied directly to the gift so it automatically
## activates when held (no LT required)"). Supersedes the earlier hold-and-drag throw aim.
## The match is a FakeMatchContext set on the controller before it enters the tree; the release
## is read from its submit_throw record and the preview from gift_launch_preview().

var _rig: CameraRig = null


func after_each() -> void:
	# Synthetic gamepad presses flip Settings' active device; restore it for later scripts.
	Settings._input(InputEventKey.new())


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


func _make_controller(context: FakeMatchContext) -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	_rig = load("res://game/player/CameraRig.tscn").instantiate() as CameraRig
	add_child_autofree(_rig)
	var controller: PlayerController = autofree(PlayerController.new())
	controller.match_context = context
	controller.ghost_path = ghost.get_path()
	controller.set_acting_slot(0)
	add_child_autofree(controller)
	controller.set_camera_rig(_rig)
	return controller


func _context_holding(special_id: StringName) -> FakeMatchContext:
	var context: FakeMatchContext = FakeMatchContext.new()
	if special_id != &"":
		context.held_special_by_slot[0] = special_id
	return context


## The unit forward of the camera the controller aims with (every rig here starts identical).
func _camera_forward() -> Vector3:
	return -_rig.get_camera().global_transform.basis.z


func test_lmb_press_over_a_held_throwable_throws_along_the_camera_forward_with_no_lt() -> void:
	var context: FakeMatchContext = _context_holding(&"bomb")
	var controller: PlayerController = _make_controller(context)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(context.submit_place_calls.size(), 0, "a throwable is thrown, not placed")
	assert_eq(context.submit_throw_calls.size(), 1, "one plain click throws (no hold, no drag, no LT)")
	assert_eq(context.submit_throw_calls[0]["slot_id"], 0)
	var sent: Vector3 = context.submit_throw_calls[0]["velocity"]
	assert_almost_eq(sent.length(), 1.0, 0.001, "the intent carries only the unit camera forward")
	assert_true(sent.is_equal_approx(_camera_forward()))


func test_synthetic_gamepad_a_press_throws_exactly_like_the_mouse() -> void:
	var mouse_context: FakeMatchContext = _context_holding(&"bomb")
	var pad_context: FakeMatchContext = _context_holding(&"bomb")
	var mouse_controller: PlayerController = _make_controller(mouse_context)
	var pad_controller: PlayerController = _make_controller(pad_context)

	mouse_controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))
	pad_controller._unhandled_input(_pad_button(JOY_BUTTON_A))

	assert_eq(pad_context.submit_place_calls.size(), 0)
	assert_eq(pad_context.submit_throw_calls.size(), 1, "A (ghost_place) throws a held throwable; LT is not needed")
	var mouse_v: Vector3 = mouse_context.submit_throw_calls[0]["velocity"]
	var pad_v: Vector3 = pad_context.submit_throw_calls[0]["velocity"]
	assert_true(mouse_v.is_equal_approx(pad_v))


func test_an_ordinary_block_still_places_on_press() -> void:
	var context: FakeMatchContext = _context_holding(&"")
	var controller: PlayerController = _make_controller(context)

	controller._unhandled_input(_mouse_press(MOUSE_BUTTON_LEFT))

	assert_eq(context.submit_place_calls.size(), 1)
	assert_eq(context.submit_place_calls[0]["slot_id"], 0)
	assert_eq(context.submit_throw_calls.size(), 0)


func test_throw_preview_uses_the_host_throw_velocity_and_spawn_point() -> void:
	var controller: PlayerController = _make_controller(_context_holding(&"bomb"))
	var preview: Dictionary = controller.gift_launch_preview()
	var forward: Vector3 = _camera_forward()
	var tuning: SpecialTuning = controller.special_tuning
	assert_false(preview.is_empty(), "a held throwable always has a preview, no LT/drag")
	assert_true((preview["velocity"] as Vector3).is_equal_approx(GiftAim.throw_velocity(forward, tuning)), "parity with the host")
	assert_eq(preview["gravity_scale"], 1.0, "a thrown block arcs under gravity")
	var ghost: GhostPreview = controller.get_node(controller.ghost_path) as GhostPreview
	var ghost_pos: Vector3 = ghost.global_position
	assert_true((preview["origin"] as Vector3).is_equal_approx(GiftAim.spawn_point(ghost_pos, forward, ghost_pos.y, tuning)))


func test_rocket_preview_is_a_straight_gravity_free_line() -> void:
	var controller: PlayerController = _make_controller(_context_holding(&"rocket"))
	var preview: Dictionary = controller.gift_launch_preview()
	assert_eq(preview["gravity_scale"], 0.0)
	var velocity: Vector3 = preview["velocity"]
	assert_true(velocity.normalized().is_equal_approx(_camera_forward().normalized()))


func test_no_preview_for_an_ordinary_piece_or_a_placed_gift() -> void:
	assert_true(_make_controller(_context_holding(&"")).gift_launch_preview().is_empty())
	assert_true(_make_controller(_context_holding(&"anvil")).gift_launch_preview().is_empty())
