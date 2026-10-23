extends "res://tests/unit/match/match_world_test.gd"
## MatchConfig.tilt_mode wired into the registered Field (spec 1.6 / 2.8).

const TICK: float = 1.0 / 60.0


func _config(tilt_mode: MatchConfig.TiltMode = MatchConfig.TiltMode.SPECIALS_ONLY) -> MatchConfig:
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 4242
	config.tilt_mode = tilt_mode
	return config


# --- register_world() + start_match() enables tilt --------------------------

func test_starting_a_specials_only_match_enables_tilt_on_the_registered_field() -> void:
	assert_false(_field.sync_to_physics, "fixture: Field starts with tilt off (no physics sync)")

	Match.start_match(_config(MatchConfig.TiltMode.SPECIALS_ONLY))

	assert_true(
		_field.sync_to_physics,
		"start_match() with tilt_mode SPECIALS_ONLY must enable the field's tilt controller"
	)

	_field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	_field._physics_process(TICK)
	assert_ne(
		_field.tilt_vector(), Vector2.ZERO,
		"with tilt enabled, an Anvil/Propeller/Earthquake-style impulse must actually move the disk"
	)


# --- M6 B5: PHYSICAL_BALANCE reads settled blocks, SPECIALS_ONLY does not ----

func _settle_offcenter_block(tuning: PhysicsTuning) -> void:
	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	_blocks_root.add_child(block)
	autofree(block)
	block.freeze = true
	block.global_position = Vector3(3.0, 0.5, 0.0)
	Events.block_placed.emit(block, shape.id)
	var settle_ticks: int = int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(settle_ticks + 30):
		await get_tree().physics_frame


func test_a_specials_only_match_ignores_the_weight_of_a_settled_offcenter_block() -> void:
	Match.start_match(_config(MatchConfig.TiltMode.SPECIALS_ONLY))
	await _settle_offcenter_block(load("res://config/physics/physics_tuning.tres"))
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "without PHYSICAL_BALANCE block weight does not tilt the disc")


func test_clearing_the_field_drops_the_balance_link_to_settled_blocks() -> void:
	Match.start_match(_config(MatchConfig.TiltMode.PHYSICAL_BALANCE))
	await _settle_offcenter_block(load("res://config/physics/physics_tuning.tres"))
	assert_ne(_field.tilt_vector(), Vector2.ZERO, "fixture: the settled block tilts a balance match")
	_field.clear_match_state()
	_field.set_tilt_enabled(true)
	for _i: int in range(30):
		_field._physics_process(TICK)
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "after a reset the block's torque no longer reaches the disc")


func test_physical_balance_match_actually_tilts_toward_a_settled_offcenter_block() -> void:
	Match.start_match(_config(MatchConfig.TiltMode.PHYSICAL_BALANCE))

	var shape: BlockShape = load("res://config/blocks/cube.tres")
	var tuning: PhysicsTuning = load("res://config/physics/physics_tuning.tres")
	var block: Block = BlockFactory.build(shape, tuning, 0)
	_blocks_root.add_child(block)
	autofree(block)
	block.freeze = true
	block.global_position = Vector3(3.0, 0.5, 0.0)
	Events.block_placed.emit(block, shape.id)

	var settle_ticks: int = int(ceil(tuning.sleep_settle_time * Engine.physics_ticks_per_second)) + 5
	for _i: int in range(settle_ticks + 30):
		await get_tree().physics_frame

	assert_gt(
		_field.tilt_vector().length(), 0.0,
		"a real match under PHYSICAL_BALANCE must tilt from a settled off-center block's own weight"
	)


# --- abort disables tilt and levels the disc ---------------------------------

func test_abort_disables_tilt_and_levels_the_disc() -> void:
	Match.start_match(_config())
	_field.apply_tilt_impulse(Vector2(1.0, 0.0), 0.5)
	_field._physics_process(TICK)
	assert_ne(_field.tilt_vector(), Vector2.ZERO, "fixture: the disk is actually tilted before abort")

	Match.abort_match()

	assert_false(_field.sync_to_physics, "abort_match() must disable the field's tilt controller")
	assert_eq(_field.tilt_vector(), Vector2.ZERO, "abort_match() must level the disc")


# --- a second match start re-enables tilt ------------------------------------
