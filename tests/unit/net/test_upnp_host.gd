extends GutTest
## Bontago-1pi.164: hosting with a FAKE UPnP backend (the real router is never touched), the lobby
## join-code row, and joining over loopback ENet by decoded join code.

const _NET_SCRIPT: GDScript = preload("res://autoload/Net.gd")
const _WAIT_MSEC: int = 6000


class FakeBackend extends UpnpBackend:
	var delay_msec: int = 0
	var address: String = "81.9.44.7"
	var fail_reason: String = ""
	var unsupported: bool = false
	var opened_port: int = 0
	var closed: int = 0
	var renews: int = 0

	func open_port(port: int, _config: UpnpConfig) -> Dictionary:
		if delay_msec > 0:
			OS.delay_msec(delay_msec)
		if unsupported:
			return {"ok": false, "address": "", "reason": "n/a", "unsupported": true}
		if fail_reason != "":
			return {"ok": false, "address": "", "reason": fail_reason, "unsupported": false}
		opened_port = port
		return {"ok": true, "address": address, "reason": "", "unsupported": false}

	func renew_port(_port: int, _config: UpnpConfig) -> bool:
		renews += 1
		return true

	func close_port(port: int) -> void:
		if opened_port == port:
			closed += 1
			opened_port = 0


var _nets: Array[Variant] = []


func _make_net(node_name: String) -> Variant:
	var node: Node = _NET_SCRIPT.new()
	node.name = node_name
	var path: NodePath = NodePath(String(get_path()) + "/" + node_name)
	get_tree().set_multiplayer(MultiplayerAPI.create_default_interface(), path)
	add_child_autofree(node)
	_nets.append(node)
	return node


func after_each() -> void:
	for n: Variant in _nets:
		if is_instance_valid(n):
			n.leave()
	_nets.clear()
	await get_tree().process_frame
	await get_tree().process_frame


func _wait_for(cond: Callable, msec: int = _WAIT_MSEC) -> bool:
	var deadline: int = Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < deadline:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _host_with(backend: FakeBackend, node_name: String = "HostNet") -> Variant:
	var net: Variant = _make_net(node_name)
	net.upnp_backend_factory = func() -> UpnpBackend: return backend
	return net


func test_opened_state_and_join_code() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	var port: int = AgentProbe.free_udp_port()
	assert_eq(net.host_game(port, "H"), OK)
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.OPENED))
	assert_eq(backend.opened_port, port)
	var decoded: Dictionary = JoinCode.decode(net.upnp_join_code())
	assert_eq(str(decoded["address"]), "81.9.44.7")
	assert_eq(int(decoded["port"]), port)


func test_private_address_is_a_failure() -> void:
	var backend: FakeBackend = FakeBackend.new()
	backend.address = "192.168.1.9"
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.FAILED))
	assert_string_contains(net.upnp_failure_reason(), "non-public")


func test_slow_router_never_stalls_the_caller() -> void:
	var backend: FakeBackend = FakeBackend.new()
	backend.delay_msec = 800
	var net: Variant = _host_with(backend)
	var t0: int = Time.get_ticks_msec()
	net.host_game(AgentProbe.free_udp_port(), "H")
	var elapsed: int = Time.get_ticks_msec() - t0
	assert_lt(elapsed, 400, "host_game returned without waiting for the router")
	assert_eq(net.upnp_state(), UpnpRunner.State.PENDING)
	var frames: int = 0
	while net.upnp_state() == UpnpRunner.State.PENDING and frames < 100000:
		await get_tree().process_frame
		frames += 1
	assert_eq(net.upnp_state(), UpnpRunner.State.OPENED)
	assert_gt(frames, 0)


func test_mapping_removed_when_hosting_stops() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.OPENED))
	net.leave()
	assert_eq(net.upnp_state(), UpnpRunner.State.IDLE)
	assert_eq(net.upnp_join_code(), "")
	assert_true(await _wait_for(func() -> bool: return backend.closed == 1))


func test_quit_removes_the_mapping_synchronously() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.OPENED))
	net._exit_tree()
	assert_eq(backend.closed, 1)


func test_headless_bot_and_private_hosts_never_try_upnp() -> void:
	var calls: Array[int] = [0]
	var net: Variant = _make_net("BotNet")
	net.upnp_backend_factory = func() -> UpnpBackend:
		calls[0] += 1
		return FakeBackend.new()
	net.host_game(AgentProbe.free_udp_port(), "Bot", true, false)
	net.leave()
	net.host_game(0, "Priv", false)
	net.leave()
	assert_eq(calls[0], 0)
	assert_eq(net.upnp_state(), UpnpRunner.State.IDLE)


func test_join_by_code_connects_over_loopback() -> void:
	var host: Variant = _make_net("HostNet")
	var client: Variant = _make_net("ClientNet")
	var port: int = AgentProbe.free_udp_port()
	assert_eq(host.host_game(port, "Hostie"), OK)
	var code: String = JoinCode.encode("127.0.0.1", port)
	var resolved: Dictionary = MainMenu.resolve_join_text(code)
	assert_true(bool(resolved["valid"]))
	assert_eq(client.join_game(str(resolved["address"]), int(resolved["port"]), "Clienty"), OK)
	assert_true(await _wait_for(func() -> bool: return host.peer_ids().size() == 2 and client.local_slot() == 1))

