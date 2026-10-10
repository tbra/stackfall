extends GutTest
## Bontago-1pi.159.5: UiTabs / UiTab: one active tab, rim notch on the active one (top when
## HORIZONTAL, left when VERTICAL), click / left-right / LB-RB selection, skipping hidden and
## disabled tabs, wrap-around index.

var _changes: Array[StringName] = []


func _make(vertical: bool = false) -> UiTabs:
	var tabs: UiTabs = UiTabs.new()
	if vertical:
		tabs.orientation = UiTabs.Orientation.VERTICAL
	tabs.add_tab(&"game", "Game")
	tabs.add_tab(&"graphics", "Graphics")
	tabs.add_tab(&"controls", "Controls")
	tabs.tab_changed.connect(func(id: StringName) -> void: _changes.append(id))
	add_child_autofree(tabs)
	return tabs


func before_each() -> void:
	_changes.clear()


func _action(action: StringName) -> InputEventAction:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func test_next_index_wraps_both_ways() -> void:
	assert_eq(UiTabs.next_index(0, 1, 3), 1)
	assert_eq(UiTabs.next_index(2, 1, 3), 0)
	assert_eq(UiTabs.next_index(0, -1, 3), 2)
	assert_eq(UiTabs.next_index(0, 1, 0), 0)


func test_first_tab_is_active_without_a_signal_and_labels_are_uppercase() -> void:
	var tabs: UiTabs = _make()
	assert_eq(tabs.current, &"game")
	assert_eq(_changes.size(), 0)
	assert_eq(tabs.get_tab(&"graphics").text, "GRAPHICS")
	assert_true(tabs.get_tab(&"game").button_pressed)


func test_click_selects_and_emits_once() -> void:
	var tabs: UiTabs = _make()
	tabs.get_tab(&"controls").pressed.emit()
	assert_eq(tabs.current, &"controls")
	assert_eq(_changes, [&"controls"])
	tabs.get_tab(&"controls").pressed.emit()
	assert_eq(_changes.size(), 1, "re-pressing the active tab does nothing")


func test_assigning_current_selects_and_keeps_exactly_one_pressed() -> void:
	var tabs: UiTabs = _make()
	tabs.current = &"graphics"
	var pressed: int = 0
	for id: StringName in tabs.tab_ids():
		if tabs.get_tab(id).button_pressed:
			pressed += 1
	assert_eq(pressed, 1)
	assert_eq(_changes, [&"graphics"])
	tabs.current = &"unknown"
	assert_eq(tabs.current, &"graphics")


func test_active_tab_has_the_rim_notch_on_top_and_vertical_on_the_left() -> void:
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var notch: int = UiRowItem.metrics().tab_notch_px
	var top: UiTabs = _make()
	var active: StyleBoxFlat = top.get_tab(&"game").get_theme_stylebox("pressed") as StyleBoxFlat
	assert_eq(active.border_width_top, notch)
	assert_eq(active.border_width_left, 0)
	assert_eq(active.border_color, arcade.rim_color)
	assert_eq(active.bg_color, arcade.disc_600_color)
	var idle: StyleBoxFlat = top.get_tab(&"game").get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(idle.border_width_top, 0)
	assert_eq(idle.bg_color.a, 0.0, "idle is transparent")
	var side: UiTabs = _make(true)
	var side_active: StyleBoxFlat = side.get_tab(&"game").get_theme_stylebox("pressed") as StyleBoxFlat
	assert_eq(side_active.border_width_left, notch)
	assert_eq(side_active.border_width_top, 0)
	assert_true(side.vertical)


func test_left_right_on_a_focused_tab_selects_the_neighbour() -> void:
	var tabs: UiTabs = _make()
	await wait_frames(1)
	tabs.get_tab(&"game").grab_focus()
	tabs.get_tab(&"game")._gui_input(_action(&"ui_right"))
	assert_eq(tabs.current, &"graphics")
	assert_true(tabs.get_tab(&"graphics").has_focus(), "focus follows the selection")
	tabs.get_tab(&"graphics")._gui_input(_action(&"ui_left"))
	assert_eq(tabs.current, &"game")
	tabs.get_tab(&"game")._gui_input(_action(&"ui_left"))
	assert_eq(tabs.current, &"controls", "wraps")


func test_vertical_bar_steps_with_up_down() -> void:
	var tabs: UiTabs = _make(true)
	await wait_frames(1)
	tabs.get_tab(&"game")._gui_input(_action(&"ui_right"))
	assert_eq(tabs.current, &"game", "left / right do nothing in a side bar")
	tabs.get_tab(&"game")._gui_input(_action(&"ui_down"))
	assert_eq(tabs.current, &"graphics")


func test_shoulders_cycle_and_the_flag_turns_them_off() -> void:
	var tabs: UiTabs = _make()
	await wait_frames(1)
	tabs._unhandled_input(_action(&"menu_tab_next"))
	assert_eq(tabs.current, &"graphics")
	tabs._unhandled_input(_action(&"menu_tab_previous"))
	tabs._unhandled_input(_action(&"menu_tab_previous"))
	assert_eq(tabs.current, &"controls", "LB wraps from the first tab")
	tabs.handle_shoulders = false
	tabs._unhandled_input(_action(&"menu_tab_next"))
	assert_eq(tabs.current, &"controls")


func test_shoulder_events_are_bound_to_lb_rb() -> void:
	var lb: InputEventJoypadButton = InputEventJoypadButton.new()
	lb.button_index = JOY_BUTTON_LEFT_SHOULDER
	lb.pressed = true
	assert_true(lb.is_action_pressed(&"menu_tab_previous"))
	var rb: InputEventJoypadButton = InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	assert_true(rb.is_action_pressed(&"menu_tab_next"))


func test_hidden_and_disabled_tabs_are_skipped() -> void:
	var tabs: UiTabs = _make()
	await wait_frames(1)
	tabs.set_tab_visible(&"graphics", false)
	tabs._unhandled_input(_action(&"menu_tab_next"))
	assert_eq(tabs.current, &"controls")
	tabs.set_tab_disabled(&"game", true)
	tabs._unhandled_input(_action(&"menu_tab_next"))
	assert_eq(tabs.current, &"controls", "nothing else selectable")
	tabs.current = &"graphics"
	assert_eq(tabs.current, &"controls", "a hidden tab cannot be selected")


func test_hiding_the_active_tab_moves_to_the_next() -> void:
	var tabs: UiTabs = _make()
	tabs.set_tab_visible(&"game", false)
	assert_eq(tabs.current, &"graphics")


func test_tab_height_comes_from_metrics() -> void:
	var tabs: UiTabs = _make()
	await wait_frames(2)
	assert_gte(tabs.get_tab(&"game").size.y, float(UiRowItem.metrics().tab_height_px))
