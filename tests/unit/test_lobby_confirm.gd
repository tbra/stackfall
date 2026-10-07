extends GutTest
## Bontago-1pi.98: Enter / KP Enter / pad Start (lobby_confirm) start the match (host) or
## toggle Ready (client) from any focus, except in a text field.


func _make_lobby(is_host: bool) -> Lobby:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	fake.is_host_value = is_host
	fake.is_offline_value = is_host
	fake.all_peers_ready_value = true
	lobby.net_provider = fake
	lobby._update_host_only_state()
	return lobby


func _key(code: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _pad_start() -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_START
	event.pressed = true
	return event


func test_action_has_keyboard_and_pad_bindings() -> void:
	assert_true(_key(KEY_ENTER).is_action_pressed(&"lobby_confirm"))
	assert_true(_key(KEY_KP_ENTER).is_action_pressed(&"lobby_confirm"))
	assert_true(_pad_start().is_action_pressed(&"lobby_confirm"))
	assert_false(_key(KEY_SPACE).is_action_pressed(&"lobby_confirm"))


func test_host_enter_and_pad_start_start_the_match_from_a_focused_button() -> void:
	for event: InputEvent in [_key(KEY_ENTER), _key(KEY_KP_ENTER), _pad_start()]:
		var lobby: Lobby = _make_lobby(true)
		var back: Button = lobby.get_node("%BackButton") as Button
		back.grab_focus()
		watch_signals(lobby)
		lobby._input(event)
		assert_signal_emitted(lobby, "start_requested")


func test_blocked_start_is_a_no_op() -> void:
	var lobby: Lobby = _make_lobby(true)
	_fake_of(lobby).all_peers_ready_value = false
	lobby._update_host_only_state()
	watch_signals(lobby)
	lobby._input(_key(KEY_ENTER))
	assert_signal_not_emitted(lobby, "start_requested")


func _fake_of(lobby: Lobby) -> FakeNet:
	return lobby.net_provider as FakeNet


func test_line_edit_focus_suppresses_the_shortcut() -> void:
	var lobby: Lobby = _make_lobby(true)
	var edit: LineEdit = LineEdit.new()
	lobby.add_child(edit)
	edit.grab_focus()
	watch_signals(lobby)
	lobby._input(_key(KEY_ENTER))
	assert_signal_not_emitted(lobby, "start_requested")


func test_client_toggles_ready() -> void:
	var lobby: Lobby = _make_lobby(false)
	var check: CheckButton = lobby.get_node("%ReadyCheck") as CheckButton
	var before: bool = check.button_pressed
	lobby._input(_pad_start())
	assert_eq(check.button_pressed, not before)
