extends GutTest
## net/LanDiscovery.gd: advert payload round-trip and list expiry
## (spec 2.6 "LAN discovery").

var _listener: LanDiscovery
var _config: NetConfig
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Concurrent GUT processes share the machine's UDP ports, so a fixed port range
## collides across processes (bind fails, or a foreign process's advert lands in
## this listener). Each test picks a random high port and start_listening is
## retried on another one if the bind is taken; the bound port is then exclusive.
const _PORT_MIN: int = 20000
const _PORT_SPAN: int = 30000
const _BIND_ATTEMPTS: int = 40
const _WAIT_SECONDS: float = 5.0


func before_each() -> void:
	_config = load("res://config/net/net_config.tres").duplicate() as NetConfig
	_rng.randomize()
	_config.discovery_port = _random_port()
	# A tiny TTL so expiry doesn't make the suite slow.
	_config.discovery_entry_ttl = 0.15
	_config.discovery_broadcast_hz = 20.0
	_listener = LanDiscovery.new()
	_listener.config = _config
	add_child_autofree(_listener)


func after_each() -> void:
	_listener.stop_listening()
	_listener.stop_advertising()


func _random_port() -> int:
	return _PORT_MIN + _rng.randi_range(0, _PORT_SPAN - 1)


## Starts listening, moving to another random port when the bind is taken.
func _listen_on_free_port() -> Error:
	var err: Error = ERR_CANT_CREATE
	for _i: int in range(_BIND_ATTEMPTS):
		err = _listener.start_listening()
		if err == OK:
			return OK
		_config.discovery_port = _random_port()
	return err


## Event-driven wait: polls each frame until `done` is true or the wall-clock
## deadline passes (never a fixed frame count, which is too short under load).
func _wait_until(done: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(_WAIT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if done.call():
			return true
		await get_tree().process_frame
	return done.call()


func _sample_info() -> Dictionary:
	return {
		"game": "stackfall",
		"version": "0.3.0",
		"name": "Alex's Game",
		"players": 3,
		"max": 8,
		"map": "round",
		"port": 47778,
	}


# --- encode_advert / decode_advert round trip -------------------------------

func test_encode_decode_round_trips_every_field() -> void:
	var info: Dictionary = _sample_info()
	var payload: PackedByteArray = LanDiscovery.encode_advert(info)
	var decoded: Dictionary = LanDiscovery.decode_advert(payload)

	assert_eq(decoded.get("version"), info["version"])
	assert_eq(decoded.get("name"), info["name"])
	assert_eq(decoded.get("players"), info["players"])
	assert_eq(decoded.get("max"), info["max"])
	assert_eq(decoded.get("map"), info["map"])
	assert_eq(decoded.get("port"), info["port"])


func test_decode_rejects_foreign_payload_without_erroring() -> void:
	var foreign: PackedByteArray = "not a stackfall advert at all".to_utf8_buffer()
	var decoded: Dictionary = LanDiscovery.decode_advert(foreign)
	assert_true(decoded.is_empty())


func test_decode_rejects_truncated_payload_without_erroring() -> void:
	var payload: PackedByteArray = LanDiscovery.encode_advert(_sample_info())
	for cut_at: int in range(payload.size()):
		var truncated: PackedByteArray = payload.slice(0, cut_at)
		var decoded: Dictionary = LanDiscovery.decode_advert(truncated)
		# Every prefix shorter than the full payload must fail cleanly; only
		# the full payload (cut_at == payload.size(), not reached by range())
		# decodes successfully.
		assert_true(decoded.is_empty(), "truncated at %d bytes must decode to {}" % cut_at)


# --- Listening + list expiry (loopback UDP) ---------------------------------

func test_discovered_entry_expires_after_ttl() -> void:
	# watch_signals()/assert_signal_emitted() rather than a connected lambda
	# flipping a local bool: GDScript lambdas capture locals *by value* at
	# creation time, so a bare `func(): flag = true` closure never actually
	# updates the outer `flag` the test reads afterward.
	_config.discovery_entry_ttl = 0.5  # long enough to observe the entry under load
	watch_signals(_listener)
	assert_eq(_listen_on_free_port(), OK)
	var sender: PacketPeerUDP = PacketPeerUDP.new()
	sender.connect_to_host("127.0.0.1", _config.discovery_port)
	sender.put_packet(LanDiscovery.encode_advert(_sample_info()))

	await _wait_until(func() -> bool: return not _listener.games().is_empty())
	assert_false(_listener.games().is_empty(), "advert must be seen before it can expire")

	var expired: bool = await _wait_until(func() -> bool: return _listener.games().is_empty())
	assert_true(expired, "entry must expire after discovery_entry_ttl with no refresh")
	assert_signal_emitted(_listener, "game_expired")
	sender.close()

