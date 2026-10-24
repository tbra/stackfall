class_name NetSteamSession
extends RefCounted
## The Steam lobby session of the Net autoload: creating and joining a lobby (a
## generation counter plus a FIFO of pending requests, because Steam's answers
## carry no call id), the lobby list, invites, the periodic self-check and the
## Steam init state. It owns no peer and no mode: when an answer lands it builds
## the transport peer and emits host_ready / client_ready, and Net seats it.

## A host lobby exists and its transport peer is built; Net turns it into HOST.
signal host_ready(peer: MultiplayerPeer, lobby_id: int, host_name: String)
## A joined lobby has its transport peer; Net turns it into CLIENT.
signal client_ready(peer: MultiplayerPeer, lobby_id: int, local_name: String)
## A request failed before any session existed (Events.net_join_failed only).
signal request_failed(error: int, detail: String)
## A joined lobby could not become a session (Net's full join-failure path).
signal join_refused(error: int, detail: String)
signal lobbies_discovered(lobbies: Array[Dictionary])


class Seams extends RefCounted:
	## () -> bool : Net has no session (mode OFFLINE).
	var is_offline: Callable = Callable()
	## () -> bool : this instance is the host.
	var is_host: Callable = Callable()
	## () -> void : Net.leave().
	var leave_session: Callable = Callable()
	## () -> Dictionary : the host's published lobby settings.
	var lobby_data: Callable = Callable()
	## () -> String : this build's version.
	var build_version: Callable = Callable()
	## (typed: String) -> String : the display name the local player goes by.
	var local_name: Callable = Callable()


## Steamworks EResult / EChatRoomEnterResponse success, both 1.
const _STEAM_OK: int = 1
const _CREATE_REQUEST: int = -1
## A lobby list request this old is presumed lost, so a new refresh may go out.
const LOBBY_LIST_STALE_MSEC: int = 15000
## --steam-lobby-debug prints the game/version data of at most this many unfiltered lobbies.
const LOBBY_DEBUG_SAMPLE_COUNT: int = 5
## Seconds between `STEAM SELFCHECK` lines while a session is live.
const SELFCHECK_PERIOD_S: float = 10.0

enum LobbyListPending { NONE, FILTERED, DEBUG }

var config: NetConfig = NetConfig.new()
var seams: NetSteamSession.Seams = NetSteamSession.Seams.new()
## `--steam-lobby-debug`; a var so tests can toggle it.
var steam_lobby_debug: bool = OS.get_cmdline_user_args().has("--steam-lobby-debug")
## Swapping the provider (tests install a FakeSteam) wires its signals once.
var steam: SteamClient = null:
	set(value):
		if value == steam:
			return
		steam = value
		if steam == null:
			return
		steam.init_result.connect(_on_init_result)
		steam.lobby_created.connect(_on_lobby_created)
		steam.lobby_match_list.connect(_on_lobby_match_list)
		steam.lobby_joined.connect(_on_lobby_joined)
		steam.lobby_join_requested.connect(_on_lobby_join_requested)

var _transport: NetTransport
var _initialized: bool = false
## True once init_result reported status 0 (steamInitEx succeeded).
var _ready: bool = false
## True once a live Steam peer exists.
var _live: bool = false
var _lobby_id: int = 0
## The player_name of the pending host_online()/join_lobby().
var _pending_name: String = ""
## Bumped by leave(). Each unanswered request is queued under the generation it
## was issued in; an answer pops its entry, and one from an older generation
## belongs to a cancelled attempt: a success is handed to leave_lobby() so no
## lobby is orphaned and the live attempt stays pending.
## DECISION: the signals carry no call id, so which queued request an answer
## resolves is FIFO by issue order (a join answer matches its own lobby id first).
var _generation: int = 0
var _pending_generations: Array[int] = []
## Parallel to _pending_generations: the lobby id a join targets, or _CREATE_REQUEST.
var _pending_targets: Array[int] = []
## Every lobby this process created. Steam sends the creator a lobby_joined echo
## for it, which is not a join answer and must never reach the stray-answer leave.
var _created_lobbies: Dictionary = {}
var _discovered: Array[Dictionary] = []
var _list_pending: LobbyListPending = LobbyListPending.NONE
var _list_refresh_queued: bool = false
var _list_sent_msec: int = 0
var _selfcheck_accum: float = 0.0


