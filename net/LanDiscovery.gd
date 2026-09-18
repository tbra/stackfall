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

@export var config: NetConfig = preload("res://config/net_config.tres")

## A host advert was received or refreshed. Net re-emits this as
## Events.net_games_discovered after de-duplicating by address:port.
signal game_seen(info: Dictionary)

## An advert aged past config.discovery_entry_ttl.
signal game_expired(address: String, port: int)

@warning_ignore_start("unused_parameter")


## Host side: begins broadcasting `info` every 1/config.discovery_broadcast_hz
## seconds. `info` is refreshed with update_advert() as players join, so the
## browser's player count stays live without a restart.
func start_advertising(info: Dictionary) -> Error:
	return OK


func update_advert(info: Dictionary) -> void:
	pass


func stop_advertising() -> void:
	pass


## Client side: binds config.discovery_port and collects adverts.
func start_listening() -> Error:
	return OK


func stop_listening() -> void:
	pass


## Adverts seen within config.discovery_entry_ttl, most recent first.
func games() -> Array[Dictionary]:
	return []


func is_advertising() -> bool:
	return false


func is_listening() -> bool:
	return false


## Serializes an advert. Split out from the socket so a unit test can assert
## the payload's shape and its size limit without opening a port; a malformed
## or foreign packet must come back as an empty Dictionary rather than throw.
static func encode_advert(info: Dictionary) -> PackedByteArray:
	return PackedByteArray()


static func decode_advert(payload: PackedByteArray) -> Dictionary:
	return {}


@warning_ignore_restore("unused_parameter")
