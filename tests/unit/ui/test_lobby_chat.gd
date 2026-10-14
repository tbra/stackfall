extends GutTest
## Bontago-1pi.192.4 C3: the lobby chat adapter (LobbyChat inside LobbyPlayersPanel).

const PANEL_SCENE: PackedScene = preload("res://ui/lobby/LobbyPlayersPanel.tscn")

var _sent: Array[String] = []


func _make(available: bool = true) -> LobbyPlayersPanel:
	var panel: LobbyPlayersPanel = PANEL_SCENE.instantiate() as LobbyPlayersPanel
	add_child_autofree(panel)
	panel.chat().availability = func() -> bool: return available
	panel.chat().refresh_availability()
	_sent.clear()
	Events.chat_send_requested.connect(_collect)
	return panel


func _collect(text: String) -> void:
	_sent.append(text)


func after_each() -> void:
	if Events.chat_send_requested.is_connected(_collect):
		Events.chat_send_requested.disconnect(_collect)


func _line(text: String, slot: int, who: String, kind: int = ChatRules.KIND_TEXT) -> Dictionary:
	return ChatRules.make_line(1, 2, slot, who, slot, text, kind)


func test_line_from_events_shows_with_tinted_name() -> void:
	var chat: LobbyChat = _make().chat()
	Events.chat_line_received.emit(_line("hello", 2, "Ann"))
	assert_true(chat.log.get_parsed_text().contains("Ann: hello"))
	assert_eq(UiChatPanel.name_color(_line("x", 2, "Ann")), Match.slot_color(2))


func test_submit_emits_trimmed_text() -> void:
	var chat: LobbyChat = _make().chat()
	chat.open_input()
	chat.edit.text = "  gg  "
	chat.edit.text_submitted.emit(chat.edit.text)
	assert_eq(_sent, ["gg"] as Array[String])


func test_history_replaces_and_notice_shows() -> void:
	var chat: LobbyChat = _make().chat()
	Events.chat_line_received.emit(_line("old", 0, "Bob"))
	Events.chat_history_received.emit([_line("a", 1, "Cy"), _line("joined", 0, "", ChatRules.KIND_SYSTEM)])
	var text: String = chat.log.get_parsed_text()
	assert_false(text.contains("old"))
	assert_true(text.contains("Cy: a"))
	assert_true(text.contains("joined"))
	Events.chat_notice.emit(ChatRules.NOTICE_RATE)
	assert_true(chat.log.get_parsed_text().contains(LobbyChat.NOTICE_TEXT_RATE))


func test_pad_focus_chain_never_lists_the_chat() -> void:
	var panel: LobbyPlayersPanel = _make()
	var chat: LobbyChat = panel.chat()
	assert_false(panel.focus_entries().has(chat.edit))
	assert_eq(chat.edit.focus_mode, Control.FOCUS_CLICK)


func test_hidden_when_chat_unavailable() -> void:
	var panel: LobbyPlayersPanel = _make(false)
	assert_false(panel.chat().visible)
	panel.chat().availability = func() -> bool: return true
	panel.chat().refresh_availability()
	assert_true(panel.chat().visible)


func test_hidden_on_private_local_host_by_default() -> void:
	var panel: LobbyPlayersPanel = _make()
	panel.chat().availability = Callable()
	panel.chat().refresh_availability()
	assert_eq(panel.chat().visible, not Net.is_offline() and not Net.is_private_session())


func test_esc_in_edit_clears_and_does_not_reach_lobby() -> void:
	var chat: LobbyChat = _make().chat()
	chat.open_input()
	chat.edit.text = "draft"
	var esc: InputEventAction = InputEventAction.new()
	esc.action = &"ui_cancel"
	esc.pressed = true
	chat.edit.gui_input.emit(esc)
	assert_false(chat.is_typing())
	assert_eq(chat.edit.text, "")
	assert_eq(_sent.size(), 0)


func test_enter_in_edit_sends_instead_of_start() -> void:
	# Lobby._input ignores lobby_confirm while a LineEdit has focus; pin that in the source.
	var src: String = FileAccess.get_file_as_string("res://ui/lobby/Lobby.gd")
	assert_true(src.contains("if focus is LineEdit or focus is TextEdit:\n\t\treturn"))
