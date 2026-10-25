extends GutTest
## M7 P4, spec 1.10 "effects + camera shake":
## game/player/CameraRig.gd's shake_offset()/Settings.camera_shake_enabled()
## integration. game/player/CameraRig.gd reads the real "Settings" autoload
## directly, so each test starts with shake enabled through the public setter and
## restores the player's value in after_each.

var _shake_before: bool


func before_each() -> void:
	_shake_before = Settings.camera_shake_enabled()
	Settings.set_camera_shake_enabled(true)


func after_each() -> void:
	Settings.set_camera_shake_enabled(_shake_before)


func _make_rig() -> CameraRig:
	var rig: CameraRig = load("res://game/player/CameraRig.tscn").instantiate()
	add_child_autofree(rig)
	return rig


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
	Match.set_process(false)
	Match.abort_match()
	var map_def: MapDef = MapDef.new()
	map_def.id = &"test_camera_far_blast"
	map_def.field_radius = 6.0
	map_def.cell_size = 1.0
	map_def.disk_height = 1.0
	map_def.territory_res = 32
	var field: Field = autofree(Field.new())
	field.map_def = map_def
	add_child_autofree(field)
	var blocks_root: Node3D = autofree(Node3D.new())
	add_child_autofree(blocks_root)
	var registry: BlockRegistry = autofree(BlockRegistry.new())
	add_child_autofree(registry)
	Match.register_world(field, registry, blocks_root)
	var rig: CameraRig = _make_rig()
	# Control: the same special on the disc shakes, so the far case below is
	# only quiet because of the range check.
	_fire(&"bomb", field.global_position)
	assert_gt(rig.shake_offset().length(), 0.0, "fixture: a blast on the disc must shake.")
	var settled: CameraRig = _make_rig()
	var far: Vector3 = field.global_position + Vector3(map_def.field_radius * 100.0, 0.0, 0.0)
	var far_rig_before: Vector3 = settled.shake_offset()
	_fire(&"bomb", far)
	assert_true(far_rig_before.is_equal_approx(Vector3.ZERO), "fixture: fresh rig starts unshaken.")
	assert_true(settled.shake_offset().is_equal_approx(Vector3.ZERO), "a blast far outside the disc must not shake.")
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


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
	var quake: EarthquakeEffect = (load("res://config/gifts/specials/earthquake.tres") as SpecialDef).effect as EarthquakeEffect
	var tick: float = 1.0 / 60.0
	var elapsed: float = 0.0
	var shaking_during: int = 0
	var ticks_in_quake: int = int(quake.disc_force.duration_s / tick)
	for i: int in range(ticks_in_quake):
		DiscForce.shake(field, quake.disc_force, elapsed, tick)
		field._physics_process(tick)
		rig._process(tick)
		elapsed += tick
		if i > ticks_in_quake / 4 and rig.shake_offset().length() > 0.0:
			shaking_during += 1
	assert_gt(shaking_during, ticks_in_quake / 2, "the camera shakes while the disc is being shaken.")
	for i: int in range(int(10.0 / tick)):
		field._physics_process(tick)
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
	var slow_rate: float = load("res://config/physics/disc_shake.tres").disc_tilt_rate_threshold * 0.4
	for frame_s: float in [1.0 / 144.0, 1.0 / 240.0]:
		var rig: CameraRig = _make_rig()
		field.apply_replicated_pose(Vector3.ZERO, Quaternion.IDENTITY)
		var tilt: float = 0.0
		var since_physics: float = 0.0
		for i: int in range(int(2.0 / frame_s)):
			since_physics += frame_s
			if since_physics >= 1.0 / 60.0:
				tilt += slow_rate * since_physics
				field.apply_replicated_pose(Vector3.ZERO, Quaternion(Vector3.RIGHT, tilt))
				since_physics = 0.0
			rig._process(frame_s)
			assert_true(rig.shake_offset().is_equal_approx(Vector3.ZERO), "slow tilt must not shake at %.0f fps" % (1.0 / frame_s))
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

