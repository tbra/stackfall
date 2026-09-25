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
	assert_eq(_settings.custom_music_dir(), "")
	assert_eq(_settings.key_override_events(_test_action).size(), 0)


func test_graphics_preset_round_trips_and_persists() -> void:
	_settings.set_graphics_preset(&"high")
	assert_eq(_settings.current_graphics_preset().id, &"high")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_eq(reloaded.current_graphics_preset().id, &"high")


func test_audio_settings_round_trip_and_persist() -> void:
	_settings.set_master_volume_db(-6.5)
	_settings.set_custom_music_dir("C:/music")
	assert_eq(_settings.master_volume_db(), -6.5)
	assert_eq(_settings.custom_music_dir(), "C:/music")

	var reloaded: Node = _fresh_settings_at_same_path()
	assert_almost_eq(reloaded.master_volume_db(), -6.5, 0.0001)
	assert_eq(reloaded.custom_music_dir(), "C:/music")


func test_graphics_preset_changed_signal_emits_the_new_preset() -> void:
	watch_signals(_settings)
	_settings.set_graphics_preset(&"low")
	assert_signal_emitted(_settings, "graphics_preset_changed")


func test_audio_settings_changed_signal_emits_on_volume_change() -> void:
	watch_signals(_settings)
	_settings.set_master_volume_db(-3.0)
	assert_signal_emitted(_settings, "audio_settings_changed")


func test_unknown_graphics_preset_id_is_ignored() -> void:
	_settings.set_graphics_preset(&"low")
	_settings.set_graphics_preset(&"not_a_real_preset")
	assert_eq(_settings.current_graphics_preset().id, &"low", "an unknown id must not overwrite the current preset")


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
