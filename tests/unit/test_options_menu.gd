extends GutTest
## docs/M6_PLAN.md package C2: ui/OptionsMenu.gd (graphics preset picker,
## master volume slider, temporarily disabled custom music folder, one KeyRebindRow per
## rebindable Input Map action) and ui/KeyRebindRow.gd (one row's own
## listen/capture state machine).
##
## Preset/volume/music-dir assertions swap OptionsMenu.settings_provider for
## a fresh Settings instance pointed at a temp cfg path after add_child()
## (ui/OptionsMenu.gd's own settings_provider doc comment; mirrors
## test_settings.gd's own set_config_path_for_test() seam), so they never
## touch the real Settings autoload or the real InputMap.
##
## The KeyRebindRow capture tests are the one exception: ui/KeyRebindRow.gd
## calls Settings.set_key_override() directly against the real autoload (no
## provider seam there -- ui/OptionsMenu.gd's settings_provider doc explains
## why a per-row seam wouldn't solve the actual problem, which is InputMap
## itself being a global singleton with no per-instance state). Those tests
## redirect the real Settings autoload's own config path to a temp file
## (Settings.set_config_path_for_test(), the same seam test_settings.gd
## uses) and exercise a synthetic action added to InputMap for the duration
## of the test, restoring both in after_each -- so they never touch a real
## rebindable action's binding or the real settings.cfg.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/KeyRebindRow.tscn")
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

func test_adaptive_quality_check_defaults_off_and_toggles_the_setting() -> void:
	var menu: OptionsMenu = _make_menu()
	var check: CheckButton = menu.get_node("%AdaptiveQualityCheck") as CheckButton
	assert_false(check.button_pressed, "Adaptive quality defaults to OFF")
	menu._on_adaptive_quality_toggled(true)
	assert_true(_settings_of(menu).adaptive_quality_enabled())


func test_preset_selection_calls_set_graphics_preset_with_matching_id() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_preset_selected(OptionsMenu.PRESET_IDS.find(&"high"))
	assert_eq(_settings_of(menu).current_graphics_preset().id, &"high")


func test_preset_selection_ignores_out_of_range_index() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_preset_selected(-1)
	menu._on_preset_selected(999)
	assert_eq(_settings_of(menu).current_graphics_preset().id, &"medium", "an out-of-range index must not change the preset")


# --- Audio channels (Master/Music/SFX) ----------------------------------------

func test_master_volume_slider_calls_set_master_volume_percent() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_master_volume_changed(0.3)
	assert_almost_eq(_settings_of(menu).master_volume_percent(), 0.3, 0.0001)


func test_music_volume_slider_calls_set_music_volume_percent_only() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_music_volume_changed(0.6)
	assert_almost_eq(_settings_of(menu).music_volume_percent(), 0.6, 0.0001)
	assert_eq(_settings_of(menu).sfx_volume_percent(), 1.0, "the SFX channel must be untouched")


func test_sfx_volume_slider_calls_set_sfx_volume_percent_only() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_sfx_volume_changed(0.6)
	assert_almost_eq(_settings_of(menu).sfx_volume_percent(), 0.6, 0.0001)
	assert_eq(_settings_of(menu).music_volume_percent(), 1.0, "the music channel must be untouched")


func test_master_mute_button_toggles_mute_and_round_trips() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%MasterMuteButton") as Button).pressed.emit()
	assert_true(_settings_of(menu).master_muted())
	assert_eq(_mute_icon(menu, "%MasterMuteButton"), OptionsMenu.SPEAKER_MUTED_ICON)

	(menu.get_node("%MasterMuteButton") as Button).pressed.emit()
	assert_false(_settings_of(menu).master_muted())


## DECISION (ui/OptionsMenu.gd): the icon lives on a child TextureRect
## (see that file's own DECISION on _style_mute_button_icon()), not the
## Button's own `icon` property.
func _mute_icon(menu: OptionsMenu, unique_name: String) -> Texture2D:
	var button: Button = menu.get_node(unique_name) as Button
	return (button.get_node("Icon") as TextureRect).texture


