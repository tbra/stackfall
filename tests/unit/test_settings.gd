extends GutTest
## autoload/Settings.gd + config/GraphicsPreset.gd: user settings persisted to
## a single user://settings.cfg ConfigFile (docs/M6_PLAN.md package C1). Uses
## a fresh Settings instance pointed at a temp cfg path
## (set_config_path_for_test) rather than the real "Settings" autoload
## singleton, mirroring autoload/Sfx.gd's own set_root_dir_for_test()
## test-seam precedent (Sfx.gd:159).

const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")

var _settings: Node
var _cfg_path: String
var _test_action: StringName = &"settings_test_action"


func before_each() -> void:
	_cfg_path = OS.get_user_data_dir().path_join("test_settings_tmp.cfg")
	_delete_if_exists(_cfg_path)
	if not InputMap.has_action(_test_action):
		InputMap.add_action(_test_action)

	_settings = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(_settings)
	_settings.set_config_path_for_test(_cfg_path)


func after_each() -> void:
	_delete_if_exists(_cfg_path)
	if InputMap.has_action(_test_action):
		InputMap.erase_action(_test_action)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fresh_settings_at_same_path() -> Node:
	var other: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(other)
	other.set_config_path_for_test(_cfg_path)
	return other


func test_defaults_with_no_saved_file() -> void:
	var preset: GraphicsPreset = _settings.current_graphics_preset()
	assert_not_null(preset, "medium preset resource should load by default")
	assert_eq(preset.id, &"medium")
	assert_eq(_settings.master_volume_db(), 0.0)
	assert_eq(_settings.master_volume_percent(), 1.0)
	assert_false(_settings.master_muted())
	assert_eq(_settings.music_volume_percent(), 1.0)
	assert_false(_settings.music_muted())
	assert_eq(_settings.sfx_volume_percent(), 1.0)
	assert_false(_settings.sfx_muted())
	assert_eq(_settings.mouse_move_speed_scale(), 1.0)
	assert_eq(_settings.stick_move_speed_scale(), 1.0)
	assert_eq(_settings.custom_music_dir(), "")
	assert_eq(_settings.key_override_events(_test_action).size(), 0)
	assert_true(_settings.camera_shake_enabled(), "Bontago-xtq.29: camera shake defaults on")
	assert_eq(_settings.window_mode(), &"borderless_fullscreen", "Bontago-xtq.45: borderless fullscreen is the default window mode")


func test_graphics_preset_round_trips_and_persists() -> void:
	_settings.set_graphics_preset(&"high")
	assert_eq(_settings.current_graphics_preset().id, &"high")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.current_graphics_preset().id, &"high")


func test_audio_settings_round_trip_and_persist() -> void:
	_settings.set_master_volume_percent(0.5)
	_settings.set_custom_music_dir("C:/music")
	assert_almost_eq(_settings.master_volume_percent(), 0.5, 0.0001)
	assert_eq(_settings.custom_music_dir(), "C:/music")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.master_volume_percent(), 0.5, 0.0001)
	assert_eq(reloaded.custom_music_dir(), "C:/music")


## Bontago (options package): Master/Music/SFX each have their own percent +
## mute flag, all persisted independently.
func test_music_and_sfx_volume_and_mute_round_trip_and_persist() -> void:
	_settings.set_music_volume_percent(0.25)
	_settings.set_sfx_volume_percent(0.75)
	_settings.set_music_muted(true)
	_settings.set_sfx_muted(true)

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.music_volume_percent(), 0.25, 0.0001)
	assert_almost_eq(reloaded.sfx_volume_percent(), 0.75, 0.0001)
	assert_true(reloaded.music_muted())
	assert_true(reloaded.sfx_muted())


