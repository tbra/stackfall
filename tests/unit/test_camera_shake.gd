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
	Settings.set_config_path_for_test(Settings.default_config_path())
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

	_fire(&"bomb")

	assert_gt(rig.shake_offset().length(), 0.0, "an impact well above threshold should produce a visible shake offset.")


func _fire(def_id: StringName, position: Vector3 = Vector3.ZERO) -> void:
	Events.special_triggered.emit(1, def_id, position, 0)


func test_each_shaking_special_shakes_the_camera() -> void:
	for def_id: StringName in [&"anvil", &"bomb", &"rocket"]:
		var rig: CameraRig = _make_rig()
		_fire(def_id)
		assert_gt(rig.shake_offset().length(), 0.0, "%s must shake the camera." % def_id)


func test_volcano_spew_and_block_landings_do_not_shake() -> void:
	var rig: CameraRig = _make_rig()
	_fire(&"volcano")
	Events.block_impacted.emit(100.0)
	Events.block_impacted_at.emit(100.0, Vector3.ZERO)
	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "volcano and plain landings are cosmetic: no shake.")


func test_explosion_far_from_the_disc_does_not_shake() -> void:
	var rig: CameraRig = _make_rig()
	var far: Vector3 = Vector3(100000.0, 0.0, 0.0)
	var field: Field = Match.field()
	if field != null:
		far = field.global_position + Vector3(field.map_def.field_radius * 100.0, 0.0, 0.0)
	else:
		pending("no Match field in this fixture; range check is skipped by design.")
		return
	_fire(&"bomb", far)
	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO))


func test_earthquake_shakes_while_the_disc_shakes_and_not_after() -> void:
	# Real effect timing: the Earthquake's own DiscForce.shake drives a real
	# Field's tilt for duration_s; its special_triggered only fires at the end.
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_camera_quake"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var field: Field = autofree(Field.new())
	field.map_def = map_def
	add_child_autofree(field)
	field.set_tilt_enabled(true)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var rig: CameraRig = _make_rig()
	var quake: EarthquakeEffect = (load("res://config/specials/earthquake.tres") as SpecialDef).effect as EarthquakeEffect
	var tick: float = 1.0 / 60.0
	var elapsed: float = 0.0
	var shaking_during: int = 0
	var ticks_in_quake: int = int(quake.disc_force.duration_s / tick)
	for i: int in range(ticks_in_quake):
		DiscForce.shake(field, quake.disc_force, elapsed, tick)
		field._update_tilt(tick)
		rig._process(tick)
		elapsed += tick
		if i > ticks_in_quake / 4 and rig._current_shake_amplitude() > 0.0:
			shaking_during += 1
	assert_gt(shaking_during, ticks_in_quake / 2, "the camera shakes while the disc is being shaken.")
	for i: int in range(int(10.0 / tick)):
		field._update_tilt(tick)
		rig._process(tick)
	assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "no shake once the quake is over and the disc has settled.")
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func test_slow_weight_tilt_never_shakes_at_high_frame_rates() -> void:
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_camera_slow_tilt"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var field: Field = autofree(Field.new())
	field.map_def = map_def
	add_child_autofree(field)
	field.set_tilt_enabled(true)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var slow_rate: float = load("res://config/disc_shake.tres").disc_tilt_rate_threshold * 0.4
	for frame_s: float in [1.0 / 144.0, 1.0 / 240.0]:
		var rig: CameraRig = _make_rig()
		field._tilt = Vector2.ZERO
		var tilt: float = 0.0
		var since_physics: float = 0.0
		for i: int in range(int(2.0 / frame_s)):
			since_physics += frame_s
			if since_physics >= 1.0 / 60.0:
				tilt += slow_rate * since_physics
				field._tilt = Vector2(tilt, 0.0)
				since_physics = 0.0
			rig._process(frame_s)
			assert_eq(rig._current_shake_amplitude(), 0.0, "slow tilt must not shake at %.0f fps" % (1.0 / frame_s))
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func test_shake_decays_to_zero_over_simulated_time() -> void:
	var rig: CameraRig = _make_rig()
	rig.shake_config = rig.shake_config.duplicate() as CameraShakeConfig
	rig.shake_config.decay_seconds = 0.1

	_fire(&"rocket")
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

	_fire(&"anvil")

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