func _init(provider: SteamClient, transport: NetTransport) -> void:
	_transport = transport
	steam = provider


## Steamworks is manual-dispatch: pumped every frame once Steam is ready (the
## list and join calls are legal from the menu, before any session). Also ticks
## the self-check.
func process(delta: float) -> void:
	if _ready and steam != null:
		steam.run_callbacks()
	if not _live or _lobby_id == 0 or steam == null:
		return
	_selfcheck_accum += delta
	if _selfcheck_accum < SELFCHECK_PERIOD_S:
		return
	_selfcheck_accum = 0.0
	var role: String = "HOST" if bool(seams.is_host.call()) else "CLIENT"
	SteamClient.log_line("SELFCHECK role=%s %s" % [role, steam.self_check_line(_lobby_id)])


## Idempotent: steamInitEx through the provider.
func init() -> void:
	if _initialized:
		return
	_initialized = true
	if steam != null:
		steam.init()


## False until the addon is present and steamInitEx succeeded.
func available() -> bool:
	return steam != null and bool(steam.is_available()) and _ready


func is_live() -> bool:
	return _live


func lobby_id() -> int:
	return _lobby_id


func persona_name() -> String:
	return steam.local_persona_name()


func discovered_lobbies() -> Array[Dictionary]:
	return _discovered.duplicate(true)


## True while a request of the current generation is unanswered.
func request_pending() -> bool:
	return _pending_generations.has(_generation)


## OK means the attempt started; the answer lands in _on_lobby_created().
func host_online(player_name: String = "") -> Error:
	if not available():
		return ERR_UNAVAILABLE
	if request_pending():
		return ERR_BUSY
	if not bool(seams.is_offline.call()):
		seams.leave_session.call()
	_pending_generations.append(_generation)
	_pending_targets.append(_CREATE_REQUEST)
	_pending_name = player_name
	steam.create_lobby(config.steam_lobby_type, config.max_peers)
	return OK


## Same contract as host_online(); the answer lands in _on_lobby_joined().
func join_lobby(lobby_id: int, player_name: String = "") -> Error:
	if not available():
		return ERR_UNAVAILABLE
	if request_pending():
		return ERR_BUSY
	if not bool(seams.is_offline.call()):
		seams.leave_session.call()
	_pending_generations.append(_generation)
	_pending_targets.append(lobby_id)
	_pending_name = player_name
	steam.join_lobby(lobby_id)
	return OK


## Asks Steam for the lobbies of this game and exact build; the answer lands in
## _on_lobby_match_list().
func refresh_lobby_list() -> void:
	if not available():
		return
	# Steam keeps one outstanding lobby list request; never overlap.
	if _list_pending != LobbyListPending.NONE and Time.get_ticks_msec() - _list_sent_msec < LOBBY_LIST_STALE_MSEC:
		_list_refresh_queued = true
		SteamClient.log_line("lobby search: refresh coalesced, a request is still pending")
		return
	var filters: Array[Dictionary] = [
		{"key": String(SteamClient.KEY_GAME), "value": String(NetIds.DISCOVERY_MAGIC)},
		{"key": String(SteamClient.KEY_VERSION), "value": String(seams.build_version.call())},
	]
	steam.request_lobby_list(filters)
	_list_pending = LobbyListPending.FILTERED
	_list_sent_msec = Time.get_ticks_msec()


## Cancels every unanswered request (their late answers become stale) and leaves
## the live lobby. Safe at any time; Net.leave() calls it before anything else
## because a pending request never moves Net off OFFLINE.
func leave() -> void:
	_generation += 1
	if _live and steam != null and _lobby_id != 0:
		steam.leave_lobby(_lobby_id, "Net.leave()")
	_live = false
	_lobby_id = 0
	_pending_name = ""
	_selfcheck_accum = 0.0


