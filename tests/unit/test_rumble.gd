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
## restored in after_each -- the same pattern tests/unit/test_camera_shake.gd
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


func test_block_impact_is_scaled_between_threshold_and_max() -> void:
	_use_gamepad()
	var config: RumbleConfig = Rumble.config
	var midpoint_speed: float = (config.impact_speed_threshold + config.impact_speed_max) * 0.5

	Events.block_impacted.emit(midpoint_speed)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], config.impact_weak_magnitude * 0.5, 0.01)
	assert_almost_eq(_calls[0]["strong"], config.impact_strong_magnitude * 0.5, 0.01)


func test_disabled_setting_suppresses_every_rumble() -> void:
	_use_gamepad()
	Settings.set_rumble_enabled(false)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "Settings.rumble_enabled() == false must be a total no-op.")


func test_last_device_keyboard_suppresses_rumble() -> void:
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, Settings.DEVICE_KEYBOARD_MOUSE)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "the last real input came from keyboard/mouse, not a gamepad -- no pad to rumble.")


func test_device_tracking_picks_the_most_recent_pad_id() -> void:
	var first: InputEventJoypadButton = InputEventJoypadButton.new()
	first.device = 0
	first.button_index = JOY_BUTTON_A
	Rumble._input(first)

	var second: InputEventJoypadButton = InputEventJoypadButton.new()
	second.device = 3
	second.button_index = JOY_BUTTON_B
	Rumble._input(second)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 1)
	assert_eq(_calls[0]["device"], 3, "the most recent joypad event's device id must win.")


func test_device_tracking_switches_to_keyboard_after_a_key_press() -> void:
	var pad_event: InputEventJoypadButton = InputEventJoypadButton.new()
	pad_event.device = 0
	pad_event.button_index = JOY_BUTTON_A
	Rumble._input(pad_event)

	var key_event: InputEventKey = InputEventKey.new()
	key_event.keycode = KEY_SPACE
	key_event.pressed = true
	Rumble._input(key_event)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "a keyboard press after gamepad input must switch the active family away from gamepad.")


func test_joypad_motion_below_deadzone_does_not_switch_device() -> void:
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, Settings.DEVICE_KEYBOARD_MOUSE)
	var motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
	motion.device = 1
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = Settings.JOYPAD_MOTION_DEVICE_THRESHOLD * 0.1
	Rumble._input(motion)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 0, "resting-stick jitter under the deadzone must not switch the active device.")


func test_placement_rejected_rumbles_only_the_local_slot() -> void:
	_use_gamepad()

	Events.placement_rejected.emit(0, &"outside_territory")

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.placement_refused_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.placement_refused_strong_magnitude, 0.001)


func test_feed_block_issued_rumbles_local_slot() -> void:
	_use_gamepad()

	Events.feed_block_issued.emit(0, &"i3", &"o2")

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.block_placed_weak_magnitude, 0.001)


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


func test_match_won_rumbles_lose_pulse_for_a_different_local_slot() -> void:
	_use_gamepad()

	# Offline/hot-seat: Match.config is null, so team_of_slot() falls back to
	# identity -- slot 0 is its own team, team 1 belongs to a different slot.
	Events.match_won.emit(1)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.match_lost_weak_magnitude, 0.001)


func test_pause_menu_opened_stops_vibration() -> void:
	_use_gamepad(4)

	Events.pause_menu_opened.emit()

	assert_eq(_stop_calls.size(), 1)
	assert_eq(_stop_calls[0], 4)


func test_strength_scale_applies_to_every_magnitude() -> void:
	_use_gamepad()
	Settings.set_rumble_strength(0.5)

	Events.block_impacted.emit(Rumble.config.impact_speed_max)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.impact_weak_magnitude * 0.5, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.impact_strong_magnitude * 0.5, 0.001)


# --- Bontago-1pi.29: 100% must reach full motor power ------------------------

## Pulses shorter than this do not let a pad's motors spin up (owner brief).
const MIN_PULSE_DURATION_S: float = 0.08


## Every `*_magnitude`/`*_duration_s` float on the shipped RumbleConfig, by
## property-name suffix, so a future event added to the config is covered
## without touching this test.
func _config_floats_with_suffix(suffix: String) -> Dictionary:
	var out: Dictionary = {}
	for prop: Dictionary in Rumble.config.get_property_list():
		var prop_name: String = prop["name"]
		if prop_name.ends_with(suffix):
			out[prop_name] = float(Rumble.config.get(prop_name))
	return out


