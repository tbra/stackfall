class_name KeyRebindRow
extends HBoxContainer
## docs/M6_PLAN.md package C2: one row per rebindable Input Map action, built
## dynamically by ui/OptionsMenu.gd's _build_rebind_rows() (one instance of
## this scene per OptionsMenu.REBINDABLE_ACTIONS entry). Shows the action's
## current binding(s) (InputMap.action_get_events(), which already reflects
## any Settings key override -- Settings._apply_key_overrides() writes
## straight onto the InputMap, see autoload/Settings.gd's own doc) and
## captures the next InputEventKey/InputEventMouseButton/InputEventJoypadButton
## while "listening".

signal rebind_captured(action: StringName, event: InputEvent)

const LISTENING_TEXT: String = "Press a key..."
const REBIND_TEXT: String = "Rebind"

@onready var _action_label: Label = %ActionLabel
@onready var _binding_label: Label = %BindingLabel
@onready var _rebind_button: Button = %RebindButton

var _action: StringName = &""
var _listening: bool = false


func _ready() -> void:
	_rebind_button.pressed.connect(_on_rebind_pressed)


## Called once by OptionsMenu right after instancing this row, the same
## "setup() before use" convention ui/TuningPanel.gd's own per-row builders
## follow (there: a resource + property name; here: one action name).
func setup(action: StringName) -> void:
	_action = action
	_action_label.text = _display_name(action)
	_refresh_binding_label()


func action_name() -> StringName:
	return _action


## Test seam (tests/unit/test_options_menu.gd): whether this row is currently
## armed to capture the next input.
func is_listening() -> bool:
	return _listening


## Test seam: the Button a synthetic `pressed.emit()` (or a real click) should
## target to start listening, without reaching past this row's own %unique
## names.
func rebind_button() -> Button:
	return _rebind_button


## Also drops keyboard focus from the button (Bontago-8or.19, owner playtest
## feedback/playtest.md: "no option to actually remap the ones that are
## mapped") -- while this button stays focused, Godot's own GUI layer treats
## Space/Enter as *that button's* activate accelerator and arrows/Tab as focus
## navigation, so a still-focused RebindButton is a second, independent path
## (besides _input() below) by which those keys could be swallowed before this
## row ever sees them.
func _on_rebind_pressed() -> void:
	_listening = true
	_rebind_button.text = LISTENING_TEXT
	_rebind_button.release_focus()


## Captures the very next real input while listening -- InputEventKey,
## InputEventMouseButton or InputEventJoypadButton (docs/M6_PLAN.md package
## C2's own list; joypad *motion*/axis is left out on purpose -- a rebind is a
## discrete press, not an analog drift, the same digital-vs-analog split
## tools/bootstrap_project.gd's own action bindings already follow).
##
## Captured in Node._input() rather than Node._unhandled_input() (Bontago-
## 8or.19, owner playtest feedback/playtest.md: "no option to actually remap
## the ones that are mapped"). Godot's own input pipeline runs, in order,
## Node._input() -> Control GUI dispatch (focus navigation, button
## accelerators, mouse_filter consumption) -> Node._unhandled_input(); as
## _unhandled_input(), this method only ever saw whatever the GUI layer left
## over, which for a full-screen options panel is close to nothing: a mouse
## click anywhere on the panel's own mouse_filter=STOP background was
## consumed by the GUI layer before it could reach here, and Space/Enter/
## arrows/Tab were consumed by the still-focused RebindButton's own GUI
## accelerator/focus-navigation handling instead (see _on_rebind_pressed()'s
## release_focus() call above, which closes that second path). Moving the
## capture to _input() runs it *before* any of that GUI processing, so a
## listening row now sees the raw event first regardless of what sits under
## the pointer or which control has focus.
##
## ui_cancel cancels the capture instead of binding Escape/gamepad B onto the
## action -- caught here, before OptionsMenu's own _unhandled_input() back-out
## handler, because _input() is delivered to every node in the tree (deepest
## first) before Godot even starts the GUI/_unhandled_input phases that
## OptionsMenu's own handler relies on, so a listening row always sees
## ui_cancel first.
func _input(event: InputEvent) -> void:
	if not _listening:
		return
	if event.is_action_pressed(&"ui_cancel"):
		_cancel_listening()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
		if not event.is_pressed() or event.is_echo():
			return
		_capture(event)
		get_viewport().set_input_as_handled()


func _capture(event: InputEvent) -> void:
	_listening = false
	Settings.set_key_override(_action, event)
	_refresh_binding_label()
	rebind_captured.emit(_action, event)


func _cancel_listening() -> void:
	_listening = false
	_refresh_binding_label()


func _refresh_binding_label() -> void:
	_rebind_button.text = REBIND_TEXT
	_binding_label.text = _binding_text(_action)


func _binding_text(action: StringName) -> String:
	if not InputMap.has_action(action):
		return "(unbound)"
	var events: Array[InputEvent] = InputMap.action_get_events(action)
	if events.is_empty():
		return "(unbound)"
	var parts: PackedStringArray = PackedStringArray()
	for event: InputEvent in events:
		parts.append(event.as_text())
	return ", ".join(parts)


## "ghost_move_left" -> "Ghost Move Left" -- purely cosmetic, so a fresh
## action added to REBINDABLE_ACTIONS never needs a matching label edit here.
func _display_name(action: StringName) -> String:
	var words: PackedStringArray = String(action).split("_")
	var parts: PackedStringArray = PackedStringArray()
	for word: String in words:
		if word.is_empty():
			continue
		parts.append(word[0].to_upper() + word.substr(1))
	return " ".join(parts)
