extends GutTest
## ui/menus/OptionsMenu.gd (graphics preset picker,
## master volume slider, temporarily disabled custom music folder, one KeyRebindRow per
## rebindable Input Map action) and ui/menus/KeyRebindRow.gd (one row's own
## listen/capture state machine).
##
## Preset/volume/music-dir assertions swap OptionsMenu.settings_provider for
## a fresh Settings instance pointed at a temp cfg path after add_child()
## (ui/menus/OptionsMenu.gd's own settings_provider doc comment; mirrors
## test_settings.gd's own set_config_path_for_test() seam), so they never
## touch the real Settings autoload or the real InputMap.
##
## The KeyRebindRow capture tests are the one exception: ui/menus/KeyRebindRow.gd
## calls Settings.set_key_override() directly against the real autoload (no
## provider seam there -- ui/menus/OptionsMenu.gd's settings_provider doc explains
## why a per-row seam wouldn't solve the actual problem, which is InputMap
## itself being a global singleton with no per-instance state). Those tests
## redirect the real Settings autoload's own config path to a temp file
## (Settings.set_config_path_for_test(), the same seam test_settings.gd
## uses) and exercise a synthetic action added to InputMap for the duration
## of the test, restoring both in after_each -- so they never touch a real
## rebindable action's binding or the real settings.cfg.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/menus/KeyRebindRow.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
var DEFAULT_SETTINGS_CFG_PATH: String = Settings.default_config_path()

var _test_action: StringName = &"options_menu_test_action"


func before_each() -> void:
	if not InputMap.has_action(_test_action):
		InputMap.add_action(_test_action)


## Unconditional even for tests that never touch the real Settings autoload:
## cheap self-healing reload from the real user://settings.cfg is safer than
## trusting every test body to restore it, and other files in the same batch
## (test_main_menu, test_settings) never read the real Settings singleton.
func after_each() -> void:
	# review: the published UI scale is static; never leak it into later tests.
	UiScaleTuning.current_scale = -1.0
	if InputMap.has_action(_test_action):
		InputMap.erase_action(_test_action)
	Settings.set_config_path_for_test(DEFAULT_SETTINGS_CFG_PATH)
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


## A fresh temp cfg path per call (not one shared filename) -- _make_menu()
## runs once per test in this file, and Settings._save() persists every
## setter immediately, so a shared path would leak one test's preset/volume
## into the next test's "defaults" assertions.
var _menu_cfg_counter: int = 0


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	_menu_cfg_counter += 1
	var cfg_path: String = OS.get_user_data_dir().path_join("test_options_menu_tmp_%d.cfg" % _menu_cfg_counter)
	_delete_if_exists(cfg_path)
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
	fresh.set_config_path_for_test(cfg_path)
	menu.settings_provider = fresh
	return menu


func _settings_of(menu: OptionsMenu) -> Node:
	return menu.settings_provider as Node


func _make_row() -> KeyRebindRow:
	var row: KeyRebindRow = autofree(KEY_REBIND_ROW_SCENE.instantiate())
	add_child_autofree(row)
	row.setup(_test_action)
	return row


# --- Graphics preset ----------------------------------------------------------

func test_fov_slider_shows_the_tuning_default_and_persists_a_change() -> void:
	var menu: OptionsMenu = await _make_menu()
	var meter: UiSegmentMeter = menu.get_node("%FovSlider") as UiSegmentMeter
	var lens: CameraTuning = CameraTuning.new()
	assert_almost_eq(menu._meter_value(meter, meter.value), lens.fov_deg, 4.0, "an unset FOV shows the CameraTuning default")
	meter.value_changed.emit(meter.step_count)
	assert_almost_eq(_settings_of(menu).fov_override_deg(), lens.fov_max_deg, 0.01, "the top cell stores the max FOV")
	menu._on_reset_pressed()
	assert_eq(_settings_of(menu).fov_override_deg(), 0.0, "Reset clears the FOV override")


