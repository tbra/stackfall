extends GutTest
## a claimed gift joins the queue one block later (gift_queue_after_next
## trial, on by default): the ordinary next piece stays and the gift is the block after next.
const MatchNetScript := preload("res://net/MatchNet.gd")

var _field: Field
var _blocks_root: Node3D
var _registry: BlockRegistry
var _map: MapDef


func _start(qol: QolExperiments = null) -> void:
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
	config.qol = qol
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	Match._feed.set_feed_timer_enabled(true)


func after_each() -> void:
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()
	await get_tree().process_frame


func _issue(slot_id: int) -> void:
	Match._feed._consume_and_refeed(slot_id, true)


func test_claim_keeps_the_ordinary_next_and_stages_the_gift_after_it() -> void:
	_start()
	var held: BlockShape = Match.held_shape(0)
	var next: BlockShape = Match.next_shape(0)
	var carrier: BlockShape = Match._feed._bags[0].peek(2)[1]
	Match._gifts._queue_claimed_special(0, &"anvil")
	assert_eq(Match.held_shape(0), held)
	assert_eq(Match.next_shape(0), next, "the ordinary next piece stays")
	assert_eq(Match.next_special(0), &"", "the gift is not next yet")
	assert_eq(Match.after_next_special(0), &"anvil")
	assert_eq(Match.pending_special_count(0), 1)
	_issue(0)
	assert_eq(Match.held_shape(0), next, "the ordinary next is issued unchanged")
	assert_eq(Match.held_special(0), &"")
	assert_eq(Match.next_special(0), &"anvil", "now the gift is next")
	assert_eq(Match.after_next_special(0), &"")
	assert_eq(Match.next_shape(0), carrier, "the carrier is the bag draw after next, so nothing was discarded")
	_issue(0)
	assert_eq(Match.held_shape(0), carrier)
	assert_eq(Match.held_special(0), &"anvil")
	assert_true(Match._feed.is_held_gift(0))
	assert_eq(Match.pending_special_count(0), 1, "held gift only")


func test_bag_order_is_the_same_with_and_without_a_claim() -> void:
	_start()
	var expected: Array[StringName] = []
	for shape: BlockShape in Match._feed._bags[0].peek(6):
		expected.append(shape.id)
	Match._gifts._queue_claimed_special(0, &"anvil")
	var seen: Array[StringName] = []
	for _i: int in range(5):
		_issue(0)
		seen.append(Match.held_shape(0).id)
	assert_eq(seen, expected.slice(0, 5), "same bag sequence, only the second piece is a gift")


func test_later_claim_replaces_a_staged_gift() -> void:
	_start()
	Match._gifts._queue_claimed_special(0, &"anvil")
	Match._gifts._queue_claimed_special(0, &"earthquake")
	assert_eq(Match.after_next_special(0), &"earthquake", "latest claim wins the after-next slot")
	assert_eq((Match._gifts._pending_queues[0] as Array).size(), 1)
	_issue(0)
	_issue(0)
	assert_eq(Match.held_special(0), &"earthquake")


func test_claim_while_a_gift_is_next_queues_behind_it() -> void:
	_start()
	Match._gifts._queue_claimed_special(0, &"anvil")
	_issue(0)
	assert_eq(Match.next_special(0), &"anvil")
	Match._gifts._queue_claimed_special(0, &"earthquake")
	assert_eq(Match.next_special(0), &"anvil", "a gift already next is not displaced")
	assert_eq(Match.after_next_special(0), &"earthquake")
	assert_eq(Match.pending_special_count(0), 2)
	_issue(0)
	assert_eq(Match.held_special(0), &"anvil")
	assert_eq(Match.next_special(0), &"earthquake", "the second gift is next right after")
	assert_eq(Match.after_next_special(0), &"")
	_issue(0)
	assert_eq(Match.held_special(0), &"earthquake")


func test_client_mirrors_staged_then_next_then_held() -> void:
	_start()
	var fake: FakeNet = FakeNet.client(0)
	Match._net_provider = fake
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	net.bind_ports(FakeSessionPort.new(fake), MatchHostPort.new(Match), MatchReplicaPort.new(Match))
	var shape_id: StringName = Match.held_shape(0).id
	var carrier_id: StringName = Match._feed._bags[0].peek(2)[1].id
	var seq: int = Match.feed_seq(0)
	net.net_match_event(MatchWireEvents.GIFT_CLAIMED, [11, 0, MatchGifts.PENDING_SPECIAL_ID, carrier_id])
	assert_eq(Match.after_next_special(0), MatchGifts.PENDING_SPECIAL_ID)
	assert_eq(Match.next_special(0), &"")
	Match.apply_replicated_feed(0, shape_id, shape_id, seq + 1, Match.feed_time_left(0), false)
	assert_eq(Match.held_special(0), &"", "the first issue is the ordinary next piece")
	assert_eq(Match.next_special(0), MatchGifts.PENDING_SPECIAL_ID, "staged gift is now next")
	assert_eq(Match.next_shape(0).id, carrier_id)
	Match.apply_replicated_feed(0, carrier_id, carrier_id, seq + 2, Match.feed_time_left(0), false)
	assert_eq(Match.held_special(0), MatchGifts.PENDING_SPECIAL_ID)
	assert_eq(Match.pending_special_count(0), 1)


func test_slot_replay_carries_the_staged_gift() -> void:
	_start()
	Match._gifts._queue_claimed_special(0, &"anvil")
	var net: MatchNetScript = MatchNetScript.new()
	net.set_process(false)
	add_child_autofree(net)
	var fake: FakeNet = FakeNet.client(0)
	net.bind_ports(FakeSessionPort.new(fake), MatchHostPort.new(Match), MatchReplicaPort.new(Match))
	var args: Array = net._slot_replay_args(0)
	assert_eq(args.size(), 10)
	assert_eq(args[8], &"anvil")
	assert_eq(args[9], Match._feed.staged_gift_shape_id(0))
	Match._feed._staged_gift_shapes.clear()
	Match._gifts._pending_queues[0].clear()
	Match._net_provider = fake
	net.net_match_event(MatchWireEvents.SLOT_REPLAY, args)
	assert_eq(Match.after_next_special(0), &"anvil")
	assert_eq(Match.next_special(0), &"")
