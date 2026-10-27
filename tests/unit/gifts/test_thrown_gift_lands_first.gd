extends "res://tests/unit/match/match_world_test.gd"
## A ballistically thrown gift (Bomb, Magnet, Jumping Bean) starts its effect at its first
## landing, not in flight: driven through the public Match.request_throw path.

const FLIGHT_STEP_S: float = 0.5
const FLIGHT_STEPS: int = 10
const MAX_LAND_FRAMES: int = 600
const UP_TILT: float = 0.3


func after_each() -> void:
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


## Throws the shipped gift `gift_id` from slot 0 and returns its behaviour (null if refused).
func _throw(gift_id: StringName) -> SpecialBehavior:
	var config: MatchConfig = _tiny_map_config()
	config.player_count = 2
	config.block_timer = 6.0
	config.rng_seed = 13579
	config.enabled_specials = [gift_id]
	Match.start_match(config)
	_run_countdown()
	Match._gifts._ensure_capacity(0)
	Match._gifts._held_specials[0] = gift_id
	Match._feed._held_is_gift[0] = true
	var home: Vector3 = _home_world_position(0)
	var inward: Vector3 = (_field.to_global(Vector3.ZERO) - home) * Vector3(1.0, 0.0, 1.0)
	var aim: Vector3 = (inward.normalized() + Vector3.UP * UP_TILT).normalized()
	var reason: StringName = Match.request_throw(0, home, 0, Quaternion.IDENTITY, aim)
	assert_eq(reason, PlacementRules.REASON_OK, "setup: the throw is accepted")
	var block: Block = _blocks_root.get_child(_blocks_root.get_child_count() - 1) as Block
	for child: Node in block.get_children():
		if child is SpecialBehavior:
			return child as SpecialBehavior
	return null


## Ages the behaviour in the air (no physics step, so the carrier cannot touch down).
func _fly(behavior: SpecialBehavior) -> void:
	for _i: int in range(FLIGHT_STEPS):
		behavior.advance(FLIGHT_STEP_S)


func _wait_landed(behavior: SpecialBehavior) -> void:
	var frames: int = 0
	while not behavior.has_landed() and frames < MAX_LAND_FRAMES:
		await wait_physics_frames(1)
		frames += 1


func test_thrown_bomb_neither_blinks_nor_counts_down_until_it_lands() -> void:
	watch_signals(Events)
	var behavior: SpecialBehavior = _throw(&"bomb")
	assert_not_null(behavior)
	var block: Block = behavior.get_parent() as Block
	assert_signal_emitted_with_parameters(Events, "special_launch_state", [block.net_id, false])
	assert_signal_emit_count(Events, "special_launch_state", 1, "only the throw so far")
	var blink_path: NodePath = NodePath(String(GiftBlink.DRIVER_NAME))
	assert_null(block.get_node_or_null(blink_path), "no blink at the throw")
	_fly(behavior)
	assert_false(behavior.has_landed())
	assert_false(behavior.is_triggered(), "5 s in flight is past the 3 s blink and nothing explodes")
	assert_eq(behavior.effect_age(), 0.0)
	assert_null(block.get_node_or_null(blink_path), "still no blink in flight")
	await _wait_landed(behavior)
	assert_true(behavior.has_landed(), "setup: the bomb lands")
	await wait_physics_frames(2)
	assert_not_null(block.get_node_or_null(blink_path), "the blink starts at landing")
	assert_signal_emitted_with_parameters(Events, "special_launch_state", [block.net_id, true])
	assert_false(behavior.is_triggered(), "the countdown has only just begun")


func test_thrown_magnet_does_not_pull_until_it_lands() -> void:
	var behavior: SpecialBehavior = _throw(&"magnet")
	assert_not_null(behavior)
	_fly(behavior)
	var state: MagnetEffect.MagnetState = behavior.state() as MagnetEffect.MagnetState
	assert_false(state.started(), "no pull window opens in flight")
	assert_false(behavior.is_triggered())
	await _wait_landed(behavior)
	await wait_physics_frames(2)
	assert_true(state.started(), "the pull window opens after landing")


func test_thrown_jumping_bean_does_not_hop_until_it_lands() -> void:
	var behavior: SpecialBehavior = _throw(&"jumping_bean")
	assert_not_null(behavior)
	var block: Block = behavior.get_parent() as Block
	var velocity: Vector3 = block.linear_velocity
	_fly(behavior)
	assert_false(behavior.has_landed())
	assert_eq(block.linear_velocity, velocity, "no hop impulse in flight")


func test_a_dropped_gift_keeps_its_clock_from_binding() -> void:
	var def: SpecialDef = SpecialDef.find_by_id(&"bomb")
	var block: Block = autofree(Block.new())
	var behavior: SpecialBehavior = autofree(SpecialBehavior.new())
	block.add_child(behavior)
	behavior.bind(block, def, SpecialTuning.new())
	behavior.advance(1.0)
	assert_almost_eq(behavior.effect_age(), behavior.age(), 0.001)
	assert_almost_eq(behavior.effect_age(), 1.0, 0.001, "an un-thrown gift counts from binding")
	behavior.starts_on_landing = true
	assert_false(behavior.has_landed())
	assert_eq(behavior.effect_age(), 0.0)
