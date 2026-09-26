extends GutTest
## docs/M6_PLAN.md package C2: ui/OptionsMenu.gd (graphics preset picker,
## master volume slider, custom music folder, one KeyRebindRow per
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
const DEFAULT_SETTINGS_CFG_PATH: String = "user://settings.cfg"

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

func test_preset_selection_calls_set_graphics_preset_with_matching_id() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_preset_selected(OptionsMenu.PRESET_IDS.find(&"high"))
	assert_eq(_settings_of(menu).current_graphics_preset().id, &"high")


func test_preset_selection_ignores_out_of_range_index() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_preset_selected(-1)
	menu._on_preset_selected(999)
	assert_eq(_settings_of(menu).current_graphics_preset().id, &"medium", "an out-of-range index must not change the preset")


# --- Master volume ---------------------------------------------------------------

func test_volume_slider_calls_set_master_volume_db() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_volume_changed(-12.0)
	assert_eq(_settings_of(menu).master_volume_db(), -12.0)


# --- Custom music folder ----------------------------------------------------------

func test_music_dir_submitted_calls_set_custom_music_dir() -> void:
	var menu: OptionsMenu = _make_menu()
	menu._on_music_dir_submitted("C:/my music")
	assert_eq(_settings_of(menu).custom_music_dir(), "C:/my music")


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


func test_options_menu_builds_one_row_per_rebindable_action() -> void:
	var menu: OptionsMenu = _make_menu()
	var rows: Array[KeyRebindRow] = menu.rebind_rows()
	assert_eq(rows.size(), OptionsMenu.REBINDABLE_ACTIONS.size())
	for i: int in range(rows.size()):
		assert_eq(rows[i].action_name(), OptionsMenu.REBINDABLE_ACTIONS[i])


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

	for row: KeyRebindRow in rows:
		var button: Control = row.rebind_button()
		assert_ne(button.focus_neighbor_top, NodePath(""), "%s's rebind button must have an up neighbor" % row.action_name())
		assert_ne(button.focus_neighbor_bottom, NodePath(""), "%s's rebind button must have a down neighbor" % row.action_name())


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


# --- KeyRebindRow: listening state machine -----------------------------------------

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
	row._unhandled_input(cancel_event)

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
	row._unhandled_input(key_event)

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
	row._unhandled_input(joy_event)

	assert_false(row.is_listening())
	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventJoypadButton)
	assert_eq((events[0] as InputEventJoypadButton).button_index, JOY_BUTTON_A)

	_delete_if_exists(cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
