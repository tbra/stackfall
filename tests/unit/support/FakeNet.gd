class_name FakeNet
extends RefCounted
## Test double for the Net autoload (docs/M3a_PLAN.md).
##
## GUT cannot double a plain autoload — addons/gut/test.gd's double_singleton
## only recognises Godot's own engine singletons — so autoload/Match.gd and
## net/MatchNet.gd (P3) read their session state through a seam
## (set_net_provider / set_providers), and ui/MainMenu.gd, ui/Lobby.gd and
## ui/NetDebugOverlay.gd (P4) read a `Variant net_provider` field, both
## defaulting to the real Net. This one double scripts every answer either
## side needs: whether this instance is the host, which slot a peer holds,
## which slots are driven by local input, and the lobby/discovery/stats calls
## the UI scripts make.
##
## It deliberately implements no transport. P1 owns the real thing; the point
## here is to put Match, MatchNet and the UI scripts into the CLIENT and
## multi-peer states a single-process unit test can otherwise never reach.
##
## Signals stay on the real Events bus: every P4 script "connects to Events
## only" (the ui/HUD.gd convention), so a test drives them the same way
## test_hud.gd does — by emitting straight onto Events — rather than through
## this fake.

var mode_value: int = 0  ## Net.Mode: 0 OFFLINE, 1 HOST, 2 CLIENT
var is_host_value: bool = true
var is_client_value: bool = false
var is_offline_value: bool = true

## peer_id -> slot_id. The host's own peer (Net.HOST_PEER_ID) is normally in
## here too, holding slot 0. Source of truth for slot_of_peer/peer_of_slot/
## peer_ids/peer_info, and freely mutable by tests (e.g.
## `_fake_net.slots_by_peer.erase(2)`).
var slots_by_peer: Dictionary = {}
## Slots this instance's own input drives. Offline that is every slot, which
## is what keeps M2's hot-seat working unchanged (see is_local_slot).
var local_slots: Array[int] = []
var names_by_peer: Dictionary = {}

var local_slot_value: int = 0
var local_peer_id_value: int = 1

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

# --- M3b: Steam session mirror (docs/M3b_PLAN.md P1) -------------------
#
# Field names match what docs/M3b_PLAN.md's P3 test bullets read directly
# (`net_provider.steam_available_value = false`, `is_steam_session_value`,
# `host_online_calls`, `join_lobby_calls`, `invite_friends_calls`) so
# ui/MainMenu.gd and ui/Lobby.gd's tests can drive this fake the same way
# test_main_menu.gd/test_lobby.gd already drive the ENet-shaped fields above.

var steam_available_value: bool = false
var is_steam_session_value: bool = false
var discovered_lobbies_value: Array[Dictionary] = []
var next_host_online_result: Error = OK
var next_join_lobby_result: Error = OK

var host_online_calls: Array[Dictionary] = []
var join_lobby_calls: Array[Dictionary] = []
var refresh_lobby_list_calls: int = 0
var invite_friends_calls: int = 0
var init_steam_calls: int = 0


static func host(peer_slots: Dictionary = {}, local: Array[int] = []) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	fake.mode_value = 1
	fake.is_host_value = true
	fake.is_client_value = false
	fake.is_offline_value = false
	fake.slots_by_peer = peer_slots
	fake.local_slots = local
	if local.size() > 0:
		fake.local_slot_value = local[0]
	return fake


static func client(local_slot_id: int) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	fake.mode_value = 2
	fake.is_host_value = false
	fake.is_client_value = true
	fake.is_offline_value = false
	fake.local_slots = [local_slot_id]
	fake.local_slot_value = local_slot_id
	return fake


static func offline() -> FakeNet:
	return FakeNet.new()


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


func slot_of_peer(peer_id: int) -> int:
	return int(slots_by_peer.get(peer_id, -1))


func peer_of_slot(slot_id: int) -> int:
	for peer_id: Variant in slots_by_peer.keys():
		if int(slots_by_peer[peer_id]) == slot_id:
			return int(peer_id)
	return -1


func local_slot() -> int:
	return local_slot_value


func is_local_slot(slot_id: int) -> bool:
	if is_offline():
		return true
	return local_slots.has(slot_id)


func peer_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for peer_id: Variant in slots_by_peer.keys():
		ids.append(int(peer_id))
	return ids


func peer_info(peer_id: int) -> Dictionary:
	if not slots_by_peer.has(peer_id):
		return {}
	return {
		"peer_id": peer_id,
		"slot_id": slot_of_peer(peer_id),
		"name": String(names_by_peer.get(peer_id, "Player")),
		"ready": true,
		"ping_ms": 0.0,
		"build": "",
	}


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


# --- M3b: Steam session mirror ------------------------------------------

func steam_available() -> bool:
	return steam_available_value


func init_steam() -> void:
	init_steam_calls += 1


func is_steam_session() -> bool:
	return is_steam_session_value


func host_online(player_name: String = "") -> Error:
	host_online_calls.append({"player_name": player_name})
	return next_host_online_result


func join_lobby(lobby_id: int, player_name: String = "") -> Error:
	join_lobby_calls.append({"lobby_id": lobby_id, "player_name": player_name})
	return next_join_lobby_result


func discovered_lobbies() -> Array[Dictionary]:
	return discovered_lobbies_value


func refresh_lobby_list() -> void:
	refresh_lobby_list_calls += 1


func invite_friends() -> void:
	invite_friends_calls += 1