func test_volume_icon_reflects_percent_tier() -> void:
	var menu: OptionsMenu = _make_menu()
	var settings: Node = _settings_of(menu)

	settings.set_sfx_volume_percent(0.1)
	menu._load_current_values()
	assert_eq(_mute_icon(menu, "%SfxMuteButton"), OptionsMenu.SPEAKER_LOW_ICON)

	settings.set_sfx_volume_percent(0.5)
	menu._load_current_values()
	assert_eq(_mute_icon(menu, "%SfxMuteButton"), OptionsMenu.SPEAKER_MID_ICON)

	settings.set_sfx_volume_percent(0.9)
	menu._load_current_values()
	assert_eq(_mute_icon(menu, "%SfxMuteButton"), OptionsMenu.SPEAKER_HIGH_ICON)

	settings.set_sfx_volume_percent(0.0)
	menu._load_current_values()
	assert_eq(_mute_icon(menu, "%SfxMuteButton"), OptionsMenu.SPEAKER_MUTED_ICON)


# --- Rumble ----------------------------------------------------------------------

func test_rumble_toggle_calls_set_rumble_enabled() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_rumble_enabled_toggled(false)
	assert_false(_settings_of(menu).rumble_enabled())
	menu._on_rumble_enabled_toggled(true)
	assert_true(_settings_of(menu).rumble_enabled())


func test_rumble_strength_slider_disabled_when_rumble_is_off() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_rumble_enabled_toggled(false)
	assert_false((menu.get_node("%RumbleStrengthSlider") as HSlider).editable)
	menu._on_rumble_enabled_toggled(true)
	assert_true((menu.get_node("%RumbleStrengthSlider") as HSlider).editable)


func test_rumble_strength_slider_calls_set_rumble_strength() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_rumble_strength_changed(0.4)
	assert_almost_eq(_settings_of(menu).rumble_strength(), 0.4, 0.0001)


# --- Block move speed (Controls tab, device-aware) -----------------------------

func test_move_speed_row_shows_mouse_speed_by_default() -> void:
	var menu: OptionsMenu = _make_menu()
	assert_eq((menu.get_node("%MoveSpeedLabel") as Label).text, "Mouse speed")


func test_move_speed_slider_calls_set_mouse_move_speed_scale_on_keyboard_mouse() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_move_speed_changed(1.4)
	assert_almost_eq(_settings_of(menu).mouse_move_speed_scale(), 1.4, 0.0001)
	assert_eq(_settings_of(menu).stick_move_speed_scale(), 1.0, "the stick scale must be untouched")


func test_move_speed_row_switches_to_stick_speed_on_gamepad_and_calls_stick_setter() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_eq((menu.get_node("%MoveSpeedLabel") as Label).text, "Stick speed")

	menu._on_move_speed_changed(0.7)
	assert_almost_eq(_settings_of(menu).stick_move_speed_scale(), 0.7, 0.0001)
	assert_eq(_settings_of(menu).mouse_move_speed_scale(), 1.0, "the mouse scale must be untouched")


func test_move_speed_slider_keeps_focus_across_a_device_switch() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%MoveSpeedSlider") as Control).grab_focus()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_true((menu.get_node("%MoveSpeedSlider") as Control).has_focus())


# --- Custom music folder ----------------------------------------------------------

func test_custom_music_override_is_hidden_and_disabled() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_music_dir_submitted("C:/my music")
	assert_eq(_settings_of(menu).custom_music_dir(), "")
	assert_false(menu.get_node("%MusicDirEdit").get_parent().visible)


# --- Camera shake (Bontago-xtq.29, M7 P4) ------------------------------------------

func test_camera_shake_check_reflects_the_current_settings_value() -> void:
	var menu: OptionsMenu = _make_menu()
	_settings_of(menu).set_camera_shake_enabled(false)
	menu._load_current_values()
	assert_false((menu.get_node("%CameraShakeCheck") as CheckButton).button_pressed)


func test_toggling_camera_shake_check_calls_set_camera_shake_enabled() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_camera_shake_toggled(false)
	assert_false(_settings_of(menu).camera_shake_enabled())
	menu._on_camera_shake_toggled(true)
	assert_true(_settings_of(menu).camera_shake_enabled())


# --- Window mode (Bontago-xtq.45, M7 P4) ------------------------------------------

func test_window_mode_option_lists_every_id_with_borderless_fullscreen_selected_by_default() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._load_current_values()
	var option: OptionButton = menu.get_node("%WindowModeOption") as OptionButton
	assert_eq(option.item_count, Settings.WINDOW_MODE_IDS.size())
	for i: int in range(Settings.WINDOW_MODE_IDS.size()):
		assert_eq(option.get_item_text(i), Settings.window_mode_label(Settings.WINDOW_MODE_IDS[i]))
	assert_eq(option.selected, Settings.WINDOW_MODE_IDS.find(&"borderless_fullscreen"))


