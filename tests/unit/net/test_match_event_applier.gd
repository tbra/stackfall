extends GutTest
## The client-side match-event table (spec networking sections; plan 1.2/1.4): every
## MatchWireEvents name has an argument shape, a malformed payload of any event is refused
## without a script error and without a visible effect, and a well-formed one reaches the
## client's match mirror and the Events bus. Driven through the entry point the host's
## net_match_event RPC calls, with a real Match as the replica and a client FakeNet.

const MatchNetScript := preload("res://net/MatchNet.gd")
const LOCAL_SLOT: int = 1
var WRONG_TYPE: PackedByteArray = PackedByteArray([1, 2, 3])

var _blocks_root: Node3D
var _field: Field
var _registry: BlockRegistry
var _tiny_map: MapDef
var _net: MatchNetScript


func before_each() -> void:
	Match.set_process(false)
	Match.abort_match()
	_tiny_map = (load("res://config/match/maps/round.tres") as MapDef).duplicate(true)
	_tiny_map.field_radius = 20.0
	_field = autofree(Field.new())
	_field.map_def = _tiny_map
	add_child_autofree(_field)
	_blocks_root = autofree(Node3D.new())
	add_child_autofree(_blocks_root)
	_registry = autofree(BlockRegistry.new())
	add_child_autofree(_registry)
	Match.register_world(_field, _registry, _blocks_root)
	var config: MatchConfig = load("res://config/match/match_defaults.tres").duplicate(true) as MatchConfig
	config.set_script(load("res://tests/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(_tiny_map)
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = 4242
	Match.start_match(config)
	for _i: int in range(int(ceil(Match.COUNTDOWN_SECONDS * 60.0)) + 2):
		Match._process(1.0 / 60.0)
	_net = MatchNetScript.new()
	_net.set_process(false)
	add_child_autofree(_net)
	Match._net_provider = FakeNet.client(LOCAL_SLOT)
	_net.set_providers(Match._net_provider, Match)
	watch_signals(Events)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
	Match._net_provider = null
	Match.abort_match()
	Match.set_process(true)
	MatchTestReset.clear_world()


func _event_names() -> Array[StringName]:
	var names: Array[StringName] = []
	var constants: Dictionary = (MatchWireEvents as Script).get_script_constant_map()
	for key: Variant in constants.keys():
		var value: Variant = constants[key]
		if value is StringName:
			names.append(value)
	return names


func _assert_nothing_emitted(context: String) -> void:
	for info: Dictionary in Events.get_signal_list():
		var signal_name: String = String(info["name"])
		assert_eq(get_signal_emit_count(Events, signal_name), 0, "%s: Events.%s must stay silent" % [context, signal_name])


## Every event name, with arguments a well-formed host would send and the Events signal a
## client observes. Events that need a world object (a block, a gift) are covered by their
## own feature tests.
func _valid_cases() -> Dictionary:
	return {
		MatchWireEvents.COUNTDOWN: {"args": [2], "signal": "countdown_tick", "params": [2]},
		MatchWireEvents.TURN_CHANGED: {"args": [0], "signal": "turn_changed", "params": [LOCAL_SLOT]},
		MatchWireEvents.FEED_EXPIRED: {"args": [0], "signal": "feed_timer_expired", "params": [0]},
		MatchWireEvents.QOL_FEED: {"args": [0, 2, true], "signal": "qol_feed_changed", "params": [0, 2, true]},
		MatchWireEvents.PLACEMENT_REJECTED: {"args": [LOCAL_SLOT, &"not_yours"], "signal": "placement_rejected", "params": [LOCAL_SLOT, &"not_yours"]},
		MatchWireEvents.PLACEMENT_RELOCATED: {"args": [LOCAL_SLOT, Vector2(1.0, 2.0)], "signal": "placement_relocated", "params": [LOCAL_SLOT, Vector2(1.0, 2.0)]},
		MatchWireEvents.PLAYER_ELIMINATED: {"args": [0, 0, -1], "signal": "player_eliminated", "params": [0, 0]},
		MatchWireEvents.MATCH_WON: {"args": [1], "signal": "match_won", "params": [1]},
		MatchWireEvents.GIFT_SPAWNED: {"args": [7, Vector2(1.0, 2.0)], "signal": "gift_spawned", "params": [7, Vector2(1.0, 2.0)]},
		MatchWireEvents.GIFT_EXPIRED: {"args": [7], "signal": "gift_expired", "params": [7]},
		MatchWireEvents.SPECIAL_TRIGGERED: {"args": [5, &"bomb", Vector3(1.0, 1.0, 1.0), 0], "signal": "special_triggered", "params": [5, &"bomb", Vector3(1.0, 1.0, 1.0), 0]},
	}


func test_every_event_has_an_argument_shape() -> void:
	var names: Array[StringName] = _event_names()
	assert_gt(names.size(), 0, "fixture: the event names were found")
	for event: StringName in names:
		assert_false(MatchWireEvents.shape_of(event).is_empty(), "%s has a shape_of row" % event)


func test_an_unknown_event_has_no_shape() -> void:
	assert_true(MatchWireEvents.shape_of(&"not_an_event").is_empty())


func test_event_names_are_distinct() -> void:
	var seen: Dictionary = {}
	for event: StringName in _event_names():
		assert_false(seen.has(event), "%s is named once" % event)
		seen[event] = true


func test_no_arguments_is_refused_for_every_event() -> void:
	for event: StringName in _event_names():
		_net.net_match_event(event, [])
	_assert_nothing_emitted("empty args")
	assert_eq(Match.state(), Match.State.PLAYING, "and the match state is untouched")


func test_extra_arguments_are_refused_for_every_event() -> void:
	for event: StringName in _event_names():
		_net.net_match_event(event, [0, 0, 0, 0, 0, 0, 0, 0, 0])
	_assert_nothing_emitted("nine ints")
	assert_eq(Match.state(), Match.State.PLAYING)


func test_wrong_types_are_refused_for_every_event() -> void:
	for event: StringName in _event_names():
		var shape: Array = MatchWireEvents.shape_of(event)
		var args: Array = []
		for _i: int in range(shape.size()):
			args.append(WRONG_TYPE)
		_net.net_match_event(event, args)
	_assert_nothing_emitted("wrong types")
	assert_eq(Match.state(), Match.State.PLAYING)


func test_one_wrong_type_among_valid_arguments_is_refused() -> void:
	var cases: Dictionary = _valid_cases()
	for event: StringName in cases.keys():
		var valid: Array = (cases[event] as Dictionary)["args"]
		for i: int in range(valid.size()):
			var args: Array = valid.duplicate()
			args[i] = WRONG_TYPE
			_net.net_match_event(event, args)
	_assert_nothing_emitted("one wrong argument")


func test_a_short_argument_list_is_refused_for_every_valid_case() -> void:
	var cases: Dictionary = _valid_cases()
	for event: StringName in cases.keys():
		var valid: Array = (cases[event] as Dictionary)["args"]
		_net.net_match_event(event, valid.slice(0, valid.size() - 1))
	_assert_nothing_emitted("one argument short")


func test_state_changed_with_bad_payloads_is_refused() -> void:
	_net.net_match_event(MatchWireEvents.STATE_CHANGED, [])
	_net.net_match_event(MatchWireEvents.STATE_CHANGED, ["PLAYING"])
	_net.net_match_event(MatchWireEvents.STATE_CHANGED, [Match.State.END, Match.State.END])
	assert_eq(Match.state(), Match.State.PLAYING)


func test_countdown_with_bad_payloads_is_refused() -> void:
	_net.net_match_event(MatchWireEvents.COUNTDOWN, [])
	_net.net_match_event(MatchWireEvents.COUNTDOWN, ["3"])
	_net.net_match_event(MatchWireEvents.COUNTDOWN, [3, 3])
	assert_signal_not_emitted(Events, "countdown_tick")


func test_a_valid_state_change_reaches_the_replica() -> void:
	_net.net_match_event(MatchWireEvents.STATE_CHANGED, [Match.State.SUDDEN_DEATH])
	assert_eq(Match.state(), Match.State.SUDDEN_DEATH)


func test_valid_events_reach_the_events_bus() -> void:
	var cases: Dictionary = _valid_cases()
	for event: StringName in cases.keys():
		var case: Dictionary = cases[event]
		_net.net_match_event(event, case["args"])
		var signal_name: String = case["signal"]
		assert_signal_emitted_with_parameters(Events, signal_name, case["params"], 0)


func test_a_rejection_naming_another_seat_is_not_sounded() -> void:
	_net.net_match_event(MatchWireEvents.PLACEMENT_REJECTED, [0, &"not_yours"])
	_net.net_match_event(MatchWireEvents.PLACEMENT_RELOCATED, [0, Vector2(1.0, 1.0)])
	assert_signal_not_emitted(Events, "placement_rejected")
	assert_signal_not_emitted(Events, "placement_relocated")


func test_a_rejection_reason_past_the_limit_is_refused() -> void:
	var too_long: StringName = StringName("r".repeat(MatchNetScript.REJECT_REASON_MAX_LENGTH + 1))
	_net.net_match_event(MatchWireEvents.PLACEMENT_REJECTED, [LOCAL_SLOT, too_long])
	assert_signal_not_emitted(Events, "placement_rejected")


func test_a_slot_outside_the_roster_is_refused() -> void:
	_net.net_match_event(MatchWireEvents.QOL_FEED, [99, 1, false])
	_net.net_match_event(MatchWireEvents.QOL_FEED, [-1, 1, false])
	assert_signal_not_emitted(Events, "qol_feed_changed")


func test_a_cat_longer_than_the_limit_is_refused_and_a_valid_one_is_not() -> void:
	var limit: float = NetConfig.new().cat_duration_max_s
	_net.net_match_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3.ZERO, limit + 1.0])
	_net.net_match_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3.ZERO, 0.0])
	_net.net_match_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3(INF, 0.0, 0.0), 1.0])
	assert_signal_not_emitted(Events, "cat_started")
	assert_null(Match.active_cat(), "no refused cat started")
	_net.net_match_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3.ZERO, 1.0])
	assert_signal_emitted_with_parameters(Events, "cat_started", [1, 0, Vector3.ZERO, 1.0])


