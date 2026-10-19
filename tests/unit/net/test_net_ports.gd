extends GutTest
## The three typed ports (net/ports/): each wraps one object, checks at
## construction that it answers every required method (a runtime check with one
## push_error, never an assert), and forwards typed calls. Covered per port:
## a minimal fake satisfies it, a fake missing a method is invalid and logs one
## error, a null object is invalid, and the real script instance (the Net / Match
## autoload) satisfies it.

const FAKE_ARG_COUNT: int = 11
const FAKE_NODE_BASE: String = "Node"
const FAKE_REFCOUNTED_BASE: String = "RefCounted"
const CONFIG_FIELD_SOURCE: String = "var config: MatchConfig = null\n"
const PEER_A: int = 7
const SLOT_A: int = 3
const FORWARD_ARG_BASE: int = 100
const FORWARD_FLOAT_BASE: float = 1.5
const FORWARD_NAME_PREFIX: String = "arg_"
const COLLABORATORS_SOURCE: String = "var _feed: Object = null\nvar _lifecycle: Object = null\n"
const LIFECYCLE_SOURCE: String = "var _match_timer_left: float = -1.0\n"
## Public port methods that do not forward to a same-named method of the adapted
## object (constants answered locally, a property read, a field write); each is
## asserted to exist so the list cannot rot.
const NOT_DIRECT_FORWARDERS: Dictionary = {
	"SessionPort": ["host_peer_id", "timeout_leave_reason"],
	"MatchHostPort": ["config"],
	"MatchReplicaPort": ["apply_replicated_match_timer"],
}
## TRANSITIONAL forwarders: port method -> [collaborator property, recorded name].
const COLLABORATOR_FORWARDERS: Dictionary = {
	"feed_knows_shape": ["_feed", "_shape_by_id"],
	"feed_claim_carrier_shape_id": ["_feed", "claim_carrier_shape_id"],
	"feed_gift_after_next_active": ["_feed", "gift_after_next_active"],
	"feed_staged_gift_shape_id": ["_feed", "staged_gift_shape_id"],
	"feed_note_special_triggered": ["_feed", "note_special_triggered"],
	"is_starting_match": ["_lifecycle", "is_starting_match"],
	"loading_gate_replay_args": ["_lifecycle", "loading_gate_replay_args"],
	"apply_replicated_next_gift": ["_feed", "apply_replicated_next_gift"],
	"apply_replicated_staged_gift": ["_feed", "apply_replicated_staged_gift"],
}


## Builds a throwaway script whose every listed method records its call in
## `calls` ([name, args]) and answers `results[name]` (null when unset), so a
## test can check that a port forwards each argument, in order, to the right
## method. `with_config` adds the `config` property the host port requires.
static func _fake(base: String, methods: Array[StringName], with_config: bool = false, extra_source: String = "") -> Object:
	var params: PackedStringArray = PackedStringArray()
	var arg_names: PackedStringArray = PackedStringArray()
	for index: int in range(FAKE_ARG_COUNT):
		params.append("a%d: Variant = null" % index)
		arg_names.append("a%d" % index)
	var source: String = "extends %s\n" % base
	source += "var calls: Array = []\n"
	source += "var results: Dictionary = {}\n"
	if with_config:
		source += CONFIG_FIELD_SOURCE
	source += extra_source
	for method_name: StringName in methods:
		source += "func %s(%s) -> Variant:\n" % [method_name, ", ".join(params)]
		source += "\tcalls.append([&\"%s\", [%s]])\n" % [method_name, ", ".join(arg_names)]
		source += "\treturn results.get(&\"%s\")\n" % method_name
	var script: GDScript = GDScript.new()
	script.source_code = source
	assert(script.reload() == OK, "the fake script compiles")
	return script.new() as Object


static func _without(methods: Array[StringName], omitted: StringName) -> Array[StringName]:
	var kept: Array[StringName] = []
	for method_name: StringName in methods:
		if method_name != omitted:
			kept.append(method_name)
	return kept