## SILENT_VOLUME_DB while muted or at 0%, linear_to_db() of the stored percent
## otherwise -- master multiplies every channel, so master_volume_db() and
## sfx_volume_db()/music_volume_db() must each reflect only their own slider.
func test_channel_volume_db_reflects_percent_and_mute() -> void:
	_settings.set_master_volume_percent(1.0)
	assert_almost_eq(_settings.master_volume_db(), 0.0, 0.01)

	_settings.set_sfx_volume_percent(0.0)
	assert_eq(_settings.sfx_volume_db(), Settings.SILENT_VOLUME_DB)

	_settings.set_music_volume_percent(0.5)
	_settings.set_music_muted(true)
	assert_eq(_settings.music_volume_db(), Settings.SILENT_VOLUME_DB, "a muted channel must be silent regardless of its stored percent")


## Owner: "restoring the previous level on unmute" -- toggling mute back off
## must reveal whatever percent the slider was already at.
func test_toggling_mute_off_restores_the_previous_percent() -> void:
	_settings.set_sfx_volume_percent(0.6)
	_settings.set_sfx_muted(true)
	assert_eq(_settings.sfx_volume_db(), Settings.SILENT_VOLUME_DB)
	assert_almost_eq(_settings.sfx_volume_percent(), 0.6, 0.0001, "the stored percent must be untouched while muted")

	_settings.set_sfx_muted(false)
	assert_almost_eq(_settings.sfx_volume_percent(), 0.6, 0.0001)
	assert_almost_eq(_settings.sfx_volume_db(), linear_to_db(0.6), 0.01)


## Owner: dragging a channel's slider above 0% while muted implies the player
## wants to hear it again.
func test_setting_a_positive_percent_unmutes_the_channel() -> void:
	_settings.set_master_muted(true)
	assert_true(_settings.master_muted())

	_settings.set_master_volume_percent(0.4)
	assert_false(_settings.master_muted())


func test_reset_audio_settings_restores_every_channel_to_full_unmuted() -> void:
	_settings.set_master_volume_percent(0.2)
	_settings.set_music_volume_percent(0.3)
	_settings.set_sfx_volume_percent(0.4)
	_settings.set_master_muted(true)
	_settings.set_music_muted(true)
	_settings.set_sfx_muted(true)

	_settings.reset_audio_settings()

	assert_eq(_settings.master_volume_percent(), 1.0)
	assert_eq(_settings.music_volume_percent(), 1.0)
	assert_eq(_settings.sfx_volume_percent(), 1.0)
	assert_false(_settings.master_muted())
	assert_false(_settings.music_muted())
	assert_false(_settings.sfx_muted())


## Bontago (options package): a pre-existing settings.cfg with only the old
## dB-based master_db key (no new percent key yet) must migrate sensibly
## rather than default back to 100%.
func test_master_volume_migrates_from_legacy_db_key() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "master_db", -6.0206)  # ~50% linear
	cfg.save(_cfg_path)

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.master_volume_percent(), 0.5, 0.01)


func test_mouse_and_stick_move_speed_scale_round_trip_and_persist() -> void:
	_settings.set_mouse_move_speed_scale(1.5)
	_settings.set_stick_move_speed_scale(0.75)

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.mouse_move_speed_scale(), 1.5, 0.0001)
	assert_almost_eq(reloaded.stick_move_speed_scale(), 0.75, 0.0001)


func test_stored_old_stick_scale_migrates_to_the_same_effective_speed() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("controls", "stick_move_speed_scale", 1.2)  # old save, no basis key
	cfg.save(_settings.effective_path())

	var reloaded: Node = _fresh_settings_at_same_path()
	# Old 120% of base 30 == new 100% of base 36.
	assert_almost_eq(reloaded.stick_move_speed_scale(), 1.0, 0.0001)
	var ghost: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	assert_almost_eq(ghost.gamepad_cursor_base_speed * reloaded.stick_move_speed_scale(), 30.0 * 1.2, 0.001)


func test_migrated_stick_scale_is_clamped_and_not_migrated_twice() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("controls", "stick_move_speed_scale", 0.55)
	cfg.save(_settings.effective_path())
	var once: Node = _fresh_settings_at_same_path()
	assert_almost_eq(once.stick_move_speed_scale(), 0.5, 0.0001, "clamped to the slider minimum")
	once.set_stick_move_speed_scale(1.5)  # saves with the basis marker
	var twice: Node = _fresh_settings_at_same_path()
	assert_almost_eq(twice.stick_move_speed_scale(), 1.5, 0.0001, "a current save must not migrate again")


