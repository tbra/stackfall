class_name HudChat
extends Control
## In-match chat adapter (sections 3 and 4 of the chat design):
## UiChatPanel in the bottom-left corner above the held/next preview, feeds it from the Events chat
## signals, opens it with the chat_open action and tells the rest of the game when it owns the keyboard
## (Events.chat_input_opened / chat_input_closed; PlayerController and CameraRig listen like they do for
## pause). The panel never takes the mouse. Chat is closed and hidden outside the live round (loading,
## results, lobby) and while the pause menu is open; pads can read it but never open it.

## Gap between the panel's bottom edge and the screen bottom: clears the HeldNextPanel (24 px margin +
## 148 px height in HUD.tscn) plus a margin.
const BOTTOM_OFFSET_PX: float = -180.0
const LEFT_OFFSET_PX: float = 24.0

var panel: UiChatPanel = null

var _pause_open: bool = false
var _results_open: bool = false
var _phase_live: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = UiChatPanel.new()
	panel.mode = UiChatPanel.Mode.HUD
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = LEFT_OFFSET_PX
	panel.offset_bottom = BOTTOM_OFFSET_PX
	panel.offset_top = BOTTOM_OFFSET_PX
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(panel)
	panel.submit_requested.connect(_on_submit_requested)
	panel.input_opened.connect(_on_panel_input_opened)
	panel.input_closed.connect(_on_panel_input_closed)
	Events.chat_line_received.connect(_on_chat_line_received)
	Events.chat_history_received.connect(_on_chat_history_received)
	Events.pause_menu_opened.connect(_on_pause_menu_opened)
	Events.pause_menu_closed.connect(_on_pause_menu_closed)
	Events.match_results_ready.connect(_on_match_results_ready)
	Events.match_scope_reset.connect(_on_match_scope_reset)
	Events.match_state_changed.connect(_on_match_state_changed)
	Events.net_mode_changed.connect(_on_net_mode_changed)
	_phase_live = _is_live_phase(Match.state())
	_refresh_visibility()


func _exit_tree() -> void:
	# Never leave gameplay input blocked behind a chat that vanished with its HUD.
	if panel != null and panel.is_typing():
		panel.close_input(false)


## True while chat may be shown or opened.
func is_chat_available() -> bool:
	return _phase_live and not _results_open


func _process(delta: float) -> void:
	if not is_chat_available():
		return
	panel.hold_visible = Input.is_action_pressed(&"show_scores") and panel.shown_line_count() > 0
	panel.apply_fade(delta)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(&"chat_open") or event is InputEventJoypadButton:
		return
	if not is_chat_available() or _pause_open or panel.is_typing():
		return
	var focus_owner: Control = get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit:
		return
	panel.open_input()
	get_viewport().set_input_as_handled()


func _on_submit_requested(text: String) -> void:
	Events.chat_send_requested.emit(text)


func _on_panel_input_opened() -> void:
	Events.chat_input_opened.emit()


func _on_panel_input_closed() -> void:
	Events.chat_input_closed.emit()


func _on_chat_line_received(line: Dictionary) -> void:
	if ChatMute.hides(line):
		return
	panel.append_line(line)
	_refresh_visibility()


func _on_chat_history_received(lines: Array) -> void:
	panel.replace_history(ChatMute.filter_lines(lines))


## Opening Pause closes chat first (pad Start is the only way: Esc is eaten by the field).
func _on_pause_menu_opened() -> void:
	_pause_open = true
	panel.close_input(false)


func _on_pause_menu_closed() -> void:
	_pause_open = false


func _on_match_results_ready(_results: Dictionary) -> void:
	_results_open = true
	panel.close_input(false)
	_refresh_visibility()


func _on_match_scope_reset() -> void:
	_results_open = false
	_refresh_visibility()


func _on_match_state_changed(_from_state: int, to_state: int) -> void:
	_phase_live = _is_live_phase(to_state)
	if not _phase_live:
		panel.close_input(false)
	_refresh_visibility()


## Disconnect / leaving the session closes the field.
func _on_net_mode_changed(mode: int) -> void:
	if mode == Net.Mode.OFFLINE:
		panel.close_input(false)


func _is_live_phase(state: int) -> bool:
	return Match.is_replicating(state)


## Hidden = not drawn and the mouse ignored (the whole node, so the panel's own fade cannot show it).
func _refresh_visibility() -> void:
	visible = is_chat_available()
