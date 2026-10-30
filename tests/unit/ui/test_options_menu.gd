extends GutTest
## ui/menus/OptionsMenu.gd (graphics preset picker,
## master volume slider, temporarily disabled custom music folder, one KeyRebindRow per
## rebindable Input Map action) and ui/menus/KeyRebindRow.gd (one row's own
## listen/capture state machine).
##
## Preset/volume/music-dir assertions swap OptionsMenu.settings_provider for
## a fresh Settings instance after add_child() (ui/menus/OptionsMenu.gd's own
## settings_provider doc comment); under GUT every Settings reads and writes
## the per-run file, never the player's, and the tests never touch the real
## Settings autoload or the real InputMap.
##
## The KeyRebindRow capture tests are the one exception: ui/menus/KeyRebindRow.gd
## calls Settings.set_key_override() directly against the real autoload (no
## provider seam there -- ui/menus/OptionsMenu.gd's settings_provider doc explains
## why a per-row seam wouldn't solve the actual problem, which is InputMap
## itself being a global singleton with no per-instance state). Those tests
## exercise a synthetic action added to InputMap for the duration of the
## test and clear the key overrides and the per-run settings file in
## after_each -- so they never touch a real rebindable action's binding.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
const KEY_REBIND_ROW_SCENE: PackedScene = preload("res://ui/menus/KeyRebindRow.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")

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
	Settings.reset_key_overrides()
	_delete_if_exists(Settings.effective_path())


## _make_menu() deletes the per-run settings file first: Settings persists
## every setter immediately, so a leftover file would leak one test's values
## into the next test's "defaults" assertions.


func _make_menu() -> OptionsMenu:
	var menu: OptionsMenu = autofree(OPTIONS_MENU_SCENE.instantiate())
	add_child_autofree(menu)
	_delete_if_exists(Settings.effective_path())
	var fresh: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(fresh)
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
	Settings._input(InputEventJoypadButton.new())
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
	var rows: Array[KeyRebindRow] = []
	for node: Node in menu.find_children("*", "KeyRebindRow", true, false):
		rows.append(node as KeyRebindRow)
	assert_eq(rows.size(), OptionsMenu.REBINDABLE_ACTIONS.size())
	var built_actions: Array[StringName] = []
	for row: KeyRebindRow in rows:
		built_actions.append(row._action)
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


## Pad and keyboard reach every control of the open page: the down loop closes, every stop is
## live, and no live focusable control of the page is left off the loop (tab buttons sit above
## the pages and are reached by ui_up, so they are not loop stops).
func test_down_loop_is_closed_and_reaches_every_live_control_on_each_page() -> void:
	var menu: OptionsMenu = _make_menu()
	Settings._input(InputEventJoypadButton.new())
	for tab_name: String in ["%SettingsTabButton", "%GraphicsTabButton", "%ControlsTabButton"]:
		(menu.get_node(tab_name) as Button).button_pressed = true
		await wait_frames(3)
		_assert_page_loop(menu, tab_name)


func _page_stops(menu: OptionsMenu) -> Array[Control]:
	var stops: Array[Control] = []
	for control: Control in FocusWalk.live_focusable(menu):
		if not _is_tab_strip(menu, control):
			stops.append(control)
	return stops


func _is_tab_strip(menu: OptionsMenu, control: Control) -> bool:
	for tabs: Node in menu.find_children("*", "UiTabs", true, false):
		if tabs.is_ancestor_of(control):
			return true
	return false


func _assert_page_loop(menu: OptionsMenu, label: String) -> void:
	var live: Array[Control] = _page_stops(menu)
	assert_gt(live.size(), 0, "%s: expected live focusable controls" % label)
	if live.is_empty():
		return
	var start: Control = menu.get_node("%BackButton") as Control
	var stops: Array[Control] = FocusWalk.loop(start)
	assert_true(FocusWalk.is_closed(stops, start), "%s: ui_down loop closes" % label)
	for stop: Control in stops:
		assert_true(FocusWalk.is_live(stop), "%s: %s is a live stop" % [label, stop.name])
	for control: Control in live:
		assert_true(stops.has(control), "%s: %s is reachable by ui_down" % [label, control.name])


## The real ui_down path (what a D-pad sends) lands where the engine resolves the neighbour.
func test_real_dpad_down_lands_on_the_resolved_neighbour() -> void:
	var menu: OptionsMenu = _make_menu()
	await wait_frames(2)
	var start: Control = menu.get_node("%BackButton") as Control
	start.grab_focus()
	var expected: Control = start.find_valid_focus_neighbor(SIDE_BOTTOM)
	assert_not_null(expected)
	var down: InputEventJoypadButton = InputEventJoypadButton.new()
	down.button_index = JOY_BUTTON_DPAD_DOWN
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up: InputEventJoypadButton = InputEventJoypadButton.new()
	up.button_index = JOY_BUTTON_DPAD_DOWN
	Input.parse_input_event(up)
	await get_tree().process_frame
	assert_eq(get_viewport().gui_get_focus_owner(), expected, "D-pad down moves to the resolved neighbour")


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


func test_capturing_a_keyboard_event_calls_set_key_override_and_exits_listening() -> void:
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
