extends GutTest
## Bontago-1pi.159.7: UiDropdown: click-to-cycle for short lists (decision 1pi.94), a popup list for
## long ones, OptionButton-parity API, ui_accept open / ui_down move / ui_accept pick / ui_cancel
## close through the Input Map, outside click closes, row-item contract.

var _picked: Array[int] = []


func _make(mode: UiDropdown.Mode, count: int) -> UiDropdown:
	var dropdown: UiDropdown = UiDropdown.new()
	dropdown.mode = mode
	for index: int in range(count):
		dropdown.add_item("Item %d" % index)
	dropdown.item_selected.connect(func(index: int) -> void: _picked.append(index))
	add_child_autofree(dropdown)
	return dropdown


func before_each() -> void:
	_picked.clear()


func _action(action: StringName, pressed: bool = true) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = pressed
	return event


func _right_click() -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	return click


func test_auto_mode_cycles_short_lists_and_pops_up_long_ones() -> void:
	assert_false(_make(UiDropdown.Mode.AUTO, UiDropdown.CYCLE_MAX_ITEMS).uses_popup())
	assert_true(_make(UiDropdown.Mode.AUTO, UiDropdown.CYCLE_MAX_ITEMS + 1).uses_popup())
	assert_true(_make(UiDropdown.Mode.POPUP, 2).uses_popup())
	assert_false(_make(UiDropdown.Mode.CYCLE, UiDropdown.CYCLE_MAX_ITEMS + 3).uses_popup())


func test_click_cycles_forward_wraps_and_right_click_goes_back() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.CYCLE, 3)
	dropdown.pressed.emit()
	dropdown.pressed.emit()
	dropdown.pressed.emit()
	assert_eq(dropdown.selected, 0, "wraps forward")
	dropdown.gui_input.emit(_right_click())
	assert_eq(dropdown.selected, 2, "right click steps back and wraps")
	assert_eq(_picked, [1, 2, 0, 2])
	assert_false(dropdown.is_open(), "cycle mode never opens a list")


func test_select_and_selected_never_emit() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.CYCLE, 3)
	dropdown.select(2)
	dropdown.selected = 1
	dropdown.selected = 9
	assert_eq(dropdown.selected, 1, "out of range is ignored")
	assert_eq(dropdown.text, "Item 1")
	assert_eq(_picked.size(), 0)


func test_cycle_skips_disabled_items() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.CYCLE, 3)
	dropdown.set_item_disabled(1, true)
	dropdown.pressed.emit()
	assert_eq(dropdown.selected, 2)


func test_row_item_contract() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.CYCLE, 3)
	await wait_frames(2)
	assert_true(dropdown.is_in_group(UiRowItem.GROUP))
	assert_eq(dropdown.size.y, float(UiRowItem.metrics().row_height_px))
	assert_gte(dropdown.size.x, float(UiRowItem.metrics().dropdown_min_width_px))
	assert_eq(dropdown.size_flags_horizontal, Control.SIZE_SHRINK_BEGIN)


func test_pad_a_opens_the_list_and_focus_lands_on_the_current_row() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 5)
	dropdown.select(2)
	dropdown.grab_focus()
	await wait_frames(2)
	var accept: InputEventAction = _action(&"ui_accept")
	Input.parse_input_event(accept)
	Input.parse_input_event(_action(&"ui_accept", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_true(dropdown.is_open(), "A (ui_accept) opens the list")
	var list: UiDropdown.DropdownList = dropdown.get_node(NodePath(String(UiDropdown.LIST_NAME))) as UiDropdown.DropdownList
	assert_eq(list.get_viewport().gui_get_focus_owner(), list.row_at(2), "current row has focus")
	assert_true(list.row_at(2).is_current)


func test_down_moves_a_picks_and_the_signal_carries_the_index() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 5)
	dropdown.grab_focus()
	await wait_frames(2)
	dropdown.open()
	await wait_frames(2)
	var list: UiDropdown.DropdownList = dropdown.get_node(NodePath(String(UiDropdown.LIST_NAME))) as UiDropdown.DropdownList
	var down: InputEventAction = _action(&"ui_down")
	Input.parse_input_event(down)
	Input.parse_input_event(_action(&"ui_down", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_eq(list.get_viewport().gui_get_focus_owner(), list.row_at(1), "ui_down moves one row")
	Input.parse_input_event(_action(&"ui_accept"))
	Input.parse_input_event(_action(&"ui_accept", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_eq(dropdown.selected, 1)
	assert_eq(_picked, [1])
	assert_false(dropdown.is_open(), "picking closes the list")
	assert_true(dropdown.has_focus(), "focus returns to the dropdown")


func test_b_cancels_without_changing_the_value() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 5)
	dropdown.select(3)
	dropdown.grab_focus()
	await wait_frames(2)
	dropdown.open()
	await wait_frames(2)
	Input.parse_input_event(_action(&"ui_cancel"))
	Input.parse_input_event(_action(&"ui_cancel", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_false(dropdown.is_open(), "B (ui_cancel) closes the list")
	assert_eq(dropdown.selected, 3)
	assert_eq(_picked.size(), 0)
	assert_true(dropdown.has_focus())


func test_list_marks_the_current_row_and_disables_unavailable_items() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 4)
	dropdown.set_item_disabled(2, true)
	dropdown.select(1)
	dropdown.open(false)
	var list: UiDropdown.DropdownList = dropdown.get_node(NodePath(String(UiDropdown.LIST_NAME))) as UiDropdown.DropdownList
	assert_true(list.row_at(1).is_current)
	assert_false(list.row_at(0).is_current)
	assert_true(list.row_at(2).disabled)
	dropdown.pick(2)
	assert_eq(dropdown.selected, 1, "a disabled row cannot be picked")
	assert_true(dropdown.is_open())


func test_picking_the_current_row_closes_without_emitting() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 3)
	dropdown.open(false)
	dropdown.pick(0)
	assert_false(dropdown.is_open())
	assert_eq(_picked.size(), 0)


func test_outside_click_closes_and_clicking_the_dropdown_toggles() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 3)
	await wait_frames(2)
	dropdown.pressed.emit()
	assert_true(dropdown.is_open())
	dropdown.pressed.emit()
	assert_false(dropdown.is_open(), "a second activation closes it")
	dropdown.open(false)
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(-5000.0, -5000.0)
	click.global_position = click.position
	var list: UiDropdown.DropdownList = dropdown.get_node(NodePath(String(UiDropdown.LIST_NAME))) as UiDropdown.DropdownList
	list._input(click)
	assert_false(dropdown.is_open(), "a press outside closes the list")


func test_disabled_dropdown_does_not_open_or_cycle() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 3)
	dropdown.disabled = true
	dropdown.open()
	assert_false(dropdown.is_open())
	var cycler: UiDropdown = _make(UiDropdown.Mode.CYCLE, 3)
	cycler.disabled = true
	cycler.cycle(false)
	assert_eq(cycler.selected, 0)


func test_hiding_the_dropdown_closes_the_list() -> void:
	var dropdown: UiDropdown = _make(UiDropdown.Mode.POPUP, 3)
	dropdown.open(false)
	dropdown.hide()
	assert_false(dropdown.is_open())