# --- SessionPort -------------------------------------------------------------

func test_session_port_accepts_the_repo_net_double() -> void:
	var fake: FakeNet = FakeNet.host({1: 0, PEER_A: SLOT_A}, [0] as Array[int])
	var port: SessionPort = SessionPort.new(fake)
	assert_true(port.is_valid())
	assert_true(port.is_host())
	assert_false(port.is_client())
	assert_false(port.is_offline())
	assert_eq(port.slot_of_peer(PEER_A), SLOT_A)
	assert_eq(port.peer_of_slot(SLOT_A), PEER_A)
	assert_true(port.is_local_slot(0))
	assert_eq(port.local_slot(), 0)
	assert_eq(port.peer_ids().size(), 2)
	assert_eq(int(port.peer_info(PEER_A).get("slot_id", -1)), SLOT_A)
	assert_false(port.is_peer_disconnecting(PEER_A), "a session without the method has no disconnecting peer")
	port.kick_peer(PEER_A, port.timeout_leave_reason())
	assert_eq(fake.kick_peer_calls.size(), 1)
	assert_eq(int(fake.kick_peer_calls[0]["peer_id"]), PEER_A)
	assert_eq(int(fake.kick_peer_calls[0]["reason"]), int(Net.LeaveReason.TIMEOUT))
	port.report_stats(&"snapshot", {"x": 1})


func test_session_port_accepts_a_minimal_node() -> void:
	var methods: Array[StringName] = SessionPort.REQUIRED_METHODS.duplicate()
	methods.append(SessionPort.OPTIONAL_DISCONNECTING_METHOD)
	var node: Node = _fake(FAKE_NODE_BASE, methods) as Node
	add_child_autofree(node)
	var port: SessionPort = SessionPort.new(node)
	assert_true(port.is_valid())
	node.results[&"is_host"] = true
	node.results[&"slot_of_peer"] = SLOT_A
	node.results[&"is_peer_disconnecting"] = true
	node.results[&"peer_ids"] = PackedInt32Array([1, PEER_A])
	node.results[&"peer_info"] = {"peer_id": PEER_A}
	assert_true(port.is_host())
	assert_eq(port.slot_of_peer(PEER_A), SLOT_A)
	assert_true(port.is_peer_disconnecting(PEER_A), "a session that implements the method is asked")
	assert_eq(port.peer_ids(), PackedInt32Array([1, PEER_A]))
	assert_eq(port.peer_info(PEER_A), {"peer_id": PEER_A})
	port.report_stats(&"snapshot", {"k": 2})
	assert_eq(node.calls.back(), [&"report_stats", [&"snapshot", {"k": 2}, null, null, null, null, null, null, null, null, null]])
	assert_eq(port.host_peer_id(), Net.HOST_PEER_ID)


func test_session_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in SessionPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(SessionPort.REQUIRED_METHODS, omitted))
		var port: SessionPort = SessionPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


func test_session_port_logs_exactly_one_error_per_invalid_object() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(SessionPort.REQUIRED_METHODS, &"peer_ids"))
	assert_false(SessionPort.new(fake).is_valid())
	assert_push_error_count(1)


func test_session_port_subset_binds_a_narrow_double() -> void:
	var narrow: Object = _fake(FAKE_REFCOUNTED_BASE, [&"is_host", &"slot_of_peer"] as Array[StringName])
	var subset: PackedStringArray = PackedStringArray(["is_host", "slot_of_peer"])
	var port: SessionPort = SessionPort.new(narrow, subset)
	assert_true(port.is_valid())
	narrow.results[&"is_host"] = true
	assert_true(port.is_host())
	assert_push_error_count(0)
	assert_false(SessionPort.new(narrow).is_valid(), "the full list still refuses the narrow double")
	assert_push_error_count(1)


