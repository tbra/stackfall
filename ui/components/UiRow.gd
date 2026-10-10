class_name UiRow
extends HBoxContainer
## A settings row: a fixed-width label column plus the row items, `space-2` apart
## (docs/UI_COMPONENTS_PLAN.md section 3.1 / 4). Screens build `UiRow.new().setup(label, control)`
## instead of aligning controls by hand; every item is a UiRowItem and so shares one height.

var label: Label = null
## The optional readout right of the items (see [method with_value]); null until requested.
var value_label: Label = null


func _init() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	add_theme_constant_override("separation", arcade.space_2_px)
	label = Label.new()
	label.custom_minimum_size.x = float(UiRowItem.metrics().row_label_width_px)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", arcade.cream_color)
	label.add_theme_font_size_override("font_size", arcade.font_size_body_px)
	add_child(label)


## Sets the label text and appends [param control] (optional). Returns self for chaining.
func setup(label_text: String, control: Control = null) -> UiRow:
	label.text = label_text
	if control != null:
		add_item(control)
	return self


func add_item(control: Control) -> void:
	add_child(control)
	if value_label != null:
		move_child(value_label, get_child_count() - 1)


## Appends a readout cell (sand text, fixed minimum width) and returns it.
func with_value(text: String = "") -> Label:
	if value_label == null:
		var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
		value_label = Label.new()
		value_label.custom_minimum_size.x = float(UiRowItem.metrics().row_value_cell_width_px)
		value_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		value_label.add_theme_color_override("font_color", arcade.sand_color)
		add_child(value_label)
	value_label.text = text
	return value_label


## The row items (every direct child in group `ui_row_item`), in order.
func items() -> Array[Control]:
	var found: Array[Control] = []
	for child: Node in get_children():
		if child is Control and child.is_in_group(UiRowItem.GROUP):
			found.append(child as Control)
	return found
