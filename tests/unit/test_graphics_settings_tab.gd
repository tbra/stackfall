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
	# The menu built its controls against the autoload; show the test Settings' state.
	_tab().refresh_from_settings()


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


func _dd(id: StringName) -> UiDropdown:
	return _tab().control_for(id) as UiDropdown


func test_picking_a_preset_sets_every_control() -> void:
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"low"))
	var low: GraphicsPreset = load("res://config/graphics_presets/low.tres") as GraphicsPreset
	assert_false(_settings.graphics_preset_is_custom())
	assert_eq((_tab().control_for(&"glow_enabled") as UiToggle).is_on(), low.glow_enabled)
	assert_eq((_tab().control_for(&"volumetric_fog_enabled") as UiToggle).is_on(), low.volumetric_fog_enabled)
	assert_eq((_tab().control_for(&"block_outline_enabled") as UiToggle).is_on(), low.block_outline_enabled)
	assert_eq(_dd(&"msaa_3d").selected, 0)
	assert_eq(_dd(&"shadows").selected, 0, "Low shadows")
	assert_eq(_dd(&"reflections").selected, 0, "Low preset = Off reflections")
	assert_eq(_dd(&"environment_detail").selected, 0)
	assert_eq(_dd(&"render_scale_3d_mode").selected, 1, "FSR 1.0")
	var meter: UiSegmentMeter = _tab().control_for(&"render_scale_3d") as UiSegmentMeter
	assert_eq(meter.display_text(), "75%")
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"high"))
	assert_true((_tab().control_for(&"glow_enabled") as UiToggle).is_on())
	assert_eq(_dd(&"msaa_3d").selected, 2)
	assert_eq(_dd(&"shadows").selected, 2, "High shadows")
	assert_eq(_dd(&"reflections").selected, 2)
	assert_eq(_dd(&"environment_detail").selected, 2)
	assert_eq(meter.display_text(), "100%")
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.find(&"high"))


func test_the_tab_is_trimmed_to_the_common_set() -> void:
	var controls: Array[Control] = _tab().focus_controls()
	assert_lte(controls.size(), 12, "preset + 10 rows + the fixed-fps meter")
	for control: Control in controls:
		assert_false(control is OptionButton or control is HSlider or control is CheckButton or control is CycleSelector)


func test_combined_rows_write_every_field_of_their_tier_and_mark_custom() -> void:
	_dd(&"shadows").pick(2)
	var effective: GraphicsPreset = _settings.current_graphics_preset()
	var high: GraphicsPreset = load("res://config/graphics_presets/high.tres") as GraphicsPreset
	assert_eq(effective.shadow_atlas_size, high.shadow_atlas_size)
	assert_eq(effective.sun_shadow_mode, high.sun_shadow_mode)
	assert_true(_settings.graphics_preset_is_custom(), "a combined row change marks the preset Custom")
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size())
	assert_eq(_dd(&"shadows").selected, 2)
	_dd(&"reflections").pick(0)
	assert_eq(_settings.current_graphics_preset().reflection_probe_mode, GraphicsPreset.ReflectionProbeMode.OFF)
	assert_false(_settings.current_graphics_preset().ssr_enabled)
	_dd(&"environment_detail").pick(0)
	assert_false(_settings.current_graphics_preset().aurora_enabled)
	assert_almost_eq(_settings.current_graphics_preset().cloud_puff_density, 0.2, 0.001)


func test_combined_row_shows_custom_when_no_tier_matches() -> void:
	_settings.set_graphics_override(&"sun_shadow_max_distance", 140.0)
	_tab().refresh_from_settings()
	assert_eq(_dd(&"shadows").selected, 3, "Custom item")
	assert_eq(_dd(&"shadows").get_item_text(3), "Custom")
	assert_true(_dd(&"shadows").is_item_disabled(3))
	_dd(&"shadows").cycle(false)
	assert_eq(_dd(&"shadows").selected, 0, "cycling skips the disabled Custom item")


func test_old_saved_per_field_overrides_load_and_show_in_the_combined_rows() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", "medium")
	cfg.set_value("graphics", "overrides", {"aurora_enabled": false, "ssr_enabled": false, "shadow_atlas_size": 8192})
	cfg.save(_cfg_path)
	_menu.settings_provider = _fresh_at_same_path()
	_tab().refresh_from_settings()
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size())
	assert_eq(_dd(&"environment_detail").selected, 3, "custom: aurora off, density still medium")
	assert_eq(_dd(&"reflections").selected, 1, "interval probe, no SSR")
	assert_eq(_dd(&"shadows").selected, 3, "8K atlas with medium cascades matches no tier")


func test_editing_a_control_switches_the_picker_to_custom_and_emits_effective_values() -> void:
	var seen: Array[GraphicsPreset] = []
	_settings.graphics_preset_changed.connect(func(preset: GraphicsPreset) -> void: seen.append(preset))
	(_tab().control_for(&"glow_enabled") as UiToggle).set_on(false)
	assert_true(_settings.graphics_preset_is_custom())
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size(), "Custom item")
	assert_eq(_tab().preset_option.get_item_text(_tab().preset_option.selected), "Custom")
	assert_false(seen.is_empty())
	assert_false(seen[-1].glow_enabled, "the signal carries the effective preset")
	assert_eq(_settings.graphics_base_preset_id(), &"medium")
	assert_eq(_settings.current_graphics_preset().id, &"medium", "id stays the base so id-keyed consumers keep working")
	# Setting it back to the base value drops the override again.
	(_tab().control_for(&"glow_enabled") as UiToggle).set_on(true)
	assert_false(_settings.graphics_preset_is_custom())


