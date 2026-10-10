extends GutTest
## Bontago-1pi.119 / 1pi.121 / 1pi.123 (playtest 2026-10-08): coarse keyboard/gamepad slider steps
## (ui/SliderNav.gd), menus opening scrolled to the top, and the mouse wheel over a slider scrolling
## the menu instead of changing the slider.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const LOBBY_SCENE: PackedScene = preload("res://ui/Lobby.tscn")
const SETTLE_FRAMES: int = 4
const PAD_DEVICE: int = 0
const SHORT_VIEW_PX: float = 200.0
const FLOAT_EPS: float = 0.0001


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

func test_coarse_step_is_a_twentieth_of_the_range_for_fine_sliders_only() -> void:
	assert_almost_eq(SliderNav.coarse_step(0.0, 1.0, 0.01), 0.05, FLOAT_EPS)
	assert_almost_eq(SliderNav.coarse_step(0.5, 2.0, 0.01), 0.08, FLOAT_EPS, "1.5 / 20 rounded up to a step multiple")
	assert_eq(SliderNav.coarse_step(3.0, 12.0, 0.5), -1.0, "already coarse: 18 native steps")
	assert_eq(SliderNav.coarse_step(0.0, 10.0, 1.0), -1.0, "10 native steps")


func test_gamepad_dpad_and_keyboard_move_a_volume_slider_by_the_configured_step() -> void:
	var menu: OptionsMenu = await _menu()
	var slider: HSlider = menu.get_node("%MasterVolumeSlider") as HSlider
	var coarse: float = SliderNav.coarse_step(slider.min_value, slider.max_value, slider.step)
	assert_gt(coarse, slider.step, "a coarser keyboard/gamepad step is configured")
	slider.set_value_no_signal(0.5)
	slider.grab_focus()
	await _settle()
	Input.parse_input_event(_pad_right(true))
	Input.parse_input_event(_pad_right(false))
	await _settle()
	assert_almost_eq(slider.value, 0.5 + coarse, FLOAT_EPS, "one d-pad press = one coarse step")
	var after_pad: float = slider.value
	Input.parse_input_event(_key(KEY_RIGHT, true))
	Input.parse_input_event(_key(KEY_RIGHT, false))
	await _settle()
	assert_almost_eq(slider.value, after_pad + coarse, FLOAT_EPS, "arrow key = the same step")


func _stick(axis_value: float) -> InputEventJoypadMotion:
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = PAD_DEVICE
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = axis_value
	return motion


## A held stick re-sends motion every frame; it must step once per push, not once per event.
func test_gamepad_stick_motion_steps_a_slider_once_per_push() -> void:
	var menu: OptionsMenu = await _menu()
	var slider: HSlider = menu.get_node("%MoveSpeedSlider") as HSlider
	var coarse: float = SliderNav.coarse_step(slider.min_value, slider.max_value, slider.step)
	slider.set_value_no_signal(1.0)
	slider.gui_input.emit(_stick(1.0))
	slider.gui_input.emit(_stick(1.0))
	slider.gui_input.emit(_stick(0.9))
	assert_almost_eq(slider.value, 1.0 + coarse, FLOAT_EPS, "three motion events of one push = one step")
	slider.gui_input.emit(_stick(0.0))
	slider.gui_input.emit(_stick(-1.0))
	assert_almost_eq(slider.value, 1.0, FLOAT_EPS, "released, then pushed left = one step back")


func test_every_lobby_and_options_slider_is_configured() -> void:
	var menu: OptionsMenu = await _menu()
	for slider_name: String in ["MasterVolumeSlider", "MusicVolumeSlider", "SfxVolumeSlider", "WeatherVolumeSlider", "RumbleStrengthSlider", "MoveSpeedSlider"]:
		var slider: HSlider = menu.get_node("%" + slider_name) as HSlider
		assert_false(slider.scrollable, "%s ignores the wheel" % slider_name)
		assert_gt(SliderNav.coarse_step(slider.min_value, slider.max_value, slider.step), slider.step, "%s steps coarsely" % slider_name)
	var lobby: Lobby = autofree(LOBBY_SCENE.instantiate()) as Lobby
	add_child_autofree(lobby)
	await _settle()
	for slider_name: String in ["DiscSizeSlider", "GravitySlider", "SpecialFreqSlider", "MatchTimerSlider", "RoundTimerSlider"]:
		assert_false((lobby.get_node("%" + slider_name) as HSlider).scrollable, "%s ignores the wheel" % slider_name)


# --- 123 ---------------------------------------------------------------------

## DECISION: headless GUT cannot route a real mouse-wheel event to a hovered Control (neither
## Input.parse_input_event nor Viewport.push_input reaches the GUI without a pointer), so the
## contract is asserted at its cause: a Slider with `scrollable == false` leaves a wheel event
## unaccepted (engine Slider::gui_input), so it propagates to the enclosing ScrollContainer.
func test_mouse_wheel_over_a_slider_leaves_it_and_is_left_for_the_scroll_container() -> void:
	var menu: OptionsMenu = await _menu()
	var slider: HSlider = menu.get_node("%MasterVolumeSlider") as HSlider
	slider.set_value_no_signal(0.5)
	assert_false(slider.scrollable, "the slider is not wheel-scrollable, so the wheel bubbles up")
	slider.gui_input.emit(_wheel_event(MOUSE_BUTTON_WHEEL_UP))
	slider.gui_input.emit(_wheel_event(MOUSE_BUTTON_WHEEL_DOWN))
	await _settle()
	assert_eq(slider.value, 0.5, "the wheel never changes a slider")
	var ancestor: Node = slider.get_parent()
	while ancestor != null and not (ancestor is ScrollContainer):
		ancestor = ancestor.get_parent()
	assert_not_null(ancestor, "the slider sits inside a ScrollContainer that receives the bubbled wheel")


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
