extends GutTest
## SessionPort through its public surface: a real Net wrapped by the port (offline answers,
## then a hosted session with one real joiner over loopback ENet, each Net on its own
## MultiplayerAPI as test_kick_broadcast.gd does), the invalid-port rules, and the contract
## of the FakeSessionPort spy every other test uses in place of a Net.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _JOIN_WAIT_S: float = 10.0
const _HOST_NAME: String = "Hostie"
const _JOINER_NAME: String = "Joiny"
const _HOST_PEER: int = 1
const _UNKNOWN_PEER: int = 4242
const _STATS_KEY: String = "snapshot_last_bytes"
const _STATS_VALUE: int = 1234
## SessionPort methods whose answer the spy inherits rather than overrides.
const _INHERITED_BY_SPY: Array[StringName] = [&"timeout_leave_reason"]

var _roots: int = 0


## An isolated Net instance on its own MultiplayerAPI, offline. Variant-typed: Net has no class_name.
func _make_net(node_name: String) -> Node:
	_roots += 1
	var root: Node = Node.new()
	root.name = "%sRoot%d" % [node_name, _roots]
	get_tree().set_multiplayer(
		MultiplayerAPI.create_default_interface(), NodePath(String(get_path()) + "/" + root.name))
	add_child_autofree(root)
	var net: Node = _NET_SCRIPT.new()
	net.name = "Net"
	root.add_child(net)
	return net


## A host Net plus one joiner Net seated in slot 1. Returns [host, joiner] or an empty array.
func _make_session() -> Array[Node]:
	var host: Node = _make_net("H")
	if host.host_game(AgentProbe.free_udp_port(), _HOST_NAME, false) != OK:
		return []
	host.set_accepting_joins(true)
	var joiner: Node = _make_net("J")
	if joiner.join_game("127.0.0.1", host.host_port(), _JOINER_NAME) != OK:
		return []
	var seated: bool = await wait_until(func() -> bool:
		return joiner.is_client() and joiner.local_slot() == 1 and host.peer_ids().size() == 2,
		_JOIN_WAIT_S)
	if not seated:
		return []
	var pair: Array[Node] = [host, joiner]
	return pair


func _end_session(pair: Array[Node]) -> void:
	for net: Node in pair:
		if is_instance_valid(net):
			net.leave()
	await get_tree().process_frame
	await get_tree().process_frame


# --- real Net, offline ---------------------------------------------------------

func test_offline_net_is_valid_and_answers_as_the_offline_host() -> void:
	var port: SessionPort = SessionPort.new(_make_net("O"))
	assert_true(port.is_valid())
	assert_true(port.is_host(), "offline plays as the host")
	assert_false(port.is_client())
	assert_true(port.is_offline())

func test_offline_net_slots_and_peers_are_empty() -> void:
	var port: SessionPort = SessionPort.new(_make_net("O"))
	assert_eq(port.local_slot(), 0)
	assert_eq(port.slot_of_peer(_HOST_PEER), -1)
	assert_eq(port.peer_of_slot(0), -1)
	assert_eq(port.peer_ids().size(), 0)
	assert_eq(port.peer_info(_HOST_PEER), {})
	assert_false(port.is_peer_disconnecting(_HOST_PEER))

func test_offline_net_drives_every_slot_locally() -> void:
	var port: SessionPort = SessionPort.new(_make_net("O"))
	assert_true(port.is_local_slot(0))
	assert_true(port.is_local_slot(3), "offline local play drives every seat")

func test_offline_kick_peer_is_a_no_op_and_report_stats_reaches_the_net() -> void:
	var net: Node = _make_net("O")
	var port: SessionPort = SessionPort.new(net)
	port.kick_peer(_UNKNOWN_PEER, port.timeout_leave_reason())
	assert_eq(net.peer_ids().size(), 0)
	port.report_stats(&"test", {_STATS_KEY: _STATS_VALUE})
	assert_eq(int((net.stats() as Dictionary)[_STATS_KEY]), _STATS_VALUE, "the port folds counters into the Net's stats()")

func test_timeout_leave_reason_is_the_net_timeout_value() -> void:
	var port: SessionPort = SessionPort.new(_make_net("O"))
	assert_eq(port.timeout_leave_reason(), int(NetIds.LeaveReason.TIMEOUT))


# --- real Net, mode_changed ----------------------------------------------------

