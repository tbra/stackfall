extends GutTest
## Bontago-1pi.11.86: Options "Graphics" tab -- presets set every control, editing a control
## switches the picker to Custom, overrides persist, and every control is gamepad-reachable.

const OPTIONS_MENU_SCENE: PackedScene = preload("res://ui/menus/OptionsMenu.tscn")
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


func _dd(id: StringName) -> UiDropdown:
	return _tab().control_for(id) as UiDropdown


func test_picking_a_preset_sets_every_control() -> void:
	_menu._on_preset_selected(GraphicsSettingsTab.PRESET_IDS.find(&"low"))
	var low: GraphicsPreset = load("res://config/graphics/presets/low.tres") as GraphicsPreset
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


func test_combined_rows_write_every_field_of_their_tier_and_mark_custom() -> void:
	_dd(&"shadows").pick(2)
	var effective: GraphicsPreset = _settings.current_graphics_preset()
	var high: GraphicsPreset = load("res://config/graphics/presets/high.tres") as GraphicsPreset
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


func test_fixed_fps_meter_is_editable_only_in_fixed_mode() -> void:
	var meter: UiSegmentMeter = _tab().control_for(&"fixed_fps") as UiSegmentMeter
	assert_false(meter.editable)
	_dd(&"frame_cap_mode").pick(_dd(&"frame_cap_mode").selected + 1)
	assert_eq(_settings.current_graphics_preset().frame_cap_mode, GraphicsPreset.FrameCap.FIXED)
	assert_true(meter.editable)
	meter.value = 5
	assert_eq(_settings.current_graphics_preset().fixed_fps, 80, "30 + 5 cells of 10")


## Bontago-mp0.154
func test_vsync_defaults_on_persists_and_leaves_the_cap_rows_active() -> void:
	for id: StringName in [&"low", &"medium", &"high"]:
		assert_true((load("res://config/graphics/presets/%s.tres" % id) as GraphicsPreset).vsync_enabled)
	var toggle: UiToggle = _tab().control_for(&"vsync_enabled") as UiToggle
	assert_not_null(toggle)
	assert_true(toggle.is_on())
	var meter: UiSegmentMeter = _tab().control_for(&"fixed_fps") as UiSegmentMeter
	_dd(&"frame_cap_mode").pick(GraphicsPreset.FrameCap.FIXED)
	assert_true(meter.editable)
	toggle.set_on(false)
	assert_false(_settings.current_graphics_preset().vsync_enabled)
	assert_true(_settings.graphics_preset_is_custom())
	assert_false(_dd(&"frame_cap_mode").disabled, "cap rows unaffected by vsync")
	assert_true(meter.editable)
	var reloaded: Node = _fresh_at_same_path()
	assert_false(reloaded.current_graphics_preset().vsync_enabled, "round-trips through settings.cfg")


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
	var medium: GraphicsPreset = load("res://config/graphics/presets/medium.tres") as GraphicsPreset
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


func test_gamepad_accept_opens_a_dropdown_list_and_flips_a_toggle() -> void:
	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	(_menu.get_node("%GraphicsTabButton") as Button).button_pressed = true
	await get_tree().process_frame
	var msaa: UiDropdown = _dd(&"msaa_3d")
	msaa.grab_focus()
	await _pad_accept()
	assert_true(msaa.is_open(), "A opens the list (Bontago-1pi.159.14)")
	assert_eq(_settings.current_graphics_preset().msaa_3d, 1, "opening changes nothing")
	msaa.pick(msaa.selected + 1)
	assert_eq(_settings.current_graphics_preset().msaa_3d, 2, "picking the next row sets MSAA 4x")
	var glow: UiToggle = _tab().control_for(&"glow_enabled") as UiToggle
	glow.grab_focus()
	await _pad_accept()
	assert_false(_settings.current_graphics_preset().glow_enabled, "A flipped Bloom off")
	assert_eq(_tab().preset_option.selected, GraphicsSettingsTab.PRESET_IDS.size())
