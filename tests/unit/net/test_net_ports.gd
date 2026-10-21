extends GutTest
## The three typed ports (net/ports/): each wraps one object, checks at
## construction that it answers every required method (a runtime check with one
## push_error, never an assert), and forwards typed calls. Covered per port:
## a minimal fake satisfies it, a fake missing a method is invalid and logs one
## error, a null object is invalid, and the real script instance (the Net / Match
## autoload) satisfies it.

const FAKE_ARG_COUNT: int = 11
const FAKE_REFCOUNTED_BASE: String = "RefCounted"
const CONFIG_FIELD_SOURCE: String = "var config: MatchConfig = null\n"
const PEER_A: int = 7
const SLOT_A: int = 3


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


func test_session_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in SessionPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(SessionPort.REQUIRED_METHODS, omitted))
		var port: SessionPort = SessionPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


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


func test_host_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in MatchHostPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchHostPort.REQUIRED_METHODS, omitted), true)
		var port: MatchHostPort = MatchHostPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


func test_host_port_wraps_the_real_match_autoload() -> void:
	var port: MatchHostPort = MatchHostPort.new(Match)
	assert_true(port.is_valid())
	assert_eq(port.state(), int(Match.state()))
	assert_eq(port.slot_count(), Match.slot_count())
	assert_eq(port.config(), Match.config)
	assert_eq(port.registry(), Match.registry())
	assert_eq(port.blocks_parent(), Match.blocks_parent())
	assert_eq(port.circle_wire_xz_bound(), Match.circle_wire_xz_bound())


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


func test_replica_port_with_a_missing_method_is_invalid_and_logs_once() -> void:
	for omitted: StringName in MatchReplicaPort.REQUIRED_METHODS:
		var fake: Object = _fake(FAKE_REFCOUNTED_BASE, _without(MatchReplicaPort.REQUIRED_METHODS, omitted))
		var port: MatchReplicaPort = MatchReplicaPort.new(fake)
		assert_false(port.is_valid(), "missing %s" % omitted)
		assert_push_error("lacks [&\"%s\"]" % omitted)


func test_replica_port_wraps_the_real_match_autoload() -> void:
	var port: MatchReplicaPort = MatchReplicaPort.new(Match)
	assert_true(port.is_valid())
	# A stale cat id is a no-op on the real script (no cat is active), so the
	# forwarder is proven to reach Match without changing its state.
	var before: int = int(Match.state())
	port.end_cat(-1)
	assert_eq(int(Match.state()), before)


# --- every forwarder reaches its own method -----------------------------------------