func test_master_mute_button_toggles_mute_and_round_trips() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%MasterMuteButton") as UiIconButton).pressed.emit()
	assert_true(_settings_of(menu).master_muted())
	assert_eq(_mute_icon(menu, "%MasterMuteButton"), OptionsMenu.SPEAKER_MUTED_ICON)

	(menu.get_node("%MasterMuteButton") as UiIconButton).pressed.emit()
	assert_false(_settings_of(menu).master_muted())


## The mute block is a UiIconButton: its icon is the Button's own `icon`.
func _mute_icon(menu: OptionsMenu, unique_name: String) -> Texture2D:
	return (menu.get_node(unique_name) as UiIconButton).icon


func test_rumble_toggle_calls_set_rumble_enabled() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_rumble_enabled_toggled(false)
	assert_false(_settings_of(menu).rumble_enabled())
	menu._on_rumble_enabled_toggled(true)
	assert_true(_settings_of(menu).rumble_enabled())


func test_ui_scale_meter_drag_applies_on_release_only() -> void:
	var menu: OptionsMenu = _make_menu()
	var meter: UiSegmentMeter = menu.get_node("%UiScaleSlider") as UiSegmentMeter
	var tuning: UiScaleTuning = UiScaleTuning.shared()
	var target_cells: int = roundi((0.9 - tuning.min_scale) / tuning.step)
	meter.gui_input.emit(_left_click(true))
	meter.value = target_cells
	assert_eq(_settings_of(menu).ui_scale(), tuning.default_scale, "no rescale mid-drag")
	assert_eq(meter.display_text(), "90%")
	meter.gui_input.emit(_left_click(false))
	assert_almost_eq(_settings_of(menu).ui_scale(), 0.9, 0.0001)
	UiScaleTuning.current_scale = -1.0


func _left_click(pressed: bool) -> InputEventMouseButton:
	var click: InputEventMouseButton = InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	return click


func test_move_speed_row_switches_to_stick_speed_on_gamepad_and_calls_stick_setter() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_eq((menu.get_node("%MoveSpeedLabel") as Label).text, "Stick speed")

	menu._on_move_speed_changed(0.7)
	assert_almost_eq(_settings_of(menu).stick_move_speed_scale(), 0.7, 0.0001)
	assert_eq(_settings_of(menu).mouse_move_speed_scale(), 1.0, "the mouse scale must be untouched")


## An explicit allow-list must exclude every
## debug-only action tools/bootstrap_project.gd's own _actions() defines --
## scans the real InputMap (already populated by project.godot's committed
## [input] section) rather than a hand-copied list, so a newly added debug
## hotkey can never silently slip through this test too.
func test_rebindable_actions_exclude_every_debug_only_action() -> void:
	var debug_prefixes: PackedStringArray = ["screenshot_", "net_debug_", "tuning_panel_", "sandbox_"]
	var found_any_debug_action: bool = false
	for action: StringName in InputMap.get_actions():
		var name: String = String(action)
		for prefix: String in debug_prefixes:
			if name.begins_with(prefix):
				found_any_debug_action = true
				assert_false(OptionsMenu.REBINDABLE_ACTIONS.has(action), "%s is debug-only and must not be player-rebindable" % name)
	assert_true(found_any_debug_action, "expected at least one debug-only action bound by tools/bootstrap_project.gd")


