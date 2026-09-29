extends GutTest
## Latest-claim replacement and the one-release gift cadence exception.
const MatchNetScript := preload("res://net/MatchNet.gd")

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_map = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true)
	_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_map)
	config.player_count = 2
	config.hot_seat = false
	config.sandbox = true
	config.block_timer = MatchConfig.BLOCK_TIMER_MIN
	config.rng_seed = 5101
	Match.start_match(config)
	for i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._feed.set_feed_timer_enabled(true)


func after_each() -> void:
	Match.set_net_provider(null)
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


func test_forced_burn_preserves_newer_queued_gift_and_retries_lone_gift() -> void:
	assert_true(Match.debug_queue_special(0, &"earthquake"))
	assert_eq(_place(Match.feed_seq(0)), PlacementRules.REASON_OK)
	assert_eq(Match.held_special(0), &"earthquake", "fixture: older gift A is held")
	assert_true(Match.debug_queue_special(0, &"anvil"))
	assert_eq((Match._gifts._pending_queues[0] as Array)[0], &"anvil", "fixture: newer gift B is next")
	TerritoryTestHelpers.blank_owned_territory(Match.raster(), Match.team_of(0))
	var far: Vector3 = _field.to_global(Vector3(5000.0, 5.0, 5000.0))
	var first_seq: int = Match.feed_seq(0)
	watch_signals(Events)
	assert_ne(
		Match.request_place(0, far, 0, Quaternion.IDENTITY, true, first_seq),
		PlacementRules.REASON_OK,
		"fixture: the forced release must take the burn path"
	)
	assert_eq(Match.feed_seq(0), first_seq + 1)
	assert_eq(Match.held_special(0), &"anvil", "the later gift wins after A burns")
	assert_eq(Match.pending_special_count(0), 1)
	assert_true((Match._gifts._pending_queues[0] as Array).is_empty())
	assert_signal_not_emitted(Events, "special_consumed")

	# With no newer gift queued, the existing burn rule retries B next.
	var second_seq: int = Match.feed_seq(0)
	assert_ne(Match.request_place(0, far, 0, Quaternion.IDENTITY, true, second_seq), PlacementRules.REASON_OK)
	assert_eq(Match.feed_seq(0), second_seq + 1)
	assert_eq(Match.held_special(0), &"anvil")
	assert_eq(Match.pending_special_count(0), 1)


func test_gift_claim_shape_wire_mirrors_next_then_held_state() -> void:
	var fake: FakeNet = FakeNet.client(0)
	Match.set_net_provider(fake)
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.set_providers(fake, Match)
	var shape_id: StringName = Match.held_shape(0).id
	var seq: int = Match.feed_seq(0)
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [11, 0, MatchGifts.PENDING_SPECIAL_ID, &"invalid_shape_id"])
	assert_eq(Match.pending_special_count(0), 0)
	net.net_match_event(MatchNetScript.EVENT_GIFT_CLAIMED, [11, 0, MatchGifts.PENDING_SPECIAL_ID, shape_id])
	assert_eq(Match.pending_special_count(0), 1)
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.next_shape(0).id, shape_id)
	Match.apply_replicated_feed(0, shape_id, shape_id, seq + 1, Match.feed_time_left(0), false)
	assert_eq(Match.held_special(0), MatchGifts.PENDING_SPECIAL_ID)
	assert_eq(Match.pending_special_count(0), 1)
	assert_eq(Match.feed_seq(0), seq + 1)
