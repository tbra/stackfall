class_name SteamClient
extends RefCounted
## The Steam-facing half of the transport (spec 3.4, docs/archive/M3b_PLAN.md P1).
##
## The only file besides autoload/Net.gd's _make_steam_host_peer() /
## _make_steam_client_peer() that may touch the Engine "Steam" singleton or a
## lobby-list/lobby-data call. Peer instantiation itself still stays inside
## Net (docs/archive/M3a_PLAN.md's "no other file may name a concrete peer class"
## rule) — this file only ever reaches Steam's matchmaking API, never
## SteamMultiplayerPeer.
##
## Extension-optional static typing (docs/archive/M3b_PLAN.md "Design notes"): the
## whole res://addons/godotsteam/ directory is gitignored (M3b research's
## "Spike results"), so most checkouts have no `.gdextension` file and no
## `Steam` class registered at all. This script must still parse cleanly
## there, so `Steam` is never written as a static type or bare identifier —
## only reached through Engine.get_singleton(&"Steam"), held as a plain
## `Object`, and driven with duck-typed `.call(...)` / `.connect(...)`,
## mirroring autoload/Net.gd's `_apply_peer_timeout()` pattern for
## ENetPacketPeer one file over. `ClassDB.class_exists(&"Steam")` is the gate.
##
## Every method call and signal name here was verified against the actual
## GodotSteam 4.22.1 addon installed on this machine (Bontago-mv0.2.1's
## spike), not guessed from documentation alone — see
## netcode-F-probe_methods.log, netcode-F-probe_signals2.log,
## netcode-F-probe_method_sigs.log and netcode-F-probe_comp.log in the
## worker's scratch directory.

## A lobby finished initializing (or steamInitEx failed / the extension is
## absent). `status` is Steamworks' own steamInitEx() status (0 ok, 1 other
## failure, 2 client not running, 3 client out of date) OR
## STATUS_EXTENSION_NOT_INSTALLED, a sentinel this file adds so a caller can
## tell "the addon was never installed in this checkout" apart from "the
## addon loaded but Steam itself refused" — both collapse to
## Net.steam_available() == false for every UI purpose, per docs/archive/M3b_PLAN.md.
signal init_result(status: int, verbal: String)
## Raw forward of Steam's own `lobby_created(connect, lobby_id)` signal.
## Despite the name GodotSteam gives the first argument, it is the
## Steamworks EResult of the create attempt (k_EResultOK == 1), not a peer id.
signal lobby_created(result: int, lobby_id: int)
signal lobby_match_list(lobby_ids: Array)
## Raw forward of Steam's `lobby_data_update(success, lobby_id, member_id)`,
## trimmed to the one field Net actually needs (see _on_lobby_data_update()).
signal lobby_data_updated(lobby_id: int)
## Raw forward of Steam's `lobby_joined(lobby, permissions, locked, response)`,
## trimmed the same way. `response` is Steamworks' EChatRoomEnterResponse
## (k_EChatRoomEnterResponseSuccess == 1).
signal lobby_joined(lobby_id: int, response: int)
## Forward of Steam's `join_requested(lobby_id, steam_id)` — the overlay's own
## "Join Game" / invite-accept path when this game is already running.
signal lobby_join_requested(lobby_id: int, friend_id: int)

## Sentinel init_result status meaning "no Steam class registered at all",
## distinct from any real steamInitEx() status code (0-3), so a caller that
## wants to distinguish "never installed" from "installed but failing" still
## can, even though Net.steam_available() treats both the same.
const STATUS_EXTENSION_NOT_INSTALLED: int = -1

## Lobby-data key names (wire protocol, not a tunable — see
## docs/archive/M3b_PLAN.md's tunables table). `KEY_MATCH_CONFIG`'s value is the
## JSON string encode_match_config() produces; the other three are the flat
## preview fields a lobby-browser row needs before actually joining.
const KEY_GAME: StringName = &"game"
const KEY_VERSION: StringName = &"version"
const KEY_MAP: StringName = &"map"
## DECISION (deviation from docs/archive/M3b_PLAN.md's three-key list): a fourth key
## for the host's display name. discovered_lobbies()'s documented return
## shape includes "name" for the list row, and Steam's lobby object itself
## has no host-display-name field the way it has a member count — the LAN
## advert's {name} field has no Steam-native equivalent, so it needs its own
## lobby-data key the same way {game, version, map} do.
const KEY_HOST_NAME: StringName = &"host_name"
const KEY_MATCH_CONFIG: StringName = &"match_config"

