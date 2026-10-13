class_name UiDialog
extends Control
## The design system's Dialog (docs/ui_reskin/components.md "Dialog"): a centred modal plate on a
## full-screen disc-900 scrim, a centred heading, an optional body line and stacked full-width small
## BlockButtons. The consumer provides a title, a body and an ordered list of actions
## ([method add_action]); the first action is the forward one (primary look unless the consumer
## passes DANGER for a destructive confirm) and gets initial focus. A trailing Cancel block is always
## present. Keyboard, mouse and gamepad all work: ui_accept presses the focused block, ui_cancel (B)
## or pause_menu (Start) dismisses, focus is trapped in the plate (UiFocusTrap) and the scrim eats
## clicks. In-tree overlay, not a Window, so it renders into every capture and follows the UI scale.

## An action block was pressed; the dialog has already hidden itself.
signal action_chosen(id: StringName)
## Cancel, B or Start dismissed the dialog (it has already hidden itself).
signal canceled

const THEME_PATH: String = "res://ui/theme/stackfall_theme.tres"
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/options_visual_tuning.tres")
const CANCEL_ID: StringName = &"cancel"
const CANCEL_TEXT: String = "Cancel"

@export var title: String = "":
	set(value):
		title = value
		_title_label.text = value.to_upper()
		_title_label.visible = value != ""
@export_multiline var dialog_text: String = "":
	set(value):
		dialog_text = value
		_body_label.text = value
		_body_label.visible = value != ""

var panel: UiPanel = null
var _title_label: UiText = null
var _body_label: UiText = null
var _actions: Array[UiBlockButton] = []
var _cancel_button: UiBlockButton = null
## The control that held focus before open(); focus returns to it on close.
var _return_focus: Control = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	theme = load(THEME_PATH) as Theme
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(arcade.disc_900_color, arcade.scrim_alpha)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = UiPanel.new()
	panel.custom_minimum_size.x = float(OPTIONS_TUNING.dialog_width_px)
	center.add_child(panel)
	_title_label = UiText.make(UiText.Role.HEADING)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.visible = false
	panel.content.add_child(_title_label)
	_body_label = UiText.make(UiText.Role.BODY)
	_body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.visible = false
	panel.content.add_child(_body_label)
	_cancel_button = _make_block(CANCEL_ID, CANCEL_TEXT, UiBlockButton.Look.SECONDARY)
	panel.content.add_child(_cancel_button)


## The ordered action blocks (excluding Cancel).
func actions() -> Array[UiBlockButton]:
	return _actions


## The Cancel block (its label is changeable: Back, No, ...).
func cancel_button() -> UiBlockButton:
	return _cancel_button


## Removes every action block (Cancel stays).
func clear_actions() -> void:
	for button: UiBlockButton in _actions:
		panel.content.remove_child(button)
		button.queue_free()
	_actions.clear()


## Adds an action block above Cancel. The FIRST action is the forward one: it gets
## initial focus (text-only blocks, no glyphs). [param look]: PRIMARY / MINT for a forward action,
## DANGER for a destructive confirm, SECONDARY otherwise.
func add_action(id: StringName, label: String, look: UiBlockButton.Look = UiBlockButton.Look.PRIMARY) -> UiBlockButton:
	var button: UiBlockButton = _make_block(id, label, look)
	panel.content.add_child(button)
	panel.content.move_child(button, _cancel_button.get_index())
	_actions.append(button)
	return button


## Shows the dialog, traps focus in it and focuses the first action (or Cancel when it has none).
func open() -> void:
	if visible:
		return
	_return_focus = get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	visible = true
	UiFocusTrap.trap(panel)
	var first: Control = _actions[0] if not _actions.is_empty() else _cancel_button
	for button: UiBlockButton in _actions:
		if not button.disabled and button.focus_mode != Control.FOCUS_NONE:
			first = button
			break
	first.grab_focus()


## Hides without emitting anything and gives focus back to whoever had it.
func close() -> void:
	if not visible:
		return
	visible = false
	if _return_focus != null and is_instance_valid(_return_focus) and _return_focus.is_visible_in_tree():
		_return_focus.grab_focus()
	_return_focus = null


## Cancel / B / Start: hides, then emits [signal canceled].
func dismiss() -> void:
	if not visible:
		return
	close()
	canceled.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed(&"ui_cancel") or event.is_action_pressed(&"pause_menu"):
		dismiss()
		get_viewport().set_input_as_handled()


func _make_block(id: StringName, label: String, look: UiBlockButton.Look) -> UiBlockButton:
	var button: UiBlockButton = UiBlockButton.new()
	button.text = label.to_upper()
	button.variant = look
	button.small = true
	button.size_flags_horizontal = Control.SIZE_FILL
	button.pressed.connect(_on_block_pressed.bind(id))
	return button


func _on_block_pressed(id: StringName) -> void:
	if id == CANCEL_ID:
		dismiss()
		return
	close()
	action_chosen.emit(id)
