extends GutTest
## Bontago-1pi.18.2: the use_gift_slot action (keyboard G, gamepad X since Bontago-1pi.18.12)
## asks Match to spend the slotted gift, and only when one is waiting.


class GiftFakeMatch:
	extends FakeMatch
	var head: StringName = &""
	var use_calls: Array[int] = []

	func gift_slot_head(_slot_id: int) -> StringName:
		return head

	func request_use_gift_slot(slot_id: int) -> bool:
		use_calls.append(slot_id)
		return true


func _controller(fake: GiftFakeMatch) -> PlayerController:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._active_slot = 0
	controller._match = fake
	return controller


func test_gamepad_x_uses_the_slot() -> void:
	var fake: GiftFakeMatch = GiftFakeMatch.new()
	fake.head = &"anvil"
	var controller: PlayerController = _controller(fake)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	assert_true(event.is_action_pressed(&"use_gift_slot"))
	controller._unhandled_input(event)
	assert_eq(fake.use_calls, [0])


func test_keyboard_g_uses_the_slot_and_empty_slot_is_ignored() -> void:
	var fake: GiftFakeMatch = GiftFakeMatch.new()
	var controller: PlayerController = _controller(fake)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	assert_true(key.is_action_pressed(&"use_gift_slot"))
	controller._unhandled_input(key)
	assert_eq(fake.use_calls.size(), 0, "empty slot sends nothing")
	fake.head = &"anvil"
	controller._unhandled_input(key)
	assert_eq(fake.use_calls, [0])


func _held_controller(special_id: StringName) -> PlayerController:
	var fake: FakeMatch = FakeMatch.new()
	if special_id != &"":
		fake.held_special_by_slot[0] = special_id
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	if special_id != &"":
		ghost.set_held_gift(special_id)
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	controller._ghost = ghost
	controller._active_slot = 0
	controller._match = fake
	return controller


func _key_event(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	return event


func _pad_button(button: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = button
	event.pressed = true
	return event


func test_rotate_actions_are_no_ops_with_a_gift_held_and_work_for_an_ordinary_piece() -> void:
	var gift: PlayerController = _held_controller(&"bomb")
	var ordinary: PlayerController = _held_controller(&"")
	var keys: Array[Key] = [KEY_S, KEY_A, KEY_W]
	for code: Key in keys:
		var event: InputEventKey = _key_event(code)
		if not (event.is_action_pressed(&"rotate_yaw_cw") or event.is_action_pressed(&"rotate_yaw_ccw") or event.is_action_pressed(&"rotate_pitch_fwd") or event.is_action_pressed(&"rotate_pitch_back")):
			continue
		gift._unhandled_input(event)
		ordinary._unhandled_input(event)
	gift._unhandled_input(_pad_button(JOY_BUTTON_B))  # rotate_snap
	ordinary._unhandled_input(_pad_button(JOY_BUTTON_B))
	assert_eq(gift._ghost.orientation_index, 0, "a held gift never rotates")
	assert_ne(ordinary._ghost.orientation_index, 0, "an ordinary piece still rotates")
	gift._ghost.apply_free_rotation_delta(1.0, 1.0)
	assert_eq(gift._ghost.free_quaternion, Quaternion.IDENTITY, "free rotation is a no-op too")


func test_a_rocket_released_by_mouse_or_pad_fires_along_the_camera_forward_identically() -> void:
	var mouse_controller: PlayerController = _held_controller(&"rocket")
	var pad_controller: PlayerController = _held_controller(&"rocket")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	mouse_controller._unhandled_input(click)
	pad_controller._unhandled_input(_pad_button(JOY_BUTTON_A))
	var mouse_fake: FakeMatch = mouse_controller._match as FakeMatch
	var pad_fake: FakeMatch = pad_controller._match as FakeMatch
	assert_eq(mouse_fake.request_place_calls.size(), 0, "an aimed gift is never a plain place")
	assert_eq(mouse_fake.request_throw_calls.size(), 1)
	assert_eq(pad_fake.request_throw_calls.size(), 1)
	var mouse_v: Vector3 = mouse_fake.request_throw_calls[0]["velocity"]
	var pad_v: Vector3 = pad_fake.request_throw_calls[0]["velocity"]
	assert_true(mouse_v.is_equal_approx(pad_v))
	assert_almost_eq(mouse_v.length(), 1.0, 0.001, "a unit camera forward")


func test_every_throwable_and_aimed_gift_releases_on_a_plain_press_but_other_gifts_place() -> void:
	for id: StringName in [&"bomb", &"magnet", &"jumping_bean", &"rocket", &"paintball"]:
		var controller: PlayerController = _held_controller(id)
		controller._unhandled_input(_pad_button(JOY_BUTTON_A))
		var fake: FakeMatch = controller._match as FakeMatch
		assert_eq(fake.request_throw_calls.size(), 1, "%s: A throws along the camera, no LT" % id)
		assert_eq(fake.request_place_calls.size(), 0, String(id))
	var anvil: PlayerController = _held_controller(&"anvil")
	anvil._unhandled_input(_pad_button(JOY_BUTTON_A))
	assert_eq((anvil._match as FakeMatch).request_throw_calls.size(), 0)
	assert_eq((anvil._match as FakeMatch).request_place_calls.size(), 1)