func test_mode_changed_is_forwarded_from_the_net_to_the_port() -> void:
	var net: Node = _make_net("M")
	var port: SessionPort = SessionPort.new(net)
	watch_signals(port)
	assert_eq(net.host_game(AgentProbe.free_udp_port(), _HOST_NAME, false), OK)
	assert_signal_emitted_with_parameters(port, "mode_changed", [net.mode()])
	assert_ne(net.mode(), 0, "hosting left offline mode")
	net.leave()
	assert_signal_emit_count(port, "mode_changed", 2)
	assert_signal_emitted_with_parameters(port, "mode_changed", [0])

func test_a_port_without_follow_net_does_not_hear_the_net() -> void:
	var net: Node = _make_net("M")
	var port: SessionPort = SessionPort.new(net, false)
	watch_signals(port)
	net.host_game(AgentProbe.free_udp_port(), _HOST_NAME, false)
	assert_signal_not_emitted(port, "mode_changed")
	net.leave()


# --- real Net, hosted with a joiner --------------------------------------------

func test_hosted_net_answers_host_slots_and_roster() -> void:
	var pair: Array[Node] = await _make_session()
	assert_eq(pair.size(), 2, "the loopback session came up")
	if pair.size() != 2:
		return
	var port: SessionPort = SessionPort.new(pair[0])
	assert_true(port.is_host())
	assert_false(port.is_client())
	assert_false(port.is_offline())
	assert_eq(port.local_slot(), 0)
	assert_true(port.is_local_slot(0))
	assert_false(port.is_local_slot(1), "the joiner's seat is not driven here")
	assert_false(port.is_local_slot(-1))
	var joiner_peer: int = int((pair[1] as Node).multiplayer.get_unique_id())
	assert_eq(port.slot_of_peer(joiner_peer), 1)
	assert_eq(port.peer_of_slot(1), joiner_peer)
	assert_eq(port.slot_of_peer(_UNKNOWN_PEER), -1)
	assert_eq(port.peer_of_slot(7), -1)
	var ids: PackedInt32Array = port.peer_ids()
	assert_eq(ids.size(), 2)
	assert_true(ids.has(_HOST_PEER))
	assert_true(ids.has(joiner_peer))
	var info: Dictionary = port.peer_info(joiner_peer)
	assert_eq(info.get("name"), _JOINER_NAME)
	assert_eq(int(info.get("slot_id", -2)), 1)
	assert_eq(port.peer_info(_UNKNOWN_PEER), {})
	await _end_session(pair)

func test_joined_net_answers_as_a_client() -> void:
	var pair: Array[Node] = await _make_session()
	assert_eq(pair.size(), 2, "the loopback session came up")
	if pair.size() != 2:
		return
	var port: SessionPort = SessionPort.new(pair[1])
	assert_true(port.is_client())
	assert_false(port.is_host())
	assert_false(port.is_offline())
	assert_eq(port.local_slot(), 1)
	assert_true(port.is_local_slot(1))
	assert_false(port.is_local_slot(0))
	assert_eq(port.peer_of_slot(0), _HOST_PEER)
	await _end_session(pair)

func test_kick_peer_removes_the_peer_and_carries_the_reason() -> void:
	var pair: Array[Node] = await _make_session()
	assert_eq(pair.size(), 2, "the loopback session came up")
	if pair.size() != 2:
		return
	var port: SessionPort = SessionPort.new(pair[0])
	var joiner_peer: int = int((pair[1] as Node).multiplayer.get_unique_id())
	assert_false(port.is_peer_disconnecting(joiner_peer))
	watch_signals(Events)
	port.kick_peer(joiner_peer, port.timeout_leave_reason())
	assert_signal_emitted_with_parameters(
		Events, "net_peer_left", [joiner_peer, 1, int(NetIds.LeaveReason.TIMEOUT)])
	assert_eq(port.slot_of_peer(joiner_peer), -1, "the kicked peer lost its seat")
	assert_false(port.peer_ids().has(joiner_peer))
	assert_true(port.is_peer_disconnecting(joiner_peer), "the transport still holds it until the disconnect completes")
	await _end_session(pair)

func test_report_stats_on_a_hosted_net_reaches_its_stats() -> void:
	var host: Node = _make_net("H")
	assert_eq(host.host_game(AgentProbe.free_udp_port(), _HOST_NAME, false), OK)
	var port: SessionPort = SessionPort.new(host)
	port.report_stats(&"test", {_STATS_KEY: _STATS_VALUE})
	assert_eq(int((host.stats() as Dictionary)[_STATS_KEY]), _STATS_VALUE)
	host.leave()


