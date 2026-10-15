extends GutTest
## C5: per-player chat mute (ChatMute) and its views.

const PANEL_SCENE: PackedScene = preload("res://ui/lobby/LobbyPlayersPanel.tscn")
const PEER_A: int = 5
const PEER_B: int = 6

func before_each() -> void:
	ChatMute.clear()


func after_each() -> void:
	ChatMute.clear()
	Events.match_state_changed.emit(MatchPhase.State.PLAYING, MatchPhase.State.LOBBY)


func _line(text: String, peer: int, kind: int = ChatRules.KIND_TEXT) -> Dictionary:
	return ChatRules.make_line(1, peer, 0, "P%d" % peer, 0, text, kind)


func test_toggle_and_hides_rules() -> void:
	assert_false(ChatMute.hides(_line("x", PEER_A)))
	assert_true(ChatMute.toggle(PEER_A))
	assert_true(ChatMute.hides(_line("x", PEER_A)))
	assert_false(ChatMute.hides(_line("x", PEER_B)))
	assert_false(ChatMute.hides(_line("sys", PEER_A, ChatRules.KIND_SYSTEM)), "system lines are never muted")
	assert_false(ChatMute.toggle(PEER_A))
	assert_false(ChatMute.hides(_line("x", PEER_A)))
	ChatMute.set_muted(0, true)
	ChatMute.set_muted(-1, true)
	assert_false(ChatMute.is_muted(0), "the no-sender id is never muted")


func test_lobby_log_hides_muted_live_and_history_and_unmute_restores() -> void:
	var panel: LobbyPlayersPanel = PANEL_SCENE.instantiate() as LobbyPlayersPanel
	add_child_autofree(panel)
	panel.chat().availability = func() -> bool: return true
	var chat: LobbyChat = panel.chat()
	ChatMute.set_muted(PEER_A, true)
	Events.chat_line_received.emit(_line("spam", PEER_A))
	Events.chat_line_received.emit(_line("fine", PEER_B))
	Events.chat_line_received.emit(_line("notice", PEER_A, ChatRules.KIND_SYSTEM))
	var text: String = chat.log.get_parsed_text()
	assert_false(text.contains("spam"))
	assert_true(text.contains("fine"))
	assert_true(text.contains("notice"))
	Events.chat_history_received.emit([_line("oldspam", PEER_A), _line("oldfine", PEER_B)])
	text = chat.log.get_parsed_text()
	assert_false(text.contains("oldspam"))
	assert_true(text.contains("oldfine"))
	ChatMute.set_muted(PEER_A, false)
	Events.chat_line_received.emit(_line("back", PEER_A))
	assert_true(chat.log.get_parsed_text().contains("back"))


func _row(seat_key: int, is_bot: bool, editable: bool, chat_on: bool = true) -> LobbySeatRow:
	var row: LobbySeatRow = LobbySeatRow.new()
	row.seat_key = seat_key
	row.display_name = "Name"
	row.is_bot = is_bot
	row.editable = editable
	row.mute_column_override = func() -> bool: return chat_on
	row.build(preload("res://config/ui/menu_visual_tuning.tres") as MenuVisualTuning, preload("res://config/ui/lobby_layout_tuning.tres") as LobbyLayoutTuning)
	add_child_autofree(row)
	return row


func test_seat_row_mute_button_only_on_remote_humans() -> void:
	var remote: LobbySeatRow = _row(PEER_A, false, false)
	assert_not_null(remote.mute_button)
	assert_eq(remote.mute_button.text, LobbySeatRow.MUTE_TEXT)
	assert_true(remote.focusable_controls().has(remote.mute_button), "a read-only (client) row still offers it to the pad")
	assert_eq(remote.kind_of(remote.mute_button), LobbySeatRow.KIND_MUTE)
	assert_eq(remote.control_of(LobbySeatRow.KIND_MUTE), remote.mute_button)
	remote.mute_button.pressed.emit()
	assert_true(ChatMute.is_muted(PEER_A))
	assert_eq(remote.mute_button.text, LobbySeatRow.UNMUTE_TEXT)
	remote.mute_button.pressed.emit()
	assert_false(ChatMute.is_muted(PEER_A))
	assert_null(_row(Net.local_peer_id(), false, true).mute_button, "no button on the local row")
	assert_null(_row(-1, true, true).mute_button, "none on a bot")
	assert_null(_row(PEER_B, false, false, false).mute_button, "none without a chat session")
	assert_null(_row(LobbySeats.KEY_NONE, false, false).mute_button, "none on a seat-less row")
