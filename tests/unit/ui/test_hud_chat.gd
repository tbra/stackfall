extends GutTest
## Bontago-1pi.192.5 C4: HudChat (in-match chat), its gameplay-input gating and Options listing.

class UnhandledProbe extends Node:
	var seen: Array[InputEvent] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed():
			seen.append(event)


var _sent: Array[String] = []
var _opened: int = 0
var _closed: int = 0


func before_each() -> void:
	_sent.clear()
	_opened = 0
	_closed = 0
	Events.chat_send_requested.connect(_on_sent)
	Events.chat_input_opened.connect(_on_opened)
	Events.chat_input_closed.connect(_on_closed)


func after_each() -> void:
	Events.chat_send_requested.disconnect(_on_sent)
	Events.chat_input_opened.disconnect(_on_opened)
	Events.chat_input_closed.disconnect(_on_closed)
	Events.pause_menu_closed.emit()
	Events.match_scope_reset.emit()


func _on_sent(text: String) -> void:
	_sent.append(text)


func _on_opened() -> void:
	_opened += 1


func _on_closed() -> void:
	_closed += 1


func _make_chat(live: bool = true) -> HudChat:
	var chat: HudChat = HudChat.new()
	add_child_autofree(chat)
	if live:
		Events.match_state_changed.emit(MatchPhase.State.LOBBY, MatchPhase.State.PLAYING)
	return chat


func _action_event(action: StringName, pressed: bool = true) -> InputEvent:
	var event: InputEvent = InputMap.action_get_events(action)[0].duplicate() as InputEvent
	if event is InputEventKey:
		(event as InputEventKey).pressed = pressed
	elif event is InputEventMouseButton:
		(event as InputEventMouseButton).pressed = pressed
	return event


func _line(text: String) -> Dictionary:
	return ChatRules.make_line(0, 1, 0, "Ann", 0, text)


func _make_controller() -> PlayerController:
	var controller: PlayerController = autofree(PlayerController.new())
	add_child_autofree(controller)
	return controller


func test_chat_open_opens_input_and_blocks_controller_and_camera() -> void:
	var chat: HudChat = _make_chat()
	var controller: PlayerController = _make_controller()
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate() as CameraRig
	add_child_autofree(rig)
	assert_true(controller.input_enabled)
	chat._unhandled_input(_action_event(&"chat_open"))
	assert_true(chat.panel.is_typing())
	assert_eq(_opened, 1)
	assert_false(controller.input_enabled)
	assert_true(rig.is_input_blocked())
	chat.panel.close_input(false)
	assert_true(controller.input_enabled)
	assert_false(rig.is_input_blocked())


func test_typing_keys_do_not_place_or_rotate() -> void:
	var chat: HudChat = _make_chat()
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	var cube_shape: BlockShape = load("res://config/blocks/cube.tres")
	ghost.set_shape(cube_shape)
	var controller: PlayerController = _make_controller()
	controller._ghost = ghost
	controller._active_slot = 0
	var fake_match: FakeMatch = FakeMatch.new()
	fake_match.held_shapes[0] = cube_shape
	controller._match = fake_match
	chat.panel.open_input()
	controller._unhandled_input(_action_event(&"rotate_yaw_cw"))
	controller._unhandled_input(_action_event(&"ghost_place"))
	assert_eq(fake_match.request_place_calls.size(), 0, "no placement while typing")
	chat.panel.close_input(false)
	controller._unhandled_input(_action_event(&"ghost_place"))
	assert_eq(fake_match.request_place_calls.size(), 1, "placement works again once chat closes")


func test_enter_sends_trimmed_text_and_closes() -> void:
	var chat: HudChat = _make_chat()
	chat._unhandled_input(_action_event(&"chat_open"))
	chat.panel.edit.text = "  hello there  "
	chat.panel.edit.text_submitted.emit(chat.panel.edit.text)
	assert_eq(_sent, ["hello there"])
	assert_false(chat.panel.is_typing())
	assert_eq(_closed, 1)


func test_empty_enter_closes_without_sending() -> void:
	var chat: HudChat = _make_chat()
	chat._unhandled_input(_action_event(&"chat_open"))
	chat.panel.edit.text_submitted.emit("   ")
	assert_eq(_sent.size(), 0)
	assert_false(chat.panel.is_typing())
	assert_eq(_closed, 1)


