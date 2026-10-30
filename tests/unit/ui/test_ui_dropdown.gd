extends GutTest
## UiDropdown is a normal popup list (the old click-to-cycle is gone; cycling options use UiCycler), OptionButton-parity API, ui_accept open / ui_down
## move / ui_accept pick / ui_cancel close through the Input Map, outside click closes, row-item contract.

var _picked: Array[int] = []


func _make(count: int) -> UiDropdown:
	var dropdown: UiDropdown = UiDropdown.new()
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


func test_click_opens_a_list_and_never_cycles() -> void:
	var dropdown: UiDropdown = _make(3)
	dropdown.pressed.emit()
	assert_true(dropdown.is_open(), "a press opens the list")
	assert_eq(dropdown.selected, 0, "and does not change the value")
	dropdown.gui_input.emit(_right_click())
	assert_eq(dropdown.selected, 0, "right click does nothing")
	assert_eq(_picked.size(), 0)
	dropdown.pressed.emit()
	assert_false(dropdown.is_open(), "a second press closes it")


func test_ui_left_right_do_not_change_the_value() -> void:
	var dropdown: UiDropdown = _make(3)
	dropdown.grab_focus()
	await wait_frames(2)
	dropdown.gui_input.emit(_action(&"ui_right"))
	dropdown.gui_input.emit(_action(&"ui_left"))
	assert_eq(dropdown.selected, 0)
	assert_false(dropdown.is_open())
	assert_eq(_picked.size(), 0)


## The row of a popup list for item `index` (rows found by class, in item order).
func _row_at(list: UiDropdown.DropdownList, index: int) -> UiDropdown.DropdownList.Row:
	var rows: Array[UiDropdown.DropdownList.Row] = []
	for found: Node in list.find_children("*", "", true, false):
		if found is UiDropdown.DropdownList.Row:
			rows.append(found as UiDropdown.DropdownList.Row)
	return rows[index]


func test_pad_a_opens_the_list_and_focus_lands_on_the_current_row() -> void:
	var dropdown: UiDropdown = _make(5)
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
	assert_eq(list.get_viewport().gui_get_focus_owner(), _row_at(list, 2), "current row has focus")
	assert_true(_row_at(list, 2).is_current)


func test_down_moves_a_picks_and_the_signal_carries_the_index() -> void:
	var dropdown: UiDropdown = _make(5)
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
	assert_eq(list.get_viewport().gui_get_focus_owner(), _row_at(list, 1), "ui_down moves one row")
	Input.parse_input_event(_action(&"ui_accept"))
	Input.parse_input_event(_action(&"ui_accept", false))
	Input.flush_buffered_events()
	await wait_frames(2)
	assert_eq(dropdown.selected, 1)
	assert_eq(_picked, [1])
	assert_false(dropdown.is_open(), "picking closes the list")
	assert_true(dropdown.has_focus(), "focus returns to the dropdown")


func test_b_cancels_without_changing_the_value() -> void:
	var dropdown: UiDropdown = _make(5)
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
	var dropdown: UiDropdown = _make(4)
	dropdown.set_item_disabled(2, true)
	dropdown.select(1)
	dropdown.open(false)
	var list: UiDropdown.DropdownList = dropdown.get_node(NodePath(String(UiDropdown.LIST_NAME))) as UiDropdown.DropdownList
	assert_true(_row_at(list, 1).is_current)
	assert_false(_row_at(list, 0).is_current)
	assert_true(_row_at(list, 2).disabled)
	dropdown.pick(2)
	assert_eq(dropdown.selected, 1, "a disabled row cannot be picked")
	assert_true(dropdown.is_open())


func test_outside_click_closes_and_clicking_the_dropdown_toggles() -> void:
	var dropdown: UiDropdown = _make(3)
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


func test_disabled_dropdown_does_not_open() -> void:
	var dropdown: UiDropdown = _make(3)
	dropdown.disabled = true
	dropdown.open()
	assert_false(dropdown.is_open())