## Steamworks' own comparison operator for addRequestLobbyListStringFilter();
## verified present as Steam.LOBBY_COMPARISON_EQUAL == 0 on the installed
## addon (netcode-F-probe_comp.log). Equality is the only comparison this
## project's lobby tags ever need.
const _LOBBY_COMPARISON_EQUAL: int = 0

## Loaded once so decode_match_config()'s size check has a byte limit to read
## without needing a NetConfig parameter — the plan's static signature takes
## only the text, and a static method has no `self.config` to read. The one
## constant this file could not avoid pulling from NetConfig.
const _DEFAULT_CONFIG: NetConfig = preload("res://config/net_config.tres")

var _steam: Object = null


## Bontago-1pi.48: lobby data values are truncated to this many characters in the diagnostic log.
const LOG_VALUE_MAX_CHARS: int = 40
## Bontago-1pi.48: the SELFCHECK line's all-lobby-data dump is cut to this many characters.
const SELFCHECK_DATA_MAX_CHARS: int = 400
## Bontago-1pi.48: call_origin() lists at most this many script frames.
const ORIGIN_MAX_FRAMES: int = 6
const _MSEC_PER_SEC: float = 1000.0


## Bontago-1pi.48: every Steam diagnostic line is `STEAM [HH:MM:SS.mmm] text`
## (local wall clock), so a host log can be lined up against another PC's log.
static func log_line(text: String) -> void:
	var now: float = Time.get_unix_time_from_system()
	var msec: int = int((now - floorf(now)) * _MSEC_PER_SEC)
	print("STEAM [%s.%03d] %s" % [Time.get_time_string_from_system(), msec, text])


## Bontago-1pi.48: the GDScript caller chain of the current call (innermost
## first, this helper and its direct caller skipped), e.g.
## "Net.gd:1023 _on_steam_lobby_joined < SteamClient.gd:290 _on_lobby_joined".
## get_stack() is empty in release exports; debug exports track it.
static func call_origin() -> String:
	var frames: Array = get_stack()
	var parts: PackedStringArray = PackedStringArray()
	for i: int in range(2, mini(frames.size(), ORIGIN_MAX_FRAMES + 2)):
		var f: Dictionary = frames[i]
		parts.append("%s:%d %s" % [String(f.get("source", "")).get_file(), int(f.get("line", 0)), f.get("function", "")])
	return " < ".join(parts) if not parts.is_empty() else "(no script stack: release build)"


func is_available() -> bool:
	return ClassDB.class_exists(&"Steam")


## Pumps Steamworks' own callback queue (`SteamAPI_RunCallbacks()` under the
## hood). Steamworks is a manual-dispatch C API: every async signal this file
## forwards (lobby_created, lobby_match_list, lobby_joined, lobby_data_update,
## join_requested) is queued internally and never actually fires unless this
## is called regularly, no matter how long a caller waits. Found empirically
## while running this package's own windowed smoke test (docs/archive/M3b_PLAN.md P1
## acceptance): host_online() reached a real Steam client (steamInitEx()
## already answered status 0, createLobby() returned no error), but
## lobby_created never arrived even after 15+ seconds — GodotSteam requires a
## periodic run_callbacks() call the same way any Steamworks integration does,
## and nothing in this codebase was calling it. `Net._process()` calls this
## every frame once _steam_ready is true (autoload/Net.gd).
func run_callbacks() -> void:
	if _steam == null:
		return
	_steam.call("run_callbacks")


## Calls Steam.steamInitEx(Net.STEAM_APP_ID_EXPECTED, false) and emits
## init_result with its {status, verbal} once. Safe to call when the
## extension isn't installed — emits STATUS_EXTENSION_NOT_INSTALLED instead
## of touching a singleton that doesn't exist.
func init() -> void:
	if not is_available():
		init_result.emit(STATUS_EXTENSION_NOT_INSTALLED, "GodotSteam extension not installed in this checkout")
		return
	_steam = Engine.get_singleton(&"Steam")
	_wire_signals()
	# Never Steam.steamInit() — docs/archive/M3b_RESEARCH.md: the bare call is
	# reported to crash in-editor. steamInitEx() returns {"verbal", "status"};
	# 0 ok, 1 other failure, 2 client not running, 3 client out of date.
	var result: Dictionary = _steam.call("steamInitEx", Net.STEAM_APP_ID_EXPECTED, false)
	log_line("steamInitEx(app_id=%d, embed_callbacks=false) -> %s" % [Net.STEAM_APP_ID_EXPECTED, str(result)])
	init_result.emit(int(result.get("status", 1)), String(result.get("verbal", "")))


func local_steam_id() -> int:
	if _steam == null:
		return 0
	return int(_steam.call("getSteamID"))


