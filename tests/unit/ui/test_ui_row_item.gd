extends GutTest
## the row-item contract (ui/components/UiRowItem.gd, UiRow.gd). Every item in a
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


func test_every_item_of_a_row_has_the_same_height() -> void:
	var row: UiRow = _row_with_all_items()
	await wait_frames(2)
	var items: Array[Control] = []
	for child: Node in row.get_children():
		if child is Control and child.is_in_group(UiRowItem.GROUP):
			items.append(child as Control)
	assert_eq(items.size(), 3)
	for item: Control in items:
		assert_eq(item.size.y, float(_metrics.row_height_px), "%s is one row height tall" % item.get_class())
		assert_true(item.is_in_group(UiRowItem.GROUP))


func test_fill_lets_an_item_expand_and_a_wider_min_width_is_kept() -> void:
	var control: Control = autofree(Control.new()) as Control
	control.custom_minimum_size.x = 999.0
	UiRowItem.apply(control, UiRowItem.Kind.METER, true)
	assert_eq(control.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
	assert_eq(control.custom_minimum_size.x, 999.0)
