class_name LanDiscovery
extends Node
## LAN game advertising and browsing over UDP broadcast (spec 3.4 "LAN
## discovery"): the host broadcasts `{game, version, name, players, max, map,
## port}` once per second to 255.255.255.255 on NetConfig.discovery_port
## (47777); clients listen and show a list.
##
## Owned and driven by autoload/Net.gd — nothing else instances it. It knows
## nothing about ENet or Steam: it moves one Dictionary and never touches the
## game peer, which is why the browser still works unchanged in M3b.
##
## **Known limitation, by design:** PacketPeerUDP.bind() does not set
## SO_REUSEADDR, so only one process per machine can listen on 47777. Two
## headless clients on one PC therefore cannot both browse; the multi-instance
## test harness joins by direct IP (127.0.0.1) instead, which is the path spec
## 3.4 calls "available as a fallback". Documented in docs/M3a_PLAN.md.

const _BROADCAST_ADDRESS: String = "255.255.255.255"
## Longest UTF-8 byte length accepted for any single string field of an
## advert. Generous for a player/game name, small enough that a malformed
## length byte (0..255) can never claim more than fits a UDP datagram.
const _MAX_FIELD_BYTES: int = 255

@export var config: NetConfig = preload("res://config/net_config.tres")

## A host advert was received or refreshed. Net re-emits this as
## Events.net_games_discovered after de-duplicating by address:port.
signal game_seen(info: Dictionary)

## An advert aged past config.discovery_entry_ttl.
signal game_expired(address: String, port: int)

var _advertising: bool = false
var _listening: bool = false
var _advert_info: Dictionary = {}
var _broadcast_accum: float = 0.0
var _broadcast_socket: PacketPeerUDP
var _listen_socket: PacketPeerUDP

## Keyed by "address:port". Each entry is {"info": Dictionary, "last_seen": float}.
var _games: Dictionary = {}


## Host side: begins broadcasting `info` every 1/config.discovery_broadcast_hz
## seconds. `info` is refreshed with update_advert() as players join, so the
## browser's player count stays live without a restart.
func start_advertising(info: Dictionary) -> Error:
	if _advertising:
		stop_advertising()
	_advert_info = info.duplicate()
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	socket.set_broadcast_enabled(true)
	var err: Error = socket.connect_to_host(_BROADCAST_ADDRESS, config.discovery_port)
	if err != OK:
		return err
	_broadcast_socket = socket
	_advertising = true
	_broadcast_accum = 0.0
	_send_advert()
	return OK


func update_advert(info: Dictionary) -> void:
	for key: String in info.keys():
		_advert_info[key] = info[key]


func stop_advertising() -> void:
	if _broadcast_socket:
		_broadcast_socket.close()
		_broadcast_socket = null
	_advertising = false


## Client side: binds config.discovery_port and collects adverts.
func start_listening() -> Error:
	if _listening:
		return OK
	var socket: PacketPeerUDP = PacketPeerUDP.new()
	var err: Error = socket.bind(config.discovery_port)
	if err != OK:
		return err
	_listen_socket = socket
	_listening = true
	return OK


func stop_listening() -> void:
	if _listen_socket:
		_listen_socket.close()
		_listen_socket = null
	_listening = false
	_games.clear()


## Adverts seen within config.discovery_entry_ttl, most recent first.
func games() -> Array[Dictionary]:
	var entries: Array = _games.values()
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["last_seen"]) > float(b["last_seen"])
	)
	var result: Array[Dictionary] = []
	for entry: Dictionary in entries:
		result.append(entry["info"])
	return result


func is_advertising() -> bool:
	return _advertising


func is_listening() -> bool:
	return _listening


func _process(delta: float) -> void:
	if _advertising:
		_broadcast_accum += delta
		var interval: float = 1.0 / maxf(config.discovery_broadcast_hz, 0.001)
		if _broadcast_accum >= interval:
			_broadcast_accum = fmod(_broadcast_accum, interval)
			_send_advert()
	if _listening:
		_poll_listen()
	if not _games.is_empty():
		_expire_stale(_now())


func _send_advert() -> void:
	if _broadcast_socket == null:
		return
	_broadcast_socket.put_packet(encode_advert(_advert_info))