func test_default_stick_cursor_base_speed_is_old_value_times_1_2() -> void:
	var ghost: GhostTuning = load("res://config/ghost_tuning.tres") as GhostTuning
	assert_almost_eq(ghost.gamepad_cursor_base_speed, 30.0 * 1.2, 0.0001)
	assert_eq(_settings.stick_move_speed_scale(), 1.0)


func test_reset_move_speed_scales_restores_defaults() -> void:
	_settings.set_mouse_move_speed_scale(1.8)
	_settings.set_stick_move_speed_scale(0.6)

	_settings.reset_move_speed_scales()

	assert_eq(_settings.mouse_move_speed_scale(), 1.0)
	assert_eq(_settings.stick_move_speed_scale(), 1.0)


func test_camera_shake_enabled_round_trips_and_persists() -> void:
	_settings.set_camera_shake_enabled(false)
	assert_false(_settings.camera_shake_enabled())

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_false(reloaded.camera_shake_enabled())


func test_camera_shake_setting_changed_signal_emits_on_toggle() -> void:
	watch_signals(_settings)
	_settings.set_camera_shake_enabled(false)
	assert_signal_emitted(_settings, "camera_shake_setting_changed")


func test_graphics_preset_changed_signal_emits_the_new_preset() -> void:
	watch_signals(_settings)
	_settings.set_graphics_preset(&"low")
	assert_signal_emitted(_settings, "graphics_preset_changed")


func test_audio_settings_changed_signal_emits_on_volume_change() -> void:
	watch_signals(_settings)
	_settings.set_master_volume_percent(0.3)
	assert_signal_emitted(_settings, "audio_settings_changed")


func test_unknown_graphics_preset_id_is_ignored() -> void:
	_settings.set_graphics_preset(&"low")
	_settings.set_graphics_preset(&"not_a_real_preset")
	assert_eq(_settings.current_graphics_preset().id, &"low", "an unknown id must not overwrite the current preset")


## Bontago-xtq.26 (M7 P1): volumetric_fog_enabled is the owner's M7
## art-direction decision (Bontago-5h7 Q6) -- Low drops the cloud-deck
## FogVolume P3 adds to the field; Medium/High keep it.
func test_graphics_presets_set_volumetric_fog_enabled_per_tier() -> void:
	_settings.set_graphics_preset(&"high")
	assert_true(_settings.current_graphics_preset().volumetric_fog_enabled, "high keeps volumetric fog")
	_settings.set_graphics_preset(&"medium")
	assert_true(_settings.current_graphics_preset().volumetric_fog_enabled, "medium keeps volumetric fog")
	_settings.set_graphics_preset(&"low")
	assert_false(_settings.current_graphics_preset().volumetric_fog_enabled, "low drops the cloud-deck FogVolume")


## Bontago-xtq.45 (M7 P4): the three window-mode ids round-trip through
## ConfigFile the same way the graphics preset id does above.
func test_window_mode_round_trips_and_persists() -> void:
	_settings.set_window_mode(&"windowed")
	assert_eq(_settings.window_mode(), &"windowed")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.window_mode(), &"windowed")


func test_window_mode_changed_signal_emits_on_change() -> void:
	watch_signals(_settings)
	_settings.set_window_mode(&"fullscreen")
	assert_signal_emitted(_settings, "window_mode_changed")


func test_unknown_window_mode_id_is_ignored() -> void:
	_settings.set_window_mode(&"fullscreen")
	_settings.set_window_mode(&"not_a_real_window_mode")
	assert_eq(_settings.window_mode(), &"fullscreen", "an unknown id must not overwrite the current window mode")


