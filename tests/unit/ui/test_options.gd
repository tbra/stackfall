extends GutTest
##/.51/.52: control labels, Reset/Back left-right focus, FOV meter 5 deg/step.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	var path: String = Settings.effective_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	menu.settings_provider = fresh
	return menu


func _press(action: StringName) -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	var up: InputEventAction = InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func test_left_right_swaps_reset_and_back() -> void:
	var menu: OptionsMenu = _make_menu()
	await wait_frames(2)
	var reset: Button = menu.get_node("%ResetButton") as Button
	var back: Button = menu.get_node("%BackButton") as Button
	assert_eq(reset.get_node(reset.focus_neighbor_right), back)
	assert_eq(reset.get_node(reset.focus_neighbor_left), back)
	assert_eq(back.get_node(back.focus_neighbor_left), reset)
	assert_eq(back.get_node(back.focus_neighbor_right), reset)
	# Keyboard and gamepad events both resolve to ui_left / ui_right.
	var pad_right: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_right.button_index = JOY_BUTTON_DPAD_RIGHT
	var key_left: InputEventKey = InputEventKey.new()
	key_left.keycode = KEY_LEFT
	assert_true(pad_right.is_action(&"ui_right"))
	assert_true(key_left.is_action(&"ui_left"))
	reset.grab_focus()
	await _press(&"ui_right")
	assert_true(back.has_focus(), "ui_right: Reset -> Back")
	await _press(&"ui_left")
	assert_true(reset.has_focus(), "ui_left: Back -> Reset")


func test_fov_meter_snaps_a_stored_off_step_value_to_the_nearest_cell() -> void:
	var path: String = Settings.effective_path()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var stored: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(stored)
	stored.set_fov_override_deg(63.0)
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	menu.settings_provider = stored
	add_child_autofree(menu)
	var meter: UiSegmentMeter = menu.get_node("%FovSlider") as UiSegmentMeter
	assert_eq(meter.step_count, 12)
	assert_eq(meter.value, 5, "63 deg snaps to the 65 deg cell")
	meter.value_changed.emit(meter.value + 1)
	assert_almost_eq(stored.fov_override_deg(), 70.0, 0.001, "each cell is 5 deg")
