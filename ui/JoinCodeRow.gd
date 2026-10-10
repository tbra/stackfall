class_name JoinCodeRow
extends HBoxContainer
## Bontago-1pi.164: one isolated host-lobby row showing the internet join code (or why there is none).
## Reads only what Net exposes (upnp_state / upnp_join_code / host_port); shown for a non-Steam host.
## The lobby rebuild may move this row anywhere: it has no layout assumptions.

const TEXT_CODE: String = "Join code: %s"
const TEXT_WORKING: String = "Opening a port on your router..."
const TEXT_FALLBACK: String = "Router didn't open the port - use Steam, or forward UDP port %d"
const TEXT_COPY: String = "Copy"
const TEXT_COPIED: String = "Copied"

var _label: Label = Label.new()
var _copy_button: Button = Button.new()
var _code: String = ""


func _ready() -> void:
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_copy_button.text = TEXT_COPY
	_copy_button.pressed.connect(_on_copy_pressed)
	add_child(_label)
	add_child(_copy_button)
	visible = false


## The Copy button, so the lobby can put it in its focus chain.
func copy_button() -> Button:
	return _copy_button


func code() -> String:
	return _code


func label_text() -> String:
	return _label.text


## `net` is the lobby's net provider. The row hides itself unless this is a non-Steam, non-private host
## whose UPnP attempt has started.
func refresh(net: Variant, is_host: bool) -> void:
	var was_visible: bool = visible
	var was_code: String = _code
	_code = ""
	var show_row: bool = false
	if is_host and net != null and net.has_method(&"upnp_state") and not bool(net.is_steam_session()):
		var state: int = int(net.upnp_state())
		match state:
			UpnpRunner.State.PENDING:
				show_row = true
				_label.text = TEXT_WORKING
			UpnpRunner.State.OPENED:
				show_row = true
				_code = str(net.upnp_join_code())
				_label.text = TEXT_CODE % _code
			UpnpRunner.State.FAILED, UpnpRunner.State.UNSUPPORTED:
				show_row = true
				_label.text = TEXT_FALLBACK % int(net.host_port())
				_label.tooltip_text = str(net.upnp_failure_reason())
	visible = show_row
	_copy_button.visible = _code != ""
	if _code != was_code:
		_copy_button.text = TEXT_COPY
	if visible != was_visible or _code != was_code:
		visibility_changed_for_focus.emit()


## The shown/hidden state or the code changed (the lobby re-wires its focus chain).
signal visibility_changed_for_focus


func _on_copy_pressed() -> void:
	if _code == "":
		return
	DisplayServer.clipboard_set(_code)
	_copy_button.text = TEXT_COPIED