## "many of them not mapped to anything": a
## row shown on the keyboard+mouse rebind screen must have a real
## keyboard/mouse binding to rebind. tests/unit/main/test_project_setup.gd's own
## DEVICE_EXCEPTIONS already names every action that is deliberately
## desktop-absent (exception value "mouse" there means "no keyboard/mouse
## event, gamepad only") -- this test asserts none of those ever sneak back
## into REBINDABLE_ACTIONS, and independently scans the live InputMap so a
## newly added gamepad-only action would fail here even if nobody remembers
## to touch this file. The reverse asymmetry (a real K+M binding, no gamepad
## one -- rotate_drag, lock_vertical, camera_mode, camera_orbit) is fine and
## deliberately not checked here: that row is still usable for a K+M player.
func test_every_rebindable_action_has_a_keyboard_or_mouse_binding() -> void:
	var found_any: bool = false
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		if not InputMap.has_action(action):
			continue  # Reported by test_project_setup.gd's test_every_required_action_exists.
		if KeyRebindRow.PAD_ONLY_ACTIONS.has(action):
			continue  # pad-only rows (B / RT) are listed on the gamepad page only.
		found_any = true
		var has_desktop: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				has_desktop = true
				break
		assert_true(has_desktop, "%s is listed as rebindable but has no keyboard/mouse binding for a K+M player to see or use" % action)
	assert_true(found_any, "expected at least one real rebindable action to check")


## polish pass: rows now build in ui/menus/OptionsMenu.gd's own
## SECTIONS grouping order ("Keep action order sensible"), not
## REBINDABLE_ACTIONS' own flat declaration order -- this only checks the
## built row set matches REBINDABLE_ACTIONS, not their relative order.
func test_options_menu_builds_one_row_per_rebindable_action() -> void:
	var menu: OptionsMenu = _make_menu()
	var rows: Array[KeyRebindRow] = menu._rows
	assert_eq(rows.size(), OptionsMenu.REBINDABLE_ACTIONS.size())
	var built_actions: Array[StringName] = []
	for row: KeyRebindRow in rows:
		built_actions.append(row.action_name())
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		assert_true(built_actions.has(action), "%s must have a built row" % action)


## Audio/rumble/move-speed rows are "reset by the Reset button" too.
func test_reset_button_also_resets_audio_rumble_and_move_speed() -> void:
	var menu: OptionsMenu = _make_menu()
	var fresh: Node = _settings_of(menu)
	fresh.set_master_volume_percent(0.2)
	fresh.set_sfx_muted(true)
	fresh.set_rumble_enabled(false)
	fresh.set_rumble_strength(0.1)
	fresh.set_mouse_move_speed_scale(1.9)
	fresh.set_stick_move_speed_scale(0.6)

	(menu.get_node("%ResetButton") as Button).pressed.emit()

	assert_eq(fresh.master_volume_percent(), 1.0)
	assert_false(fresh.sfx_muted())
	assert_true(fresh.rumble_enabled())
	assert_eq(fresh.rumble_strength(), 1.0)
	assert_eq(fresh.mouse_move_speed_scale(), 1.0)
	assert_eq(fresh.stick_move_speed_scale(), 1.0)
	assert_eq((menu.get_node("%MasterVolumeSlider") as UiSegmentMeter).value, OptionsMenu.PERCENT_METER_CELLS, "the UI must reload after a reset, not just the underlying Settings")


# --- Settings/Controls tabs ----------------------------------------

func test_pressing_the_controls_tab_shows_the_controls_page_and_hides_settings() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	assert_true((menu.get_node("%ControlsPage") as Control).visible)
	assert_false((menu.get_node("%SettingsPage") as Control).visible)


