extends GutTest
## M4 P4-SPAWN (docs/M4_SPECIALS_PACKAGES.md "P4-SPAWN"):
## Match.spawn_special_projectile() / MatchPlacement.spawn_special_projectile().
## Same tiny-map/real-Field fixture as tests/unit/test_match_throw.gd; a
## hand-built SpecialDef stands in for a real config/specials/ resource
## (that file's own convention -- "do not add real specials under
## config/specials/" outside the per-special packages that own it).

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _tuning: SpecialTuning


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
	_tuning = (load("res://config/special_tuning.tres") as SpecialTuning).duplicate(true) as SpecialTuning


func after_each() -> void:
	Match.set_net_provider(null)
	Match.abort_match()
	# See test_match_throw.gd's own after_each() comment: free synchronously
	# here rather than relying on abort_match()'s deferred queue_free(), since
	# GUT's end-of-script orphan check runs before the next idle frame does.
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	await get_tree().process_frame


func _config(player_count: int = 2) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = player_count
	config.hot_seat = false
	config.block_timer = 6.0
	config.rng_seed = 13579
	return config


func _run_countdown() -> void:
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * Engine.physics_ticks_per_second)) + 2):
		Match._process(1.0 / Engine.physics_ticks_per_second)


func _home_world_position(slot_id: int) -> Vector3:
	var home: Vector2 = Match.slot(slot_id).home_position
	return _field.to_global(Vector3(home.x, 5.0, home.y))


func _make_test_def(id: StringName = &"orb_test") -> SpecialDef:
	var def: SpecialDef = SpecialDef.new()
	def.id = id
	def.arm_delay = 999.0
	def.arm_impulse = 999.0
	def.fuse_timeout_s = 999.0
	return def


func _cube_shape() -> BlockShape:
	return load("res://config/blocks/cube.tres") as BlockShape


# --- Off-host: null, nothing spawned, nothing signalled ---------------------

func test_off_host_returns_null_and_spawns_nothing() -> void:
	Match.start_match(_config())
	_run_countdown()
	Match.set_net_provider(FakeNet.client(0))
	watch_signals(Events)

	var result: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3(0.0, 5.0, 0.0), _make_test_def(), _tuning
	)

	assert_null(result, "off-host must never spawn a projectile")
	assert_eq(_blocks_root.get_child_count(), 0)
	assert_signal_not_emitted(Events, "block_placed")


# --- On-host: spawns, net_id, velocity, special binding ----------------------

func test_on_host_spawns_a_registered_block_with_the_requested_velocity() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var velocity: Vector3 = Vector3(2.0, 4.0, 0.0)  # length < ccd_speed_threshold_mps
	watch_signals(Events)

	var result: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(slot_id), Basis.IDENTITY, slot_id,
		velocity, _make_test_def(), _tuning
	)

	assert_not_null(result, "on-host must return the spawned Block")
	assert_eq(_blocks_root.get_child_count(), 1)
	assert_true(result.net_id > 0, "must be allocated a valid wire net_id")
	assert_eq(_registry.block_for_net_id(result.net_id), result, "must be registered in BlockRegistry")
	assert_true(result.linear_velocity.is_equal_approx(velocity))
	assert_signal_emit_count(Events, "block_placed", 1)


func test_ccd_is_armed_above_the_threshold_and_not_below() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slow: Vector3 = Vector3(1.0, 0.0, 0.0) * (_tuning.ccd_speed_threshold_mps * 0.5)
	var fast: Vector3 = Vector3(1.0, 0.0, 0.0) * (_tuning.ccd_speed_threshold_mps * 2.0)

	var slow_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0, slow, _make_test_def(), _tuning
	)
	var fast_block: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(1), Basis.IDENTITY, 1, fast, _make_test_def(), _tuning
	)

	assert_false(slow_block.continuous_cd, "below the threshold, continuous_cd must be false")
	assert_true(fast_block.continuous_cd, "above the threshold, continuous_cd must be true")


func test_null_orb_tuning_falls_back_to_the_match_tuning_instead_of_crashing() -> void:
	Match.start_match(_config())
	_run_countdown()
	var velocity: Vector3 = Vector3.UP * 20.0

	var result: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		velocity, _make_test_def(), null
	)

	assert_not_null(result, "must return a spawned Block even with null orb_tuning")
	assert_true(result.continuous_cd, "must use fallback tuning's ccd_speed_threshold_mps (15 m/s), and 20 m/s is above it")


func test_spawned_projectile_binds_and_arms_a_special_behavior_referencing_orb_def() -> void:
	Match.start_match(_config())
	_run_countdown()
	var def: SpecialDef = _make_test_def(&"orb_test")
	watch_signals(Events)

	var result: Block = Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(0), Basis.IDENTITY, 0,
		Vector3(0.0, 5.0, 0.0), def, _tuning
	)

	var behavior: SpecialBehavior = null
	for child: Node in result.get_children():
		if child is SpecialBehavior:
			behavior = child as SpecialBehavior
	assert_not_null(behavior, "a bound SpecialBehavior must be attached")
	assert_false(behavior.is_armed(), "arm_delay=999 must not have armed yet")

	behavior.trigger(0)
	assert_signal_emitted_with_parameters(
		Events, "special_triggered", [result.net_id, def.id, result.global_position, 0]
	)
	# Freed synchronously, exactly like test_match_throw.gd's own convention.
	behavior.free()


# --- Not a player intent: the feed/held piece is untouched -------------------

func test_spawning_a_projectile_does_not_touch_the_owner_slots_feed() -> void:
	Match.start_match(_config())
	_run_countdown()
	var slot_id: int = 0
	var seq_before: int = Match.feed_seq(slot_id)
	var shape_before: BlockShape = Match.held_shape(slot_id)
	var pending_before: int = Match.pending_special_count(slot_id)

	Match.spawn_special_projectile(
		_cube_shape(), _home_world_position(slot_id), Basis.IDENTITY, slot_id,
		Vector3(0.0, 5.0, 0.0), _make_test_def(), _tuning
	)

	assert_eq(Match.feed_seq(slot_id), seq_before, "no feed_seq advance -- not a player intent")
	assert_eq(Match.held_shape(slot_id), shape_before, "the held piece must be untouched")
	assert_eq(Match.pending_special_count(slot_id), pending_before, "no pending special popped")
