extends GutTest
## Bontago-1pi.159.4: the row-item contract (ui/components/UiRowItem.gd, UiRow.gd). Every item in a
## row reports the same height, sizes to its content, never expands unless marked fill.

var _metrics: ComponentMetrics = null


func before_each() -> void:
	_metrics = UiRowItem.metrics()


func _row_with_all_items() -> UiRow:
	var row: UiRow = UiRow.new().setup("ROW")
	var button: UiBlockButton = UiBlockButton.new()
	button.text = "ADD BOT"
	row.add_item(button)
	row.add_item(UiIconButton.new())
	var badge: UiStatusBadge = UiStatusBadge.new()
	badge.text = "READY"
	badge.variant = UiStatusBadge.Look.READY
	row.add_item(badge)
	add_child_autofree(row)
	return row


func test_metrics_default_row_height_equals_the_current_row_control_height() -> void:
	assert_eq(_metrics.row_height_px, 36)
	assert_eq(_metrics.row_height_px, (load("res://config/lobby_layout_tuning.tres") as LobbyLayoutTuning).row_control_height_px)


func test_every_item_of_a_row_has_the_same_height() -> void:
	var row: UiRow = _row_with_all_items()
	await wait_frames(2)
	var items: Array[Control] = row.items()
	assert_eq(items.size(), 3)
	for item: Control in items:
		assert_eq(item.size.y, float(_metrics.row_height_px), "%s is one row height tall" % item.get_class())
		assert_true(item.is_in_group(UiRowItem.GROUP))


func test_apply_sets_min_height_flags_and_group() -> void:
	var control: Control = autofree(Control.new()) as Control
	UiRowItem.apply(control, UiRowItem.Kind.STEPPER)
	assert_eq(control.custom_minimum_size.y, float(_metrics.row_height_px))
	assert_eq(control.custom_minimum_size.x, float(_metrics.stepper_width_units * _metrics.row_height_px))
	assert_eq(control.size_flags_vertical, Control.SIZE_SHRINK_CENTER)
	assert_eq(control.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN, "never expands by default")
	assert_true(control.is_in_group(UiRowItem.GROUP))


func test_fill_lets_an_item_expand_and_a_wider_min_width_is_kept() -> void:
	var control: Control = autofree(Control.new()) as Control
	control.custom_minimum_size.x = 999.0
	UiRowItem.apply(control, UiRowItem.Kind.METER, true)
	assert_eq(control.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(control.custom_minimum_size.x, 999.0)


func test_icon_kind_is_square_row_height() -> void:
	assert_eq(UiRowItem.min_width_for(UiRowItem.Kind.ICON), float(_metrics.row_height_px))


func test_row_label_column_is_fixed_width_and_value_cell_trails() -> void:
	var row: UiRow = UiRow.new().setup("LABEL", UiBlockButton.new())
	var value: Label = row.with_value("42")
	add_child_autofree(row)
	await wait_frames(2)
	assert_eq(row.label.size.x, float(_metrics.row_label_width_px))
	assert_eq(row.get_child(row.get_child_count() - 1), value, "the readout is the last cell")
	assert_eq(value.text, "42")
	assert_eq(row.get_theme_constant("separation"), MenuStyleFactory.arcade_tuning().space_2_px, "items are space-2 apart")
