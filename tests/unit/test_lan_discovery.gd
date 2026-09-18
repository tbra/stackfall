extends GutTest
## net/LanDiscovery.gd: advert payload round-trip and list expiry
## (spec 3.4 "LAN discovery", docs/M3a_PLAN.md P1).

var _listener: LanDiscovery
var _config: NetConfig

## Each test gets its own port so a socket lingering from the previous test
## (the OS can take a moment to release a closed UDP socket) never collides.
static var _next_test_port: int = 47790


func before_each() -> void:
	_config = load("res://config/net_config.tres").duplicate() as NetConfig
	_config.discovery_port = _next_test_port
	_next_test_port += 1
	# A tiny TTL so expiry doesn't make the suite slow.
	_config.discovery_entry_ttl = 0.15
	_config.discovery_broadcast_hz = 20.0
	_listener = LanDiscovery.new()
	_listener.config = _config
	add_child_autofree(_listener)


func after_each() -> void:
	_listener.stop_listening()
	_listener.stop_advertising()


func _sample_info() -> Dictionary:
	return {
		"game": "stackfall",
		"version": "0.3.0",
		"name": "Tony's Game",
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


func test_decode_rejects_empty_payload() -> void:
	assert_true(LanDiscovery.decode_advert(PackedByteArray()).is_empty())


func test_decode_rejects_random_garbage_without_erroring() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	for _i: int in range(50):
		var junk: PackedByteArray = PackedByteArray()
		var length: int = rng.randi_range(0, 40)
		for _b: int in range(length):
			junk.append(rng.randi_range(0, 255))
		# Must not throw; either decodes (unlikely with random bytes) or
		# returns {}.
		var decoded: Dictionary = LanDiscovery.decode_advert(junk)
		assert_true(decoded is Dictionary)


# --- Listening + list expiry (loopback UDP) ---------------------------------

func test_listen_sees_a_loopback_advert() -> void:
	assert_eq(_listener.start_listening(), OK)
	var sender: PacketPeerUDP = PacketPeerUDP.new()
	sender.connect_to_host("127.0.0.1", _config.discovery_port)
	sender.put_packet(LanDiscovery.encode_advert(_sample_info()))

	var seen: bool = false
	for _attempt: int in range(50):
		await get_tree().process_frame
		if not _listener.games().is_empty():
			seen = true
			break
	assert_true(seen, "advert sent to loopback must appear in games()")
	if seen:
		assert_eq(_listener.games()[0].get("name"), "Tony's Game")
		assert_eq(_listener.games()[0].get("address"), "127.0.0.1")
	sender.close()


func test_discovered_entry_expires_after_ttl() -> void:
	# watch_signals()/assert_signal_emitted() rather than a connected lambda
	# flipping a local bool: GDScript lambdas capture locals *by value* at
	# creation time, so a bare `func(): flag = true` closure never actually
	# updates the outer `flag` the test reads afterward.
	watch_signals(_listener)
	assert_eq(_listener.start_listening(), OK)
	var sender: PacketPeerUDP = PacketPeerUDP.new()
	sender.connect_to_host("127.0.0.1", _config.discovery_port)
	sender.put_packet(LanDiscovery.encode_advert(_sample_info()))

	for _attempt: int in range(50):
		await get_tree().process_frame
		if not _listener.games().is_empty():
			break
	assert_false(_listener.games().is_empty(), "advert must be seen before it can expire")

	var expired: bool = false
	for _attempt: int in range(120):
		await get_tree().process_frame
		if _listener.games().is_empty():
			expired = true
			break
	assert_true(expired, "entry must expire after discovery_entry_ttl with no refresh")
	assert_signal_emitted(_listener, "game_expired")
	sender.close()


func test_refreshed_advert_does_not_expire() -> void:
	assert_eq(_listener.start_listening(), OK)
	var sender: PacketPeerUDP = PacketPeerUDP.new()
	sender.connect_to_host("127.0.0.1", _config.discovery_port)

	# Keep refreshing faster than the TTL for longer than the TTL would allow
	# a stale entry to survive.
	var elapsed: float = 0.0
	var step: float = 0.03
	while elapsed < _config.discovery_entry_ttl * 3.0:
		sender.put_packet(LanDiscovery.encode_advert(_sample_info()))
		await get_tree().create_timer(step).timeout
		elapsed += step

	assert_false(_listener.games().is_empty(), "a continuously refreshed advert must never expire")
	sender.close()