func test_a_host_refuses_every_client_bound_event() -> void:
	_net.set_providers(FakeNet.host({}, [0]), Match)
	for event: StringName in [MatchWireEvents.QOL_FEED, MatchWireEvents.PLACEMENT_REJECTED, MatchWireEvents.PLACEMENT_RELOCATED]:
		var case: Dictionary = _valid_cases()[event]
		_net.net_match_event(event, case["args"])
	assert_signal_not_emitted(Events, "qol_feed_changed")
	assert_signal_not_emitted(Events, "placement_rejected")
	assert_signal_not_emitted(Events, "placement_relocated")


# --- a spy MatchReplicaPort bound through bind_replica ------------------------------------------


## Records every write the applier makes; answers true to the writes that answer.
class SpyReplica extends RefCounted:
	var calls: Array[Array] = []

	func _note(method: StringName, args: Array) -> void:
		calls.append([method, args])

	func apply_replicated_state_change(a: int) -> void: _note(&"apply_replicated_state_change", [a])
	func apply_replicated_countdown(a: int) -> void: _note(&"apply_replicated_countdown", [a])
	func apply_replicated_feed(a: int, b: StringName, c: StringName, d: int, e: float = -1.0, f: bool = false) -> void: _note(&"apply_replicated_feed", [a, b, c, d, e, f])
	func apply_replicated_turn(a: int) -> void: _note(&"apply_replicated_turn", [a])
	func apply_replicated_elimination(a: int, b: int = -1) -> void: _note(&"apply_replicated_elimination", [a, b])
	func apply_replicated_mode_state(a: Dictionary) -> void: _note(&"apply_replicated_mode_state", [a])
	func apply_replicated_gift_spawned(a: int, b: Vector2) -> void: _note(&"apply_replicated_gift_spawned", [a, b])
	func apply_replicated_gift_flight(a: int, b: Vector3, c: Vector3) -> void: _note(&"apply_replicated_gift_flight", [a, b, c])
	func apply_replicated_gift_landed(a: int, b: Vector3) -> void: _note(&"apply_replicated_gift_landed", [a, b])
	func apply_replicated_gift_claimed(a: int, b: int, c: StringName) -> void: _note(&"apply_replicated_gift_claimed", [a, b, c])
	func apply_replicated_gift_expired(a: int) -> void: _note(&"apply_replicated_gift_expired", [a])
	func apply_replicated_gift_slot(a: int, b: Array, c: StringName, d: StringName) -> void: _note(&"apply_replicated_gift_slot", [a, b, c, d])
	func apply_replicated_qol(a: int, b: int, c: bool) -> void: _note(&"apply_replicated_qol", [a, b, c])
	func apply_replicated_special_consumed(a: int, b: StringName) -> void: _note(&"apply_replicated_special_consumed", [a, b])
	func apply_replicated_territory(a: PackedInt32Array, _b: PackedByteArray, _c: PackedByteArray, _d: bool, _e: PackedFloat32Array = PackedFloat32Array(), _f: PackedFloat32Array = PackedFloat32Array(), _g: PackedFloat32Array = PackedFloat32Array(), _h: PackedInt32Array = PackedInt32Array(), _i: PackedVector2Array = PackedVector2Array(), _j: PackedFloat32Array = PackedFloat32Array(), _k: bool = false) -> void: _note(&"apply_replicated_territory", [a])
	func apply_replicated_glue_charges(a: int, b: int, c: int) -> bool:
		_note(&"apply_replicated_glue_charges", [a, b, c])
		return true
	func apply_replicated_block_owner(a: int, b: int) -> bool:
		_note(&"apply_replicated_block_owner", [a, b])
		return true
	func apply_replicated_cat_start(a: int, b: int, c: Vector3, d: float) -> bool:
		_note(&"apply_replicated_cat_start", [a, b, c, d])
		return true
	func apply_replicated_cat_state(a: int, b: Vector3, c: Vector3, d: Vector3, e: float) -> void: _note(&"apply_replicated_cat_state", [a, b, c, d, e])
	func end_cat(a: int) -> void: _note(&"end_cat", [a])