## A window-mode id that made it onto disk despite not being one of
## WINDOW_MODE_IDS (corrupted/handwritten settings.cfg, or a mode retired in a
## later version) must not be trusted back into _window_mode_id either --
## _load() falls back to DEFAULT_WINDOW_MODE_ID exactly like the "unknown id"
## setter guard above.
func test_unknown_window_mode_id_on_disk_falls_back_to_default() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "window_mode", "not_a_real_window_mode")
	cfg.save(_cfg_path)

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.window_mode(), &"borderless_fullscreen")


func test_window_mode_ids_constant_covers_every_mode() -> void:
	var ids: Array[StringName] = SETTINGS_SCRIPT.WINDOW_MODE_IDS
	assert_eq(ids.size(), 3)
	assert_true(ids.has(&"fullscreen"))
	assert_true(ids.has(&"borderless_fullscreen"))
	assert_true(ids.has(&"windowed"))
	for id: StringName in ids:
		assert_ne(_settings.window_mode_label(id), "", "every window mode id should have a display label")


## The GUT runner is always headless (CLAUDE.md's own headless unit test
## command), so apply_window_mode()'s DisplayServer.get_name() == "headless"
## guard must make every call here a pure no-op -- no DisplayServer call to
## assert against directly, but window_mode() itself (and, implicitly, the
## absence of a crash/hang reaching into a nonexistent window) must be
## unaffected by calling it.
func test_apply_window_mode_is_a_no_op_under_headless() -> void:
	_settings.set_window_mode(&"windowed")
	assert_eq(DisplayServer.get_name(), "headless", "this test only proves the guard under a headless run")
	_settings.apply_window_mode()
	assert_eq(_settings.window_mode(), &"windowed", "apply_window_mode() must not change window_mode() itself")


func test_set_key_override_updates_input_map_immediately() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F9

	_settings.set_key_override(_test_action, event)

	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq((events[0] as InputEventKey).keycode, KEY_F9)


func test_key_override_events_reads_back_the_override() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F10

	_settings.set_key_override(_test_action, event)

	var overrides: Array[InputEvent] = _settings.key_override_events(_test_action)
	assert_eq(overrides.size(), 1)
	assert_eq((overrides[0] as InputEventKey).keycode, KEY_F10)


func test_key_override_persists_and_reapplies_on_fresh_settings() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F11
	_settings.set_key_override(_test_action, event)

	# Simulate a restart: erase the runtime InputMap override, then load a
	# fresh Settings pointed at the same file -- it must re-apply the
	# persisted override itself, the same way _ready() would on a real launch.
	InputMap.action_erase_events(_test_action)

	var reloaded: Node = _fresh_settings_at_same_path()
	var reapplied: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(reapplied.size(), 1, "a fresh Settings instance must re-apply the persisted override")
	assert_eq((reapplied[0] as InputEventKey).keycode, KEY_F11)
	assert_eq(reloaded.key_override_events(_test_action).size(), 1)


## F2 regression: a keyboard override must not erase the action's gamepad
## default (and vice versa) -- overrides are device-class aware. Also
## verifies a keyboard override and a joypad override for the same action
## coexist through a ConfigFile persist + reload cycle (docs/M6_PLAN.md C1
## review finding F1).
func test_key_override_keeps_other_device_class_and_round_trips_both() -> void:
	var key_default: InputEventKey = InputEventKey.new()
	key_default.keycode = KEY_F1
	InputMap.action_add_event(_test_action, key_default)
	var joy_default: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_default.button_index = JOY_BUTTON_A
	InputMap.action_add_event(_test_action, joy_default)

	var key_override: InputEventKey = InputEventKey.new()
	key_override.keycode = KEY_F9
	_settings.set_key_override(_test_action, key_override)

	var after_key_override: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(after_key_override.size(), 2, "a keyboard override must not erase the joypad default")
	assert_true(_events_contain_joy(after_key_override, JOY_BUTTON_A), "joypad default should remain bound")
	assert_true(_events_contain_key(after_key_override, KEY_F9), "new keyboard override should be bound")

	var joy_override: InputEventJoypadButton = InputEventJoypadButton.new()
	joy_override.button_index = JOY_BUTTON_X
	_settings.set_key_override(_test_action, joy_override)

	# Simulate a restart: erase the runtime InputMap state, restore the
	# bootstrap defaults, then load a fresh Settings pointed at the same
	# file -- both persisted overrides must reapply.
	InputMap.action_erase_events(_test_action)
	InputMap.action_add_event(_test_action, key_default)
	InputMap.action_add_event(_test_action, joy_default)

	var reloaded: Node = _fresh_settings_at_same_path()
	var overrides: Array[InputEvent] = reloaded.key_override_events(_test_action)
	assert_eq(overrides.size(), 2, "both a keyboard and a joypad override should persist through ConfigFile")

	var reapplied: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(reapplied.size(), 2)
	assert_true(_events_contain_key(reapplied, KEY_F9), "keyboard override should reapply on a fresh Settings instance")
	assert_true(_events_contain_joy(reapplied, JOY_BUTTON_X), "joypad override should reapply on a fresh Settings instance")


