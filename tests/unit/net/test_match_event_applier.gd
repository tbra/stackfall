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
	_net.set_providers(FakeNet.client(LOCAL_SLOT), Match)
	watch_signals(Events)


func after_each() -> void:
	if _net != null and is_instance_valid(_net):
		_net.set_providers(null, null)
	_net = null
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
		MatchWireEvents.PLAYER_ELIMINATED: {"args": [0, 0], "signal": "player_eliminated", "params": [0, 0]},
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