## The applier the game uses (a child of MatchNet), with the spy bound as its write port.
func _spied_applier(spy: SpyReplica) -> Node:
	_net.late_activate()
	var applier: Node = _net.get_node("MatchEventApplier")
	applier.bind_replica(MatchReplicaPort.new(spy))
	return applier


func _port_cases() -> Dictionary:
	return {
		MatchWireEvents.STATE_CHANGED: {"args": [Match.State.SUDDEN_DEATH], "call": &"apply_replicated_state_change", "params": [Match.State.SUDDEN_DEATH]},
		MatchWireEvents.COUNTDOWN: {"args": [2], "call": &"apply_replicated_countdown", "params": [2]},
		MatchWireEvents.TURN_CHANGED: {"args": [0], "call": &"apply_replicated_turn", "params": [LOCAL_SLOT]},
		MatchWireEvents.FEED_ISSUED: {"args": [1, &"cube", &"domino", 9, 5.5, true], "call": &"apply_replicated_feed", "params": [1, &"cube", &"domino", 9, 5.5, true]},
		MatchWireEvents.QOL_FEED: {"args": [0, 2, true], "call": &"apply_replicated_qol", "params": [0, 2, true]},
		MatchWireEvents.PLAYER_ELIMINATED: {"args": [0, 0, 1], "call": &"apply_replicated_elimination", "params": [0, 1]},
		MatchWireEvents.GLUE_CHARGES: {"args": [0, 3, 1], "call": &"apply_replicated_glue_charges", "params": [0, 3, 1]},
		MatchWireEvents.BLOCK_OWNER_CHANGED: {"args": [5, 0], "call": &"apply_replicated_block_owner", "params": [5, 0]},
		MatchWireEvents.CAT_STARTED: {"args": [1, 0, Vector3.ZERO, 1.0], "call": &"apply_replicated_cat_start", "params": [1, 0, Vector3.ZERO, 1.0]},
		MatchWireEvents.CAT_ENDED: {"args": [1], "call": &"end_cat", "params": [1]},
		MatchWireEvents.SPECIAL_CONSUMED: {"args": [1, MatchGifts.PENDING_SPECIAL_ID], "call": &"apply_replicated_special_consumed", "params": [1, MatchGifts.PENDING_SPECIAL_ID]},
		MatchWireEvents.GIFT_EXPIRED: {"args": [7], "call": &"apply_replicated_gift_expired", "params": [7]},
		MatchWireEvents.GIFT_SPAWNED: {"args": [8, Vector2(1.0, 2.0)], "call": &"apply_replicated_gift_spawned", "params": [8, Vector2(1.0, 2.0)]},
	}


