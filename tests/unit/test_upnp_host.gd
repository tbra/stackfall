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


class StubNet extends RefCounted:
	var state: int = 0
	var code: String = ""
	var steam: bool = false
	func is_steam_session() -> bool:
		return steam
	func upnp_state() -> int:
		return state
	func upnp_join_code() -> String:
		return code
	func upnp_failure_reason() -> String:
		return "nope"
	func host_port() -> int:
		return 47778


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


func test_failed_and_unsupported_states() -> void:
	var failing: FakeBackend = FakeBackend.new()
	failing.fail_reason = "router said no"
	var net: Variant = _host_with(failing)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.FAILED))
	assert_eq(net.upnp_failure_reason(), "router said no")
	assert_eq(net.upnp_join_code(), "")
	var none: FakeBackend = FakeBackend.new()
	none.unsupported = true
	var net2: Variant = _host_with(none, "HostNet2")
	net2.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net2.upnp_state() == UpnpRunner.State.UNSUPPORTED))


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


func test_shipped_lease_is_finite() -> void:
	var cfg: UpnpConfig = load("res://config/upnp_config.tres") as UpnpConfig
	assert_eq(cfg.lease_seconds, 3600)


func test_lease_is_renewed_while_hosting_and_stops_with_the_host() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	var fast: UpnpConfig = net.upnp_config.duplicate() as UpnpConfig
	fast.lease_seconds = 1
	net.upnp_config = fast
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return backend.renews >= 2))
	net.leave()
	assert_true(await _wait_for(func() -> bool: return backend.closed == 1))
	var after_stop: int = backend.renews
	await get_tree().create_timer(1.2).timeout
	assert_eq(backend.renews, after_stop, "no renewals after the host stopped")


func test_mapping_removed_when_hosting_stops() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.OPENED))
	net.leave()
	assert_eq(net.upnp_state(), UpnpRunner.State.IDLE)
	assert_eq(net.upnp_join_code(), "")
	assert_true(await _wait_for(func() -> bool: return backend.closed == 1))


func test_leave_while_pending_still_removes_the_mapping() -> void:
	var backend: FakeBackend = FakeBackend.new()
	backend.delay_msec = 300
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	net.leave()
	assert_true(await _wait_for(func() -> bool: return backend.closed == 1))
	assert_eq(net.upnp_state(), UpnpRunner.State.IDLE, "a late open result does not revive the state")


func test_quit_removes_the_mapping_synchronously() -> void:
	var backend: FakeBackend = FakeBackend.new()
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_true(await _wait_for(func() -> bool: return net.upnp_state() == UpnpRunner.State.OPENED))
	net._exit_tree()
	assert_eq(backend.closed, 1)


func test_quit_while_open_is_pending_does_not_leave_a_mapping() -> void:
	var backend: FakeBackend = FakeBackend.new()
	backend.delay_msec = 300
	var net: Variant = _host_with(backend)
	net.host_game(AgentProbe.free_udp_port(), "H")
	net._exit_tree()
	assert_eq(backend.opened_port, 0)


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


func test_no_backend_in_headless_or_non_autoload_instances() -> void:
	var net: Variant = _make_net("PlainNet")
	net.host_game(AgentProbe.free_udp_port(), "H")
	assert_eq(net.upnp_state(), UpnpRunner.State.IDLE, "tests never reach a router")


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


func test_lobby_row_states() -> void:
	var row: JoinCodeRow = JoinCodeRow.new()
	add_child_autofree(row)
	var stub: StubNet = StubNet.new()
	row.refresh(stub, true)
	assert_false(row.visible, "idle: hidden")
	stub.state = UpnpRunner.State.PENDING
	row.refresh(stub, true)
	assert_true(row.visible)
	assert_false(row.copy_button().visible)
	stub.state = UpnpRunner.State.OPENED
	stub.code = "7XK2M-9QD4R"
	row.refresh(stub, true)
	assert_eq(row.label_text(), "Join code: 7XK2M-9QD4R")
	assert_true(row.copy_button().visible)
	row.copy_button().pressed.emit()
	assert_eq(row.copy_button().text, JoinCodeRow.TEXT_COPIED)
	stub.state = UpnpRunner.State.FAILED
	row.refresh(stub, true)
	assert_eq(row.label_text(), "Router didn't open the port - use Steam, or forward UDP port 47778")
	assert_false(row.copy_button().visible)
	stub.steam = true
	row.refresh(stub, true)
	assert_false(row.visible, "Steam lobbies unchanged")
	stub.steam = false
	row.refresh(stub, false)
	assert_false(row.visible, "clients never see it")


func test_lobby_with_a_plain_provider_hides_the_row() -> void:
	var scene: PackedScene = load("res://ui/Lobby.tscn")
	var lobby: Lobby = autofree(scene.instantiate())
	add_child_autofree(lobby)
	var fake: FakeNet = FakeNet.new()
	lobby.net_provider = fake
	lobby._update_host_only_state()
	var row: JoinCodeRow = lobby.find_child("JoinCodeRow", true, false) as JoinCodeRow
	assert_not_null(row)
	assert_false(row.visible)