func test_selecting_a_window_mode_calls_set_window_mode_with_matching_id() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_window_mode_selected(Settings.WINDOW_MODE_IDS.find(&"windowed"))
	assert_eq(_settings_of(menu).window_mode(), &"windowed")


func test_window_mode_selection_ignores_out_of_range_index() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_window_mode_selected(-1)
	menu._on_window_mode_selected(999)
	assert_eq(_settings_of(menu).window_mode(), &"borderless_fullscreen", "an out-of-range index must not change the window mode")


# --- Rebindable action allow-list -------------------------------------------------

## docs/M6_PLAN.md package C2: an explicit allow-list must exclude every
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


func test_rebindable_actions_exclude_throw_aim() -> void:
	assert_true(InputMap.has_action(&"throw_aim"), "throw_aim should exist so this exclusion is meaningful")
	assert_false(OptionsMenu.REBINDABLE_ACTIONS.has(&"throw_aim"))


## Bontago-8or.19 (owner playtest: "many of them not mapped to anything"): a
## row shown on the keyboard+mouse rebind screen must have a real
## keyboard/mouse binding to rebind. tests/unit/test_project_setup.gd's own
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
		found_any = true
		var has_desktop: bool = false
		for event: InputEvent in InputMap.action_get_events(action):
			if event is InputEventKey or event is InputEventMouseButton:
				has_desktop = true
				break
		assert_true(has_desktop, "%s is listed as rebindable but has no keyboard/mouse binding for a K+M player to see or use" % action)
	assert_true(found_any, "expected at least one real rebindable action to check")


## Bontago-1pi.10 polish pass: rows now build in ui/OptionsMenu.gd's own
## SECTIONS grouping order (owner: "Keep action order sensible"), not
## REBINDABLE_ACTIONS' own flat declaration order -- this only checks the
## built row set matches REBINDABLE_ACTIONS, not their relative order.
func test_options_menu_builds_one_row_per_rebindable_action() -> void:
	var menu: OptionsMenu = _make_menu()
	var rows: Array[KeyRebindRow] = menu.rebind_rows()
	assert_eq(rows.size(), OptionsMenu.REBINDABLE_ACTIONS.size())
	var built_actions: Array[StringName] = []
	for row: KeyRebindRow in rows:
		built_actions.append(row.action_name())
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		assert_true(built_actions.has(action), "%s must have a built row" % action)


## Guards ui/OptionsMenu.gd's own SECTIONS grouping: every rebindable action
## must appear in exactly one section, so a future action added to
## REBINDABLE_ACTIONS can't silently go missing from the Controls page (or
## end up listed twice) just because nobody updated SECTIONS.
func test_sections_cover_every_rebindable_action_exactly_once() -> void:
	var seen: Dictionary[StringName, int] = {}
	for section: Dictionary in OptionsMenu.SECTIONS:
		for action: StringName in (section.get("actions", []) as Array):
			seen[action] = seen.get(action, 0) + 1
	for action: StringName in OptionsMenu.REBINDABLE_ACTIONS:
		assert_eq(seen.get(action, 0), 1, "%s must appear in exactly one SECTIONS entry" % action)
	assert_eq(seen.size(), OptionsMenu.REBINDABLE_ACTIONS.size(), "SECTIONS must not list any action outside REBINDABLE_ACTIONS")


## Owner: "Friendly action names ... human labels" -- spot-checks a few
## representative rows rather than asserting on the whole DISPLAY_NAMES
## dictionary (which would just be a change-detector copy of it).
func test_rebind_rows_use_friendly_display_names() -> void:
	var menu: OptionsMenu = _make_menu()
	var by_action: Dictionary[StringName, KeyRebindRow] = {}
	for row: KeyRebindRow in menu.rebind_rows():
		by_action[row.action_name()] = row
	assert_eq((by_action[&"ghost_place"].get_node("%ActionLabel") as Label).text, "Place block")
	assert_eq((by_action[&"hover_raise"].get_node("%ActionLabel") as Label).text, "Raise block")
	assert_eq((by_action[&"hover_lower"].get_node("%ActionLabel") as Label).text, "Lower block")
	assert_eq((by_action[&"pause_menu"].get_node("%ActionLabel") as Label).text, "Pause")


