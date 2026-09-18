class_name FakeNet
extends RefCounted
## Test double for the Net autoload (docs/M3a_PLAN.md P4).
##
## autoload/Net.gd is still P1's stub as P4 lands, and even once it is real,
## driving ui/MainMenu.gd, ui/Lobby.gd and ui/NetDebugOverlay.gd through an
## actual ENet handshake would make their unit tests slow and network-flaky
## for no benefit — they only need a scripted answer to a handful of calls.
## Each of those scripts reads a `Variant net_provider` field (see their
## matching DECISION comments, the same seam tests/unit/support/FakeMatch.gd
## uses for Match) instead of the global `Net` singleton, so tests can swap
## one of these in and drive the documented contract directly.
##
## Signals stay on the real Events bus: every P4 script "connects to Events
## only" (the ui/HUD.gd convention), so a test drives them the same way
## test_hud.gd does — by emitting straight onto Events — rather than through
## this fake.

var mode_value: int = 0  # Net.Mode.OFFLINE
var is_host_value: bool = true
var is_client_value: bool = false
var is_offline_value: bool = true
var local_slot_value: int = 0
var local_peer_id_value: int = 1

var peer_ids_value: PackedInt32Array = PackedInt32Array()
var peer_info_by_id: Dictionary = {}
var all_peers_ready_value: bool = false

var lobby_data_value: Dictionary = {}
var discovered_games_value: Array[Dictionary] = []

var stats_value: Dictionary = {}
var simulation_enabled_value: bool = false
var config: NetConfig = preload("res://config/net_config.tres")

## Every call this fake recorded, for "did the script ask for the right
## thing" assertions.
var host_game_calls: Array[Dictionary] = []
var join_game_calls: Array[Dictionary] = []
var set_lobby_data_calls: Array[Dictionary] = []
var set_local_ready_calls: Array[bool] = []
var set_simulation_calls: Array[Dictionary] = []
var start_discovery_calls: int = 0
var stop_discovery_calls: int = 0

## What host_game()/join_game() return next; tests drive JoinError paths with it.
var next_host_result: Error = OK
var next_join_result: Error = OK


func host_game(port: int = 0, player_name: String = "") -> Error:
	host_game_calls.append({"port": port, "player_name": player_name})
	return next_host_result


func join_game(address: String, port: int = 0, player_name: String = "") -> Error:
	join_game_calls.append({"address": address, "port": port, "player_name": player_name})
	return next_join_result


func leave() -> void:
	pass


func mode() -> int:
	return mode_value


func is_host() -> bool:
	return is_host_value


func is_client() -> bool:
	return is_client_value


func is_offline() -> bool:
	return is_offline_value


func local_peer_id() -> int:
	return local_peer_id_value


func build_version() -> String:
	return "test"


func peer_ids() -> PackedInt32Array:
	return peer_ids_value


func peer_info(peer_id: int) -> Dictionary:
	return peer_info_by_id.get(peer_id, {})


func slot_of_peer(peer_id: int) -> int:
	var info: Dictionary = peer_info(peer_id)
	return int(info.get("slot_id", -1))


func peer_of_slot(slot_id: int) -> int:
	for peer_id: int in peer_ids_value:
		if slot_of_peer(peer_id) == slot_id:
			return peer_id
	return -1


func local_slot() -> int:
	return local_slot_value


func is_local_slot(_slot_id: int) -> bool:
	return true


func set_peer_ready(_peer_id: int, _ready: bool) -> void:
	pass


func kick_peer(_peer_id: int, _reason: int = 0) -> void:
	pass


func set_local_ready(ready: bool) -> void:
	set_local_ready_calls.append(ready)


func all_peers_ready() -> bool:
	return all_peers_ready_value


func ping_ms(_peer_id: int = 0) -> float:
	return float(stats_value.get("ping_ms", 0.0))


func set_lobby_data(data: Dictionary) -> void:
	set_lobby_data_calls.append(data)
	lobby_data_value = data


func lobby_data() -> Dictionary:
	return lobby_data_value


func start_discovery() -> void:
	start_discovery_calls += 1


func stop_discovery() -> void:
	stop_discovery_calls += 1


func discovered_games() -> Array[Dictionary]:
	return discovered_games_value


func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	set_simulation_calls.append({"lag_ms": lag_ms, "jitter_ms": jitter_ms, "loss": loss})


func simulation() -> NetSim:
	return null


func simulation_enabled() -> bool:
	return simulation_enabled_value


func stats() -> Dictionary:
	return stats_value


func report_stats(_source: StringName, _values: Dictionary) -> void:
	pass


func apply_command_line() -> bool:
	return false
