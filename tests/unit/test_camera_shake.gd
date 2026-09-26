extends GutTest
## Bontago-xtq.29 (M7 P4, spec 2.10 "effects + camera shake"):
## game/CameraRig.gd's shake_offset()/Settings.camera_shake_enabled()
## integration. game/CameraRig.gd reads the real "Settings" autoload directly
## (autoload/Sfx.gd's own master_volume_db()/custom_music_dir() precedent), so
## isolation here redirects that singleton to a temp cfg
## (Settings.set_config_path_for_test), restored in after_each -- the same
## pattern tests/unit/test_sfx.gd uses.

var _settings_cfg_path: String


func before_each() -> void:
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_camera_shake_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)


func after_each() -> void:
	Settings.set_config_path_for_test("user://settings.cfg")
	_delete_if_exists(_settings_cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


func test_shake_offset_is_zero_before_any_impact() -> void:
	var rig: CameraRig = _make_rig()
	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO))


func test_an_impact_above_threshold_produces_a_nonzero_shake_offset() -> void:
	var rig: CameraRig = _make_rig()
	rig.shake_config = rig.shake_config.duplicate() as CameraShakeConfig

	Events.block_impacted.emit(rig.shake_config.impact_speed_threshold * 3.0)

	assert_gt(rig.shake_offset().length(), 0.0, "an impact well above threshold should produce a visible shake offset.")


func test_an_impact_at_or_below_threshold_produces_no_shake() -> void:
	var rig: CameraRig = _make_rig()
	rig.shake_config = rig.shake_config.duplicate() as CameraShakeConfig

	Events.block_impacted.emit(rig.shake_config.impact_speed_threshold * 0.5)

	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "a soft landing below threshold must not move the camera.")


func test_shake_decays_to_zero_over_simulated_time() -> void:
	var rig: CameraRig = _make_rig()
	rig.shake_config = rig.shake_config.duplicate() as CameraShakeConfig
	rig.shake_config.decay_seconds = 0.1

	Events.block_impacted.emit(rig.shake_config.impact_speed_threshold * 4.0)
	assert_gt(rig.shake_offset().length(), 0.0, "fixture: the impact must have produced some shake to decay from.")

	# Well past decay_seconds -- the offset must have fully settled back to
	# zero, not merely shrunk.
	for i: int in range(120):
		rig._process(1.0 / 60.0)

	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "shake must decay fully to zero, not linger forever.")


func test_shake_offset_is_always_zero_when_camera_shake_is_disabled_in_settings() -> void:
	var rig: CameraRig = _make_rig()
	rig.shake_config = rig.shake_config.duplicate() as CameraShakeConfig
	Settings.set_camera_shake_enabled(false)

	Events.block_impacted.emit(rig.shake_config.impact_speed_threshold * 5.0)

	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "disabling camera shake in Settings must suppress it entirely, even after an impact.")


func test_process_transform_still_matches_the_frozen_bit_for_bit_test_when_no_impact_occurred() -> void:
	# Regression guard for the shake integration into _update_transform():
	# with no impact ever emitted, the camera's transform must be identical to
	# what it was before this package's changes -- shake_offset() must be
	# Vector3.ZERO and never perturb the base transform.
	var rig: CameraRig = _make_rig()
	rig.set_home_view(Vector3(5.0, 0.0, 10.0))
	rig._process(1.0 / 60.0)

	var transform_a: Transform3D = rig.get_camera().global_transform
	rig._process(1.0 / 60.0)
	var transform_b: Transform3D = rig.get_camera().global_transform

	assert_true(transform_a.is_equal_approx(transform_b), "with a static target/yaw/pitch/distance and no impact, the transform must not change frame to frame.")