# --- isolated instances wrap independently -------------------------------------

func test_two_net_instances_wrap_independently() -> void:
	var hosting: Node = _make_net("A")
	var idle: Node = _make_net("B")
	var hosting_port: SessionPort = SessionPort.new(hosting)
	var idle_port: SessionPort = SessionPort.new(idle)
	watch_signals(hosting_port)
	watch_signals(idle_port)
	assert_eq(hosting.host_game(AgentProbe.free_udp_port(), _HOST_NAME, false), OK)
	assert_false(hosting_port.is_offline())
	assert_true(idle_port.is_offline(), "the other instance is untouched")
	assert_eq(hosting_port.peer_ids().size(), 1)
	assert_eq(idle_port.peer_ids().size(), 0)
	assert_signal_emitted(hosting_port, "mode_changed")
	assert_signal_not_emitted(idle_port, "mode_changed")
	hosting.leave()


# --- invalid and unspied ports -------------------------------------------------

func test_null_session_is_an_invalid_and_quiet_port() -> void:
	var port: SessionPort = SessionPort.new(null)
	assert_false(port.is_valid())

func test_null_session_with_follow_net_false_is_invalid_and_quiet() -> void:
	var port: SessionPort = SessionPort.new(null, false)
	assert_false(port.is_valid())


# --- FakeSessionPort contract --------------------------------------------------

func _public_methods(script: Script) -> Array[StringName]:
	var names: Array[StringName] = []
	for entry: Dictionary in script.get_script_method_list():
		var method_name: StringName = StringName(String(entry["name"]))
		if not String(method_name).begins_with("_"):
			names.append(method_name)
	return names


func test_spy_overrides_every_public_port_method() -> void:
	var spy_methods: Array[StringName] = _public_methods(FakeSessionPort)
	for method_name: StringName in _public_methods(SessionPort):
		if _INHERITED_BY_SPY.has(method_name):
			continue
		assert_true(spy_methods.has(method_name), "FakeSessionPort answers %s" % method_name)

func test_spy_is_valid_and_quiet_to_construct() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new(FakeNet.host({_HOST_PEER: 0}, [0]))
	assert_true(spy.is_valid())

func test_spy_answers_from_a_host_fake() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new(FakeNet.host({_HOST_PEER: 0, 7: 1}, [0]))
	assert_true(spy.is_host())
	assert_false(spy.is_client())
	assert_false(spy.is_offline())
	assert_eq(spy.local_slot(), 0)
	assert_true(spy.is_local_slot(0))
	assert_false(spy.is_local_slot(1))
	assert_eq(spy.slot_of_peer(7), 1)
	assert_eq(spy.peer_of_slot(1), 7)
	assert_eq(spy.peer_ids().size(), 2)
	assert_eq(int(spy.peer_info(7).get("slot_id", -2)), 1)
	assert_false(spy.is_peer_disconnecting(7))
	assert_eq(spy.timeout_leave_reason(), int(NetIds.LeaveReason.TIMEOUT))

func test_spy_answers_from_a_client_fake() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new(FakeNet.client(2))
	assert_true(spy.is_client())
	assert_false(spy.is_host())
	assert_eq(spy.local_slot(), 2)
	assert_true(spy.is_local_slot(2))

func test_spy_defaults_to_an_offline_session() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new()
	assert_true(spy.is_offline())
	assert_true(spy.is_host())

func test_spy_records_writes_in_order() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new(FakeNet.host({_HOST_PEER: 0, 7: 1}, [0]))
	spy.kick_peer(7, spy.timeout_leave_reason())
	spy.report_stats(&"snap", {"k": 1})
	assert_eq(spy.calls.size(), 2)
	assert_eq(spy.calls_to(&"kick_peer"), [[7, spy.timeout_leave_reason()]])
	assert_eq(spy.calls_to(&"report_stats"), [[&"snap", {"k": 1}]])
	assert_eq(spy.calls_to(&"is_host").size(), 0)

func test_spy_mode_changed_can_be_emitted_to_its_consumers() -> void:
	var spy: FakeSessionPort = FakeSessionPort.new()
	watch_signals(spy)
	spy.mode_changed.emit(1)
	assert_signal_emitted_with_parameters(spy, "mode_changed", [1])