func test_strongest_configured_event_reaches_full_motor_power_at_full_strength() -> void:
	_use_gamepad()
	var magnitudes: Dictionary = _config_floats_with_suffix("_magnitude")
	assert_gt(magnitudes.size(), 0, "the config must expose per-event magnitudes.")
	var highest: float = 0.0
	for key: String in magnitudes:
		var value: float = magnitudes[key]
		assert_between(value, 0.0, 1.0, "%s must stay within 0..1." % key)
		highest = maxf(highest, value)
	assert_almost_eq(highest, 1.0, 0.0001, "at least one configured motor magnitude must be 1.0 so 100% drives a motor flat out.")

	# Strength 1.0 (set in before_each) must pass that magnitude through unclamped-down.
	Events.player_eliminated.emit(0, 0)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["strong"], 1.0, 0.0001, "the strongest event at 100% must hit the strong motor at 1.0.")


func test_half_strength_scales_the_strongest_event_proportionally() -> void:
	_use_gamepad()
	Settings.set_rumble_strength(0.5)

	Events.player_eliminated.emit(0, 0)

	assert_eq(_calls.size(), 1)
	assert_almost_eq(_calls[0]["strong"], 0.5, 0.0001, "50% of a 1.0 magnitude must be 0.5.")
	assert_almost_eq(_calls[0]["weak"], Rumble.config.player_eliminated_weak_magnitude * 0.5, 0.0001)


func test_full_speed_impact_and_test_pulse_drive_the_strong_motor_flat_out() -> void:
	# The pulse the owner feels at 100% (Options slider test pulse) and the
	# most frequent in-match event were the ones topping out at 0.55.
	_use_gamepad()

	Events.block_impacted.emit(Rumble.config.impact_speed_max)
	Rumble.trigger_test_pulse()

	assert_eq(_calls.size(), 2)
	for pulse: Dictionary in _calls:
		assert_almost_eq(pulse["strong"], 1.0, 0.0001, "a max-speed impact / test pulse at 100% must reach 1.0.")
		assert_gt(pulse["weak"], 0.5, "the weak motor must be clearly driven too, not left near the old 0.35.")
		assert_lt(pulse["weak"], pulse["strong"], "the weak:strong shape (strong motor dominates) must be kept.")


func test_impact_beyond_max_speed_never_exceeds_one() -> void:
	_use_gamepad()

	Events.block_impacted.emit(Rumble.config.impact_speed_max * 5.0)

	assert_eq(_calls.size(), 1)
	assert_lte(_calls[0]["weak"], 1.0)
	assert_lte(_calls[0]["strong"], 1.0)


func test_every_configured_pulse_is_long_enough_for_the_motors_to_spin_up() -> void:
	var durations: Dictionary = _config_floats_with_suffix("_duration_s")
	assert_gt(durations.size(), 0)
	for key: String in durations:
		assert_gte(float(durations[key]), MIN_PULSE_DURATION_S, "%s is below the motor spin-up floor." % key)


func test_event_weights_keep_their_relative_order() -> void:
	var config: RumbleConfig = Rumble.config
	assert_gte(config.player_eliminated_strong_magnitude, config.special_triggered_strong_magnitude)
	assert_gte(config.special_triggered_strong_magnitude, config.match_won_strong_magnitude)
	assert_gt(config.match_won_strong_magnitude, config.match_lost_strong_magnitude, "winning pulse stays stronger than losing.")
	assert_gt(config.impact_strong_magnitude, config.block_placed_strong_magnitude + config.block_placed_weak_magnitude, "the placement tick stays lighter than a hard impact.")


# --- trigger_test_pulse() (options package: rumble intensity slider nudge) ---

func test_trigger_test_pulse_rumbles_the_last_gamepad() -> void:
	_use_gamepad(3)

	Rumble.trigger_test_pulse()

	assert_eq(_calls.size(), 1)
	assert_eq(_calls[0]["device"], 3)
	assert_almost_eq(_calls[0]["weak"], Rumble.config.impact_weak_magnitude, 0.001)
	assert_almost_eq(_calls[0]["strong"], Rumble.config.impact_strong_magnitude, 0.001)


func test_trigger_test_pulse_is_silent_when_rumble_disabled() -> void:
	_use_gamepad()
	Settings.set_rumble_enabled(false)

	Rumble.trigger_test_pulse()

	assert_eq(_calls.size(), 0, "a disabled rumble setting must silence the test pulse too.")


func test_trigger_test_pulse_is_silent_with_no_gamepad_active() -> void:
	Rumble.set_last_device_for_test(Rumble.DEVICE_NONE, Settings.DEVICE_KEYBOARD_MOUSE)

	Rumble.trigger_test_pulse()

	assert_eq(_calls.size(), 0, "no active gamepad means nothing to nudge.")
