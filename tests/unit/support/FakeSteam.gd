class_name FakeSteam
extends RefCounted
## Test double for net/SteamClient.gd (docs/M3b_PLAN.md P1).
##
## GUT cannot double a plain RefCounted script driven only through duck-typed
## `.call()`s the way the real SteamClient reaches the Engine "Steam"
## singleton, and every P1 test must pass with **no real Steam singleton
## present** (docs/M3b_PLAN.md's acceptance criterion). This fake implements
## SteamClient's exact public method/signal surface so autoload/Net.gd's
## `steam_provider: Variant` seam cannot tell the difference at the call
## site — same role FakeNet plays for the whole Net autoload.
##
## Every method that would touch a real lobby id instead reads/writes this
## fake's own `_lobby_data`/`_lobby_owners`/`_lobby_members` Dictionaries, so
## a test can set up a lobby's state and then assert Net's Steam-facing
## methods (discovered_lobbies(), invite_friends(), ...) read it back
## correctly, exactly the round trip the real Steam lobby-data calls give.

signal init_result(status: int, verbal: String)
signal lobby_created(result: int, lobby_id: int)
signal lobby_match_list(lobby_ids: Array)
signal lobby_data_updated(lobby_id: int)
signal lobby_joined(lobby_id: int, response: int)
signal lobby_join_requested(lobby_id: int, friend_id: int)

## Steamworks' own well-known result/response codes (see net/SteamClient.gd's
## matching DECISION comments) — tests fire the fake's signals with these by
## default so "the happy path" doesn't need every test to know the raw ints.
const RESULT_OK: int = 1
const CHAT_ROOM_ENTER_SUCCESS: int = 1

var available_value: bool = true
var local_steam_id_value: int = 76561197960287930 # an arbitrary, valid-shaped 64-bit id
var local_persona_name_value: String = "TestSteamUser"

## lobby_id -> {key -> value}, mutated by set_lobby_data() and read by
## get_lobby_data() and discovered_lobbies() filtering, so a test can seed a
## foreign lobby's tags without ever calling create_lobby() on it.
var lobby_data_store: Dictionary = {}
var lobby_owners: Dictionary = {}
var lobby_member_counts: Dictionary = {}

var init_calls: int = 0
var create_lobby_calls: Array[Dictionary] = []
var set_lobby_data_calls: Array[Dictionary] = []
var join_lobby_calls: Array[int] = []
var leave_lobby_calls: Array[int] = []
var request_lobby_list_calls: Array = []
var activate_invite_overlay_calls: Array[int] = []
var run_callbacks_calls: int = 0

## What init() answers with when called; tests override before calling
## Net.init_steam().
var init_status_value: int = 0
var init_verbal_value: String = ""


func is_available() -> bool:
	return available_value


func init() -> void:
	init_calls += 1
	init_result.emit(init_status_value, init_verbal_value)


func local_steam_id() -> int:
	return local_steam_id_value


func local_persona_name() -> String:
	return local_persona_name_value


## Unlike the real SteamClient, this fake does not auto-answer with a
## lobby_created signal — a test must emit it explicitly (usually right
## after asserting create_lobby_calls, mirroring how the real Steamworks
## callback would land on a later frame). This keeps the async shape
## test-visible instead of hiding it behind a fake that always succeeds.
func create_lobby(lobby_type: int, max_members: int) -> void:
	create_lobby_calls.append({"lobby_type": lobby_type, "max_members": max_members})


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	set_lobby_data_calls.append({"lobby_id": lobby_id, "key": key, "value": value})
	if not lobby_data_store.has(lobby_id):
		lobby_data_store[lobby_id] = {}
	(lobby_data_store[lobby_id] as Dictionary)[key] = value


func get_lobby_data(lobby_id: int, key: String) -> String:
	if not lobby_data_store.has(lobby_id):
		return ""
	return String((lobby_data_store[lobby_id] as Dictionary).get(key, ""))


func lobby_owner(lobby_id: int) -> int:
	return int(lobby_owners.get(lobby_id, 0))


func lobby_member_count(lobby_id: int) -> int:
	return int(lobby_member_counts.get(lobby_id, 0))


func join_lobby(lobby_id: int) -> void:
	join_lobby_calls.append(lobby_id)


func leave_lobby(lobby_id: int) -> void:
	leave_lobby_calls.append(lobby_id)


func request_lobby_list(string_filters: Array[Dictionary]) -> void:
	request_lobby_list_calls.append(string_filters)


func activate_invite_overlay(lobby_id: int) -> void:
	activate_invite_overlay_calls.append(lobby_id)


## Mirrors net/SteamClient.gd's run_callbacks() (docs/M3b_PLAN.md P1 — every
## real method needs a fake counterpart so Net._process()'s unconditional
## per-frame call never errors on a FakeSteam-driven test). A no-op: this fake
## already fires its own signals synchronously and explicitly, so it has no
## queued callbacks to pump.
func run_callbacks() -> void:
	run_callbacks_calls += 1


## Convenience for tests: seeds a lobby this fake will report as if a real
## Steam session had already tagged it (game/version/map/host_name), so
## discovered_lobbies() filtering can be exercised without going through
## host_online() first.
func seed_lobby(lobby_id: int, owner_id: int, member_count: int, data: Dictionary) -> void:
	lobby_owners[lobby_id] = owner_id
	lobby_member_counts[lobby_id] = member_count
	lobby_data_store[lobby_id] = data.duplicate(true)
