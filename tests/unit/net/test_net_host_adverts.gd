extends GutTest
## net/session/NetHostAdverts.gd: the LAN advert and UPnP glue a host publishes,
## against a real LanDiscovery on a private port and a fake UpnpBackend (the
## real router is never touched).

const _PORT_MIN: int = 20000
const _PORT_SPAN: int = 30000
const _BIND_ATTEMPTS: int = 40
const _WAIT_MSEC: int = 6000
const _GAME_PORT: int = 47911
const _EXTERNAL_ADDRESS: String = "81.9.44.7"
const _VERSION: String = "9.9.9"
const _HOST_NAME: String = "Hosty"


class FakeBackend extends UpnpBackend:
	var address: String = "81.9.44.7"
	var opened_port: int = 0
	var open_calls: int = 0
	var closed: int = 0

	func open_port(port: int, _config: UpnpConfig) -> Dictionary:
		open_calls += 1
		opened_port = port
		return {"ok": true, "address": address, "reason": "", "unsupported": false}

	func close_port(port: int) -> void:
		if opened_port == port:
			closed += 1
			opened_port = 0


var _config: NetConfig
var _lan: LanDiscovery
var _listener: LanDiscovery
var _upnp: UpnpRunner
var _adverts: NetHostAdverts
var _backend: FakeBackend
var _factory_calls: int = 0
var _states: Array[int] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func before_each() -> void:
	_rng.randomize()
	_config = load("res://config/net/net_config.tres").duplicate() as NetConfig
	_config.discovery_port = _random_port()
	_config.discovery_broadcast_hz = 20.0
	_lan = LanDiscovery.new()
	_lan.config = _config
	add_child_autofree(_lan)
	_listener = LanDiscovery.new()
	_listener.config = _config
	add_child_autofree(_listener)
	_upnp = UpnpRunner.new()
	_backend = FakeBackend.new()
	_factory_calls = 0
	_states.clear()
	_adverts = NetHostAdverts.new(_lan, _upnp, _config)
	_adverts.upnp_config = UpnpConfig.new()
	_adverts.backend_source = func() -> UpnpBackend:
		_factory_calls += 1
		return _backend
	_adverts.upnp_state_changed.connect(func(state: int) -> void: _states.append(state))


func after_each() -> void:
	_listener.stop_listening()
	_adverts.stop()
	_adverts.shutdown()


func _random_port() -> int:
	return _PORT_MIN + _rng.randi_range(0, _PORT_SPAN - 1)


func _listen_on_free_port() -> Error:
	var err: Error = ERR_CANT_CREATE
	for _i: int in range(_BIND_ATTEMPTS):
		err = _listener.start_listening()
		if err == OK:
			return OK
		_config.discovery_port = _random_port()
	return err


func _wait_until(done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + _WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		_adverts.poll()
		if done.call():
			return true
		await get_tree().process_frame
	return done.call()


func _opened() -> bool:
	return _adverts.router_state() == UpnpRunner.State.OPENED


func test_private_session_publishes_nothing() -> void:
	_adverts.start(false, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_false(_lan.is_advertising())
	assert_eq(_factory_calls, 0, "no backend is even built for a private or bot host")
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)
	assert_eq(_adverts.join_code(), "")
	assert_eq(_states.size(), 0)


func test_start_advertises_on_lan_and_opens_the_router() -> void:
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(_lan.is_advertising())
	assert_eq(_adverts.router_state(), UpnpRunner.State.PENDING)
	assert_eq(_adverts.join_code(), "", "no code until the router answered")
	assert_true(await _wait_until(_opened))
	assert_eq(_backend.opened_port, _GAME_PORT)
	assert_eq(_states, [UpnpRunner.State.PENDING, UpnpRunner.State.OPENED] as Array[int])


func test_join_code_decodes_to_the_external_address_and_port() -> void:
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(await _wait_until(_opened))
	var decoded: Dictionary = JoinCode.decode(_adverts.join_code())
	assert_eq(str(decoded["address"]), _EXTERNAL_ADDRESS)
	assert_eq(int(decoded["port"]), _GAME_PORT)


func test_private_router_address_is_a_failure_with_no_code() -> void:
	_backend.address = "192.168.1.9"
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(await _wait_until(func() -> bool: return _adverts.router_state() == UpnpRunner.State.FAILED))
	assert_eq(_adverts.join_code(), "")
	assert_eq(_states.back(), UpnpRunner.State.FAILED)


func test_lan_announce_off_still_opens_the_router() -> void:
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION, false)
	assert_false(_lan.is_advertising(), "an agent run stays out of the LAN browser")
	assert_true(await _wait_until(_opened))


func test_advert_carries_name_version_port_and_capacity() -> void:
	assert_eq(_listen_on_free_port(), OK)
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION, true)
	assert_true(await _wait_until(func() -> bool: return not _listener.games().is_empty()))
	var info: Dictionary = _listener.games()[0]
	assert_eq(str(info["version"]), _VERSION)
	assert_eq(str(info["name"]), _HOST_NAME)
	assert_eq(int(info["port"]), _GAME_PORT)
	assert_eq(int(info["max"]), _config.max_peers)
	assert_eq(int(info["players"]), 1)


func test_update_players_refreshes_the_live_advert() -> void:
	assert_eq(_listen_on_free_port(), OK)
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	_adverts.update_players(3)
	assert_true(await _wait_until(func() -> bool:
		return not _listener.games().is_empty() and int(_listener.games()[0]["players"]) == 3
	))


func test_update_players_is_a_no_op_without_an_advert() -> void:
	_adverts.update_players(5)
	assert_false(_lan.is_advertising())


func test_stop_ends_the_advert_and_removes_the_mapping() -> void:
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(await _wait_until(_opened))
	_adverts.stop()
	assert_false(_lan.is_advertising())
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)
	assert_eq(_adverts.join_code(), "")
	assert_eq(_states.back(), UpnpRunner.State.IDLE, "the lobby is told the row is gone")
	assert_true(await _wait_until(func() -> bool: return _backend.closed == 1))


func test_stop_when_idle_is_silent() -> void:
	_adverts.stop()
	assert_eq(_states.size(), 0)
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)


func test_shutdown_removes_the_mapping_synchronously() -> void:
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(await _wait_until(_opened))
	_adverts.shutdown()
	assert_eq(_backend.closed, 1)


func test_disabled_config_never_asks_for_a_backend() -> void:
	_adverts.upnp_config.enabled = false
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_true(_lan.is_advertising(), "the LAN advert does not depend on UPnP")
	assert_eq(_factory_calls, 0)
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)


func test_no_backend_leaves_upnp_untried() -> void:
	_adverts.backend_source = func() -> UpnpBackend: return null
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)
	assert_eq(_states.size(), 0)


func test_unset_backend_source_or_config_leaves_upnp_untried() -> void:
	_adverts.backend_source = Callable()
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)
	_adverts.stop()
	_adverts.backend_source = func() -> UpnpBackend: return _backend
	_adverts.upnp_config = null
	_adverts.start(true, _GAME_PORT, _HOST_NAME, 1, _VERSION)
	assert_eq(_adverts.router_state(), UpnpRunner.State.IDLE)
	assert_eq(_backend.open_calls, 0)