func test_session_port_subset_with_an_unknown_name_is_invalid() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, SessionPort.REQUIRED_METHODS)
	var port: SessionPort = SessionPort.new(fake, PackedStringArray(["is_host", "not_a_port_method"]))
	assert_false(port.is_valid())
	assert_push_error("not_a_port_method")
	assert_push_error_count(1)


func test_session_port_subset_missing_a_named_method_is_invalid() -> void:
	var narrow: Object = _fake(FAKE_REFCOUNTED_BASE, [&"is_host"] as Array[StringName])
	assert_false(SessionPort.new(narrow, PackedStringArray(["is_host", "peer_ids"])).is_valid())
	assert_push_error("lacks [&\"peer_ids\"]")


func test_session_port_call_outside_the_subset_logs_once_and_answers_the_default() -> void:
	var narrow: Object = _fake(FAKE_REFCOUNTED_BASE, [&"is_host"] as Array[StringName])
	var port: SessionPort = SessionPort.new(narrow, PackedStringArray(["is_host"]))
	assert_true(port.is_valid())
	assert_eq(port.peer_ids(), PackedInt32Array())
	assert_eq(port.peer_ids(), PackedInt32Array())
	assert_eq(port.slot_of_peer(PEER_A), -1)
	assert_eq(port.peer_info(PEER_A), {})
	port.kick_peer(PEER_A, 0)
	assert_false(port.is_client())
	assert_push_error_count(5, "one error per missing method, not per call")
	assert_eq(narrow.calls.size(), 0)


func test_session_port_with_null_is_invalid() -> void:
	var port: SessionPort = SessionPort.new(null)
	assert_false(port.is_valid())
	assert_push_error("null")


func test_session_port_wraps_the_real_net_autoload() -> void:
	var port: SessionPort = SessionPort.new(Net)
	assert_true(port.is_valid())
	assert_eq(port.is_host(), Net.is_host())
	assert_eq(port.is_client(), Net.is_client())
	assert_eq(port.is_offline(), Net.is_offline())
	assert_eq(port.local_slot(), Net.local_slot())
	assert_eq(port.slot_of_peer(PEER_A), Net.slot_of_peer(PEER_A))
	assert_eq(port.peer_ids(), Net.peer_ids())
	assert_eq(port.is_peer_disconnecting(PEER_A), Net.is_peer_disconnecting(PEER_A))
	assert_eq(port.host_peer_id(), Net.HOST_PEER_ID)
	assert_eq(port.timeout_leave_reason(), int(Net.LeaveReason.TIMEOUT))


# --- MatchHostPort ---------------------------------------------------------------

func test_host_port_accepts_a_minimal_fake_and_forwards_arguments() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchHostPort.REQUIRED_METHODS, true)
	var port: MatchHostPort = MatchHostPort.new(fake)
	assert_true(port.is_valid())
	assert_null(port.config())
	var running: MatchConfig = MatchConfig.new()
	fake.config = running
	assert_eq(port.config(), running)
	fake.results[&"state"] = 4
	assert_eq(port.state(), 4)
	fake.results[&"request_place"] = &"refused"
	var quat: Quaternion = Quaternion(0.0, 1.0, 0.0, 0.0)
	var reason: StringName = port.request_place(SLOT_A, Vector3(1, 2, 3), 5, quat, true, 9)
	assert_eq(reason, &"refused")
	assert_eq(fake.calls.back()[1].slice(0, 6), [SLOT_A, Vector3(1, 2, 3), 5, quat, true, 9])
	fake.results[&"request_throw"] = &""
	port.request_throw(SLOT_A, Vector3.ONE, 2, quat, Vector3.UP, 8)
	assert_eq(fake.calls.back()[1].slice(0, 6), [SLOT_A, Vector3.ONE, 2, quat, Vector3.UP, 8])
	fake.results[&"is_pose_well_formed"] = true
	assert_true(port.is_pose_well_formed(Vector3.ZERO, 1, quat))
	assert_eq(fake.calls.back()[1].slice(0, 3), [Vector3.ZERO, 1, quat])
	fake.results[&"set_cat_target"] = true
	assert_true(port.set_cat_target(SLOT_A, Vector3.ONE))
	fake.results[&"territory_share"] = 0.25
	assert_eq(port.territory_share(1), 0.25)