# --- Reset to defaults (owner: "Add one 'Reset to defaults' action in the
# footer") --------------------------------------------------------------------

func test_reset_button_calls_reset_key_overrides_on_the_settings_provider() -> void:
	var menu: OptionsMenu = _make_menu()
	var fresh: Node = _settings_of(menu)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F9
	fresh.set_key_override(&"ghost_place", event)
	assert_eq(fresh.key_override_events(&"ghost_place").size(), 1, "sanity: an override exists before reset")

	(menu.get_node("%ResetButton") as Button).pressed.emit()

	assert_eq(fresh.key_override_events(&"ghost_place").size(), 0, "Reset to defaults must clear every persisted override")


## Owner: audio/rumble/move-speed rows are "reset by the Reset button" too.
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
	assert_eq((menu.get_node("%MasterVolumeSlider") as HSlider).value, 1.0, "the UI must reload after a reset, not just the underlying Settings")


# --- Settings/Controls tabs (Bontago-1pi.10) ----------------------------------------

func test_settings_tab_is_selected_by_default() -> void:
	var menu: OptionsMenu = _make_menu()
	assert_true((menu.get_node("%SettingsPage") as Control).visible)
	assert_false((menu.get_node("%ControlsPage") as Control).visible)


func test_pressing_the_controls_tab_shows_the_controls_page_and_hides_settings() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	assert_true((menu.get_node("%ControlsPage") as Control).visible)
	assert_false((menu.get_node("%SettingsPage") as Control).visible)


