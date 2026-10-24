extends GutTest
## net/MatchEventApplier.gd built through bind(session, host, replica, config, gifts) over the
## FakeHostPort / FakeReplicaPort spies, driven through apply_event: the gift wire order
## (flight, landed, claimed or expired), the refusal of a replayed gift, and the validation of
## the slot-replay payload. No MatchNet and no Match are involved.

const SLOT: int = 1
const GIFT: int = 9
const ORIGIN: Vector3 = Vector3(0.0, 8.0, 0.0)
const LANDING: Vector3 = Vector3(2.0, 0.5, 1.0)
const HELD: StringName = &"cube"
const NEXT: StringName = &"domino"
const CARRIER: StringName = &"L3"

var _applier: Node
var _host: WorldHost
var _replica: FakeReplicaPort
var _guard: GiftWireGuard
var _session: FakeSessionPort
var _config: NetConfig
var _special: StringName


## The reads the gift and slot-replay handlers make: two seats, the shapes the feed knows and the
## landing the host holds for the gift.
class WorldHost extends FakeHostPort:
	var running: MatchConfig = null
	var landing: Vector3 = LANDING
	var known_shapes: Array[StringName] = [HELD, NEXT, CARRIER]
	var slot_mode: bool = false

	func config() -> MatchConfig:
		return running

	func slot_count() -> int:
		return 2

	func feed_knows_shape(shape_id: StringName) -> bool:
		return known_shapes.has(shape_id)

	func gift_state(gift_id: int) -> Dictionary:
		return {"landing": landing} if gift_id == GIFT else {}

	func gift_slot_enabled() -> bool:
		return slot_mode


func before_each() -> void:
	var map: MapDef = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	map.field_radius = 20.0
	var running: TinyMapMatchConfig = TinyMapMatchConfig.new()
	running.set_tiny_map(map)
	_host = WorldHost.new()
	_host.running = running
	_replica = FakeReplicaPort.new()
	_session = FakeSessionPort.new(FakeNet.client(SLOT))
	_config = load("res://config/net/net_config.tres") as NetConfig
	_guard = GiftWireGuard.new()
	_guard.bind(_host, _config)
	_special = SpecialDef.load_all_specials()[0].id
	_applier = autofree((load("res://net/MatchEventApplier.gd") as GDScript).new() as Node)
	_applier.bind(_session, _host, _replica, _config, _guard)
	watch_signals(Events)


func _replica_methods() -> Array[StringName]:
	var methods: Array[StringName] = []
	for call: Dictionary in _replica.calls:
		methods.append(call["method"])
	return methods


func _flight(gift_id: int = GIFT) -> bool:
	return _applier.apply_event(MatchWireEvents.GIFT_FLIGHT, [gift_id, ORIGIN, LANDING])


func _landed(landing: Vector3 = LANDING, gift_id: int = GIFT) -> bool:
	return _applier.apply_event(MatchWireEvents.GIFT_LANDED, [gift_id, landing])


func _claimed(special: StringName = _special, gift_id: int = GIFT) -> bool:
	return _applier.apply_event(MatchWireEvents.GIFT_CLAIMED, [gift_id, SLOT, special, HELD])


func _expired(gift_id: int = GIFT) -> bool:
	return _applier.apply_event(MatchWireEvents.GIFT_EXPIRED, [gift_id])


# --- gift wire order ------------------------------------------------------------------------


func test_flight_then_landed_then_claimed_reaches_the_replica_in_that_order() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_true(_claimed())
	assert_eq(_replica_methods(), [
		&"apply_replicated_gift_flight",
		&"apply_replicated_gift_landed",
		&"apply_replicated_gift_claimed",
		&"apply_replicated_next_gift",
	] as Array[StringName])
	assert_eq(_replica.calls_to(&"apply_replicated_gift_flight")[0], [GIFT, ORIGIN, LANDING])
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed")[0], [GIFT, SLOT, _special])
	assert_signal_emitted_with_parameters(Events, "gift_flight_spawned", [GIFT, ORIGIN, LANDING])
	assert_signal_emitted_with_parameters(Events, "gift_landed", [GIFT, LANDING])
	assert_signal_emitted_with_parameters(Events, "gift_claimed", [GIFT, SLOT, _special])


