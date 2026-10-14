extends GutTest
## Bontago-1pi.192.6 C5: per-player chat mute (ChatMute) and its views.

const PANEL_SCENE: PackedScene = preload("res://ui/lobby/LobbyPlayersPanel.tscn")
const PEER_A: int = 5
const PEER_B: int = 6

class KeyProbe extends Node:
	var seen: Array[InputEvent] = []

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_pressed():
			seen.append(event)


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


func test_filter_lines_keeps_order_and_system() -> void:
	ChatMute.set_muted(PEER_A, true)
	var kept: Array = ChatMute.filter_lines([_line("a", PEER_A), _line("b", PEER_B), _line("s", PEER_A, ChatRules.KIND_SYSTEM)])
	assert_eq(kept.size(), 2)
	assert_eq((kept[0] as Dictionary)[ChatRules.KEY_TEXT], "b")


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


func test_hud_log_hides_muted_lines_and_history() -> void:
	var chat: HudChat = HudChat.new()
	add_child_autofree(chat)
	Events.match_state_changed.emit(MatchPhase.State.LOBBY, MatchPhase.State.PLAYING)
	ChatMute.set_muted(PEER_A, true)
	Events.chat_line_received.emit(_line("spam", PEER_A))
	Events.chat_line_received.emit(_line("fine", PEER_B))
	assert_eq(chat.panel.shown_line_count(), 1)
	Events.chat_history_received.emit([_line("oldspam", PEER_A), _line("oldfine", PEER_B), _line("oldfine2", PEER_B)])
	assert_eq(chat.panel.shown_line_count(), 2)


func test_mute_survives_state_changes_and_clears_with_the_session() -> void:
	ChatMute.set_muted(PEER_A, true)
	Events.match_state_changed.emit(MatchPhase.State.LOBBY, MatchPhase.State.PLAYING)
	Events.match_state_changed.emit(MatchPhase.State.PLAYING, MatchPhase.State.LOBBY)
	assert_true(ChatMute.is_muted(PEER_A), "lobby -> match -> lobby")
	var net: Node = (preload("res://autoload/Net.gd") as GDScript).new()
	add_child_autofree(net)
	net._reset_rejoin_state()
	assert_false(ChatMute.is_muted(PEER_A), "a new session starts unmuted")


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


func test_scoreboard_strip_hidden_offline() -> void:
	var board: ScoreboardOverlay = (preload("res://ui/hud/ScoreboardOverlay.tscn") as PackedScene).instantiate() as ScoreboardOverlay
	add_child_autofree(board)
	board._refresh_mute_strip()
	assert_false(board._mute_box.visible, "offline: no remote players, no strip")


func _action_event(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_held_scoreboard_needs_explicit_nav_before_mute_is_reachable() -> void:
	var saved_mode: Variant = Net._mode
	var saved_peers: Dictionary = Net._peers.duplicate()
	Net._mode = Net.Mode.HOST
	Net._peers[PEER_A] = {"name": "Ann", "slot_id": 1}
	var probe: KeyProbe = KeyProbe.new()
	add_child_autofree(probe)
	var board: ScoreboardOverlay = (preload("res://ui/hud/ScoreboardOverlay.tscn") as PackedScene).instantiate() as ScoreboardOverlay
	board.match_provider = ProbeMatch.new()
	add_child_autofree(board)
	move_child(probe, 0)  # earlier in the tree = later in input order: the overlay sees events first
	Input.action_press(&"show_scores")
	board._holding = true
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(board.is_showing())
	assert_false(board._mute_peers.is_empty())
	var button: Button = board._mute_buttons[PEER_A] as Button
	assert_false(button.has_focus(), "opening the held table grabs no focus")
	# Drop / accept with the table held: nothing is muted, the gameplay event is delivered.
	for action: StringName in [&"ui_accept", &"drop_block"]:
		if InputMap.has_action(action):
			var event: InputEventAction = _action_event(action)
			get_viewport().push_input(event)
	assert_false(ChatMute.is_muted(PEER_A))
	assert_gt(probe.seen.size(), 0, "gameplay input still reaches the game while held")
	# An explicit D-pad press hands the strip focus; accept then toggles the mute.
	get_viewport().push_input(_action_event(&"ui_down"))
	assert_true(button.has_focus())
	# A focused button's ui_accept is the engine's own BaseButton path (synthetic keys do not reach it
	# headless here), so emit the press it produces.
	button.pressed.emit()
	assert_true(ChatMute.is_muted(PEER_A))
	Input.action_release(&"show_scores")
	board._process(0.0)
	assert_false(board.is_showing())
	assert_false(button.has_focus(), "releasing the hold releases focus")
	Net._mode = saved_mode
	Net._peers = saved_peers


class ProbeStats:
	extends RefCounted
	func live_payload() -> Dictionary:
		return {"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": -1, "winner_name": "", "match_duration": 1.0, "live": true, "rows": []}


class ProbeMatch:
	extends RefCounted
	var config: MatchConfig = MatchConfig.new()
	var st: ProbeStats = ProbeStats.new()
	func slot(_i: int) -> PlayerSlot:
		return null
	func state() -> MatchAutoload.State:
		return MatchAutoload.State.PLAYING
	func stats() -> ProbeStats:
		return st
