extends GutTest
## Bontago-1pi.18.2: the use_gift_slot action (keyboard G, gamepad touchpad)
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


func test_gamepad_touchpad_uses_the_slot() -> void:
	var fake: GiftFakeMatch = GiftFakeMatch.new()
	fake.head = &"anvil"
	var controller: PlayerController = _controller(fake)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_TOUCHPAD
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


func test_r3_no_longer_spends_a_gift_it_shows_the_scoreboard() -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_RIGHT_STICK
	event.pressed = true
	assert_false(event.is_action_pressed(&"use_gift_slot"), "Bontago-1pi.69: R3 belongs to show_scores")
	assert_true(event.is_action_pressed(&"show_scores"))


# --- Bontago-1pi.85.16: gift input policy (no rotate/recolour, throw vs aimed launch) ---

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


func test_a_held_gift_ghost_visual_is_not_recoloured_by_the_owner_colour() -> void:
	var controller: PlayerController = _held_controller(&"bomb")
	var ghost: GhostPreview = controller._ghost
	ghost.apply_validity(PlacementRules.Result.VALID)
	ghost.set_player_color(Color(1.0, 0.0, 0.0))
	# Bontago-1pi.85.33: the valid state shows the model's own materials with only the glow
	# rim overlay, so compare the overlay itself (not a tint colour) across owner colours.
	var red: Material = (ghost.gift_visual().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_overlay
	ghost.set_player_color(Color(0.0, 0.0, 1.0))
	ghost.apply_validity(PlacementRules.Result.VALID)
	var blue: Material = (ghost.gift_visual().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_overlay
	assert_eq(red, blue, "owner colour must not tint a held gift")
	if blue is StandardMaterial3D:
		assert_ne((blue as StandardMaterial3D).albedo_color, Color(0.0, 0.0, 1.0), "the overlay never takes the owner colour")


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


func test_a_rocket_never_starts_a_throw_aim_but_a_bomb_does() -> void:
	assert_false(_held_controller(&"rocket")._can_begin_throw_aim())
	assert_false(_held_controller(&"anvil")._can_begin_throw_aim())
	assert_true(_held_controller(&"bomb")._can_begin_throw_aim())
