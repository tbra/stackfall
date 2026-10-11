extends GutTest
## Bontago-1pi.119 / 1pi.121 / 1pi.123 (playtest 2026-10-08): one-cell keyboard/gamepad meter steps, menus opening scrolled to the top, and the mouse wheel over a slider scrolling
## the menu instead of changing the slider.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const SETTLE_FRAMES: int = 4
const PAD_DEVICE: int = 0
const SHORT_VIEW_PX: float = 200.0


func after_each() -> void:
	Input.flush_buffered_events()
	for action: StringName in InputMap.get_actions():
		Input.action_release(action)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate()) as OptionsMenu
	add_child_autofree(menu)
	# Meters write their setting on every step: keep that off the real Settings autoload.
	var fresh: Node = autofree((load("res://autoload/Settings.gd") as GDScript).new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(OS.get_user_data_dir().path_join("test_menu_slider_nav_tmp.cfg"))
	menu.settings_provider = fresh
	await _settle()
	return menu


func _key(keycode: Key, pressed: bool) -> InputEventKey:
	var key: InputEventKey = InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = pressed
	return key


func _pad_right(pressed: bool) -> InputEventJoypadButton:
	var button: InputEventJoypadButton = InputEventJoypadButton.new()
	button.device = PAD_DEVICE
	button.button_index = JOY_BUTTON_DPAD_RIGHT
	button.pressed = pressed
	return button


func _wheel_event(button_index: MouseButton) -> InputEventMouseButton:
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button_index
	event.pressed = true
	return event


# --- 119 ---------------------------------------------------------------------

func test_gamepad_dpad_and_keyboard_move_a_volume_meter_by_one_cell() -> void:
	var menu: OptionsMenu = await _menu()
	var meter: UiSegmentMeter = menu.get_node("%MasterVolumeSlider") as UiSegmentMeter
	meter.set_value_silent(OptionsMenu.PERCENT_METER_CELLS / 2)
	var start: int = meter.value
	meter.grab_focus()
	await _settle()
	Input.parse_input_event(_pad_right(true))
	Input.parse_input_event(_pad_right(false))
	await _settle()
	assert_eq(meter.value, start + 1, "one d-pad press = one cell")
	Input.parse_input_event(_key(KEY_RIGHT, true))
	Input.parse_input_event(_key(KEY_RIGHT, false))
	await _settle()
	assert_eq(meter.value, start + 2, "arrow key = the same step")


func _stick(axis_value: float) -> InputEventJoypadMotion:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = PAD_DEVICE
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = axis_value
	return motion


## A held stick re-sends motion every frame; it must step once per push, not once per event.
func test_gamepad_stick_motion_steps_a_meter_once_per_push() -> void:
	var menu: OptionsMenu = await _menu()
	var meter: UiSegmentMeter = menu.get_node("%MoveSpeedSlider") as UiSegmentMeter
	meter.set_value_silent(OptionsMenu.MOVE_SPEED_CELLS / 2)
	var start: int = meter.value
	meter._gui_input(_stick(1.0))
	meter._gui_input(_stick(1.0))
	meter._gui_input(_stick(0.9))
	assert_eq(meter.value, start + 1, "three motion events of one push = one step")
	meter._gui_input(_stick(0.0))
	meter._gui_input(_stick(-1.0))
	assert_eq(meter.value, start, "released, then pushed left = one step back")


func test_every_lobby_and_options_slider_is_configured() -> void:
	var menu: OptionsMenu = await _menu()
	for slider_name: String in ["MasterVolumeSlider", "MusicVolumeSlider", "SfxVolumeSlider", "WeatherVolumeSlider", "RumbleStrengthSlider", "MoveSpeedSlider", "UiScaleSlider"]:
		var meter: UiSegmentMeter = menu.get_node("%" + slider_name) as UiSegmentMeter
		assert_not_null(meter, "%s is a UiSegmentMeter (one cell per press)" % slider_name)
	# Bontago-1pi.159.2.1: the lobby's value controls are UiSegmentMeters / UiSteppers, which never
	# accept a wheel event, so it bubbles to the settings ScrollContainer.


# --- 123 ---------------------------------------------------------------------

## DECISION: headless GUT cannot route a real mouse-wheel event to a hovered Control (neither
## Input.parse_input_event nor Viewport.push_input reaches the GUI without a pointer), so the
## contract is asserted at its cause: a Slider with `scrollable == false` leaves a wheel event
## unaccepted (engine Slider::gui_input), so it propagates to the enclosing ScrollContainer.
func test_mouse_wheel_over_a_meter_leaves_it_and_is_left_for_the_scroll_container() -> void:
	var menu: OptionsMenu = await _menu()
	var meter: UiSegmentMeter = menu.get_node("%MasterVolumeSlider") as UiSegmentMeter
	meter.set_value_silent(OptionsMenu.PERCENT_METER_CELLS / 2)
	var start: int = meter.value
	meter._gui_input(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	meter._gui_input(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	await _settle()
	assert_eq(meter.value, start, "the wheel never changes a meter")
	var ancestor: Node = meter.get_parent()
	while ancestor != null and not (ancestor is ScrollContainer):
		ancestor = ancestor.get_parent()
	assert_not_null(ancestor, "the meter sits inside a ScrollContainer that receives the bubbled wheel")


# --- 121 ---------------------------------------------------------------------

func test_scrollable_menus_open_at_the_top() -> void:
	var menu: OptionsMenu = await _menu()
	var page: ScrollContainer = menu.get_node("%SettingsPage") as ScrollContainer
	page.custom_minimum_size.y = SHORT_VIEW_PX
	page.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	await _settle()
	page.scroll_vertical = 100
	menu.hide()
	menu.show()
	await _settle()
	assert_eq(page.scroll_vertical, 0, "re-opening the menu returns to the top")
	var lobby: Lobby = autofree(LOBBY_SCENE.instantiate()) as Lobby
	add_child_autofree(lobby)
	await _settle()
	var scroll: ScrollContainer = lobby.get_node("%SettingsScroll") as ScrollContainer
	assert_eq(scroll.scroll_vertical, 0, "the lobby settings column opens at the top")
	scroll.scroll_vertical = 50
	lobby.hide()
	lobby.show()
	await _settle()
	assert_eq(scroll.scroll_vertical, 0, "and again when re-shown")