## Opens the overlay's invite dialog; a no-op off Steam or before the lobby exists.
func open_invite_overlay() -> void:
	if not available() or not _live or _lobby_id == 0:
		return
	steam.activate_invite_overlay(_lobby_id)


## Host: tees the lobby settings into the lobby data under one JSON key.
func publish_match_config(data: Dictionary) -> void:
	if _live and steam != null and _lobby_id != 0:
		steam.set_lobby_data(_lobby_id, String(SteamClient.KEY_MATCH_CONFIG), SteamClient.encode_match_config(data))


## Whether the provider may build a real SteamMultiplayerPeer (never a test double).
func _real_provider() -> bool:
	return steam.get_script() == SteamClient


func _on_init_result(status: int, _verbal: String) -> void:
	_ready = status == 0


## Pops the request entry `index` resolves (-1: none matches) and reports whether
## the answer is stale; a stale or stray success is handed to leave_lobby().
func _answer_is_stale(index: int, ok: bool, lobby_id: int) -> bool:
	if index < 0 or index >= _pending_generations.size():
		if ok:
			steam.leave_lobby(lobby_id, "stray answer: no pending request matches it")
		return true
	var answer_generation: int = _pending_generations[index]
	_pending_generations.remove_at(index)
	_pending_targets.remove_at(index)
	if answer_generation != _generation:
		if ok:
			steam.leave_lobby(lobby_id, "stale answer: leave() cancelled its request")
		return true
	return false


func _first_pending_join_index() -> int:
	for i: int in _pending_targets.size():
		if _pending_targets[i] != _CREATE_REQUEST:
			return i
	return -1


## True for Steam's LobbyEnter echo of a lobby this process created (or a repeat
## enter of the one it is in): a success no join_lobby() asked for. The order
## against lobby_created is not relied on.
func _is_own_lobby_enter_echo(lobby_id: int, response: int) -> bool:
	if response != _STEAM_OK or _pending_targets.find(lobby_id) >= 0:
		return false
	if _created_lobbies.has(lobby_id):
		return true
	if _live and lobby_id == _lobby_id:
		return true
	return _pending_targets.find(_CREATE_REQUEST) >= 0


func _on_lobby_created(result: int, lobby_id: int) -> void:
	SteamClient.log_line("lobby_created: result=%d lobby_id=%d" % [result, lobby_id])
	if result == _STEAM_OK:
		_created_lobbies[lobby_id] = true
	if _answer_is_stale(_pending_targets.find(_CREATE_REQUEST), result == _STEAM_OK, lobby_id):
		return
	if not bool(seams.is_offline.call()):
		return
	if result != _STEAM_OK:
		request_failed.emit(Net.JoinError.TRANSPORT, "Steam lobby creation failed (result %d)" % result)
		return
	var host_name: String = PlayerNames.sanitize(
		String(seams.local_name.call(_pending_name)), config.max_player_name_length, 0
	)
	var version: String = String(seams.build_version.call())
	# Tagged before the peer is built: the lobby-data half stays testable with a fake alone.
	steam.set_lobby_data(lobby_id, String(SteamClient.KEY_GAME), String(NetIds.DISCOVERY_MAGIC))
	steam.set_lobby_data(lobby_id, String(SteamClient.KEY_VERSION), version)
	steam.set_lobby_data(lobby_id, String(SteamClient.KEY_MAP), "")
	steam.set_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME), host_name)
	steam.set_lobby_data(
		lobby_id, String(SteamClient.KEY_MATCH_CONFIG), SteamClient.encode_match_config(seams.lobby_data.call())
	)
	steam.set_lobby_joinable(lobby_id, true)
	SteamClient.log_line("lobby readback: game=%s version=%s" % [
		steam.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME)),
		steam.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION))])
	var peer: MultiplayerPeer = _transport.make_steam_host_peer(_ready, _real_provider())
	if peer == null:
		request_failed.emit(Net.JoinError.TRANSPORT, "SteamMultiplayerPeer unavailable")
		steam.leave_lobby(lobby_id, "host peer unavailable")
		return
	_live = true
	_lobby_id = lobby_id
	_selfcheck_accum = 0.0
	host_ready.emit(peer, lobby_id, host_name)