func test_picking_a_preset_after_edits_resets_to_that_preset() -> void:
	_settings.set_graphics_override(&"ssr_enabled", false)
	_tab().refresh_from_settings()
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"medium"))
	assert_false(_settings.graphics_preset_is_custom())
	assert_true(_settings.current_graphics_preset().ssr_enabled)
	assert_eq(_dd(&"reflections").selected, 2, "SSR back on")


func test_custom_item_cannot_be_picked() -> void:
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.size())
	assert_false(_settings.graphics_preset_is_custom())
	assert_eq(_settings.graphics_base_preset_id(), &"medium")


func test_meter_and_dropdown_edits_land_in_the_effective_preset() -> void:
	(_tab().control_for(&"render_scale_3d") as UiSegmentMeter).value = 4
	_dd(&"msaa_3d").cycle(false)
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


func test_fixed_fps_meter_is_editable_only_in_fixed_mode() -> void:
	var meter: UiSegmentMeter = _tab().control_for(&"fixed_fps") as UiSegmentMeter
	assert_false(meter.editable)
	_dd(&"frame_cap_mode").cycle(false)
	assert_eq(_settings.current_graphics_preset().frame_cap_mode, GraphicsPreset.FrameCap.FIXED)
	assert_true(meter.editable)
	meter.value = 5
	assert_eq(_settings.current_graphics_preset().fixed_fps, 80, "30 + 5 cells of 10")


func test_every_graphics_control_is_in_the_focus_chain() -> void:
	var controls: Array[Control] = _tab().focus_controls()
	assert_gt(controls.size(), 10)
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


func test_out_of_range_and_bogus_saved_overrides_are_clamped_or_dropped() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "preset", "medium")
	cfg.set_value("graphics", "overrides", {
		"fixed_fps": 100000, "render_scale_3d": 0.01, "sun_shadow_max_distance": -5.0,
		"shadow_atlas_size": 3000, "msaa_3d": 99, "frame_cap_mode": 7, "reflection_probe_mode": -1,
		"cloud_puff_density": 9.0,
	})
	cfg.save(_cfg_path)
	var loaded: Node = _fresh_at_same_path()
	var effective: GraphicsPreset = loaded.current_graphics_preset()
	var medium: GraphicsPreset = load("res://config/graphics_presets/medium.tres") as GraphicsPreset
	assert_eq(effective.fixed_fps, int(GraphicsPreset.FIXED_FPS["max"]), "clamped to the tab's max")
	assert_almost_eq(effective.render_scale_3d, float(GraphicsPreset.RENDER_SCALE_3D["min"]), 0.0001)
	assert_almost_eq(effective.sun_shadow_max_distance, float(GraphicsPreset.SUN_SHADOW_MAX_DISTANCE["min"]), 0.0001)
	assert_almost_eq(effective.cloud_puff_density, 1.0, 0.0001)
	assert_eq(effective.shadow_atlas_size, medium.shadow_atlas_size, "bogus enum dropped")
	assert_eq(effective.msaa_3d, medium.msaa_3d)
	assert_eq(effective.frame_cap_mode, medium.frame_cap_mode)
	assert_eq(effective.reflection_probe_mode, medium.reflection_probe_mode)
	# The same table guards live edits.
	loaded.set_graphics_override(&"msaa_3d", 42)
	assert_eq(loaded.current_graphics_preset().msaa_3d, medium.msaa_3d)


func _pad_accept() -> void:
	await _pad_tap(JOY_BUTTON_A)


func test_gamepad_accept_cycles_a_dropdown_and_flips_a_toggle() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	(_menu.get_node("%GraphicsTabButton") as Button).button_pressed = true
	await get_tree().process_frame
	var msaa: UiDropdown = _dd(&"msaa_3d")
	msaa.grab_focus()
	await _pad_accept()
	assert_eq(_settings.current_graphics_preset().msaa_3d, 2, "A cycled MSAA 2x -> 4x")
	var glow: UiToggle = _tab().control_for(&"glow_enabled") as UiToggle
	glow.grab_focus()
	await _pad_accept()
	assert_false(_settings.current_graphics_preset().glow_enabled, "A flipped Bloom off")
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size())


func test_mouse_click_cycles_a_dropdown_and_flips_a_toggle() -> void:
	(_menu.get_node("%GraphicsTabButton") as Button).button_pressed = true
	await get_tree().process_frame
	_dd(&"environment_detail").pressed.emit()
	assert_eq(_dd(&"environment_detail").selected, 2, "Medium -> High")
	(_tab().control_for(&"volumetric_fog_enabled") as UiToggle).set_on(false)
	assert_false(_settings.current_graphics_preset().volumetric_fog_enabled)