## Bontago-1pi.10 polish pass (owner: "Add one 'Reset to defaults' action in
## the footer"): uses a real project action (ghost_place) rather than
## _test_action -- InputMap.load_from_project_settings() reloads strictly
## from project.godot's own [input] section, so a synthetic action added at
## runtime (never in project.godot) would just vanish from the InputMap
## entirely, not "reset to its default", which isn't what this is testing.
func test_reset_key_overrides_clears_overrides_and_restores_project_defaults() -> void:
	var real_action: StringName = &"ghost_place"
	var original_count: int = InputMap.action_get_events(real_action).size()

	var override_event: InputEventKey = InputEventKey.new()
	override_event.keycode = KEY_F9
	_settings.set_key_override(real_action, override_event)
	assert_eq(_settings.key_override_events(real_action).size(), 1, "sanity: an override exists before reset")

	_settings.reset_key_overrides()

	assert_eq(_settings.key_override_events(real_action).size(), 0, "reset must clear the persisted override")
	assert_eq(InputMap.action_get_events(real_action).size(), original_count, "reset must restore the action's original project.godot bindings")


func _events_contain_key(events: Array[InputEvent], keycode: Key) -> bool:
	for event: InputEvent in events:
		if event is InputEventKey and (event as InputEventKey).keycode == keycode:
			return true
	return false


func _events_contain_joy(events: Array[InputEvent], button_index: JoyButton) -> bool:
	for event: InputEvent in events:
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false


## Bontago-1pi.20: in a GUT run, restoring the "default" (real) path then saving
## must never touch the owner's user://settings.cfg.
func test_gut_run_never_touches_real_settings_file() -> void:
	var real: String = Settings.REAL_CONFIG_PATH
	var existed: bool = FileAccess.file_exists(real)
	var mtime: int = FileAccess.get_modified_time(real) if existed else 0
	var content: String = FileAccess.get_file_as_string(real) if existed else ""
	var other: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(other)
	other.set_config_path_for_test(real)
	assert_ne(other.effective_path(), real, "real path maps to the per-PID GUT path")
	other.set_master_volume_percent(0.5)
	assert_eq(FileAccess.file_exists(real), existed, "real file existence unchanged")
	if existed:
		assert_eq(FileAccess.get_modified_time(real), mtime, "mtime unchanged")
		assert_eq(FileAccess.get_file_as_string(real), content, "content unchanged")
	assert_true(FileAccess.file_exists(other.effective_path()), "saved to the GUT file instead")
	DirAccess.remove_absolute(other.effective_path())


func test_weather_volume_and_mute_persist_independently() -> void:
	assert_eq(_settings.weather_volume_percent(), 1.0)
	_settings.set_weather_volume_percent(0.4)
	_settings.set_weather_muted(true)
	assert_eq(_settings.sfx_volume_percent(), 1.0, "SFX untouched")
	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.weather_volume_percent(), 0.4, 0.0001)
	assert_true(reloaded.weather_muted())
	assert_eq(reloaded.weather_volume_db(), Settings.SILENT_VOLUME_DB)