func test_host_port_note_aim_is_a_no_op_without_the_method() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchHostPort.REQUIRED_METHODS, true)
	var port: MatchHostPort = MatchHostPort.new(fake)
	assert_true(port.is_valid(), "note_aim is optional")
	port.note_aim(SLOT_A, Vector3.FORWARD)
	assert_eq(fake.calls.size(), 0, "the double has no note_aim, so nothing is called")
	var with_aim: Array[StringName] = MatchHostPort.REQUIRED_METHODS.duplicate()
	with_aim.append(MatchHostPort.NOTE_AIM_METHOD)
	var aimed: Object = _fake(FAKE_REFCOUNTED_BASE, with_aim, true)
	MatchHostPort.new(aimed).note_aim(SLOT_A, Vector3.FORWARD)
	assert_eq(aimed.calls.back()[1].slice(0, 2), [SLOT_A, Vector3.FORWARD])


func test_host_port_private_collaborators_answer_defaults_when_absent() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchHostPort.REQUIRED_METHODS, true)
	var port: MatchHostPort = MatchHostPort.new(fake)
	assert_false(port.feed_knows_shape(&"cube"))
	assert_eq(port.feed_claim_carrier_shape_id(0), &"")
	assert_false(port.feed_gift_after_next_active())
	assert_eq(port.feed_staged_gift_shape_id(0), &"")
	port.feed_note_special_triggered()
	assert_false(port.is_starting_match())
	assert_eq(port.loading_gate_replay_args(), [])


func test_host_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in MatchHostPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchHostPort.REQUIRED_METHODS, omitted), true)
		var port: MatchHostPort = MatchHostPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


func test_host_port_logs_exactly_one_error_per_invalid_object() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchHostPort.REQUIRED_METHODS, &"raster"), true)
	assert_false(MatchHostPort.new(fake).is_valid())
	assert_push_error_count(1)


func test_host_port_without_the_config_property_is_invalid() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchHostPort.REQUIRED_METHODS, false)
	var port: MatchHostPort = MatchHostPort.new(fake)
	assert_false(port.is_valid())
	assert_push_error_count(1)


func test_host_port_with_null_is_invalid() -> void:
	assert_false(MatchHostPort.new(null).is_valid())
	assert_push_error("null")


func test_host_port_wraps_the_real_match_autoload() -> void:
	var port: MatchHostPort = MatchHostPort.new(Match)
	assert_true(port.is_valid())
	assert_eq(port.state(), int(Match.state()))
	assert_eq(port.slot_count(), Match.slot_count())
	assert_eq(port.config(), Match.config)
	assert_eq(port.registry(), Match.registry())
	assert_eq(port.replicator(), Match.replicator())
	assert_eq(port.circle_wire_xz_bound(), Match.circle_wire_xz_bound())


func test_host_port_subset_binds_the_repo_narrow_double() -> void:
	var narrow: FakeMatch = FakeMatch.new()
	var subset: PackedStringArray = PackedStringArray(["slot", "held_shape", "next_shape", "feed_seq", "request_place", "request_throw"])
	var port: MatchHostPort = MatchHostPort.new(narrow, subset)
	assert_true(port.is_valid())
	assert_push_error_count(0)
	assert_false(MatchHostPort.new(narrow).is_valid(), "the full list refuses the narrow double")
	assert_push_error_count(1)


func test_host_port_subset_with_an_unknown_name_is_invalid() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchHostPort.REQUIRED_METHODS, true)
	assert_false(MatchHostPort.new(fake, PackedStringArray(["state", "no_such_thing"])).is_valid())
	assert_push_error("no_such_thing")
	assert_push_error_count(1)