func test_valid_args_reach_the_bound_port_and_are_accepted() -> void:
	var spy: SpyReplica = SpyReplica.new()
	var applier: Node = _spied_applier(spy)
	var cases: Dictionary = _port_cases()
	for event: StringName in cases.keys():
		var case: Dictionary = cases[event]
		spy.calls.clear()
		assert_true(applier.apply_event(event, case["args"]), "%s is accepted" % event)
		assert_eq(spy.calls.size(), 1, "%s makes one write" % event)
		if spy.calls.size() == 1:
			assert_eq(spy.calls[0], [case["call"], case["params"]], "%s reaches %s" % [event, case["call"]])


func test_malformed_args_are_refused_and_never_reach_the_port() -> void:
	var spy: SpyReplica = SpyReplica.new()
	var applier: Node = _spied_applier(spy)
	for event: StringName in _event_names():
		var shape: Array = MatchWireEvents.shape_of(event)
		var wrong: Array = []
		for _i: int in range(shape.size()):
			wrong.append(WRONG_TYPE)
		assert_false(applier.apply_event(event, []), "%s with no args" % event)
		assert_false(applier.apply_event(event, wrong), "%s with the wrong types" % event)
		assert_false(applier.apply_event(event, wrong + [0]), "%s with one extra" % event)
	var cases: Dictionary = _port_cases()
	for event: StringName in cases.keys():
		var valid: Array = (cases[event] as Dictionary)["args"]
		assert_false(applier.apply_event(event, valid.slice(0, valid.size() - 1)), "%s one short" % event)
	assert_eq(spy.calls.size(), 0, "nothing malformed was written")


