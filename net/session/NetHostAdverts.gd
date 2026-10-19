class_name NetHostAdverts
extends RefCounted
## What a non-Steam host publishes about itself: the LAN browser advert
## (LanDiscovery) and the router port opening (UpnpRunner), plus the join code
## built from the router's external address. Net owns one of these, calls
## start() when hosting begins, stop() when it ends, poll() each frame and
## shutdown() at quit. It knows nothing about ENet, Steam or the roster.

## `state` of the UpnpRunner changed (Net re-emits it as its own signal).
signal upnp_state_changed(state: int)

## The UPnP settings (lease, enable switch); Net assigns its own before start().
var upnp_config: UpnpConfig = null
## Returns the UpnpBackend to use, or null when this process must not touch a
## router (headless, agent probe, test instance). Called lazily, only when a
## session is actually advertised, so a bot or private host never builds one.
var backend_source: Callable = Callable()

var _lan: LanDiscovery
var _upnp: UpnpRunner
var _config: NetConfig
var _port: int = 0


func _init(lan: LanDiscovery, upnp: UpnpRunner, config: NetConfig) -> void:
	_lan = lan
	_upnp = upnp
	_config = config


## Begins publishing a listen server on `port`. `advertise` is false for a
## private or bot-hosted session (nothing is published, no router is asked).
## `announce_lan` false keeps the UPnP opening but skips the LAN broadcast
## (agent runs must not appear in the owner's LAN browser). `version` is the
## build version a joiner's browser compares; `players` the current head count.
func start(advertise: bool, port: int, name: String, players: int, version: String, announce_lan: bool = true) -> void:
	_port = port
	if not advertise:
		return
	if announce_lan:
		_lan.start_advertising({
			"game": String(NetIds.DISCOVERY_MAGIC),
			"version": version,
			"name": name,
			"players": players,
			"max": _config.max_peers,
			"map": "",
			"port": port,
		})
	_start_upnp(port)


## Stops the LAN advert and schedules the router mapping's removal. Safe when idle.
func stop() -> void:
	_lan.stop_advertising()
	var was_active: bool = _upnp.state != UpnpRunner.State.IDLE
	_upnp.stop()
	if was_active:
		upnp_state_changed.emit(int(_upnp.state))


## Keeps the browser's player count live while an advert is running.
func update_players(players: int) -> void:
	if _lan.is_advertising():
		_lan.update_advert({"players": players})


## Call every frame: collects a finished router job.
func poll() -> void:
	if _upnp.poll():
		upnp_state_changed.emit(int(_upnp.state))


## Quit: the mapping must not outlive the process (blocking, one router round trip).
func shutdown() -> void:
	_upnp.shutdown()


## UpnpRunner.State as an int; IDLE = not tried.
func router_state() -> int:
	return int(_upnp.state)


## "XXXXX-XXXXX" once the router opened the port, else "".
func join_code() -> String:
	if _upnp.state != UpnpRunner.State.OPENED:
		return ""
	return JoinCode.encode(_upnp.external_address, _port)


func _start_upnp(port: int) -> void:
	if upnp_config == null or not upnp_config.enabled:
		return
	if not backend_source.is_valid():
		return
	var backend: UpnpBackend = backend_source.call() as UpnpBackend
	if backend == null:
		return
	_upnp.start(backend, port, upnp_config)
	upnp_state_changed.emit(int(_upnp.state))
