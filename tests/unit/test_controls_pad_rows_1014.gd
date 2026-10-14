extends GutTest
## Bontago-1pi.159.63 (owner decision 1pi.159.62, option A): the gamepad Controls page lists only
## the pad's real controls ("Rotate 90 deg" = B, "Free rotate (hold)" = RT), the keyboard page
## keeps "Free rotate (drag)" and a rebindable "Orbit camera".

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const PAD_HIDDEN: Array[StringName] = [
	&"rotate_yaw_ccw", &"rotate_yaw_cw", &"rotation_mode", &"rotate_drag", &"camera_orbit", &"camera_mode",
]
const WALK_LIMIT: int = 64

var _cfg_path: String = OS.get_user_data_dir().path_join("test_controls_pad_rows_1014.cfg")
var _default_cfg_path: String = Settings.default_config_path()


func after_each() -> void:
	Settings.set_config_path_for_test(_default_cfg_path)
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
	InputMap.load_from_project_settings()
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(_cfg_path)
	menu.settings_provider = fresh
	return menu


func _row(menu: OptionsMenu, action: StringName) -> KeyRebindRow:
	for row: KeyRebindRow in menu.rebind_rows():
		if row.action_name() == action:
			return row
	return null


func _label(row: KeyRebindRow) -> String:
	return (row.get_node("%ActionLabel") as Label).text


func _glyphs(row: KeyRebindRow) -> Array[String]:
	var texts: Array[String] = []
	for child: Node in (row.get_node("%GlyphRow") as HBoxContainer).get_children():
		texts.append((child as InputGlyph).label_text())
	return texts


func test_pad_page_lists_the_real_rotate_controls_only() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var snap: KeyRebindRow = _row(menu, &"rotate_snap")
	var drag: KeyRebindRow = _row(menu, &"rotate_drag_pad")
	assert_not_null(snap)
	assert_not_null(drag)
	assert_true(snap.visible and drag.visible)
	assert_eq(_label(snap), "Rotate 90 deg")
	assert_eq(_label(drag), "Free rotate (hold)")
	assert_eq(_glyphs(snap), ["B"])
	assert_eq(_glyphs(drag), ["RT"])
	for action: StringName in PAD_HIDDEN:
		var row: KeyRebindRow = _row(menu, action)
		if row != null:
			assert_false(row.visible, "%s must be hidden on the pad page" % action)
			assert_false(row.is_available_on_active_device())


func test_keyboard_page_renames_free_rotate_and_keeps_orbit_camera() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	assert_eq(_label(_row(menu, &"rotate_drag")), "Free rotate (drag)")
	var orbit: KeyRebindRow = _row(menu, &"camera_orbit")
	assert_true(orbit.visible, "Orbit camera stays on the keyboard page")
	assert_false(_glyphs(orbit).is_empty(), "it shows its right mouse binding")
	orbit.rebind_button().pressed.emit()
	assert_true(orbit.is_listening(), "and is rebindable")
	orbit._cancel_listening()
	assert_false(_row(menu, &"rotate_snap").visible, "pad-only rows stay off the keyboard page")
	assert_false(_row(menu, &"rotate_drag_pad").visible)


func test_rebinding_rotate_snap_on_the_pad_persists() -> void:
	if FileAccess.file_exists(_cfg_path):
		DirAccess.remove_absolute(_cfg_path)
	Settings.set_config_path_for_test(_cfg_path)
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
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

	var reloaded: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(reloaded)
	reloaded.set_config_path_for_test(_cfg_path)
	var stored: Array[InputEvent] = reloaded.key_override_events(&"rotate_snap")
	assert_eq(stored.size(), 1, "the override is saved and reloaded")
	assert_eq((stored[0] as InputEventJoypadButton).button_index, JOY_BUTTON_Y)


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
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await wait_frames(3)
	var shown: Array[KeyRebindRow] = []
	for row: KeyRebindRow in menu.rebind_rows():
		if row.is_available_on_active_device():
			shown.append(row)
	assert_gt(shown.size(), 0)
	shown[0].grab_focus()
	assert_true(shown[0].has_focus())
	for i: int in range(1, shown.size()):
		await _pad_press(JOY_BUTTON_DPAD_DOWN)
		assert_true(shown[i].has_focus(), "ui_down reaches %s after %s" % [shown[i].action_name(), shown[i - 1].action_name()])
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
		assert_true(shown[i].has_focus(), "ui_up reaches %s" % shown[i].action_name())