func test_the_four_argument_feed_event_is_malformed() -> void:
	var spy: SpyReplica = SpyReplica.new()
	var applier: Node = _spied_applier(spy)
	assert_false(applier.apply_event(MatchWireEvents.FEED_ISSUED, [1, &"cube", &"domino", 9]))
	assert_eq(spy.calls.size(), 0)


func test_an_unknown_event_is_refused() -> void:
	var applier: Node = _spied_applier(SpyReplica.new())
	assert_false(applier.apply_event(&"not_an_event", [1]))


func test_values_the_client_cannot_trust_are_refused_through_the_port() -> void:
	var spy: SpyReplica = SpyReplica.new()
	var applier: Node = _spied_applier(spy)
	assert_false(applier.apply_event(MatchWireEvents.QOL_FEED, [99, 1, false]), "slot outside the roster")
	assert_false(applier.apply_event(MatchWireEvents.GLUE_CHARGES, [0, 3, 0]), "revision must be positive")
	assert_false(applier.apply_event(MatchWireEvents.BLOCK_OWNER_CHANGED, [5, -1]), "owner slot below zero")
	assert_false(applier.apply_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3.ZERO, NetConfig.new().cat_duration_max_s + 1.0]), "cat past the cap")
	assert_false(applier.apply_event(MatchWireEvents.CAT_STARTED, [1, 0, Vector3(INF, 0.0, 0.0), 1.0]), "non-finite cat position")
	assert_eq(spy.calls.size(), 0)


func test_a_host_applies_nothing_it_receives() -> void:
	Match._net_provider = FakeNet.host({}, [0])
	_net.set_providers(Match._net_provider, Match)
	var spy: SpyReplica = SpyReplica.new()
	var applier: Node = _spied_applier(spy)
	assert_false(applier.apply_event(MatchWireEvents.QOL_FEED, [0, 1, false]))
	assert_false(applier.apply_event(MatchWireEvents.CAT_ENDED, [1]))
	assert_eq(spy.calls.size(), 0)


# --- the host-side mirror, through spy Seams ----------------------------------------------------


