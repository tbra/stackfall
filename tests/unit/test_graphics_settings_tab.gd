extends GutTest
## Bontago-1pi.11.86: Options "Graphics" tab -- presets set every control, editing a control
## switches the picker to Custom, overrides persist, and every control is gamepad-reachable.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/OptionsMenu.tscn")
const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")
const PAD_DEVICE: int = 0

var _cfg_path: String = ""
var _settings: Node = null
var _menu: OptionsMenu = null


func before_each() -> void:
	_cfg_path = OS.get_user_data_dir().path_join("test_graphics_tab_tmp.cfg")
	_delete_if_exists(_cfg_path)
	_settings = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(_settings)
	_settings.set_config_path_for_test(_cfg_path)
	_menu = autofree(OPTIONS_MENU_SCENE.instantiate()) as OptionsMenu
	add_child_autofree(_menu)
	_menu.settings_provider = _settings


func after_each() -> void:
	_delete_if_exists(_cfg_path)
	Settings.set_config_path_for_test(Settings.default_config_path())
	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _tab() -> GraphicsSettingsTab:
	return _menu.get_node("%GraphicsPage") as GraphicsSettingsTab


func _fresh_at_same_path() -> Node:
	var other: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(other)
	other.set_config_path_for_test(_cfg_path)
	return other


func test_graphics_tab_exists_and_shows_when_its_tab_is_pressed() -> void:
	assert_false(_tab().visible)
	(_menu.get_node("%GraphicsTabButton") as Button).button_pressed = true
	assert_true(_tab().visible)
	assert_false((_menu.get_node("%SettingsPage") as Control).visible)


func test_picking_a_preset_sets_every_control() -> void:
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"low"))
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	assert_false(_settings.graphics_preset_is_custom())
	assert_eq((_tab().control_for(&"ssr_enabled") as CheckButton).button_pressed, low.ssr_enabled)
	assert_eq((_tab().control_for(&"msaa_3d") as CycleSelector).selected, 0)
	assert_almost_eq((_tab().control_for(&"render_scale_3d") as HSlider).value, low.render_scale_3d, 0.001)
	assert_almost_eq((_tab().control_for(&"cloud_puff_density") as HSlider).value, low.cloud_puff_density, 0.001)
	assert_eq((_tab().control_for(&"shadow_atlas_size") as CycleSelector).selected, 1, "2K")
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"high"))
	assert_true((_tab().control_for(&"ssr_enabled") as CheckButton).button_pressed)
	assert_eq((_tab().control_for(&"msaa_3d") as CycleSelector).selected, 2)
	assert_eq((_tab().control_for(&"shadow_atlas_size") as CycleSelector).selected, 3, "8K")
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.find(&"high"))


func test_editing_a_control_switches_the_picker_to_custom_and_emits_effective_values() -> void:
	var seen: Array[GraphicsPreset] = []
	_settings.graphics_preset_changed.connect(func(preset: GraphicsPreset) -> void: seen.append(preset))
	(_tab().control_for(&"glow_enabled") as CheckButton).button_pressed = false
	assert_true(_settings.graphics_preset_is_custom())
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size(), "Custom item")
	assert_eq(_tab().preset_option.get_item_text(_tab().preset_option.selected), "Custom")
	assert_false(seen.is_empty())
	assert_false(seen[-1].glow_enabled, "the signal carries the effective preset")
	assert_eq(_settings.graphics_base_preset_id(), &"medium")
	assert_eq(_settings.current_graphics_preset().id, &"medium", "id stays the base so id-keyed consumers keep working")
	# Setting it back to the base value drops the override again.
	(_tab().control_for(&"glow_enabled") as CheckButton).button_pressed = true
	assert_false(_settings.graphics_preset_is_custom())


func test_picking_a_preset_after_edits_resets_to_that_preset() -> void:
	_settings.set_graphics_override(&"ssr_enabled", false)
	_tab().refresh_from_settings()
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"medium"))
	assert_false(_settings.graphics_preset_is_custom())
	assert_true(_settings.current_graphics_preset().ssr_enabled)
	assert_true((_tab().control_for(&"ssr_enabled") as CheckButton).button_pressed)


func test_custom_item_cannot_be_picked() -> void:
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.size())
	assert_false(_settings.graphics_preset_is_custom())
	assert_eq(_settings.graphics_base_preset_id(), &"medium")