func test_focus_chain_is_a_closed_loop_through_every_row() -> void:
	var menu: OptionsMenu = _make_menu()
	var rows: Array[KeyRebindRow] = menu._rows
	assert_gt(rows.size(), 0, "expected at least one rebind row")

	var window_mode_option: Control = menu.get_node("%WindowModeOption") as Control
	var back_button: Control = menu.get_node("%BackButton") as Control
	var back_bottom: Node = back_button.get_node(back_button.focus_neighbor_bottom)
	assert_eq(back_bottom, window_mode_option, "the chain must wrap from BackButton back to WindowModeOption")

	var camera_shake_check: Control = menu.get_node("%CameraShakeCheck") as Control
	assert_ne(camera_shake_check.focus_neighbor_top, NodePath(""), "CameraShakeCheck must have an up neighbor")
	assert_ne(camera_shake_check.focus_neighbor_bottom, NodePath(""), "CameraShakeCheck must have a down neighbor")

	# Orchestrator review correction: the chain now matches the Settings tab's
	# own visual row order top to bottom -- PresetOption -> WindowModeOption ->
	# CameraShakeCheck -> Master/Music/SFX mute+volume -> Rumble toggle+
	# intensity -> MoveSpeedSlider (Controls tab) -> first rebind row.
	# Computed via the same get_path_to() NodePaths the rest of this test
	# already checks (a real gamepad D-pad/stick "move focus down" sends
	# ui_down, which Godot's own Control focus-neighbor resolution consumes
	# via these NodePaths -- there is no separate synthetic-input path to
	# drive here).
	# UiScaleSlider sits between WindowModeOption and CameraShakeCheck.
	var ui_scale_slider: Control = menu.get_node("%UiScaleSlider") as Control
	assert_eq(window_mode_option.get_node(window_mode_option.focus_neighbor_bottom), ui_scale_slider, "WindowModeOption must move focus down to UiScaleSlider")
	# HudScaleSlider and MinimapSizeOption follow the UI scale row.
	var hud_scale_slider: Control = menu.get_node("%HudScaleSlider") as Control
	var minimap_option: Control = menu.get_node("%MinimapSizeOption") as Control
	assert_eq(ui_scale_slider.get_node(ui_scale_slider.focus_neighbor_bottom), hud_scale_slider, "UiScaleSlider must move focus down to HudScaleSlider")
	assert_eq(hud_scale_slider.get_node(hud_scale_slider.focus_neighbor_bottom), minimap_option, "HudScaleSlider must move focus down to MinimapSizeOption")
	assert_eq(minimap_option.get_node(minimap_option.focus_neighbor_bottom), camera_shake_check, "MinimapSizeOption must move focus down to CameraShakeCheck")
	assert_eq(camera_shake_check.get_node(camera_shake_check.focus_neighbor_top), minimap_option, "CameraShakeCheck must move focus up to MinimapSizeOption")

	var master_mute: Control = menu.get_node("%MasterMuteButton") as Control
	var rumble_check: Control = menu.get_node("%RumbleEnabledCheck") as Control
	var rumble_slider: Control = menu.get_node("%RumbleStrengthSlider") as Control
	var move_speed_slider: Control = menu.get_node("%MoveSpeedSlider") as Control
	var adaptive_check: Control = menu.get_node("%AdaptiveQualityCheck") as Control
	assert_eq(camera_shake_check.get_node(camera_shake_check.focus_neighbor_bottom), adaptive_check, "CameraShakeCheck must move focus down to AdaptiveQualityCheck")
	var fov_slider: Control = menu.get_node("%FovSlider") as Control
	assert_eq(adaptive_check.get_node(adaptive_check.focus_neighbor_bottom), fov_slider, "AdaptiveQualityCheck must move focus down to FovSlider")
	assert_eq(fov_slider.get_node(fov_slider.focus_neighbor_bottom), master_mute, "FovSlider must move focus down to MasterMuteButton")
	assert_eq(rumble_check.get_node(rumble_check.focus_neighbor_bottom), rumble_slider, "RumbleEnabledCheck must move focus down to RumbleStrengthSlider")
	assert_eq(rumble_slider.get_node(rumble_slider.focus_neighbor_bottom), move_speed_slider, "RumbleStrengthSlider must move focus down to MoveSpeedSlider")
	assert_eq(move_speed_slider.get_node(move_speed_slider.focus_neighbor_bottom), rows[0].rebind_button(), "MoveSpeedSlider must move focus down to the first rebind row")

	for row: KeyRebindRow in rows:
		if not row.is_available_on_active_device():
			continue  # hidden rows (snap while disabled) are not focus stops.
		var button: Control = row.rebind_button()
		assert_ne(button.focus_neighbor_top, NodePath(""), "%s's rebind button must have an up neighbor" % row.action_name())
		assert_ne(button.focus_neighbor_bottom, NodePath(""), "%s's rebind button must have a down neighbor" % row.action_name())


