extends GutTest
## Bontago-hfa.4 (UI reskin P2): the Stackfall Arcade look of Options, Pause and the rebinding rows
## (docs/UI_RESKIN_PLAN.md P2). Look-only checks: side-tab rim notch, SegmentMeter cells, ON/OFF
## words, BindingRow listening state and a synthetic gamepad focus traversal of both screens, each
## focus owner carrying a visible focus stylebox.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const PAUSE_MENU_SCENE: PackedScene = preload("res://ui/PauseMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const OPTIONS_TUNING: OptionsVisualTuning = preload("res://config/options_visual_tuning.tres")
const SETTLE_FRAMES: int = 3
const PAD_DEVICE: int = 0
const MIN_SEGMENTS: int = 5
## Bold text on a bright face / on a disc face must clear the design system's documented ratios.
const MIN_TEXT_RATIO: float = 4.5
const MIN_LARGE_TEXT_RATIO: float = 3.0
const HALF_FILLED_CELLS: int = 5
const FULL_FILLED_CELLS: int = 10

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


func _has_visible_focus(control: Control) -> bool:
	var box: StyleBox = control.get_theme_stylebox("focus")
	return box != null and not (box is StyleBoxEmpty)


# --- Options: tabs, meters, toggles -------------------------------------------

func test_active_tab_has_a_rim_notch_and_the_idle_tab_has_none() -> void:
	var menu: OptionsMenu = _make_options()
	await _settle()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var tab: Button = menu.get_node("%SettingsTabButton") as Button
	var active: StyleBoxFlat = tab.get_theme_stylebox("pressed") as StyleBoxFlat
	var idle: StyleBoxFlat = tab.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(active.border_width_left, OPTIONS_TUNING.tab_notch_px)
	assert_eq(active.border_color, arcade.rim_color)
	assert_eq(active.bg_color, arcade.disc_600_color)
	assert_eq(idle.border_width_left, 0)


func test_every_slider_is_a_segment_meter_with_enough_cells() -> void:
	var menu: OptionsMenu = _make_options()
	await _settle()
	assert_gte(OPTIONS_TUNING.segment_count, MIN_SEGMENTS, "never fewer than 5 cells")
	for name: String in ["%MasterVolumeSlider", "%MusicVolumeSlider", "%SfxVolumeSlider", "%WeatherVolumeSlider", "%RumbleStrengthSlider", "%MoveSpeedSlider"]:
		var slider: HSlider = menu.get_node(name) as HSlider
		assert_not_null(slider.get_node_or_null("SegmentMeter"), "%s draws as a SegmentMeter" % name)


func test_filled_cell_count_follows_the_slider_value() -> void:
	var slider: HSlider = autofree(HSlider.new()) as HSlider
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = 0.0
	assert_eq(SegmentMeter.filled_cells(slider, FULL_FILLED_CELLS), 0)
	slider.value = 0.5
	assert_eq(SegmentMeter.filled_cells(slider, FULL_FILLED_CELLS), HALF_FILLED_CELLS)
	slider.value = 1.0
	assert_eq(SegmentMeter.filled_cells(slider, FULL_FILLED_CELLS), FULL_FILLED_CELLS)


func test_toggle_words_read_on_and_off() -> void:
	var menu: OptionsMenu = _make_options()
	await _settle()
	var check: CheckButton = menu.get_node("%AdaptiveQualityCheck") as CheckButton
	var word: Label = check.get_parent().get_node("StateWord") as Label
	check.button_pressed = false
	assert_eq(word.text, OptionsMenu.OFF_WORD)
	check.button_pressed = true
	assert_eq(word.text, OptionsMenu.ON_WORD)
	assert_eq(word.get_theme_color("font_color"), MenuStyleFactory.arcade_tuning().mint_color, "ON is mint")


# --- BindingRow ------------------------------------------------------------------

func test_listening_row_shows_the_rim_prompt_and_a_rim_edge() -> void:
	var menu: OptionsMenu = _make_options()
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await _settle()
	var arcade: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	var row: KeyRebindRow = menu.rebind_rows()[0]
	row.pressed.emit()
	assert_true(row.is_listening())
	var prompt: Label = row.get_node("%GlyphRow").get_node(KeyRebindRow.LISTENING_LABEL_NAME) as Label
	assert_eq(prompt.text, KeyRebindRow.LISTENING_TEXT_KEYBOARD)
	assert_eq(prompt.get_theme_color("font_color"), arcade.rim_color)
	var edge: StyleBoxFlat = row.get_theme_stylebox("normal") as StyleBoxFlat
	assert_eq(edge.border_color, arcade.rim_color)
	var cancel: InputEventAction = InputEventAction.new()
	cancel.action = &"ui_cancel"
	cancel.pressed = true
	row._input(cancel)
	assert_false(row.is_listening())
	assert_true(row.get_theme_stylebox("normal") is StyleBoxEmpty or (row.get_theme_stylebox("normal") as StyleBoxFlat).border_width_left == 0, "the rim edge goes away")


func test_alternate_rows_are_banded() -> void:
	var menu: OptionsMenu = _make_options()
	await _settle()
	var rows: Array[KeyRebindRow] = menu.rebind_rows()
	assert_true(rows[0].get_theme_stylebox("normal") is StyleBoxEmpty, "first row is plain")
	assert_true(rows[1].get_theme_stylebox("normal") is StyleBoxFlat, "second row is banded")


# --- Contrast of the documented pairs --------------------------------------------

func test_pause_and_options_label_pairs_meet_their_documented_ratios() -> void:
	var a: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_gte(MenuStyleFactory.contrast_ratio(a.ink_color, a.flare_color), MIN_TEXT_RATIO, "ink on the primary flare block")
	assert_gte(MenuStyleFactory.contrast_ratio(a.cream_color, a.disc_600_color), MIN_TEXT_RATIO, "cream on secondary blocks and tabs")
	assert_gte(MenuStyleFactory.contrast_ratio(a.rim_color, a.disc_700_color), MIN_TEXT_RATIO, "rim PRESS A KEY prompt on a row")
	assert_gte(MenuStyleFactory.contrast_ratio(a.alert_color, a.disc_600_color), MIN_LARGE_TEXT_RATIO, "flare LEAVE MATCH label on a secondary block")
	assert_gte(MenuStyleFactory.contrast_ratio(a.mint_color, a.disc_800_color), MIN_TEXT_RATIO, "mint ON word on the panel")


# --- Pause dialog ----------------------------------------------------------------

func test_pause_dialog_resume_is_the_only_flare_primary_and_leave_has_a_flare_label() -> void:
	var menu: PauseMenu = autofree(PAUSE_MENU_SCENE.instantiate()) as PauseMenu
	add_child_autofree(menu)
	var a: ArcadeVisualTuning = MenuStyleFactory.arcade_tuning()
	assert_eq((menu.get_node("%ResumeButton") as Button).get_theme_color("font_color"), a.ink_color)
	assert_eq((menu.get_node("%LeaveButton") as Button).get_theme_color("font_color"), a.alert_color)
	assert_eq((menu.get_node("%Panel") as Control).custom_minimum_size.x, float(OPTIONS_TUNING.dialog_width_px))


# --- Gamepad focus traversal ------------------------------------------------------

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
	assert_true(seen.has(menu.get_node("%RumbleEnabledCheck")), "the traversal reaches the rumble toggle")
	assert_true(seen.has(menu.get_node("%BackButton")), "the traversal reaches Back")
	assert_gt(seen.size(), 10, "every settings control is a stop")
