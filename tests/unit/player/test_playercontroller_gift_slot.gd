extends GutTest
## the use_gift_slot action (keyboard G, gamepad X since)
## asks the match to spend the slotted gift, and only when one is waiting.
## The controller reaches the match only through its MatchContext port; these tests set a
## FakeMatchContext on it before it enters the tree and read the context's intent records.


## A controller acting for slot 0 over `context`, with a ghost holding a cube.
func _controller(context: FakeMatchContext) -> PlayerController:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	var controller: PlayerController = autofree(PlayerController.new())
	controller.match_context = context
	controller.ghost_path = ghost.get_path()
	controller.set_acting_slot(0)
	add_child_autofree(controller)
	return controller


func _ghost_of(controller: PlayerController) -> GhostPreview:
	return controller.get_node(controller.ghost_path) as GhostPreview


func test_gamepad_x_uses_the_slot() -> void:
	var context: FakeMatchContext = FakeMatchContext.new()
	context.gift_slot_head_by_slot[0] = &"anvil"
	var controller: PlayerController = _controller(context)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_X
	event.pressed = true
	assert_true(event.is_action_pressed(&"use_gift_slot"))
	controller._unhandled_input(event)
	assert_eq(context.submit_use_gift_slot_calls.size(), 1)
	assert_eq(context.submit_use_gift_slot_calls[0]["slot_id"], 0)


func test_keyboard_g_uses_the_slot_and_empty_slot_is_ignored() -> void:
	var context: FakeMatchContext = FakeMatchContext.new()
	var controller: PlayerController = _controller(context)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	assert_true(key.is_action_pressed(&"use_gift_slot"))
	controller._unhandled_input(key)
	assert_eq(context.submit_use_gift_slot_calls.size(), 0, "empty slot sends nothing")
	context.gift_slot_head_by_slot[0] = &"anvil"
	controller._unhandled_input(key)
	assert_eq(context.submit_use_gift_slot_calls.size(), 1)
	assert_eq(context.submit_use_gift_slot_calls[0]["slot_id"], 0)


func test_using_the_slot_sends_no_placement_or_throw() -> void:
	var context: FakeMatchContext = FakeMatchContext.new()
	context.gift_slot_head_by_slot[0] = &"anvil"
	var controller: PlayerController = _controller(context)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_G
	key.pressed = true
	controller._unhandled_input(key)
	assert_eq(context.submit_place_calls.size(), 0)
	assert_eq(context.submit_throw_calls.size(), 0)


## [controller, context] for a slot-0 controller holding `special_id` (an ordinary piece for &"").
func _held_controller(special_id: StringName) -> Array:
	var context: FakeMatchContext = FakeMatchContext.new()
	if special_id != &"":
		context.held_special_by_slot[0] = special_id
	var controller: PlayerController = _controller(context)
	if special_id != &"":
		_ghost_of(controller).set_held_gift(special_id)
	return [controller, context]


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
	var gift: PlayerController = _held_controller(&"bomb")[0]
	var ordinary: PlayerController = _held_controller(&"")[0]
	var keys: Array[Key] = [KEY_S, KEY_A, KEY_W]
	for code: Key in keys:
		var event: InputEventKey = _key_event(code)
		if not (event.is_action_pressed(&"rotate_yaw_cw") or event.is_action_pressed(&"rotate_yaw_ccw") or event.is_action_pressed(&"rotate_pitch_fwd") or event.is_action_pressed(&"rotate_pitch_back")):
			continue
		gift._unhandled_input(event)
		ordinary._unhandled_input(event)
	gift._unhandled_input(_pad_button(JOY_BUTTON_B))  # rotate_snap
	ordinary._unhandled_input(_pad_button(JOY_BUTTON_B))
	var gift_ghost: GhostPreview = _ghost_of(gift)
	assert_eq(gift_ghost.orientation_index, 0, "a held gift never rotates")
	assert_ne(_ghost_of(ordinary).orientation_index, 0, "an ordinary piece still rotates")
	gift_ghost.apply_free_rotation_delta(1.0, 1.0)
	assert_eq(gift_ghost.free_quaternion, Quaternion.IDENTITY, "free rotation is a no-op too")


func test_a_rocket_released_by_mouse_or_pad_fires_along_the_camera_forward_identically() -> void:
	var mouse_parts: Array = _held_controller(&"rocket")
	var pad_parts: Array = _held_controller(&"rocket")
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	(mouse_parts[0] as PlayerController)._unhandled_input(click)
	(pad_parts[0] as PlayerController)._unhandled_input(_pad_button(JOY_BUTTON_A))
	var mouse_context: FakeMatchContext = mouse_parts[1]
	var pad_context: FakeMatchContext = pad_parts[1]
	assert_eq(mouse_context.submit_place_calls.size(), 0, "an aimed gift is never a plain place")
	assert_eq(mouse_context.submit_throw_calls.size(), 1)
	assert_eq(pad_context.submit_throw_calls.size(), 1)
	var mouse_v: Vector3 = mouse_context.submit_throw_calls[0]["velocity"]
	var pad_v: Vector3 = pad_context.submit_throw_calls[0]["velocity"]
	assert_true(mouse_v.is_equal_approx(pad_v))
	assert_almost_eq(mouse_v.length(), 1.0, 0.001, "a unit camera forward")


func test_every_throwable_and_aimed_gift_releases_on_a_plain_press_but_other_gifts_place() -> void:
	for id: StringName in [&"bomb", &"magnet", &"jumping_bean", &"rocket", &"paintball"]:
		var parts: Array = _held_controller(id)
		(parts[0] as PlayerController)._unhandled_input(_pad_button(JOY_BUTTON_A))
		var context: FakeMatchContext = parts[1]
		assert_eq(context.submit_throw_calls.size(), 1, "%s: A throws along the camera, no LT" % id)
		assert_eq(context.submit_place_calls.size(), 0, String(id))
	var anvil_parts: Array = _held_controller(&"anvil")
	(anvil_parts[0] as PlayerController)._unhandled_input(_pad_button(JOY_BUTTON_A))
	var anvil: FakeMatchContext = anvil_parts[1]
	assert_eq(anvil.submit_throw_calls.size(), 0)
	assert_eq(anvil.submit_place_calls.size(), 1)