func _on_lobby_joined(lobby_id: int, response: int) -> void:
	# The creator also gets a lobby_joined for its own new lobby; treating it as a
	# stray answer would leave the lobby and kill every game-hosted lobby.
	if _is_own_lobby_enter_echo(lobby_id, response):
		SteamClient.log_line("lobby_joined: lobby=%d is this process's own lobby enter (creator echo); ignored" % lobby_id)
		return
	var index: int = _pending_targets.find(lobby_id)
	if index < 0:
		# DECISION: an answer matching no pending join resolves the oldest pending join, never a create.
		index = _first_pending_join_index()
	if _answer_is_stale(index, response == _STEAM_OK, lobby_id):
		return
	if not bool(seams.is_offline.call()):
		return
	if response != _STEAM_OK:
		join_refused.emit(Net.JoinError.REFUSED, "could not join Steam lobby (response %d)" % response)
		return
	var peer: MultiplayerPeer = _transport.make_steam_client_peer(steam.lobby_owner(lobby_id), _ready, _real_provider())
	if peer == null:
		# Already a lobby member, but _live is not set yet and leave() would no-op.
		steam.leave_lobby(lobby_id, "client peer unavailable")
		join_refused.emit(Net.JoinError.TRANSPORT, "SteamMultiplayerPeer unavailable")
		return
	_live = true
	_lobby_id = lobby_id
	_selfcheck_accum = 0.0
	client_ready.emit(peer, lobby_id, String(seams.local_name.call(_pending_name)))


func _on_lobby_match_list(lobby_ids: Array) -> void:
	if _list_pending == LobbyListPending.DEBUG:
		_list_pending = LobbyListPending.NONE
		var lines: PackedStringArray = PackedStringArray()
		for i: int in mini(LOBBY_DEBUG_SAMPLE_COUNT, lobby_ids.size()):
			var id: int = int(lobby_ids[i])
			lines.append("%d{owner=%d members=%d game=%s version=%s}" % [id, steam.lobby_owner(id), steam.lobby_member_count(id), steam.get_lobby_data(id, String(SteamClient.KEY_GAME)), steam.get_lobby_data(id, String(SteamClient.KEY_VERSION))])
		SteamClient.log_line("unfiltered debug search (answers the unfiltered request): %d lobbies visible; first: %s" % [lobby_ids.size(), " ".join(lines)])
		_drain_queued_refresh()
		return
	var was_filtered: bool = _list_pending == LobbyListPending.FILTERED
	_list_pending = LobbyListPending.NONE
	if was_filtered and steam_lobby_debug:
		# Sent only after the filtered answer, so Steam never cancels one for the other.
		steam.request_unfiltered_debug_list()
		_list_pending = LobbyListPending.DEBUG
		_list_sent_msec = Time.get_ticks_msec()
	var version: String = String(seams.build_version.call())
	var result: Array[Dictionary] = []
	for raw_id: Variant in lobby_ids:
		var lobby_id: int = int(raw_id)
		if steam.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME)) != String(NetIds.DISCOVERY_MAGIC) \
				or steam.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION)) != version:
			continue
		result.append({
			"lobby_id": lobby_id,
			"name": steam.get_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME)),
			"players": steam.lobby_member_count(lobby_id),
			"max": config.max_peers,
			"map": steam.get_lobby_data(lobby_id, String(SteamClient.KEY_MAP)),
		})
	_discovered = result
	lobbies_discovered.emit(result)
	SteamClient.log_line("lobby search (answers the filtered request): %d lobbies returned, %d match game+version %s" % [lobby_ids.size(), result.size(), version])
	_drain_queued_refresh()


func _drain_queued_refresh() -> void:
	if _list_refresh_queued and _list_pending == LobbyListPending.NONE:
		_list_refresh_queued = false
		refresh_lobby_list()


## The overlay's "Join Game" / invite-accept while the game runs (the other
## invite path, +connect_lobby, is Net's command line).
func _on_lobby_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_lobby(lobby_id, "")