func _poll_listen() -> void:
	if _listen_socket == null:
		return
	while _listen_socket.get_available_packet_count() > 0:
		var payload: PackedByteArray = _listen_socket.get_packet()
		var address: String = _listen_socket.get_packet_ip()
		var info: Dictionary = decode_advert(payload)
		if info.is_empty():
			continue
		info["address"] = address
		var key: String = "%s:%d" % [address, int(info.get("port", 0))]
		_games[key] = {"info": info, "last_seen": _now()}
		game_seen.emit(info.duplicate())


func _expire_stale(now: float) -> void:
	var expired: Array[String] = []
	for key: String in _games.keys():
		var entry: Dictionary = _games[key]
		if now - float(entry["last_seen"]) > config.discovery_entry_ttl:
			expired.append(key)
	for key: String in expired:
		var entry: Dictionary = _games[key]
		_games.erase(key)
		game_expired.emit(String(entry["info"]["address"]), int(entry["info"]["port"]))


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Serializes an advert. Split out from the socket so a unit test can assert
## the payload's shape and its size limit without opening a port; a malformed
## or foreign packet must come back as an empty Dictionary rather than throw.
static func encode_advert(info: Dictionary) -> PackedByteArray:
	var magic: PackedByteArray = String(Net.DISCOVERY_MAGIC).to_utf8_buffer()
	var version: PackedByteArray = String(info.get("version", "")).to_utf8_buffer()
	var player_name: PackedByteArray = String(info.get("name", "")).to_utf8_buffer()
	var map_name: PackedByteArray = String(info.get("map", "")).to_utf8_buffer()
	var players: int = clampi(int(info.get("players", 0)), 0, 255)
	var max_players: int = clampi(int(info.get("max", 0)), 0, 255)
	var port: int = clampi(int(info.get("port", 0)), 0, 65535)

	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	_put_field(buf, magic)
	_put_field(buf, version)
	_put_field(buf, player_name)
	buf.put_u8(players)
	buf.put_u8(max_players)
	_put_field(buf, map_name)
	buf.put_u16(port)
	return buf.data_array


static func decode_advert(payload: PackedByteArray) -> Dictionary:
	var buf: StreamPeerBuffer = StreamPeerBuffer.new()
	buf.data_array = payload

	if buf.get_available_bytes() < 1:
		return {}
	var magic_len: int = buf.get_u8()
	if buf.get_available_bytes() < magic_len:
		return {}
	# Compared as raw bytes, not decoded to a string first: random/foreign
	# payloads are the expected case here, and running them through
	# get_string_from_utf8() first would print a UTF-8 warning for every one.
	if _read_bytes(buf, magic_len) != String(Net.DISCOVERY_MAGIC).to_utf8_buffer():
		return {}

	if buf.get_available_bytes() < 1:
		return {}
	var version_len: int = buf.get_u8()
	if buf.get_available_bytes() < version_len:
		return {}
	var version: String = _read_bytes(buf, version_len).get_string_from_utf8()

	if buf.get_available_bytes() < 1:
		return {}
	var name_len: int = buf.get_u8()
	if buf.get_available_bytes() < name_len:
		return {}
	var player_name: String = _read_bytes(buf, name_len).get_string_from_utf8()

	if buf.get_available_bytes() < 2:
		return {}
	var players: int = buf.get_u8()
	var max_players: int = buf.get_u8()

	if buf.get_available_bytes() < 1:
		return {}
	var map_len: int = buf.get_u8()
	if buf.get_available_bytes() < map_len:
		return {}
	var map_name: String = _read_bytes(buf, map_len).get_string_from_utf8()

	if buf.get_available_bytes() < 2:
		return {}
	var port: int = buf.get_u16()

	return {
		"name": player_name,
		"version": version,
		"players": players,
		"max": max_players,
		"map": map_name,
		"port": port,
	}


## Writes a length-prefixed byte field, truncated to `_MAX_FIELD_BYTES`.
static func _put_field(buf: StreamPeerBuffer, data: PackedByteArray) -> void:
	var trimmed: PackedByteArray = data.slice(0, mini(data.size(), _MAX_FIELD_BYTES))
	buf.put_u8(trimmed.size())
	if not trimmed.is_empty():
		buf.put_data(trimmed)


## Reads exactly `length` bytes. The caller has already checked
## `get_available_bytes()`, so this never runs past the end of the buffer.
static func _read_bytes(buf: StreamPeerBuffer, length: int) -> PackedByteArray:
	if length <= 0:
		return PackedByteArray()
	var result: Array = buf.get_data(length)
	return result[1]