func test_flight_then_landed_then_expired_retires_the_crate() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_true(_expired())
	assert_eq(_replica.calls_to(&"apply_replicated_gift_expired"), [[GIFT]] as Array[Array])
	assert_signal_emitted_with_parameters(Events, "gift_expired", [GIFT])


func test_a_claim_in_gift_slot_mode_only_retires_the_crate() -> void:
	_host.slot_mode = true
	assert_true(_flight())
	assert_true(_landed())
	assert_true(_claimed())
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed").size(), 0)
	assert_eq(_replica.calls_to(&"apply_replicated_gift_expired"), [[GIFT]] as Array[Array])


func test_landing_before_flight_is_refused_and_writes_nothing() -> void:
	assert_false(_landed())
	assert_eq(_replica.calls.size(), 0)
	assert_signal_not_emitted(Events, "gift_landed")
	assert_true(_flight(), "the refused landing did not block the flight")


func test_a_landing_that_differs_from_the_hosts_is_refused_and_the_gift_can_still_land() -> void:
	assert_true(_flight())
	assert_false(_landed(LANDING + Vector3.RIGHT))
	assert_eq(_replica.calls_to(&"apply_replicated_gift_landed").size(), 0)
	assert_true(_landed(), "the good landing is still accepted")


func test_a_landing_for_a_gift_the_host_does_not_hold_is_refused() -> void:
	assert_true(_flight(GIFT + 1))
	assert_false(_landed(LANDING, GIFT + 1))


func test_a_replayed_flight_is_refused() -> void:
	assert_true(_flight())
	assert_false(_flight())
	assert_eq(_replica.calls_to(&"apply_replicated_gift_flight").size(), 1)
	assert_signal_emit_count(Events, "gift_flight_spawned", 1)


func test_a_flight_after_landing_is_refused() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_false(_flight())
	assert_eq(_replica.calls_to(&"apply_replicated_gift_flight").size(), 1)


func test_a_replayed_landing_is_refused() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_false(_landed())
	assert_eq(_replica.calls_to(&"apply_replicated_gift_landed").size(), 1)


func test_a_replayed_claim_is_refused_and_applies_nothing_twice() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_true(_claimed())
	var writes: int = _replica.calls.size()
	assert_false(_claimed())
	assert_eq(_replica.calls.size(), writes, "the replay reached the replica")
	assert_signal_emit_count(Events, "gift_claimed", 1)


func test_a_claim_or_expiry_after_removal_is_refused_either_way_round() -> void:
	assert_true(_flight())
	assert_true(_claimed())
	assert_false(_expired(), "claimed, then expired")
	assert_true(_flight(GIFT + 1))
	assert_true(_expired(GIFT + 1))
	assert_false(_claimed(_special, GIFT + 1), "expired, then claimed")
	assert_false(_expired(GIFT + 1), "expired twice")


func test_a_removed_gift_cannot_fly_or_be_announced_again() -> void:
	assert_true(_expired())
	assert_false(_flight())
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_SPAWNED, [GIFT, Vector2.ONE]))


func test_a_claim_with_an_unknown_special_a_bad_slot_or_an_unknown_shape_is_refused_and_leaves_the_gift_claimable() -> void:
	assert_true(_flight())
	assert_true(_landed())
	assert_false(_claimed(&"not_a_real_special"), "special outside the roster")
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_CLAIMED, [GIFT, 2, _special, HELD]), "slot past the seat count")
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_CLAIMED, [GIFT, -1, _special, HELD]), "negative slot")
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_CLAIMED, [GIFT, SLOT, _special, &"no_such_shape"]), "unknown shape")
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed").size(), 0)
	assert_true(_claimed(), "nothing was marked removed")


func test_the_pending_placeholder_is_a_claimable_special() -> void:
	assert_true(_claimed(SpecialIds.PENDING))


