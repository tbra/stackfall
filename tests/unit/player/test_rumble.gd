extends GutTest
## autoload/Rumble.gd: Events -> Input.start_joy_vibration()/stop_joy_vibration()
## reactions. Real hardware never delivers a synthetic InputEventJoypadButton/
## Motion to a headless test run (this project's own operating notes), so
## every test here drives Rumble.set_last_device_for_test() (the device/family
## tracker) directly, and swaps Rumble.start_vibration_fn/stop_vibration_fn
## for a recording Callable instead of touching the real Input singleton --
## the same Variant/Callable seam idea autoload/Sfx.gd's set_root_dir_for_test()
## uses for a value GUT can't otherwise inject into the real singleton.
##
## Settings is redirected to a temp cfg (Settings.set_config_path_for_test),
## restored in after_each -- the same pattern tests/unit/player/test_camera_shake.gd
## uses for the same real "Settings" autoload dependency.

var _settings_cfg_path: String
var _calls: Array[Dictionary] = []
var _stop_calls: Array[int] = []


func before_each() -> void:
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_rumble_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)
	Settings.set_rumble_enabled(true)
	Settings.set_rumble_strength(1.0)

	_calls = []
	_stop_calls = []
	Rumble.start_vibration_fn = Callable(self, "_record_start")
	Rumble.stop_vibration_fn = Callable(self, "_record_stop")
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, &"")


func after_each() -> void:
	Rumble.start_vibration_fn = Callable(Rumble, "_start_vibration_real")
	Rumble.stop_vibration_fn = Callable(Rumble, "_stop_vibration_real")
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, &"")
	Settings.set_config_path_for_test(Settings.default_config_path())
	_delete_if_exists(_settings_cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _record_start(device: int, weak_magnitude: float, strong_magnitude: float, duration_s: float) -> void:
	_calls.append({
		"device": device,
		"weak": weak_magnitude,
		"strong": strong_magnitude,
		"duration": duration_s,
	})


func _record_stop(device: int) -> void:
	_stop_calls.append(device)


func _use_gamepad(device_id: int = 0) -> void:
	Rumble.set_last_device_for_test(device_id, Settings.DEVICE_GAMEPAD)


func test_block_impact_above_threshold_rumbles_the_last_gamepad() -> void:
	_use_gamepad(2)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 1, "a hard impact should trigger exactly one vibration call.")
	assert_eq(_calls[0]["device"], 2, "must rumble the last device that sent real gamepad input.")
	assert_almost_eq(_calls[0]["weak"], Rumble.config.impact_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.impact_strong_magnitude, 0.001)
	assert_almost_eq(_calls[0]["duration"], Rumble.config.impact_duration_s, 0.001)


func test_block_impact_below_threshold_does_not_rumble() -> void:
	_use_gamepad()

	Events.block_impacted.emit(Rumble.config.impact_speed_threshold * 0.5)

	assert_eq(_calls.size(), 0, "a soft landing below threshold must not rumble.")


func test_disabled_setting_suppresses_every_rumble() -> void:
	_use_gamepad()
	Settings.set_rumble_enabled(false)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "Settings.rumble_enabled() == false must be a total no-op.")


func test_last_device_keyboard_suppresses_rumble() -> void:
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, Settings.DEVICE_KEYBOARD_MOUSE)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "the last real input came from keyboard/mouse, not a gamepad -- no pad to rumble.")


func test_placement_rejected_rumbles_only_the_local_slot() -> void:
	_use_gamepad()

	Events.placement_rejected.emit(0, &"outside_territory")

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.placement_refused_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.placement_refused_strong_magnitude, 0.001)


func test_special_triggered_rumbles_globally_with_no_slot_gate() -> void:
	_use_gamepad()

	Events.special_triggered.emit(7, &"bomb", Vector3.ZERO, 0)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.special_triggered_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.special_triggered_strong_magnitude, 0.001)


func test_player_eliminated_rumbles_only_local_slot() -> void:
	_use_gamepad()

	Events.player_eliminated.emit(0, 0)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.player_eliminated_strong_magnitude, 0.001)


func test_match_won_rumbles_win_pulse_for_the_matching_local_slot() -> void:
	_use_gamepad()

	Events.match_won.emit(0)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.match_won_weak_magnitude, 0.001)
	assert_eq(_stop_calls.size(), 1, "match end must stop any lingering rumble first.")


func test_trigger_test_pulse_rumbles_the_last_gamepad() -> void:
	_use_gamepad(3)

	Rumble.trigger_test_pulse()

	assert_eq(_calls.size(), 1)
	assert_eq(_calls[0]["device"], 3)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.impact_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.impact_strong_magnitude, 0.001)

