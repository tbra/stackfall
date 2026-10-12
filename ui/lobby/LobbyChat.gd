class_name LobbyChat
extends UiChatPanel
## Lobby adapter for the chat panel (Bontago-1pi.192.4, docs/CHAT_PLAN.md C3): the opaque LOBBY skin at the
## foot of the right players panel, wired to the Events chat bus. Typed text goes out through
## Events.chat_send_requested; wire lines, the late-join history and host notices come back through Events.
## The panel hides itself offline and on the private local bot host, where nobody can chat.
## Pad users read only: the edit is FOCUS_CLICK and LobbyPlayersPanel.focus_entries() never lists it.

const NOTICE_TEXT_RATE: String = "Slow down, you are sending too fast."
const NOTICE_TEXT_DUPLICATE: String = "You just said that."
## Slot / peer of a local-only notice line (no sender).
const NOTICE_NO_ID: int = -1

## Overridable in tests: true when the session can carry chat.
var availability: Callable = Callable()


func _init() -> void:
	super._init()
	mode = UiChatPanel.Mode.LOBBY
	size_flags_vertical = Control.SIZE_SHRINK_END


func _ready() -> void:
	submit_requested.connect(_on_submit_requested)
	Events.chat_line_received.connect(_on_chat_line)
	Events.chat_history_received.connect(_on_chat_history)
	Events.chat_notice.connect(_on_notice)
	refresh_availability()


func _process(_delta: float) -> void:
	refresh_availability()


## True when a networked session carries chat (not offline, not the private local host).
func is_chat_available() -> bool:
	if availability.is_valid():
		return availability.call() as bool
	return not Net.is_offline() and not Net.is_private_session()


func refresh_availability() -> void:
	var available: bool = is_chat_available()
	if visible != available:
		visible = available
		if not available and is_typing():
			close_input(false)


## T opens the field from anywhere in the lobby unless another text field already has focus.
## (Enter stays Start: Lobby._input takes lobby_confirm first.)
func _unhandled_input(event: InputEvent) -> void:
	if not visible or not is_visible_in_tree() or is_typing() or not event.is_action_pressed(&"chat_open"):
		return
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		return
	open_input()
	get_viewport().set_input_as_handled()


func _on_submit_requested(text: String) -> void:
	Events.chat_send_requested.emit(text)


## Wire lines from a muted peer are dropped here (ChatMute); system lines always show.
func _on_chat_line(line: Dictionary) -> void:
	if not ChatMute.hides(line):
		append_line(line)


func _on_chat_history(lines: Array) -> void:
	replace_history(ChatMute.filter_lines(lines))


func _on_notice(code: int) -> void:
	var text: String = NOTICE_TEXT_RATE if code == ChatRules.NOTICE_RATE else NOTICE_TEXT_DUPLICATE
	append_line(ChatRules.make_line(0, NOTICE_NO_ID, NOTICE_NO_ID, "", 0, text, ChatRules.KIND_SYSTEM))
