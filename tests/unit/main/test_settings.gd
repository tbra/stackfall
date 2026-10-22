extends GutTest
## autoload/Settings.gd + config/graphics/GraphicsPreset.gd: user settings persisted to
## a single user://settings.cfg ConfigFile. Uses fresh Settings instances; under
## GUT every instance reads and writes the per-PID file (Settings.effective_path()),
## so the file is deleted before each test and instances share it by design.

const SETTINGS_SCRIPT: GDScript = preload("res://autoload/Settings.gd")

var _settings: Node
var _test_action: StringName = &"settings_test_action"


func before_each() -> void:
	_delete_if_exists(Settings.effective_path())
	if not InputMap.has_action(_test_action):
		InputMap.add_action(_test_action)

	_settings = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(_settings)


func after_each() -> void:
	_delete_if_exists(Settings.effective_path())
	# review: the published UI scale is static; never leak it into later tests.
	UiScaleTuning.current_scale = -1.0
	if InputMap.has_action(_test_action):
		InputMap.erase_action(_test_action)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _fresh_settings_at_same_path() -> Node:
	var other: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(other)
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
	assert_eq(_settings._key_overrides.get(_test_action, []).size(), 0)
	assert_true(_settings.camera_shake_enabled(), "camera shake defaults on")
	assert_eq(_settings.window_mode(), &"borderless_fullscreen", "borderless fullscreen is the default window mode")


func test_audio_settings_round_trip_and_persist() -> void:
	_settings.set_master_volume_percent(0.5)
	assert_almost_eq(_settings.master_volume_percent(), 0.5, 0.0001)

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.master_volume_percent(), 0.5, 0.0001)


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


## A settings.cfg written by an older build (keys that no longer exist) still
## loads: the unknown keys are ignored and the current ones are read.
func test_old_settings_file_with_removed_keys_still_loads() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("audio", "master_db", -6.0206)
	cfg.set_value("audio", "custom_music_dir", "old/music")
	cfg.set_value("audio", "music_volume_percent", 0.25)
	cfg.save(Settings.effective_path())

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.music_volume_percent(), 0.25, 0.0001)
	assert_almost_eq(reloaded.master_volume_percent(), 1.0, 0.0001)


func test_stored_old_stick_scale_migrates_to_the_same_effective_speed() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("controls", "stick_move_speed_scale", 1.2)  # old save, no basis key
	cfg.save(_settings.effective_path())

	var reloaded: Node = _fresh_settings_at_same_path()
	# Old 120% of base 30 == new 100% of base 36.
	assert_almost_eq(reloaded.stick_move_speed_scale(), 1.0, 0.0001)
	var ghost: GhostTuning = load("res://config/blocks/tuning/ghost_tuning.tres") as GhostTuning
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


## M7 P4: the three window-mode ids round-trip through
## ConfigFile the same way the graphics preset id does above.
func test_window_mode_round_trips_and_persists() -> void:
	_settings.set_window_mode(&"windowed")
	assert_eq(_settings.window_mode(), &"windowed")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.window_mode(), &"windowed")


## A window-mode id that made it onto disk despite not being one of
## WINDOW_MODE_IDS (corrupted/handwritten settings.cfg, or a mode retired in a
## later version) must not be trusted back into _window_mode_id either --
## _load() falls back to DEFAULT_WINDOW_MODE_ID exactly like the "unknown id"
## setter guard above.
func test_unknown_window_mode_id_on_disk_falls_back_to_default() -> void:
	var cfg: ConfigFile = ConfigFile.new()
	cfg.set_value("graphics", "window_mode", "not_a_real_window_mode")
	cfg.save(Settings.effective_path())

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.window_mode(), &"borderless_fullscreen")


func test_set_key_override_updates_input_map_immediately() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_F9

	_settings.set_key_override(_test_action, event)

	var events: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(events.size(), 1)
	assert_true(events[0] is InputEventKey)
	assert_eq((events[0] as InputEventKey).keycode, KEY_F9)


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
	assert_eq(reloaded._key_overrides.get(_test_action, []).size(), 1)


## F2 regression: a keyboard override must not erase the action's gamepad
## default (and vice versa) -- overrides are device-class aware. Also
## verifies a keyboard override and a joypad override for the same action
## coexist through a ConfigFile persist + reload cycle.
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
	var overrides: Array = reloaded._key_overrides.get(_test_action, [])
	assert_eq(overrides.size(), 2, "both a keyboard and a joypad override should persist through ConfigFile")

	var reapplied: Array[InputEvent] = InputMap.action_get_events(_test_action)
	assert_eq(reapplied.size(), 2)
	assert_true(_events_contain_key(reapplied, KEY_F9), "keyboard override should reapply on a fresh Settings instance")
	assert_true(_events_contain_joy(reapplied, JOY_BUTTON_X), "joypad override should reapply on a fresh Settings instance")


## polish pass ("Add one 'Reset to defaults' action in
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
	assert_eq(_settings._key_overrides.get(real_action, []).size(), 1, "sanity: an override exists before reset")

	_settings.reset_key_overrides()

	assert_eq(_settings._key_overrides.get(real_action, []).size(), 0, "reset must clear the persisted override")
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


## in a GUT run, a default instance saving must never touch the user's
## user://settings.cfg.
func test_gut_run_never_touches_real_settings_file() -> void:
	var real: String = Settings.REAL_CONFIG_PATH
	var existed: bool = FileAccess.file_exists(real)
	var mtime: int = FileAccess.get_modified_time(real) if existed else 0
	var content: String = FileAccess.get_file_as_string(real) if existed else ""
	var other: Node = autofree(SETTINGS_SCRIPT.new())
	add_child_autofree(other)
	assert_ne(other.effective_path(), real, "a default instance uses the per-PID GUT path")
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

