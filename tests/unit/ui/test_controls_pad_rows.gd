extends GutTest
## The gamepad Controls page lists only
## the pad's real controls ("Rotate 90 deg" = B, "Free rotate (hold)" = RT), the keyboard page
## keeps "Free rotate (drag)" and a rebindable "Orbit camera".

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const PAD_HIDDEN: Array[StringName] = [
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotation_mode", &"rotate_drag", &"camera_orbit", &"camera_mode",
]
const WALK_LIMIT: int = 64

func before_each() -> void:
	_delete_settings_file()


func after_each() -> void:
	Settings._input(InputEventKey.new())
	InputMap.load_from_project_settings()
	_delete_settings_file()


func _delete_settings_file() -> void:
	if FileAccess.file_exists(Settings.effective_path()):
		DirAccess.remove_absolute(Settings.effective_path())


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	menu.settings_provider = fresh
	return menu


func _row(menu: OptionsMenu, action: StringName) -> KeyRebindRow:
	for row: KeyRebindRow in menu._rows:
		if row._action == action:
			return row
	return null


func test_rebinding_rotate_snap_on_the_pad_persists() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings._input(InputEventJoypadButton.new())
	var row: KeyRebindRow = _row(menu, &"rotate_snap")
	row.rebind_button().pressed.emit()
	var joy: InputEventJoypadButton = InputEventJoypadButton.new()
	joy.button_index = JOY_BUTTON_Y
	joy.pressed = true
	row._input(joy)
	assert_false(row.is_listening())
	var live: Array[InputEvent] = InputMap.action_get_events(&"rotate_snap")
	assert_eq(live.size(), 1)
	assert_eq((live[0] as InputEventJoypadButton).button_index, JOY_BUTTON_Y)

	# A fresh Settings reads the saved file and reapplies the override.
	InputMap.load_from_project_settings()
	var reloaded: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(reloaded)
	var stored: Array[InputEvent] = InputMap.action_get_events(&"rotate_snap")
	var stored_pad: Array[InputEventJoypadButton] = []
	for event: InputEvent in stored:
		if event is InputEventJoypadButton:
			stored_pad.append(event)
	assert_eq(stored_pad.size(), 1, "the override is saved and reloaded")
	assert_eq(stored_pad[0].button_index, JOY_BUTTON_Y)


func _pad_press(button: JoyButton) -> void:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	var up: InputEventJoypadButton = InputEventJoypadButton.new()
	up.button_index = button
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func test_pad_focus_walks_every_row_to_reset_and_back_with_no_dead_end() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings._input(InputEventJoypadButton.new())
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await wait_frames(3)
	var shown: Array[KeyRebindRow] = []
	for row: KeyRebindRow in menu._rows:
		if row.is_available_on_active_device():
			shown.append(row)
	assert_gt(shown.size(), 0)
	shown[0].grab_focus()
	assert_true(shown[0].has_focus())
	for i: int in range(1, shown.size()):
		await _pad_press(JOY_BUTTON_DPAD_DOWN)
		assert_true(shown[i].has_focus(), "ui_down reaches %s after %s" % [shown[i]._action, shown[i - 1]._action])
	var reset: Button = menu.get_node("%ResetButton") as Button
	var back: Button = menu.get_node("%BackButton") as Button
	var steps: int = 0
	while not reset.has_focus() and steps < WALK_LIMIT:
		await _pad_press(JOY_BUTTON_DPAD_DOWN)
		steps += 1
		assert_not_null(get_viewport().gui_get_focus_owner(), "focus must never be lost")
	assert_true(reset.has_focus(), "ui_down reaches Reset below the last row")
	await _pad_press(JOY_BUTTON_DPAD_RIGHT)
	assert_true(back.has_focus(), "and Back beside it")
	reset.grab_focus()
	steps = 0
	while not shown[shown.size() - 1].has_focus() and steps < WALK_LIMIT:
		await _pad_press(JOY_BUTTON_DPAD_UP)
		steps += 1
	assert_true(shown[shown.size() - 1].has_focus(), "ui_up from Reset climbs back to the last row")
	for i: int in range(shown.size() - 2, -1, -1):
		await _pad_press(JOY_BUTTON_DPAD_UP)
		assert_true(shown[i].has_focus(), "ui_up reaches %s" % shown[i]._action)