func test_escape_cancels_and_never_reaches_unhandled_pause_listeners() -> void:
	var chat: HudChat = _make_chat()
	var probe: UnhandledProbe = UnhandledProbe.new()
	add_child_autofree(probe)
	chat.panel.open_input()
	chat.panel.edit.text = "draft"
	chat.panel.edit.grab_focus()
	var esc: InputEventKey = _action_event(&"ui_cancel") as InputEventKey
	get_viewport().push_input(esc)
	assert_false(chat.panel.is_typing(), "Esc closes the field")
	assert_eq(_sent.size(), 0, "Esc discards")
	assert_eq(probe.seen.size(), 0, "the first Esc is handled by the field and never reaches PauseMenu")


func test_pause_opening_closes_chat_and_controller_stays_blocked() -> void:
	var chat: HudChat = _make_chat()
	var controller: PlayerController = _make_controller()
	chat.panel.open_input()
	Events.pause_menu_opened.emit()
	assert_false(chat.panel.is_typing())
	assert_false(controller.input_enabled, "pause still holds input after chat closes")
	chat._unhandled_input(_action_event(&"chat_open"))
	assert_false(chat.panel.is_typing(), "chat_open is ignored while pause is open")
	Events.pause_menu_closed.emit()
	assert_true(controller.input_enabled)


func test_chat_closing_does_not_reenable_input_under_pause() -> void:
	var controller: PlayerController = _make_controller()
	Events.chat_input_opened.emit()
	Events.pause_menu_opened.emit()
	Events.chat_input_closed.emit()
	assert_false(controller.input_enabled)
	Events.pause_menu_closed.emit()
	assert_true(controller.input_enabled)


func test_pad_buttons_never_open_chat() -> void:
	var chat: HudChat = _make_chat()
	for button: JoyButton in [JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y, JOY_BUTTON_START, JOY_BUTTON_BACK, JOY_BUTTON_DPAD_UP]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.button_index = button
		event.pressed = true
		chat._unhandled_input(event)
		assert_false(chat.panel.is_typing())
	for input_event: InputEvent in InputMap.action_get_events(&"chat_open"):
		assert_false(input_event is InputEventJoypadButton or input_event is InputEventJoypadMotion)


func test_pad_event_while_typing_closes_chat_and_restores_input() -> void:
	var chat: HudChat = _make_chat()
	var controller: PlayerController = _make_controller()
	chat.panel.open_input()
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = JOY_BUTTON_A
	event.pressed = true
	chat.panel._input(event)
	assert_false(chat.panel.is_typing())
	assert_true(controller.input_enabled)


func test_fade_timeline_in_hud_and_show_scores_reveals() -> void:
	var chat: HudChat = _make_chat()
	Events.chat_line_received.emit(_line("hello"))
	var cfg: ChatConfig = chat.panel.config
	assert_true(chat.visible)
	assert_true(chat.panel.visible)
	chat._process(cfg.line_visible_s + cfg.fade_s + 1.0)
	assert_false(chat.panel.visible, "faded out")
	Input.action_press(&"show_scores")
	chat._process(0.0)
	Input.action_release(&"show_scores")
	assert_true(chat.panel.visible, "holding show_scores reveals the log")
	assert_eq(chat.panel.modulate.a, 1.0)
	Events.chat_line_received.emit(_line("again"))
	assert_true(chat.panel.visible, "a new line restores it")


func test_hidden_outside_the_live_round() -> void:
	var chat: HudChat = _make_chat(false)
	assert_false(chat.visible, "not live: no chat")
	chat._unhandled_input(_action_event(&"chat_open"))
	assert_false(chat.panel.is_typing())
	Events.match_state_changed.emit(MatchPhase.State.LOBBY, MatchPhase.State.LOADING)
	assert_false(chat.visible)
	Events.match_state_changed.emit(MatchPhase.State.LOADING, MatchPhase.State.PLAYING)
	assert_true(chat.visible)
	chat.panel.open_input()
	Events.match_results_ready.emit({})
	assert_false(chat.panel.is_typing(), "results close chat")
	assert_false(chat.visible)
	assert_eq(chat.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	Events.match_scope_reset.emit()
	assert_true(chat.visible)


func test_chat_open_is_listed_on_the_keyboard_page_only() -> void:
	assert_true(OptionsMenu.REBINDABLE_ACTIONS.has(&"chat_open"))
	assert_true(KeyRebindRow.PAD_NOT_APPLICABLE.has(&"chat_open"))
	assert_true(KeyRebindRow.DISPLAY_NAMES.has(&"chat_open"))