func local_persona_name() -> String:
	if _steam == null:
		return ""
	return String(_steam.call("getPersonaName"))


func create_lobby(lobby_type: int, max_members: int) -> void:
	if _steam == null:
		return
	log_line("createLobby requested: type=%d (%s) max_members=%d origin=%s" % [lobby_type, _LOBBY_TYPE_NAMES.get(lobby_type, "?"), max_members, call_origin()])
	_print_account_diagnostics()
	_steam.call("createLobby", lobby_type, max_members)


func set_lobby_data(lobby_id: int, key: String, value: String) -> void:
	if _steam == null:
		return
	var ok: Variant = _steam.call("setLobbyData", lobby_id, key, value)
	log_line("setLobbyData lobby=%d %s=%s -> %s" % [lobby_id, key, value.left(LOG_VALUE_MAX_CHARS), str(ok)])


## Bontago-1pi.48 diagnostics: explicitly marks the lobby joinable and logs the result.
func set_lobby_joinable(lobby_id: int, joinable: bool) -> void:
	if _steam == null:
		return
	var ok: Variant = _steam.call("setLobbyJoinable", lobby_id, joinable)
	log_line("setLobbyJoinable lobby=%d joinable=%s -> %s" % [lobby_id, str(joinable), str(ok)])


const _LOBBY_TYPE_NAMES: Dictionary = {0: "Private", 1: "FriendsOnly", 2: "Public", 3: "Invisible", 4: "PrivateUnique"}
## Candidate GodotSteam account getters; only those the installed API exposes are printed.
const _ACCOUNT_DIAG_METHODS: Array[String] = [
	"getSteamID", "getPersonaName", "getPersonaState", "isSubscribed", "loggedOn", "isLimitedAccount", "isLimited", "getAppID"
]


func _print_account_diagnostics() -> void:
	var parts: PackedStringArray = PackedStringArray()
	for m: String in _ACCOUNT_DIAG_METHODS:
		if _steam != null and _steam.has_method(m):
			parts.append("%s=%s" % [m, str(_steam.call(m))])
	log_line("account: " + (" ".join(parts) if not parts.is_empty() else "(no account getters exposed)"))


## `--steam-lobby-debug`: unfiltered request with Steam's default distance filter (nearest first).
func request_unfiltered_debug_list() -> void:
	if _steam == null:
		return
	_steam.call("requestLobbyList")


func get_lobby_data(lobby_id: int, key: String) -> String:
	if _steam == null:
		return ""
	return String(_steam.call("getLobbyData", lobby_id, key))


func lobby_owner(lobby_id: int) -> int:
	if _steam == null:
		return 0
	return int(_steam.call("getLobbyOwner", lobby_id))


func lobby_member_count(lobby_id: int) -> int:
	if _steam == null:
		return 0
	return int(_steam.call("getNumLobbyMembers", lobby_id))


func join_lobby(lobby_id: int) -> void:
	if _steam == null:
		return
	log_line("joinLobby lobby=%d origin=%s" % [lobby_id, call_origin()])
	_steam.call("joinLobby", lobby_id)


## `reason` names the Net path that gave up the lobby (Bontago-1pi.48: a host
## leaving its own lobby must always be visible in the log).
func leave_lobby(lobby_id: int, reason: String = "") -> void:
	if _steam == null:
		return
	log_line("leaveLobby lobby=%d reason=%s origin=%s" % [lobby_id, reason, call_origin()])
	_steam.call("leaveLobby", lobby_id)


## Bontago-1pi.48 diagnostics: one line describing what Steam itself reports for
## `lobby_id` (membership, owner vs this account, member limit, all lobby data).
func self_check_line(lobby_id: int) -> String:
	if _steam == null:
		return "lobby=%d (Steam not initialised)" % lobby_id
	var me: int = local_steam_id()
	var owner_id: int = lobby_owner(lobby_id)
	var limit: String = str(_steam.call("getLobbyMemberLimit", lobby_id)) if _steam.has_method("getLobbyMemberLimit") else "?"
	var data: String = str(_steam.call("getAllLobbyData", lobby_id)) if _steam.has_method("getAllLobbyData") else "?"
	return "lobby=%d members=%d member_limit=%s owner=%d me=%d owner_is_me=%s data=%s" % [
		lobby_id, lobby_member_count(lobby_id), limit, owner_id, me, str(owner_id == me and me != 0),
		data.left(SELFCHECK_DATA_MAX_CHARS)]