var _sent_to_peer: Array[Array] = []
var _broadcast: Array[Array] = []


func _mirror(host: bool) -> MatchEventMirror:
	_sent_to_peer.clear()
	_broadcast.clear()
	var seams: MatchIntentGateway.Seams = MatchIntentGateway.Seams.new()
	seams.can_send = func() -> bool: return true
	seams.send_to_host = func(_method: StringName, _args: Array) -> void: pass
	seams.send_to_peer = func(peer_id: int, method: StringName, args: Array) -> bool:
		_sent_to_peer.append([peer_id, method, args])
		return true
	seams.broadcast = func(method: StringName, args: Array) -> void: _broadcast.append([method, args])
	var fake: FakeNet = FakeNet.host({1: 0, 2: 1}, [0]) if host else FakeNet.client(1)
	fake.slots_by_peer = {1: 0, 2: 1}
	var mirror: MatchEventMirror = MatchEventMirror.new(seams)
	mirror.bind_ports(
		SessionPort.new(fake, PackedStringArray(["is_host", "is_local_slot", "peer_of_slot"])),
		MatchHostPort.new(Match)
	)
	return mirror


func test_a_relocation_goes_to_the_owning_peer_alone() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_placement_relocated(1, Vector2(3.0, -2.0))
	assert_eq(_broadcast.size(), 0, "never broadcast to every peer")
	assert_eq(_sent_to_peer, [[2, &"net_match_event", [MatchWireEvents.PLACEMENT_RELOCATED, [1, Vector2(3.0, -2.0)]]]] as Array[Array])


func test_a_relocation_for_the_hosts_own_seat_is_sent_nowhere() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_placement_relocated(0, Vector2(1.0, 1.0))
	assert_eq(_sent_to_peer.size(), 0)
	assert_eq(_broadcast.size(), 0)


func test_a_refusal_goes_to_the_owning_peer_alone() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	assert_true(mirror.on_placement_rejected(1, &"contested"))
	assert_false(mirror.on_placement_rejected(0, &"contested"), "the host's own seat is not sent a reply")
	assert_eq(_broadcast.size(), 0)
	assert_eq(_sent_to_peer, [[2, &"net_match_event", [MatchWireEvents.PLACEMENT_REJECTED, [1, &"contested"]]]] as Array[Array])


func test_a_glue_change_is_broadcast_with_the_wire_payload() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_block_glued(231, true)
	mirror.on_block_glued(231, false)
	assert_eq(_broadcast, [
		[&"net_match_event", [MatchWireEvents.BLOCK_GLUED, [231, true]]],
		[&"net_match_event", [MatchWireEvents.BLOCK_GLUED, [231, false]]],
	] as Array[Array])


func test_a_client_mirror_sends_nothing() -> void:
	var mirror: MatchEventMirror = _mirror(false)
	mirror.on_block_glued(231, true)
	mirror.on_countdown(3)
	mirror.on_placement_relocated(1, Vector2.ZERO)
	assert_eq(_broadcast.size() + _sent_to_peer.size(), 0)


func test_every_mirror_payload_has_the_shape_the_applier_expects() -> void:
	var mirror: MatchEventMirror = _mirror(true)
	mirror.on_countdown(3)
	mirror.on_turn_changed(0)
	mirror.on_qol_feed(0, 1, false)
	mirror.on_match_won(1)
	mirror.on_gift_spawned(7, Vector2.ONE)
	mirror.on_gift_expired(7)
	mirror.on_special_consumed(1, &"bomb")
	mirror.on_glue_charges(0, 2, 1)
	mirror.on_block_owner_changed(5, 0)
	mirror.on_block_frozen(5, true)
	mirror.on_cat_started(1, 0, Vector3.ZERO, 1.0)
	mirror.on_cat_ended(1)
	mirror.on_player_eliminated(0, 0)
	mirror.on_feed_issued(1, &"cube", &"domino")
	assert_eq(_broadcast.size(), 14)
	for sent: Array in _broadcast:
		var payload: Array = sent[1]
		assert_true(WireLimits.args_shape_ok(payload[1], MatchWireEvents.shape_of(payload[0])), "%s matches its row" % payload[0])