func test_ui_cancel_emits_closed_when_no_row_is_listening() -> void:
	var menu: OptionsMenu = _make_menu()
	watch_signals(menu)
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	menu._unhandled_input(cancel_event)
	assert_signal_emitted(menu, "closed")


# --- Gamepad parity ("gamepad works in some menus but not
# all; B never goes back in any menu") ------------------------------------------
#
# Real InputEventJoypadButton, checked via the event's own is_action_pressed()
# against the real InputMap (not a synthetic InputEventAction) -- proves
# tools/bootstrap_project.gd's ui_accept/ui_cancel gamepad bindings actually
# reach this screen.

func test_gamepad_b_emits_closed_via_real_binding() -> void:
	var menu: OptionsMenu = _make_menu()
	watch_signals(menu)
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.device = -1
	event.button_index = JOY_BUTTON_B
	event.pressed = true
	assert_true(event.is_action_pressed(&"ui_cancel"), "gamepad B should map to ui_cancel")
	menu._unhandled_input(event)
	assert_signal_emitted(menu, "closed")


## Redirects the real Settings autoload's own config path to a temp file for
## the duration of this test (see the file header) so KeyRebindRow's direct
## Settings.set_key_override() call never touches the real settings.cfg.
func test_capturing_a_keyboard_event_calls_set_key_override_and_exits_listening() -> void:
	var cfg_path: String = OS.get_user_data_dir().path_join("test_options_menu_rebind_kbd_tmp.cfg")
	_delete_if_exists(cfg_path)
	Settings.set_config_path_for_test(cfg_path)

	var row: KeyRebindRow = _make_row()
	row.rebind_button().pressed.emit()

	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_F9
	key_event.pressed = true
	row._input(key_event)

	assert_false(row.is_listening())
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq((events[0] as InputEventKey).keycode, KEY_F9)

	_delete_if_exists(cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_shoulder_actions_cycle_options_tabs() -> void:
	var menu: OptionsMenu = _make_menu()
	var next_tab: InputEventAction = InputEventAction.new()
	next_tab.action = "menu_tab_next"
	next_tab.pressed = true
	menu._unhandled_input(next_tab)
	assert_true((menu.get_node("%GraphicsTabButton") as Button).button_pressed)
	assert_true((menu.get_node("%GraphicsTabButton") as Button).has_focus())
	menu._unhandled_input(next_tab)
	assert_true((menu.get_node("%ControlsTabButton") as Button).button_pressed)
	var previous_tab: InputEventAction = InputEventAction.new()
	previous_tab.action = "menu_tab_previous"
	previous_tab.pressed = true
	menu._unhandled_input(previous_tab)
	assert_true((menu.get_node("%GraphicsTabButton") as Button).button_pressed)
	menu._unhandled_input(previous_tab)
	assert_true((menu.get_node("%SettingsTabButton") as Button).button_pressed)


func test_toggles_write_their_settings_and_ui_left_right_set_them() -> void:
	var menu: OptionsMenu = _make_menu()
	var toggle: UiToggle = menu.get_node("%CameraShakeCheck") as UiToggle
	var left: InputEventAction = InputEventAction.new()
	left.action = &"ui_left"
	left.pressed = true
	toggle._gui_input(left)
	assert_false(_settings_of(menu).camera_shake_enabled())
	var right: InputEventAction = InputEventAction.new()
	right.action = &"ui_right"
	right.pressed = true
	toggle._gui_input(right)
	assert_true(_settings_of(menu).camera_shake_enabled())