func test_a_negative_gift_id_is_refused_by_every_gift_event() -> void:
	assert_false(_flight(-1))
	assert_false(_landed(LANDING, -1))
	assert_false(_claimed(_special, -1))
	assert_false(_expired(-1))
	assert_eq(_replica.calls.size(), 0)
	assert_true(_flight(), "control: a well-formed gift event is applied")


func test_a_spawn_notice_is_applied_once_and_a_flight_may_follow() -> void:
	assert_true(_applier.apply_event(MatchWireEvents.GIFT_SPAWNED, [GIFT, Vector2(3.0, 4.0)]))
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_SPAWNED, [GIFT, Vector2(3.0, 4.0)]), "replayed")
	assert_eq(_replica.calls_to(&"apply_replicated_gift_spawned"), [[GIFT, Vector2(3.0, 4.0)]] as Array[Array])
	assert_true(_flight())


func test_a_spawn_notice_outside_the_field_is_refused() -> void:
	assert_false(_applier.apply_event(MatchWireEvents.GIFT_SPAWNED, [GIFT, Vector2(25.0, 0.0)]))
	assert_eq(_replica.calls.size(), 0)
	assert_true(_applier.apply_event(MatchWireEvents.GIFT_SPAWNED, [GIFT, Vector2(3.0, 4.0)]), "control: an in-field notice is applied")


func test_the_wire_state_is_shared_with_the_guard_the_applier_was_bound_to() -> void:
	assert_true(_flight())
	assert_false(_guard.begin_flight(GIFT), "the guard saw the flight the applier applied")
	assert_true(_guard.land(GIFT))
	assert_false(_landed(), "the applier sees the landing the guard marked")


func test_rebinding_keeps_the_gift_wire_state() -> void:
	assert_true(_flight())
	var other: FakeReplicaPort = FakeReplicaPort.new()
	_guard.bind(_host, _config)
	_applier.bind(_session, _host, other, _config, _guard)
	assert_false(_flight(), "still falling after the rebind")
	assert_true(_landed())
	assert_eq(other.calls_to(&"apply_replicated_gift_landed").size(), 1, "the new replica is the write port")
	assert_eq(_replica.calls_to(&"apply_replicated_gift_landed").size(), 0)


func test_a_reset_guard_accepts_the_gift_again() -> void:
	assert_true(_flight())
	assert_true(_expired())
	_guard.reset()
	assert_true(_flight())


# --- slot replay ----------------------------------------------------------------------------


func _replay(overrides: Dictionary = {}) -> Array:
	var args: Array = [SLOT, HELD, NEXT, 3, 4.5, false, &"", &"", &"", &""]
	for index: int in overrides:
		args[index] = overrides[index]
	return args


func _assert_replay_refused(args: Array, context: String) -> void:
	var issued_before: int = get_signal_emit_count(Events, "feed_block_issued")
	assert_false(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, args), context)
	assert_eq(_replica.calls.size(), 0, "%s: nothing reached the replica" % context)
	assert_eq(get_signal_emit_count(Events, "feed_block_issued"), issued_before, "%s: no feed event" % context)
	# Control: the same applier wiring accepts the plain replay, so the refusal above is the payload's.
	if _host.running == null:
		return
	var control: Node = autofree((load("res://net/MatchEventApplier.gd") as GDScript).new() as Node)
	control.bind(_session, _host, FakeReplicaPort.new(), _config, _guard)
	assert_true(control.apply_event(MatchWireEvents.SLOT_REPLAY, _replay()), "%s: control" % context)


func test_a_plain_slot_replay_rebuilds_the_feed() -> void:
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, _replay()))
	assert_eq(_replica_methods(), [&"apply_replicated_feed"] as Array[StringName])
	assert_eq(_replica.calls_to(&"apply_replicated_feed")[0], [SLOT, HELD, NEXT, 3, 4.5, false])
	assert_signal_emitted_with_parameters(Events, "feed_block_issued", [SLOT, HELD, NEXT])