func test_pressing_the_settings_tab_again_switches_back() -> void:
	var menu: OptionsMenu = _make_menu()
	(menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	(menu.get_node("%SettingsTabButton") as Button).button_pressed = true
	assert_true((menu.get_node("%SettingsPage") as Control).visible)
	assert_false((menu.get_node("%ControlsPage") as Control).visible)


# --- Footer/device hint (owner: "show a device hint in the footer ... matching
# the active device") ----------------------------------------------------------------

func test_footer_hint_and_controls_label_default_to_keyboard_mouse() -> void:
	var menu: OptionsMenu = _make_menu()
	assert_eq((menu.get_node("%FooterHintLabel") as InputPromptFlow).template, OptionsMenu.FOOTER_HINT_KEYBOARD_MOUSE)
	assert_eq((menu.get_node("%ControlsDeviceLabel") as Label).text, OptionsMenu.CONTROLS_LABEL_KEYBOARD_MOUSE)


func test_footer_hint_and_controls_label_switch_live_when_the_active_device_changes() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_eq((menu.get_node("%FooterHintLabel") as InputPromptFlow).template, OptionsMenu.FOOTER_HINT_GAMEPAD)
	assert_eq((menu.get_node("%ControlsDeviceLabel") as Label).text, OptionsMenu.CONTROLS_LABEL_GAMEPAD)

	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	assert_eq((menu.get_node("%FooterHintLabel") as InputPromptFlow).template, OptionsMenu.FOOTER_HINT_KEYBOARD_MOUSE)
	assert_eq((menu.get_node("%ControlsDeviceLabel") as Label).text, OptionsMenu.CONTROLS_LABEL_KEYBOARD_MOUSE)


# --- Focus chain (gamepad/keyboard navigability) -----------------------------------

func test_focus_chain_is_a_closed_loop_through_every_row() -> void:
	var menu: OptionsMenu = _make_menu()
	var rows: Array[KeyRebindRow] = menu.rebind_rows()
	assert_gt(rows.size(), 0, "expected at least one rebind row")

	var preset_option: Control = menu.get_node("%PresetOption") as Control
	var back_button: Control = menu.get_node("%BackButton") as Control
	var back_bottom: Node = back_button.get_node(back_button.focus_neighbor_bottom)
	assert_eq(back_bottom, preset_option, "the chain must wrap from BackButton back to PresetOption")

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
	var window_mode_option: Control = menu.get_node("%WindowModeOption") as Control
	assert_eq(preset_option.get_node(preset_option.focus_neighbor_bottom), window_mode_option, "PresetOption must move focus down to WindowModeOption")
	assert_eq(window_mode_option.get_node(window_mode_option.focus_neighbor_bottom), camera_shake_check, "WindowModeOption must move focus down to CameraShakeCheck")
	assert_eq(camera_shake_check.get_node(camera_shake_check.focus_neighbor_top), window_mode_option, "CameraShakeCheck must move focus up to WindowModeOption")

	var master_mute: Control = menu.get_node("%MasterMuteButton") as Control
	var rumble_check: Control = menu.get_node("%RumbleEnabledCheck") as Control
	var rumble_slider: Control = menu.get_node("%RumbleStrengthSlider") as Control
	var move_speed_slider: Control = menu.get_node("%MoveSpeedSlider") as Control
	var adaptive_check: Control = menu.get_node("%AdaptiveQualityCheck") as Control
	assert_eq(camera_shake_check.get_node(camera_shake_check.focus_neighbor_bottom), adaptive_check, "CameraShakeCheck must move focus down to AdaptiveQualityCheck")
	assert_eq(adaptive_check.get_node(adaptive_check.focus_neighbor_bottom), master_mute, "AdaptiveQualityCheck must move focus down to MasterMuteButton")
	assert_eq(rumble_check.get_node(rumble_check.focus_neighbor_bottom), rumble_slider, "RumbleEnabledCheck must move focus down to RumbleStrengthSlider")
	assert_eq(rumble_slider.get_node(rumble_slider.focus_neighbor_bottom), move_speed_slider, "RumbleStrengthSlider must move focus down to MoveSpeedSlider")
	assert_eq(move_speed_slider.get_node(move_speed_slider.focus_neighbor_bottom), rows[0].rebind_button(), "MoveSpeedSlider must move focus down to the first rebind row")

	for row: KeyRebindRow in rows:
		var button: Control = row.rebind_button()
		assert_ne(button.focus_neighbor_top, NodePath(""), "%s's rebind button must have an up neighbor" % row.action_name())
		assert_ne(button.focus_neighbor_bottom, NodePath(""), "%s's rebind button must have a down neighbor" % row.action_name())


## Bontago-1pi.41: Lock height has no gamepad function, so its row is hidden on
## the gamepad page (ui/KeyRebindRow.gd PAD_NOT_APPLICABLE); the focus chain
## must skip it there and pick it up again on keyboard/mouse.
func test_focus_chain_skips_rows_hidden_on_the_gamepad_page() -> void:
	var menu: OptionsMenu = _make_menu()
	var lock_button: Control = null
	for row: KeyRebindRow in menu.rebind_rows():
		if row.action_name() == &"lock_vertical":
			lock_button = row.rebind_button()
	assert_not_null(lock_button, "lock_vertical must have a row")
	var preset: Control = menu.get_node("%PresetOption") as Control
	var chain_before: Array[Control] = _chain_from(preset)
	assert_true(chain_before.has(lock_button), "keyboard/mouse chain includes Lock height")

	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	assert_false(lock_button.visible, "Lock height row is hidden on the gamepad page")
	var chain_pad: Array[Control] = _chain_from(preset)
	assert_false(chain_pad.has(lock_button), "no focus-chain stop may point at the hidden row")
	assert_eq(chain_pad.size(), chain_before.size() - 1, "only the hidden row drops out of the chain")

	Settings.set_active_input_device_for_test(Settings.DEVICE_KEYBOARD_MOUSE)
	assert_true(lock_button.visible)
	assert_true(_chain_from(preset).has(lock_button), "chain restored on keyboard/mouse")


## Walks focus_neighbor_bottom from `start` until the loop closes; the visited
## controls are the chain's stops.
func _chain_from(start: Control) -> Array[Control]:
	var stops: Array[Control] = []
	var current: Control = start
	for _i: int in range(512):
		if stops.has(current):
			break
		stops.append(current)
		if current.focus_neighbor_bottom == NodePath(""):
			break
		current = current.get_node(current.focus_neighbor_bottom) as Control
	return stops


# --- OptionsMenu: back button / ui_cancel ------------------------------------------

func test_back_button_emits_closed() -> void:
	var menu: OptionsMenu = _make_menu()
	watch_signals(menu)
	(menu.get_node("%BackButton") as Button).pressed.emit()
	assert_signal_emitted(menu, "closed")


func test_ui_cancel_emits_closed_when_no_row_is_listening() -> void:
	var menu: OptionsMenu = _make_menu()
	watch_signals(menu)
	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	menu._unhandled_input(cancel_event)
	assert_signal_emitted(menu, "closed")


# --- Gamepad parity (Bontago-1pi.15.1: "gamepad works in some menus but not
# all; B never goes back in any menu") ------------------------------------------
#
# Real InputEventJoypadButton, checked via the event's own is_action_pressed()
# against the real InputMap (not a synthetic InputEventAction) -- proves
# tools/bootstrap_project.gd's ui_accept/ui_cancel gamepad bindings actually
# reach this screen.

func test_opening_grabs_focus_on_the_preset_option() -> void:
	var menu: OptionsMenu = _make_menu()
	assert_not_null(get_viewport().gui_get_focus_owner(), "OptionsMenu must land focus somewhere as soon as it opens.")
	assert_true((menu.get_node("%PresetOption") as Control).has_focus())


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


func test_gamepad_a_activates_the_focused_back_button() -> void:
	var menu: OptionsMenu = _make_menu()
	watch_signals(menu)
	(menu.get_node("%BackButton") as Button).grab_focus()

	var press: InputEventJoypadButton = InputEventJoypadButton.new()
	press.device = -1
	press.button_index = JOY_BUTTON_A
	press.pressed = true
	Input.parse_input_event(press)
	var release: InputEventJoypadButton = InputEventJoypadButton.new()
	release.device = -1
	release.button_index = JOY_BUTTON_A
	release.pressed = false
	Input.parse_input_event(release)
	await get_tree().process_frame
	await get_tree().process_frame

	assert_signal_emitted(menu, "closed", "gamepad A on the focused Back button must activate it via ui_accept.")


# --- KeyRebindRow: listening state machine -----------------------------------------
## These call row._input(event) directly (ui/KeyRebindRow.gd's own capture
## method, Bontago-8or.19) rather than pushing input through a real Viewport
## -- a fast unit-level check of the capture/cancel branches on their own,
## with no Control/GUI layer involved at all. The GUI-layer regressions this
## bug was actually about (a click over a mouse_filter=STOP panel, Space/
## Enter/arrows/Tab swallowed by a focused Button) need a real Viewport to
## reproduce and are covered by tests/unit/test_key_rebind_row.gd instead.

func test_pressing_rebind_button_enters_listening_state() -> void:
	var row: KeyRebindRow = _make_row()
	row.rebind_button().pressed.emit()
	assert_true(row.is_listening())


func test_ui_cancel_exits_listening_without_capturing() -> void:
	var row: KeyRebindRow = _make_row()
	row.rebind_button().pressed.emit()

	var cancel_event: InputEventAction = InputEventAction.new()
	cancel_event.action = &"ui_cancel"
	cancel_event.pressed = true
	row._input(cancel_event)

	assert_false(row.is_listening())
	assert_eq(InputMap.action_get_events(_test_action).size(), 0, "cancelling must not bind anything")


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


func test_capturing_a_gamepad_event_calls_set_key_override() -> void:
	var cfg_path: String = OS.get_user_data_dir().path_join("test_options_menu_rebind_pad_tmp.cfg")
	_delete_if_exists(cfg_path)
	Settings.set_config_path_for_test(cfg_path)

	var row: KeyRebindRow = _make_row()
	row.rebind_button().pressed.emit()

	var joy_event: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_event.button_index = JOY_BUTTON_A
	joy_event.pressed = true
	row._input(joy_event)

	assert_false(row.is_listening())
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadButton)
	assert_eq((events[0] as InputEventJoypadButton).button_index, JOY_BUTTON_A)

	_delete_if_exists(cfg_path)


