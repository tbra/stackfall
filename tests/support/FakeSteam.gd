class_name FakeSteam
extends SteamClient
## Test double for net/SteamClient.gd.
##
## Extends SteamClient, so it is a SteamClient to every typed seam (Net's
## steam_provider, NetSteamSession's `steam` argument) and inherits the real
## signals and constants. Every method that would reach the Engine "Steam"
## singleton is overridden with an in-memory version, so every test passes with
## **no real Steam singleton present**.
##
## Lobby state lives in this fake's own `lobby_data_store`/`lobby_owners`/
## `lobby_member_counts`, so a test can seed a lobby and read back what the
## session wrote.
##
## Answers are asynchronous the way Steamworks' are: queue_lobby_created() and
## friends only queue, and run_callbacks() (the per-frame pump Net._process
## calls) delivers them in order. A test drives a frame, not a private method.

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
var _queued: Array[Dictionary] = []

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


var joinable_calls: Array = []
var unfiltered_requests: int = 0


func set_lobby_joinable(lobby_id: int, joinable: bool) -> void:
	joinable_calls.append([lobby_id, joinable])


func request_unfiltered_debug_list() -> void:
	unfiltered_requests += 1


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


var leave_lobby_reasons: Array[String] = []
var self_check_calls: Array[int] = []


func leave_lobby(lobby_id: int, reason: String = "") -> void:
	leave_lobby_calls.append(lobby_id)
	leave_lobby_reasons.append(reason)


func self_check_line(lobby_id: int) -> String:
	self_check_calls.append(lobby_id)
	return "lobby=%d members=%d owner=%d" % [lobby_id, lobby_member_count(lobby_id), lobby_owner(lobby_id)]


## Queues the answer to a create_lobby() the way Steamworks does (seen in
## every probe log): lobby_created, then, on success, the creator's own
## lobby_joined (LobbyEnter_t) for the same lobby. Delivered by run_callbacks().
func queue_create_answer(result: int, lobby_id: int) -> void:
	_queued.append({"kind": &"created", "a": result, "b": lobby_id})
	if result == RESULT_OK:
		queue_lobby_joined(lobby_id, CHAT_ROOM_ENTER_SUCCESS)


func queue_lobby_created(result: int, lobby_id: int) -> void:
	_queued.append({"kind": &"created", "a": result, "b": lobby_id})


func queue_lobby_joined(lobby_id: int, response: int) -> void:
	_queued.append({"kind": &"joined", "a": lobby_id, "b": response})


func queue_lobby_match_list(lobby_ids: Array) -> void:
	_queued.append({"kind": &"list", "a": lobby_ids, "b": 0})


func queue_join_requested(lobby_id: int, friend_id: int) -> void:
	_queued.append({"kind": &"requested", "a": lobby_id, "b": friend_id})


func request_lobby_list(string_filters: Array[Dictionary]) -> void:
	request_lobby_list_calls.append(string_filters)


func activate_invite_overlay(lobby_id: int) -> void:
	activate_invite_overlay_calls.append(lobby_id)


## The per-frame pump (net/SteamClient.gd's run_callbacks()): delivers every
## answer queued so far, oldest first. An answer queued by a listener while this
## runs waits for the next call, as a real Steamworks answer lands on a later frame.
func run_callbacks() -> void:
	run_callbacks_calls += 1
	var batch: Array[Dictionary] = _queued
	_queued = []
	for item: Dictionary in batch:
		match StringName(item["kind"]):
			&"created":
				lobby_created.emit(int(item["a"]), int(item["b"]))
			&"joined":
				lobby_joined.emit(int(item["a"]), int(item["b"]))
			&"list":
				lobby_match_list.emit(item["a"] as Array)
			&"requested":
				lobby_join_requested.emit(int(item["a"]), int(item["b"]))


## Convenience for tests: seeds a lobby this fake will report as if a real
## Steam session had already tagged it (game/version/map/host_name), so
## discovered_lobbies() filtering can be exercised without going through
## host_online() first.
func seed_lobby(lobby_id: int, owner_id: int, member_count: int, data: Dictionary) -> void:
	lobby_owners[lobby_id] = owner_id
	lobby_member_counts[lobby_id] = member_count
	lobby_data_store[lobby_id] = data.duplicate(true)
