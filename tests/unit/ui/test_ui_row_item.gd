extends GutTest
## the row-item contract (ui/components/UiRowItem.gd): an item expands only when marked fill.

func test_fill_lets_an_item_expand() -> void:
	var control: Control = autofree(Control.new()) as Control
	UiRowItem.apply(control, UiRowItem.Kind.METER, true)
	assert_eq(control.size_flags_horizontal, Control.SIZE_EXPAND_FILL)