# --- KeyRebindRow: device-filtered glyphs (Bontago-1pi.10) --------------------------
## Owner: "default to only showing mouse/keyboard, switch to showing only
## gamepad options on gamepad input and switch back on mouse/keyboard input."
## _test_action starts with no bound events at all (before_each only adds a
## bare action), so each test below binds exactly the events it needs first.

func test_row_shows_a_glyph_per_keyboard_mouse_binding_by_default() -> void:
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F9))
	InputMap.action_add_event(_test_action, _make_joy_event(JOY_BUTTON_A))

	var row: KeyRebindRow = _make_row()
	var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
	assert_eq(glyph_row.get_child_count(), 1, "only the keyboard/mouse binding should show while that device is active")
	assert_true(row.visible)


func test_row_switches_to_the_gamepad_glyph_when_the_active_device_changes() -> void:
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F9))
	InputMap.action_add_event(_test_action, _make_joy_event(JOY_BUTTON_A))

	var row: KeyRebindRow = _make_row()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
	assert_eq(glyph_row.get_child_count(), 1)
	var glyph: InputGlyph = glyph_row.get_child(0) as InputGlyph
	assert_eq(glyph.label_text(), "A")
	assert_true(row.visible)


func test_row_shows_no_glyph_but_stays_visible_when_the_active_device_has_no_binding() -> void:
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F9))
	# No gamepad binding at all for this action.

	var row: KeyRebindRow = _make_row()
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)

	var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
	assert_eq(glyph_row.get_child_count(), 0, "no gamepad glyph exists for this action")
	assert_true(row.visible, "the row itself (and its Rebind button) must stay usable, not disappear")


