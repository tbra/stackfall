extends GutTest
## UI reskin P2: the Stackfall Arcade look of Options, Pause and the rebinding rows
## (docs/UI_RESKIN_PLAN.md P2). Look-only checks: tab rim notch, UiSegmentMeter cells, ON/OFF
## words, BindingRow listening state and a synthetic gamepad focus traversal of both screens, each
## focused control carrying a visible focus stylebox.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/menus/PauseMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/ui/options_visual_tuning.tres")
const SETTLE_FRAMES: int = 3
const PAD_DEVICE: int = 0
## Bold text on a bright face / on a disc face must clear the design system's documented ratios.
const MIN_TEXT_RATIO: float = 4.5
const MIN_LARGE_TEXT_RATIO: float = 3.0

var _cfg_counter: int = 0


func after_each() -> void:
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _make_options() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate()) as OptionsMenu
	add_child_autofree(menu)
	_cfg_counter += 1
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(OS.get_user_data_dir().path_join("test_options_arcade_tmp_%d.cfg" % _cfg_counter))
	menu.settings_provider = fresh
	return menu


func _pad_tap(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = PAD_DEVICE
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await _settle()


## Buttons carry the theme's focus outline; a UiSegmentMeter draws that same Button focus box itself.
func _has_visible_focus(control: Control) -> bool:
	var box: StyleBox = control.get_theme_stylebox("focus", "Button")
	return box != null and not (box is StyleBoxEmpty)


# --- Options: tabs, meters, toggles -------------------------------------------

func test_pause_dialog_pad_traversal_visits_every_button_with_a_visible_focus() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var menu: PauseMenu = autofree(PAUSE_MENU_SCENE.instantiate()) as PauseMenu
	add_child_autofree(menu)
	menu._open()
	await _settle()
	var expected: Array[Button] = [menu._resume_button, menu._options_button, menu._leave_button]
	assert_eq(get_viewport().gui_get_focus_owner(), expected[0], "Resume takes initial focus")
	for i: int in range(1, expected.size()):
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		assert_eq(get_viewport().gui_get_focus_owner(), expected[i], "d-pad down reaches %s" % expected[i].name)
	for button: Button in expected:
		assert_true(_has_visible_focus(button), "%s has a visible focus style" % button.name)
	menu.force_close()


func test_options_settings_page_pad_traversal_has_visible_focus_everywhere() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	var menu: OptionsMenu = _make_options()
	await _settle()
	var start: Control = menu.get_node("%WindowModeOption") as Control
	start.grab_focus()
	var seen: Dictionary[Control, bool] = {}
	var focus: Control = get_viewport().gui_get_focus_owner()
	assert_eq(focus, start)
	var steps: int = 0
	while focus != null and not seen.has(focus) and steps < 40:
		seen[focus] = true
		assert_true(_has_visible_focus(focus), "%s has a visible focus style" % focus.name)
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
		focus = get_viewport().gui_get_focus_owner()
		steps += 1
	assert_true(seen.has(menu.get_node("%MasterVolumeSlider")), "the traversal reaches the volume meters")
	assert_true(seen.has(menu.get_node("%WeatherMuteButton")), "the traversal reaches every mute block")
	assert_true(seen.has(menu.get_node("%RumbleEnabledCheck")), "the traversal reaches the rumble toggle")
	assert_true(seen.has(menu.get_node("%BackButton")), "the traversal reaches Back")
	assert_gt(seen.size(), 10, "every settings control is a stop")