func test_host_port_subset_may_name_the_config_property() -> void:
	var with_config: Object = _fake(FAKE_REFCOUNTED_BASE, [&"state"] as Array[StringName], true)
	assert_true(MatchHostPort.new(with_config, PackedStringArray(["state", "config"])).is_valid())
	var without: Object = _fake(FAKE_REFCOUNTED_BASE, [&"state"] as Array[StringName], false)
	assert_false(MatchHostPort.new(without, PackedStringArray(["state", "config"])).is_valid())
	assert_push_error("lacks [&\"config\"]")


func test_host_port_call_outside_the_subset_logs_once_and_answers_the_default() -> void:
	var narrow: FakeMatch = FakeMatch.new()
	var port: MatchHostPort = MatchHostPort.new(narrow, PackedStringArray(["feed_seq"]))
	assert_true(port.is_valid())
	assert_eq(port.state(), 0)
	assert_eq(port.state(), 0)
	assert_null(port.config(), "FakeMatch has the config property, so reading it outside the subset is fine")
	assert_eq(port.default_ghost_origin(SLOT_A), Vector3.ZERO)
	assert_eq(port.gift_slot_contents(SLOT_A).size(), 0)
	assert_eq(port.gift_states().size(), 0)
	assert_false(port.request_use_gift_slot(SLOT_A))
	port.abort_match()
	assert_push_error_count(6, "one error per missing method, not per call")


# --- MatchReplicaPort -------------------------------------------------------------

func test_replica_port_accepts_a_minimal_fake_and_forwards_arguments() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchReplicaPort.REQUIRED_METHODS)
	var port: MatchReplicaPort = MatchReplicaPort.new(fake)
	assert_true(port.is_valid())
	port.apply_replicated_state_change(2)
	assert_eq(fake.calls.back()[0], &"apply_replicated_state_change")
	assert_eq(fake.calls.back()[1][0], 2)
	port.apply_replicated_feed(SLOT_A, &"cube", &"bar", 6)
	assert_eq(fake.calls.back()[1].slice(0, 6), [SLOT_A, &"cube", &"bar", 6, -1.0, false])
	port.apply_replicated_elimination(SLOT_A)
	assert_eq(fake.calls.back()[1].slice(0, 2), [SLOT_A, -1], "by_slot keeps Match's default")
	port.apply_replicated_territory(PackedInt32Array([1]), PackedByteArray([2]), PackedByteArray([3]), true)
	var territory_args: Array = fake.calls.back()[1]
	assert_eq(territory_args.size(), FAKE_ARG_COUNT)
	assert_eq(territory_args[3], true)
	assert_eq(territory_args[10], false, "argmax_mode default")
	fake.results[&"apply_replicated_glue_charges"] = true
	assert_true(port.apply_replicated_glue_charges(SLOT_A, 2, 5))
	fake.results[&"apply_replicated_cat_start"] = true
	assert_true(port.apply_replicated_cat_start(4, SLOT_A, Vector3.ONE, 1.5))
	port.end_cat(4)
	assert_eq(fake.calls.back()[0], &"end_cat")


func test_replica_port_private_collaborators_are_no_ops_when_absent() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchReplicaPort.REQUIRED_METHODS)
	var port: MatchReplicaPort = MatchReplicaPort.new(fake)
	var before: int = fake.calls.size()
	port.apply_replicated_next_gift(SLOT_A, &"cube")
	port.apply_replicated_staged_gift(SLOT_A, &"cube")
	port.apply_replicated_match_timer(12.0)
	assert_eq(fake.calls.size(), before)


func test_replica_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in MatchReplicaPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchReplicaPort.REQUIRED_METHODS, omitted))
		var port: MatchReplicaPort = MatchReplicaPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


func test_replica_port_logs_exactly_one_error_per_invalid_object() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchReplicaPort.REQUIRED_METHODS, &"end_cat"))
	assert_false(MatchReplicaPort.new(fake).is_valid())
	assert_push_error_count(1)