func test_a_slot_replay_with_gifts_queues_them_in_the_order_a_seated_client_saw() -> void:
	var args: Array = _replay({6: _special, 7: SpecialIds.PENDING, 8: _special, 9: CARRIER, 2: NEXT})
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, args))
	assert_eq(_replica_methods(), [
		&"apply_replicated_gift_claimed",
		&"apply_replicated_next_gift",
		&"apply_replicated_feed",
		&"apply_replicated_gift_claimed",
		&"apply_replicated_next_gift",
		&"apply_replicated_gift_claimed",
	] as Array[StringName])
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed")[0], [-1, SLOT, _special])
	assert_eq(_replica.calls_to(&"apply_replicated_next_gift")[0], [SLOT, HELD])
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed")[1], [-1, SLOT, SpecialIds.PENDING])
	assert_eq(_replica.calls_to(&"apply_replicated_next_gift")[1], [SLOT, NEXT])
	assert_eq(_replica.calls_to(&"apply_replicated_gift_claimed")[2], [-1, SLOT, _special], "the after-next gift is queued last")


func test_a_slot_replay_with_no_next_block_is_accepted() -> void:
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, _replay({2: &""})))


func test_a_stale_held_shape_is_refused() -> void:
	_assert_replay_refused(_replay({1: &"retired_shape"}), "held")


func test_a_stale_next_shape_is_refused() -> void:
	_assert_replay_refused(_replay({2: &"retired_shape"}), "next")


func test_a_stale_after_next_carrier_is_refused() -> void:
	_assert_replay_refused(_replay({8: _special, 9: &"retired_shape"}), "carrier")


func test_a_bad_time_is_refused() -> void:
	_assert_replay_refused(_replay({4: -0.5}), "negative")
	_assert_replay_refused(_replay({4: NAN}), "NaN")
	_assert_replay_refused(_replay({4: INF}), "infinite")
	_assert_replay_refused(_replay({4: MatchConfig.BLOCK_TIMER_MAX + 0.5}), "past the block timer")


func test_the_block_timer_bounds_are_accepted() -> void:
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, _replay({4: 0.0})))
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, _replay({4: MatchConfig.BLOCK_TIMER_MAX})))


func test_a_negative_feed_sequence_is_refused() -> void:
	_assert_replay_refused(_replay({3: -1}), "feed_seq")


func test_a_slot_outside_the_seats_is_refused() -> void:
	_assert_replay_refused(_replay({0: 2}), "past the seat count")
	_assert_replay_refused(_replay({0: -1}), "negative")


func test_an_unknown_special_in_any_position_is_refused() -> void:
	_assert_replay_refused(_replay({6: &"not_a_real_special"}), "held special")
	_assert_replay_refused(_replay({7: &"not_a_real_special"}), "next special")
	_assert_replay_refused(_replay({8: &"not_a_real_special", 9: CARRIER}), "after-next special")
	_assert_replay_refused(_replay({6: &"bad id"}), "malformed id")


func test_a_next_special_needs_a_next_block() -> void:
	_assert_replay_refused(_replay({2: &"", 7: _special}), "next special without a next shape")


func test_a_malformed_payload_is_refused() -> void:
	_assert_replay_refused([], "empty")
	_assert_replay_refused(_replay().slice(0, 9), "one argument short")
	_assert_replay_refused(_replay() + [&"extra"], "one argument over")
	_assert_replay_refused(_replay({0: "one"}), "slot as text")
	_assert_replay_refused(_replay({5: 1}), "locked as an int")


func test_a_host_refuses_a_slot_replay() -> void:
	var host_session: FakeSessionPort = FakeSessionPort.new(FakeNet.host())
	_applier.bind(host_session, _host, _replica, _config, _guard)
	_assert_replay_refused(_replay(), "host")


func test_without_a_running_match_a_slot_replay_is_refused() -> void:
	_host.running = null
	_assert_replay_refused(_replay(), "no match")


func test_a_refused_replay_does_not_block_a_later_good_one() -> void:
	_assert_replay_refused(_replay({1: &"retired_shape"}), "stale")
	assert_true(_applier.apply_event(MatchWireEvents.SLOT_REPLAY, _replay()))
