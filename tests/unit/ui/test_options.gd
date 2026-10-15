extends GutTest
## Bontago-1pi.159.50/.51/.52: control labels, Reset/Back left-right focus, FOV meter 5 deg/step.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
var _counter: int = 0


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	_counter += 1
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(OS.get_user_data_dir().path_join("test_options_1014_%d.cfg" % _counter))
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


func test_fov_meter_steps_five_degrees_and_snaps_old_values() -> void:
	var menu: OptionsMenu = _make_menu()
	var meter: UiSegmentMeter = menu.get_node("%FovSlider") as UiSegmentMeter
	var lens: CameraTuning = CameraTuning.new()
	assert_eq(meter.step_count, 12)
	assert_almost_eq(menu._meter_value(meter, 1) - menu._meter_value(meter, 0), 5.0, 0.001)
	assert_almost_eq(menu._meter_value(meter, 0), lens.fov_min_deg, 0.001)
	assert_almost_eq(menu._meter_value(meter, 12), lens.fov_max_deg, 0.001)
	menu.settings_provider.set_fov_override_deg(63.0)
	menu._show_meter_value(meter, 63.0)
	assert_eq(meter.value, 5, "63 deg snaps to the 65 deg cell")
	assert_almost_eq(menu._meter_value(meter, meter.value), 65.0, 0.001)
