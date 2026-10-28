extends GutTest
var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.sandbox = true
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.rng_seed = 5101
	# Old rule (claim replaces next); the default after-next rule is covered in test_gift_queue_after_next.gd.
	config.experiments_enabled = true
	config.qol = QolExperiments.new()
	config.qol.gift_loads_next = true
	Match.start_match(config)
	for i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._feed.set_feed_timer_enabled(true)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	for child: Node in _blocks_root.get_children():
		child.free()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _home() -> Vector3:
	var point: Vector2 = Match.slot(0).home_position
	return _field.to_global(Vector3(point.x, 5.0, point.y))


func _place(seq: int) -> StringName:
	return Match.request_place(0, _home(), 0, Quaternion.IDENTITY, false, seq)


func test_latest_claim_keeps_held_piece_and_replaces_next_gift() -> void:
	var held: BlockShape = Match.held_shape(0)
	var seq: int = Match.feed_seq(0)
	assert_true(Match.debug_queue_special(0, &"earthquake"))
	assert_eq(Match.held_shape(0), held)
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.pending_special_count(0), 1)
	assert_eq(Match.feed_seq(0), seq)
	assert_true(Match.debug_queue_special(0, &"anvil"))
	assert_eq(Match.pending_special_count(0), 1)
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], &"anvil")
	assert_eq(Match.held_shape(0), held)


func test_gift_releases_during_ordinary_lock_then_ordinary_clock_recovers() -> void:
	assert_true(Match.debug_queue_special(0, &"earthquake"))
	var first_seq: int = Match.feed_seq(0)
	var initial_time: float = Match.feed_time_left(0)
	assert_eq(_place(first_seq), PlacementRules.REASON_OK)
	var gift_seq: int = Match.feed_seq(0)
	assert_eq(gift_seq, first_seq + 1)
	assert_eq(Match.held_special(0), &"earthquake")
	assert_false(Match.is_release_locked(0))
	assert_almost_eq(Match.feed_time_left(0), initial_time, 0.01)
	assert_eq(_place(first_seq), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.feed_seq(0), gift_seq)
	assert_eq(_place(gift_seq), PlacementRules.REASON_OK)
	var ordinary_seq: int = Match.feed_seq(0)
	assert_eq(ordinary_seq, gift_seq + 1)
	assert_eq(Match.held_special(0), &"")
	assert_true(Match.is_release_locked(0))
	assert_almost_eq(Match.feed_time_left(0), initial_time, 0.01)
	assert_eq(_place(ordinary_seq), PlacementRules.REASON_NO_BLOCK)
	assert_eq(Match.feed_seq(0), ordinary_seq)
	Match._feed._tick_feed(initial_time)
	assert_false(Match.is_release_locked(0))
	assert_eq(_place(ordinary_seq), PlacementRules.REASON_OK)


func test_rejected_gift_action_does_not_spend_it() -> void:
	assert_true(Match.debug_queue_special(0, &"earthquake"))
	assert_eq(_place(Match.feed_seq(0)), PlacementRules.REASON_OK)
	var gift_seq: int = Match.feed_seq(0)
	var bad: Vector3 = _field.to_global(Vector3(999.0, 5.0, 999.0))
	assert_ne(Match.request_place(0, bad, 0, Quaternion.IDENTITY, false, gift_seq), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), gift_seq)
	assert_eq(Match.held_special(0), &"earthquake")
	assert_eq(_place(gift_seq), PlacementRules.REASON_OK)
