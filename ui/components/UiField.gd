class_name UiField
extends VBoxContainer
## The design system's Field (docs/ui_reskin/components.md "Field"): a sunken disc-900 text input
## with a 2px disc-400 edge (cream when focused), cream text, dust placeholder, and an optional
## caption above it in the label style. For the player name, direct IP and lobby code. A UiRowItem
## (METER-style fill: it expands to its column, one row height for the input).
## Keyboard / pad: the LineEdit takes focus; ui_accept / Enter submits ([signal text_submitted]).
## Screens read and write [member text] and connect the forwarded signals; they never style the
## inner [member edit] themselves.

signal text_changed(new_text: String)
signal text_submitted(new_text: String)

## Caption above the input; empty hides it.
@export var label_text: String = "":
	set(caption):
		label_text = caption
		label.text = caption
		label.visible = caption != ""
@export var placeholder: String = "":
	set(hint):
		placeholder = hint
		edit.placeholder_text = hint
@export var text: String = "":
	set(new_text):
		text = new_text
		if edit.text != new_text:
			edit.text = new_text
@export var max_length: int = 0:
	set(limit):
		max_length = limit
		edit.max_length = limit
@export var secret: bool = false:
	set(hide_text):
		secret = hide_text
		edit.secret = hide_text
@export var editable: bool = true:
	set(can_edit):
		editable = can_edit
		edit.editable = can_edit

var label: Label = null
var edit: LineEdit = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	add_theme_constant_override("separation", arcade.space_1_px)
	focus_mode = Control.FOCUS_NONE
	label = Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	add_child(label)
	edit = LineEdit.new()
	edit.custom_minimum_size.y = float(UiRowItem.metrics().row_height_px)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_edit(edit, arcade)
	edit.text_changed.connect(_on_edit_changed)
	edit.text_submitted.connect(text_submitted.emit)
	add_child(edit)
	UiRowItem.apply(self, UiRowItem.Kind.METER, true)


## Focus goes to the input (the container itself never takes it).
func focus_input() -> void:
	edit.grab_focus()


func select_all() -> void:
	edit.select_all()


## The disc-900 sunken look from tokens; focus turns the edge cream.
static func _style_edit(line: LineEdit, arcade: ArcadeVisualTuning) -> void:
	for state: String in ["normal", "read_only"]:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = arcade.disc_900_color
		box.border_color = arcade.disc_400_color
		box.set_border_width_all(arcade.well_border_px)
		box.set_corner_radius_all(arcade.radius_block_px)
		box.content_margin_left = float(arcade.space_3_px)
		box.content_margin_right = float(arcade.space_3_px)
		line.add_theme_stylebox_override(state, box)
	var focus: StyleBoxFlat = StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = arcade.cream_color
	focus.set_border_width_all(arcade.well_border_px)
	focus.set_corner_radius_all(arcade.radius_block_px)
	line.add_theme_stylebox_override("focus", focus)
	line.add_theme_color_override("font_color", arcade.cream_color)
	line.add_theme_color_override("font_uneditable_color", arcade.dust_color)
	line.add_theme_color_override("font_placeholder_color", arcade.dust_color)
	line.add_theme_color_override("caret_color", arcade.cream_color)
	line.add_theme_font_size_override("font_size", arcade.font_size_body_px)


func _on_edit_changed(new_text: String) -> void:
	text = new_text
	text_changed.emit(new_text)