func test_slider_and_cycle_edits_land_in_the_effective_preset() -> void:
	(_tab().control_for(&"render_scale_3d") as HSlider).value = 0.7
	(_tab().control_for(&"msaa_3d") as CycleSelector).cycle(false)
	var effective: GraphicsPreset = _settings.current_graphics_preset()
	assert_almost_eq(effective.render_scale_3d, 0.7, 0.001)
	assert_eq(effective.msaa_3d, 2, "medium MSAA 2x -> next is 4x")


func test_overrides_persist_across_restart_and_old_files_load_unchanged() -> void:
	_settings.set_graphics_preset(&"low")
	_settings.set_graphics_override(&"ssr_enabled", true)
	_settings.set_graphics_override(&"frame_cap_mode", GraphicsPreset.FrameCap.FIXED)
	_settings.set_graphics_override(&"fixed_fps", 75)
	_settings.set_graphics_override(&"render_scale_3d", 0.6)
	var reloaded: Node = _fresh_at_same_path()
	assert_true(reloaded.graphics_preset_is_custom())
	assert_eq(reloaded.graphics_base_preset_id(), &"low")
	var effective: GraphicsPreset = reloaded.current_graphics_preset()
	assert_true(effective.ssr_enabled)
	assert_eq(effective.frame_cap_mode, GraphicsPreset.FrameCap.FIXED)
	assert_eq(effective.fixed_fps, 75)
	assert_almost_eq(effective.render_scale_3d, 0.6, 0.001)
	assert_false(effective.glow_enabled, "untouched fields keep the base preset's values")
	# An old file (preset id only, no overrides key) loads unchanged.
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", "high")
	cfg.save(_cfg_path)
	var old: Node = _fresh_at_same_path()
	assert_false(old.graphics_preset_is_custom())
	assert_eq(old.current_graphics_preset().id, &"high")


func test_bad_saved_overrides_are_dropped() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", "medium")
	cfg.set_value("graphics", "overrides", {"id": "evil", "ssr_enabled": "yes", "glow_enabled": false})
	cfg.save(_cfg_path)
	var loaded: Node = _fresh_at_same_path()
	assert_eq(loaded.current_graphics_preset().id, &"medium")
	assert_true(loaded.current_graphics_preset().ssr_enabled, "mistyped value dropped")
	assert_false(loaded.current_graphics_preset().glow_enabled, "valid override kept")


func test_fixed_fps_slider_is_editable_only_in_fixed_mode() -> void:
	var slider: HSlider = _tab().control_for(&"fixed_fps") as HSlider
	assert_false(slider.editable)
	(_tab().control_for(&"frame_cap_mode") as CycleSelector).cycle(false)
	assert_eq(_settings.current_graphics_preset().frame_cap_mode, GraphicsPreset.FrameCap.FIXED)
	assert_true(slider.editable)


func test_every_graphics_control_is_in_the_focus_chain() -> void:
	var controls: Array[Control] = _tab().focus_controls()
	assert_gt(controls.size(), 20)
	for control: Control in controls:
		assert_eq(control.focus_mode, Control.FOCUS_ALL, "%s focusable" % control.name)
		assert_ne(control.focus_neighbor_bottom, NodePath(""), "%s has a down neighbor" % control.name)
		assert_ne(control.focus_neighbor_top, NodePath(""), "%s has an up neighbor" % control.name)


func _pad_tap(button: JoyButton) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventJoypadButton = InputEventJoypadButton.new()
		event.device = PAD_DEVICE
		event.button_index = button
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await get_tree().process_frame
	await get_tree().process_frame


func test_gamepad_dpad_down_visits_every_graphics_control() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	(_menu.get_node("%GraphicsTabButton") as Button).button_pressed = true
	await get_tree().process_frame
	var expected: Array[Control] = _tab().focus_controls()
	expected[0].grab_focus()
	var seen: Dictionary[Control, bool] = {}
	for _i: int in range(expected.size()):
		var focus: Control = get_viewport().gui_get_focus_owner()
		if focus == null:
			break
		seen[focus] = true
		await _pad_tap(JOY_BUTTON_DPAD_DOWN)
	for control: Control in expected:
		assert_true(seen.has(control), "d-pad down reaches %s" % control.name)
