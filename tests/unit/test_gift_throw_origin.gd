extends GutTest
## Bontago-1pi.85.47: a throw (and its preview) starts at the held gift (ghost pose), the aim
## direction still follows the camera. Real host path (Match.request_throw), tiny-map fixture
## of test_match_throw.gd.

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _config() -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 97531
	return config


func _start_with_bomb() -> void:
	Match.start_match(_config())
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = &"bomb"
	Match._feed._held_is_gift[0] = true


func _ghost_pose() -> Vector3:
	var home: Vector2 = Match.slot(0).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _throw_at_yaw(yaw: float) -> Block:
	var forward: Vector3 = Vector3(-sin(yaw), 0.0, -cos(yaw))
	var reason: StringName = Match.request_throw(0, _ghost_pose(), 0, Quaternion.IDENTITY, forward)
	assert_eq(reason, PlacementRules.REASON_OK)
	return _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block


func test_the_default_back_off_is_zero() -> void:
	var tuning: SpecialTuning = load("res://config/special_tuning.tres")
	assert_eq(tuning.gift_aim_back_m, 0.0)
	assert_eq(SpecialTuning.new().gift_aim_back_m, 0.0)


func test_spawn_point_is_the_ghost_pose_with_the_min_height_clamp_kept() -> void:
	var tuning: SpecialTuning = load("res://config/special_tuning.tres")
	var pose: Vector3 = Vector3(3.0, 6.0, -2.0)
	var forward: Vector3 = Vector3(0.3, -0.5, -0.8).normalized()
	assert_true(GiftAim.spawn_point(pose, forward, 0.0, tuning).is_equal_approx(pose))
	var low: Vector3 = GiftAim.spawn_point(Vector3(1.0, 0.1, 1.0), forward, 0.0, tuning)
	assert_almost_eq(low.y, tuning.gift_aim_min_height_m, 0.001, "clamped over the surface")
	assert_almost_eq(low.x, 1.0, 0.001)
	assert_almost_eq(low.z, 1.0, 0.001)


func test_real_throw_spawns_at_the_ghost_pose_and_flies_along_the_camera_yaw() -> void:
	_start_with_bomb()
	var block: Block = _throw_at_yaw(0.0)
	var pose: Vector3 = _ghost_pose()
	assert_almost_eq(block.global_position.x, pose.x, 0.01)
	assert_almost_eq(block.global_position.y, pose.y, 0.01)
	assert_almost_eq(block.global_position.z, pose.z, 0.01)
	assert_lt(block.linear_velocity.z, 0.0, "yaw 0 heads along -Z")
	assert_almost_eq(block.linear_velocity.x, 0.0, 0.01)


func test_yaw_90_degrees_turns_the_launch_direction() -> void:
	_start_with_bomb()
	var block: Block = _throw_at_yaw(PI * 0.5)
	assert_lt(block.linear_velocity.x, 0.0, "yaw 90 heads along -X")
	assert_almost_eq(block.linear_velocity.z, 0.0, 0.01)
	var pose: Vector3 = _ghost_pose()
	assert_almost_eq(block.global_position.x, pose.x, 0.01, "same origin whatever the camera yaw")
	assert_almost_eq(block.global_position.z, pose.z, 0.01)


func test_pitch_changes_the_launch_elevation() -> void:
	var tuning: SpecialTuning = load("res://config/special_tuning.tres")
	var flat: Vector3 = GiftAim.throw_velocity(Vector3(0.0, 0.0, -1.0), tuning)
	var up: Vector3 = GiftAim.throw_velocity(Vector3(0.0, 0.5, -1.0).normalized(), tuning)
	assert_gt(up.y, flat.y, "a higher pitch launches higher")
