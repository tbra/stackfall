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