func test_replica_port_subset_binds_a_narrow_double_and_defaults_the_rest() -> void:
	var narrow: Object = _fake(FAKE_REFCOUNTED_BASE, [&"end_cat"] as Array[StringName])
	var port: MatchReplicaPort = MatchReplicaPort.new(narrow, PackedStringArray(["end_cat"]))
	assert_true(port.is_valid())
	port.end_cat(4)
	assert_eq(narrow.calls.size(), 1)
	assert_false(port.apply_replicated_glue_charges(SLOT_A, 1, 1))
	port.apply_replicated_turn(SLOT_A)
	assert_push_error_count(2)
	assert_false(MatchReplicaPort.new(narrow).is_valid())
	assert_push_error_count(3)


func test_replica_port_subset_with_an_unknown_name_is_invalid() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchReplicaPort.REQUIRED_METHODS)
	assert_false(MatchReplicaPort.new(fake, PackedStringArray(["end_cat", "bogus"])).is_valid())
	assert_push_error("bogus")
	assert_push_error_count(1)


func test_replica_port_with_null_is_invalid() -> void:
	assert_false(MatchReplicaPort.new(null).is_valid())
	assert_push_error("null")


func test_replica_port_wraps_the_real_match_autoload() -> void:
	var port: MatchReplicaPort = MatchReplicaPort.new(Match)
	assert_true(port.is_valid())
	# A stale cat id is a no-op on the real script (no cat is active), so the
	# forwarder is proven to reach Match without changing its state.
	var before: int = int(Match.state())
	port.end_cat(-1)
	assert_eq(int(Match.state()), before)


# --- every forwarder reaches its own method -----------------------------------------

## A typo in any `_call(&"name")` string must fail here: each public port method
## is called on a recording double and must record the same method name with the
## arguments it was given. The method list comes from the port script itself.
func test_session_port_forwards_every_public_method_to_its_own_name() -> void:
	var methods: Array[StringName] = SessionPort.REQUIRED_METHODS.duplicate()
	methods.append(SessionPort.OPTIONAL_DISCONNECTING_METHOD)
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, methods)
	_assert_forwards_every_method(SessionPort.new(fake), "SessionPort", fake)


func test_host_port_forwards_every_public_method_to_its_own_name() -> void:
	var methods: Array[StringName] = MatchHostPort.REQUIRED_METHODS.duplicate()
	methods.append(MatchHostPort.NOTE_AIM_METHOD)
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, methods, true, COLLABORATORS_SOURCE)
	fake._feed = _fake(FAKE_REFCOUNTED_BASE, [
		&"_shape_by_id", &"claim_carrier_shape_id", &"gift_after_next_active",
		&"staged_gift_shape_id", &"note_special_triggered",
	] as Array[StringName])
	fake._lifecycle = _fake(FAKE_REFCOUNTED_BASE, [&"is_starting_match", &"loading_gate_replay_args"] as Array[StringName])
	_assert_forwards_every_method(MatchHostPort.new(fake), "MatchHostPort", fake)


func test_replica_port_forwards_every_public_method_to_its_own_name() -> void:
	var fake: Object = _fake(FAKE_REFCOUNTED_BASE, MatchReplicaPort.REQUIRED_METHODS, false, COLLABORATORS_SOURCE)
	fake._feed = _fake(FAKE_REFCOUNTED_BASE, [&"apply_replicated_next_gift", &"apply_replicated_staged_gift"] as Array[StringName])
	fake._lifecycle = _fake(FAKE_REFCOUNTED_BASE, [] as Array[StringName], false, LIFECYCLE_SOURCE)
	var port: MatchReplicaPort = MatchReplicaPort.new(fake)
	_assert_forwards_every_method(port, "MatchReplicaPort", fake)
	port.apply_replicated_match_timer(12.5)
	assert_eq(fake._lifecycle._match_timer_left, 12.5, "the match clock lands in the lifecycle's field")