## Owner: "max two glyphs per row, extra bindings hidden behind '+1'".
func test_row_shows_at_most_two_glyphs_and_an_overflow_badge_for_a_third_binding() -> void:
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F9))
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F10))
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F11))

	var row: KeyRebindRow = _make_row()
	var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
	assert_eq(glyph_row.get_child_count(), KeyRebindRow.MAX_GLYPHS + 1, "two real glyphs plus one overflow badge")
	var overflow: InputGlyph = glyph_row.get_child(KeyRebindRow.MAX_GLYPHS) as InputGlyph
	assert_eq(overflow.label_text(), "+1")


## Owner: "activating it enters 'press a key/button…' state shown in the
## glyph slot" -- clicking the row (its own `pressed` signal, since the row
## IS the Button now) must replace the glyph row with a listening
## placeholder rather than leaving the old bindings showing.
func test_pressing_the_row_shows_a_listening_placeholder_in_the_glyph_slot() -> void:
	InputMap.action_add_event(_test_action, _make_key_event(KEY_F9))
	var row: KeyRebindRow = _make_row()

	row.rebind_button().pressed.emit()

	assert_true(row.is_listening())
	var glyph_row: HBoxContainer = row.get_node("%GlyphRow") as HBoxContainer
	assert_eq(glyph_row.get_child_count(), 1, "exactly one listening placeholder, not the old bindings")


func _make_key_event(keycode: Key) -> InputEventKey:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	return event


func _make_joy_event(button_index: JoyButton) -> InputEventJoypadButton:
	var event: InputEventJoypadButton = InputEventJoypadButton.new()
	event.button_index = button_index
	return event


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func test_shoulder_actions_cycle_options_tabs() -> void:
	var menu: OptionsMenu = _make_menu()
	var next_tab: InputEventAction = InputEventAction.new()
	next_tab.action = "menu_tab_next"
	next_tab.pressed = true
	menu._unhandled_input(next_tab)
	assert_true((menu.get_node("%ControlsTabButton") as Button).button_pressed)
	assert_true((menu.get_node("%ControlsTabButton") as Button).has_focus())
	var previous_tab: InputEventAction = InputEventAction.new()
	previous_tab.action = "menu_tab_previous"
	previous_tab.pressed = true
	menu._unhandled_input(previous_tab)
	assert_true((menu.get_node("%SettingsTabButton") as Button).button_pressed)


func test_shoulder_action_does_not_change_tabs_during_key_capture() -> void:
	var menu: OptionsMenu = _make_menu()
	assert_gt(menu._rows.size(), 0)
	menu._rows[0]._on_pressed()
	var next_tab: InputEventAction = InputEventAction.new()
	next_tab.action = "menu_tab_next"
	next_tab.pressed = true
	menu._unhandled_input(next_tab)
	assert_true((menu.get_node("%SettingsTabButton") as Button).button_pressed)


func test_real_gamepad_shoulders_switch_options_tabs() -> void:
	var menu: OptionsMenu = _make_menu()
	var right: InputEventJoypadButton = InputEventJoypadButton.new()
	right.device = -1
	right.button_index = JOY_BUTTON_RIGHT_SHOULDER
	right.pressed = true
	assert_true(right.is_action_pressed(&"menu_tab_next"))
	menu._unhandled_input(right)
	assert_true((menu.get_node("%ControlsTabButton") as Button).button_pressed)
	var left: InputEventJoypadButton = InputEventJoypadButton.new()
	left.device = -1
	left.button_index = JOY_BUTTON_LEFT_SHOULDER
	left.pressed = true
	assert_true(left.is_action_pressed(&"menu_tab_previous"))
	menu._unhandled_input(left)
	assert_true((menu.get_node("%SettingsTabButton") as Button).button_pressed)