## `string_filters` is `[{"key": String, "value": String}, ...]`, ANDed by
## Steam's own request_lobby_list(); applied fresh before every call since
## Steamworks does not persist filters between requests.
## Valve ELobbyDistanceFilter ordinal (Close=0, Default=1, Far=2, Worldwide=3).
## Bontago-1pi.48: Steam's default distance filter only returns lobbies in the
## searcher's own/nearby region, so a friend elsewhere never saw the host's
## lobby; search worldwide (results stay filtered to this game + version).
const LOBBY_DISTANCE_FILTER_WORLDWIDE: int = 3


func request_lobby_list(string_filters: Array[Dictionary]) -> void:
	if _steam == null:
		return
	_steam.call("addRequestLobbyListDistanceFilter", LOBBY_DISTANCE_FILTER_WORLDWIDE)
	var desc: PackedStringArray = PackedStringArray()
	for f: Dictionary in string_filters:
		desc.append("%s=%s" % [f.get("key", ""), f.get("value", "")])
	log_line("lobby request: distance=worldwide(3) filters: " + ", ".join(desc))
	for filter: Dictionary in string_filters:
		_steam.call(
			"addRequestLobbyListStringFilter",
			String(filter.get("key", "")),
			String(filter.get("value", "")),
			_LOBBY_COMPARISON_EQUAL
		)
	_steam.call("requestLobbyList")


func activate_invite_overlay(lobby_id: int) -> void:
	if _steam == null:
		return
	_steam.call("activateGameOverlayInviteDialog", lobby_id)


func _wire_signals() -> void:
	if _steam == null:
		return
	if not _steam.is_connected(&"lobby_created", Callable(self, "_on_lobby_created")):
		_steam.connect(&"lobby_created", Callable(self, "_on_lobby_created"))
	if not _steam.is_connected(&"lobby_match_list", Callable(self, "_on_lobby_match_list")):
		_steam.connect(&"lobby_match_list", Callable(self, "_on_lobby_match_list"))
	if not _steam.is_connected(&"lobby_data_update", Callable(self, "_on_lobby_data_update")):
		_steam.connect(&"lobby_data_update", Callable(self, "_on_lobby_data_update"))
	if not _steam.is_connected(&"lobby_joined", Callable(self, "_on_lobby_joined")):
		_steam.connect(&"lobby_joined", Callable(self, "_on_lobby_joined"))
	if not _steam.is_connected(&"join_requested", Callable(self, "_on_join_requested")):
		_steam.connect(&"join_requested", Callable(self, "_on_join_requested"))


func _on_lobby_created(result: int, lobby_id: int) -> void:
	lobby_created.emit(result, lobby_id)


func _on_lobby_match_list(lobby_ids: Array) -> void:
	lobby_match_list.emit(lobby_ids)


func _on_lobby_data_update(_success: int, lobby_id: int, _member_id: int) -> void:
	lobby_data_updated.emit(lobby_id)


func _on_lobby_joined(lobby_id: int, permissions: int, locked: bool, response: int) -> void:
	log_line("lobby_joined (LobbyEnter) lobby=%d permissions=%d locked=%s response=%d" % [lobby_id, permissions, str(locked), response])
	lobby_joined.emit(lobby_id, response)


func _on_join_requested(lobby_id: int, friend_id: int) -> void:
	lobby_join_requested.emit(lobby_id, friend_id)


## Serializes a MatchConfig.to_dict()-shaped Dictionary as one lobby-data
## value (research's decision: one JSON string, not a key per field). Split
## out from any Steam call so a unit test can assert the round trip without
## the singleton — mirrors net/LanDiscovery.gd's encode_advert/decode_advert
## split.
static func encode_match_config(data: Dictionary) -> String:
	return JSON.stringify(data)


## Malformed, truncated, random, or oversized text decodes to {} without
## erroring — same contract as LanDiscovery.decode_advert() for a foreign
## payload.
##
## DECISION/bugfix: the static convenience function `JSON.parse_string()`
## returns null on invalid input as documented, but it *also* prints an
## engine `ERROR: Parse JSON failed...` line (core/io/json.cpp) on every
## malformed call — confirmed empirically
## (netcode-F-gut-quick.log/netcode-F-probe_json.log), and GUT counts that as
## an "Unexpected Error" test failure, not a silent {} return. A per-call
## `JSON.new()` instance's `parse()` returns the same information as an
## `Error` code with no engine-level print, so this is the version that
## actually meets "without erroring".
static func decode_match_config(text: String) -> Dictionary:
	if text.is_empty():
		return {}
	if text.to_utf8_buffer().size() > _DEFAULT_CONFIG.steam_lobby_data_max_bytes:
		return {}
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {}
	var parsed: Variant = json.get_data()
	if not (parsed is Dictionary):
		return {}
	return parsed as Dictionary