func _assert_forwards_every_method(port: RefCounted, port_name: String, fake: Object) -> void:
	var skipped: Array = NOT_DIRECT_FORWARDERS[port_name]
	var seen: Array[String] = []
	for entry: Dictionary in (port.get_script() as Script).get_script_method_list():
		var method_name: String = String(entry["name"])
		if method_name.begins_with("_") or method_name == "is_valid":
			continue
		seen.append(method_name)
		if skipped.has(method_name):
			continue
		var target: Object = fake
		var recorded_name: String = method_name
		if COLLABORATOR_FORWARDERS.has(method_name):
			var route: Array = COLLABORATOR_FORWARDERS[method_name]
			target = fake.get(StringName(route[0])) as Object
			recorded_name = String(route[1])
		target.results[StringName(recorded_name)] = _result_for(entry, method_name)
		var args: Array = _forward_args(entry)
		var calls_before: int = target.calls.size()
		port.callv(method_name, args)
		assert_eq(target.calls.size(), calls_before + 1, "%s.%s reached the adapted object once" % [port_name, method_name])
		if target.calls.size() != calls_before + 1:
			continue
		var recorded: Array = target.calls.back()
		assert_eq(String(recorded[0]), recorded_name, "%s.%s forwards to a method of its own name" % [port_name, method_name])
		assert_eq((recorded[1] as Array).slice(0, args.size()), args, "%s.%s forwards its arguments in order" % [port_name, method_name])
	for skipped_name: String in skipped:
		assert_true(seen.has(skipped_name), "%s still has the exempted method %s" % [port_name, skipped_name])
	assert_gt(seen.size(), skipped.size(), "the port script lists its public methods")


## Distinct, type-correct argument values so a swapped or dropped argument shows.
func _forward_args(entry: Dictionary) -> Array:
	var args: Array = []
	var index: int = 0
	for arg: Dictionary in entry["args"]:
		match int(arg["type"]):
			TYPE_INT:
				args.append(FORWARD_ARG_BASE + index)
			TYPE_FLOAT:
				args.append(FORWARD_FLOAT_BASE + float(index))
			TYPE_BOOL:
				args.append(true)
			TYPE_STRING_NAME:
				args.append(StringName("%s%d" % [FORWARD_NAME_PREFIX, index]))
			TYPE_VECTOR2:
				args.append(Vector2(index + 1, index + 2))
			TYPE_VECTOR3:
				args.append(Vector3(index + 1, index + 2, index + 3))
			TYPE_QUATERNION:
				args.append(Quaternion(0.0, 1.0, 0.0, 0.0))
			TYPE_DICTIONARY:
				args.append({"i": index})
			TYPE_ARRAY:
				args.append([index])
			TYPE_PACKED_INT32_ARRAY:
				args.append(PackedInt32Array([index]))
			TYPE_PACKED_BYTE_ARRAY:
				args.append(PackedByteArray([index]))
			TYPE_PACKED_FLOAT32_ARRAY:
				args.append(PackedFloat32Array([float(index)]))
			TYPE_PACKED_VECTOR2_ARRAY:
				args.append(PackedVector2Array([Vector2(index, index)]))
			_:
				args.append(null)
		index += 1
	return args


## A value of the type the port casts its answer to, so the forwarder under test
## completes without a cast error.
func _result_for(entry: Dictionary, method_name: String) -> Variant:
	var returns: Dictionary = entry["return"]
	match int(returns["type"]):
		TYPE_INT:
			return 0
		TYPE_FLOAT:
			return 0.0
		TYPE_BOOL:
			return false
		TYPE_STRING_NAME:
			return &""
		TYPE_VECTOR3:
			return Vector3.ZERO
		TYPE_DICTIONARY:
			return {}
		TYPE_PACKED_INT32_ARRAY:
			return PackedInt32Array()
		TYPE_ARRAY:
			if method_name == "gift_states":
				var dicts: Array[Dictionary] = []
				return dicts
			if method_name == "loading_gate_replay_args":
				return []
			var names: Array[StringName] = []
			return names
	return null
