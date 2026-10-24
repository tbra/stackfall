extends NetSession
## NetworkManager: transport selection, host/join, LAN discovery, peer registry
## (spec 2.6).
##
## Gameplay code only ever talks to MultiplayerAPI; this node decides whether
## the peer underneath is ENet (LAN, direct IP, tests) or Steam.
## **Swapping the transport must be a change to net/session/NetTransport.gd
## and nothing else** — no other file in the project may name
## ENetMultiplayerPeer, an IP address, or a port.
##
## Net owns the *session*: who is connected, which slot each peer holds, the
## build-version handshake, ping, lobby data, and the lag/loss simulator. It
## owns no gameplay: placements, snapshots and territory live in
## net/MatchNet.gd and net/SnapshotSync.gd.
##
## No `class_name`: this script is the `Net` autoload, and a class_name would
## collide with the singleton (the same reason Events, Settings and Match have
## none). Other packages reach the enums as `Net.Mode.HOST`, or use the
## is_host() / is_client() / is_offline() predicates, which is what gameplay
## code should prefer.

## What this instance is. OFFLINE covers the main menu and every single-PC
## mode including local play, and is_host() is true in it, so rule code
## written as `if not Net.is_host(): return` behaves identically offline.
enum Mode { OFFLINE, HOST, CLIENT }

## Why a join attempt failed. The lobby shows a message per case.
enum JoinError { NONE, TIMEOUT, VERSION_MISMATCH, SERVER_FULL, MATCH_IN_PROGRESS, REFUSED, TRANSPORT }

## Why a peer left, carried on Events.net_peer_left.
const LeaveReason = NetIds.LeaveReason

## Peer id of the listen-server host. Godot fixes this at 1; named here so no
## other file writes the literal.
const HOST_PEER_ID: int = NetRoster.HOST_PEER_ID

## Key the LAN advert carries so a stray UDP broadcast on 47777 is ignored.
## Defined in core/net/NetIds.gd; aliased here.
const DISCOVERY_MAGIC: StringName = NetIds.DISCOVERY_MAGIC

## Steam's public test app ("Spacewar"), passed directly into
## Steam.steamInitEx() (no steam_appid.txt is needed once the app id is
## passed as an argument). Named here, not in
## net/SteamClient.gd, per the tunables table in config/net/NetConfig.gd.
const STEAM_APP_ID_EXPECTED: int = NetIds.STEAM_APP_ID_EXPECTED

## Size of a rejoin token (random bytes; hex doubles it) and
## the longest token string the handshake will even look up. Defined in
## net/session/NetRoster.gd; aliased here.
const REJOIN_TOKEN_BYTES: int = NetRoster.REJOIN_TOKEN_BYTES
const REJOIN_TOKEN_MAX_CHARS: int = NetRoster.REJOIN_TOKEN_MAX_CHARS

@export var config: NetConfig = preload("res://config/net/net_config.tres"):
	set(value):
		config = value
		net_roster.config = value

## Who is seated where, ready flags, rejoin tokens and reservations, slot compaction
## and the handshake gate (net/session/NetRoster.gd). On the host this is the source
## of truth; on a client it is a mirror kept in sync by _rpc_roster_update.
var net_roster: NetRoster = NetRoster.new(config)

var _mode: Mode = Mode.OFFLINE
## The peer this instance created, generic MultiplayerPeer only — never typed
## or cast to ENetMultiplayerPeer outside net/session/NetTransport.gd.
var _peer: MultiplayerPeer = null

## Host only: peer_id -> deadline (seconds, _now()) by which the peer must
## have sent its handshake, or it is dropped.
var _pending_handshake: Dictionary = {}
## The ENet/Steam peer factories, dead-peer timeouts, link predicates and the
## set of peers kick_peer() or a refusal is still disconnecting
## (net/session/NetTransport.gd). Public so a FakeSteam test can set
## `transport.steam_host_peer_factory`.
var transport: NetTransport = NetTransport.new()
## The host-side collaborators (net/session): lobby intents, chat and ping share one
## flood gate built from NetConfig in _ready, so a leaver is forgotten once.
var _flood: PeerFloodGate = null
var _lobby: NetLobbyIntents = null
var _chat: NetChatService = null
var _ping: NetPing = null

## -- Player chat ----------------------------------------------------------------
## Tunables (clamped in _ready like `config`).
var chat_config: ChatConfig = preload("res://config/net/chat_config.tres")
## The lobby seat table key inside the published lobby data (ui/lobby/Lobby.gd SEATS_KEY).
const _CHAT_LOBBY_SEATS_KEY: String = "seats"
const _CHAT_JOINED_FORMAT: String = "%s joined"
const _CHAT_LEFT_FORMAT: String = "%s left"
## True for a private loopback host (host_game(..., advertise=false), the
## Vs bots session); lets the lobby badge say so instead of "LAN". Cleared by leave().
var _private_session: bool = false

## -- Mid-match join and reconnect (spec 2.6 "Late join / reconnect") ----------
## The match phase, the rejoin tokens and reservations and the installed seat policy
## (set_seat_policy()) live in `net_roster`: a handshake quoting a reserved token reclaims
## that slot if the seat policy still calls it reclaimable (inside its NetConfig.
## disconnect_grace). Net never decides what "open" means: that is a gameplay question.
## Client only: the token the host issued on our last accepted join. Survives
## a connection loss on purpose (leave(false)), so a dropped player who joins
## the same host again (the direct-IP field, the LAN browser or the Steam
## lobby) quotes it and gets its slot back. A deliberate leave() clears it, and
## it is only ever sent to the host it came from (_rejoin_scope). DECISION:
## memory only -- a crashed and restarted client has no token and rejoins as a new late joiner. Persisting
## it would write a bearer credential to disk for a window that is only
## NetConfig.disconnect_grace long.
var _rejoin_token: String = ""
## Which host issued _rejoin_token: "enet:<address>:<port>" or "steam:<lobby>".
var _rejoin_scope: String = ""
## Last peer id local_peer_id() read from a live transport.
var _last_local_peer_id: int = 0
## Scope of the ENet connection the client is making now (join_game()).
var _join_scope: String = ""

## Snapshot of build_version() taken when hosting started, so the version a
## host advertises for a session can never drift even if something else
## rewrites ProjectSettings mid-run (and so the comparison in _rpc_handshake
## has one unambiguous value to check against).
var _host_build_version: String = ""

## The port host_game() actually bound (it may differ from config.game_port —
## --port= overrides it so several hosts can share a PC), so the LAN advert
## and any caller asking "what port is this" tell the truth.
var _host_port: int = 0

var _local_slot: int = 0
var _join_deadline: float = 0.0
## Client only: this instance's own ping to the host, reported down by the
## host (the host measures the RTT; the client cannot measure it itself).
var _own_ping_ms: float = 0.0

var _lobby_data: Dictionary = {}
var _lan: LanDiscovery

## Router port opening (UPnP) for non-Steam internet hosting. The real backend is
## built only for the real autoload on a windowed, non-agent run; tests set `upnp_backend_factory`
## to a Callable returning a fake UpnpBackend and never touch a router.
signal upnp_state_changed(state: int)
var upnp_config: UpnpConfig = preload("res://config/net/upnp_config.tres")
var upnp_backend_factory: Callable = Callable()
var _upnp: UpnpRunner = UpnpRunner.new()
## Set by attach_global_wiring(): only the running game may reach a real router.
var _real_upnp: bool = false
## LAN advert + UPnP glue and the join code (net/session/NetHostAdverts.gd); built in _ready().
var _adverts: NetHostAdverts

## `--match-config=<res path>`: host-only override for the MatchConfig a
## `--headless-host` match starts from. Null means "no override" --
## game/main/Main.gd's _build_headless_bot_config() then falls back to its
## preloaded config/match/match_defaults.tres. Set only from
## _apply_command_line_args()'s host branch (see _load_match_config_override()),
## never by --join, so a client passing this flag is silently ignored (spec
## 2.6: only the host's MatchConfig ever matters).
var _match_config_override: MatchConfig = null

## The Steam-facing seam, the same net_provider/match_provider pattern
## ui/menus/MainMenu.gd, ui/lobby/Lobby.gd and ui/debug/NetDebugOverlay.gd use.
## A real SteamClient from _ready(); tests overwrite it with a FakeSteam.
var steam_provider: SteamClient:
	get:
		return _steam.steam
	set(value):
		_steam.steam = value
## The Steam lobby session; Net seats the peers it builds.
var _steam: NetSteamSession = null

var _sim: NetSim = NetSim.new()
## Cross-package stats reported via report_stats(), folded into stats().
var _report: Dictionary = {}

var _stats_accum: float = 0.0


func _ready() -> void:
	# The shipped resource goes through the same clamps every other config
	# does, so a hand-edited net_config.tres (a zero
	# seat_pref_burst, a tiny packet cap) cannot lock clients out or break the wire.
	config.sanitize()
	# Keep transport/Steam/UPnP/handshake/ping polling alive while the offline
	# pause menu has paused the tree, so a peer joining during a solo pause still gets through.
	process_mode = Node.PROCESS_MODE_ALWAYS
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_lan = LanDiscovery.new()
	_lan.name = "LanDiscovery"
	_lan.config = config
	add_child(_lan)
	_lan.game_seen.connect(_on_lan_advert_changed)
	_lan.game_expired.connect(_on_lan_advert_expired)
	_adverts = NetHostAdverts.new(_lan, _upnp, config)
	_adverts.backend_source = _upnp_backend
	_adverts.upnp_state_changed.connect(upnp_state_changed.emit)
	_build_steam_session()
	# The host mirrors the loading-screen ready gate to clients.
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	chat_config.sanitize()
	_build_session_services()


## Global wiring that only the running game performs (Main._ready): the UI chat bus
## and the real UPnP backend. Test instances skip it and call send_chat() directly.
## Safe to call twice.
func attach_global_wiring() -> void:
	_real_upnp = true
	if not Events.chat_send_requested.is_connected(send_chat):
		Events.chat_send_requested.connect(send_chat)


func _process(delta: float) -> void:
	_adverts.poll()
	# Steamworks is a manual-dispatch API: every async Steam signal (lobby
	# creation, the lobby list, joins, invite-accepts) is queued internally
	# and never fires without this (see net/SteamClient.gd's run_callbacks()).
	# Gated on Steam being ready inside NetSteamSession, not
	# steam_available()/is_steam_session(), because a caller can legitimately
	# call refresh_lobby_list() or join_lobby() from the main menu before any
	# session exists — those need callbacks pumped too.
	_steam.process(delta)

	var now: float = _now()
	if _mode == Mode.HOST:
		_tick_handshake_timeouts(now)
		_ping.tick(Time.get_ticks_msec())
	elif _mode == Mode.CLIENT:
		if not net_roster.joined_accepted and now > _join_deadline:
			_fail_join(JoinError.TIMEOUT, "no response from host")

	_stats_accum += delta
	var stats_interval: float = 1.0 / maxf(config.stats_hz, 0.001)
	if _stats_accum >= stats_interval:
		_stats_accum = fmod(_stats_accum, stats_interval)
		Events.net_stats_updated.emit(stats())


# --- Session lifecycle ------------------------------------------------------

## Starts a listen server on `port` (0 means config.game_port). A private
## local bot host uses a free loopback port, refuses remote joins, and does not
## advertise; ordinary hosts keep the existing LAN behavior. The host is slot 0.
func host_game(port: int = 0, player_name: String = "", advertise: bool = true, lan_visible: bool = true) -> Error:
	if _mode != Mode.OFFLINE:
		leave()
	var use_port: int = port if port > 0 else config.game_port
	if not advertise and port <= 0:
		use_port = AgentProbe.free_udp_port()
		if use_port == 0:
			return ERR_CANT_CREATE
	# Agent runs (AgentProbe: tool/bench scenes, --agent-probe) host on a random
	# free port unless one was given, so parallel benches and the ENet harness
	# never fight over the default port.
	if port <= 0 and AgentProbe.is_active() and not AgentProbe.has_cli_port(OS.get_cmdline_user_args()):
		var free_port: int = AgentProbe.free_udp_port()
		if free_port > 0:
			use_port = free_port
	var peer: MultiplayerPeer = transport.make_host_peer(use_port, config.max_peers, not advertise)
	if peer == null:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.HOST
	_host_port = use_port
	_host_build_version = build_version()
	# The host's own name goes through the same check a joiner's
	# does, so an empty or oversized typed name is "Player 1" or cut, everywhere.
	var host_name: String = PlayerNames.sanitize(resolve_local_name(player_name), config.max_player_name_length, 0)
	net_roster.add_host(host_name, _host_build_version, advertise)
	_private_session = not advertise
	_reset_rejoin_state()
	Events.net_mode_changed.emit(_mode)
	mode_changed.emit(_mode)
	# Agent runs must not appear in the owner's LAN browser.
	# `lan_visible=false` keeps the normal "*" bind and open joins but skips the
	# broadcast (headless bot hosts must not show up in a Join browser).
	_adverts.upnp_config = upnp_config
	_adverts.start(advertise and lan_visible, use_port, host_name, net_roster.peers.size(), build_version(), not AgentProbe.is_active())
	return OK


## Connects to `address`:`port`. Emits Events.net_join_failed and returns to
## OFFLINE if the handshake is refused or times out.
func join_game(address: String, port: int = 0, player_name: String = "") -> Error:
	if _mode != Mode.OFFLINE:
		leave()
	var use_port: int = port if port > 0 else config.game_port
	var peer: MultiplayerPeer = transport.make_client_peer(address, use_port)
	if peer == null:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.CLIENT
	# Cleaned here so a bad name is never sent; "" stays "" (the
	# host seats the joiner as "Player N"). The host re-checks it regardless.
	net_roster.begin_client(PlayerNames.clean(resolve_local_name(player_name), config.max_player_name_length))
	_join_scope = "enet:%s:%d" % [address, use_port]
	_join_deadline = _now() + config.connect_timeout + config.handshake_timeout
	Events.net_mode_changed.emit(_mode)
	mode_changed.emit(_mode)
	return OK


## Leaves whatever session is running and returns to OFFLINE. Safe to call
## when already offline. The host disconnects everyone with
## LeaveReason.HOST_SHUTDOWN first. A deliberate leave forgets the rejoin
## token; the connection-lost and failed-join paths pass false to keep it.
func leave(forget_rejoin: bool = true) -> void:
	# DECISION: first and unconditional: a pending host_online()/join_lobby() never
	# moves _mode off OFFLINE, so a caller cancelling mid-attempt would otherwise
	# never reach the teardown. See NetSteamSession.leave().
	_steam.leave()
	if forget_rejoin:
		_rejoin_token = ""
		_rejoin_scope = ""
	if _mode == Mode.OFFLINE:
		return
	if _mode == Mode.HOST:
		for peer_id: int in net_roster.peers.keys():
			if peer_id != HOST_PEER_ID:
				Events.net_peer_left.emit(peer_id, net_roster.slot_of_peer(peer_id), LeaveReason.HOST_SHUTDOWN)

	_adverts.stop()
	_lan.stop_listening()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	_mode = Mode.OFFLINE
	net_roster.end_session()
	_ping.reset()
	_pending_handshake.clear()
	_local_slot = 0
	_own_ping_ms = 0.0
	_lobby_data = {}
	_private_session = false
	_reset_rejoin_state()
	Events.net_mode_changed.emit(_mode)
	mode_changed.emit(_mode)


func mode() -> Mode:
	return _mode


## True on the host **and offline**. This is the single predicate that gates
## host-only work (Match's solve and feed, Field's kill plane, SnapshotSync's
## sender). Never branch on multiplayer.is_server() directly: with no peer set
## its answer depends on engine internals, and it says nothing about Steam.
func is_host() -> bool:
	return _mode == Mode.HOST or _mode == Mode.OFFLINE


func is_client() -> bool:
	return _mode == Mode.CLIENT


func is_offline() -> bool:
	return _mode == Mode.OFFLINE


## True when
## no remote human shares this session, so ui/menus/PauseMenu.gd may pause the whole tree.
func is_solo_session() -> bool:
	return solo_session_rule(is_offline(), is_client(), peer_ids(), local_peer_id())


## Pure rule behind is_solo_session(). Offline (sandbox/local play/tutorial) is solo; a client
## never is (host authority); a host is solo only when its roster holds nobody but itself, which
## is how Vs bots starts. `peer_ids` includes the host's own id.
static func solo_session_rule(offline: bool, client: bool, peers: PackedInt32Array, local_id: int) -> bool:
	if client:
		return false
	if offline:
		return true
	for id: int in peers:
		if id != local_id:
			return false
	return true


## This instance's multiplayer peer id, or HOST_PEER_ID when offline.
func local_peer_id() -> int:
	if _mode == Mode.OFFLINE:
		return HOST_PEER_ID
	# While the transport is already closed (the server_disconnected
	# path emits net_peer_left before leave() runs, and listeners such as Sfx ask
	# "was that me?"), get_unique_id() is an engine error ("The multiplayer
	# instance isn't currently active"). Answer with the last live id instead.
	if transport.is_link_down(multiplayer):
		return _last_local_peer_id
	_last_local_peer_id = multiplayer.get_unique_id()
	return _last_local_peer_id


## The game build version both ends compare during the handshake. Reads
## ProjectSettings' application/config/version, so bumping the version there is
## all it takes to refuse older builds (spec 2.6 "Version check").
func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


# --- Peer <-> slot registry -------------------------------------------------

## Every connected peer id including the host, in slot order.
func peer_ids() -> PackedInt32Array:
	return net_roster.peer_ids()


## {"peer_id": int, "slot_id": int, "name": String, "name_auto": bool (joiners
## only: the name is the host's "Player N" for the seat), "ready": bool,
## "ping_ms": float, "build": String}. Empty for an unknown peer.
func peer_info(peer_id: int) -> Dictionary:
	return net_roster.peer_info(peer_id)


## Which PlayerSlot a peer holds, or -1. The host assigns these and broadcasts
## the roster; a client never invents one.
func slot_of_peer(peer_id: int) -> int:
	return net_roster.slot_of_peer(peer_id)


## Inverse of slot_of_peer(). -1 for an unclaimed slot (an empty seat or a
## bot's). A negative slot_id is never a seat: spectators all hold -1, so it must not match the first of them.
func peer_of_slot(slot_id: int) -> int:
	return net_roster.peer_of_slot(slot_id)


## The replicated name of the human peer seated at `slot_id`, or
## "" when no peer holds it (a bot, an empty seat, a departed player). Host and
## client read the same roster, so the loading screen and HUD show one name per
## slot on both sides; late joiners and rejoiners get theirs from the roster
## RPC the host already sends on every change.
func name_for_slot(slot_id: int) -> String:
	return net_roster.name_at_slot(slot_id)


## The slot this instance's local player controls. Offline this is
## Match.active_slot()'s business instead, so it returns 0.
func local_slot() -> int:
	if _mode == Mode.HOST:
		return 0
	if _mode == Mode.CLIENT:
		return _local_slot
	return 0


## True when `slot_id` is driven by this instance's own input. The one check
## PlayerController and the HUD use to decide "is this me?"; it is also true
## for **every** slot in offline local play, which keeps the strict turn
## alternation working.
func is_local_slot(slot_id: int) -> bool:
	if _mode == Mode.OFFLINE:
		return true
	# A spectator's local_slot() is -1; no real slot is -1.
	return slot_id >= 0 and slot_id == local_slot()


## Host only: marks a peer ready in the lobby, or drops it from the session.
func set_peer_ready(peer_id: int, ready: bool) -> void:
	if not is_host() or not net_roster.has_peer(peer_id):
		return
	net_roster.set_ready(peer_id, ready)
	# Broadcast on every accepted call, changed or not: the roster stays synchronous
	# and ordered; the caller's flood bucket bounds the rate.
	_broadcast_roster()


func kick_peer(peer_id: int, reason: LeaveReason = LeaveReason.KICKED) -> void:
	if not is_host() or not net_roster.has_peer(peer_id):
		return
	var kicked_name: String = net_roster.name_of_peer(peer_id)
	# A kicked peer forfeits its rejoin token: no reservation is made for it.
	var slot_id: int = net_roster.remove(peer_id, false)
	_forget_peer_services(peer_id)
	_pending_handshake.erase(peer_id)
	# ENet keeps a disconnecting peer in get_peers() until the
	# disconnect completes a poll later, and a send to it logs an engine error.
	# Mark it before anything below can broadcast (the roster, and whatever a
	# net_peer_left listener republishes), so it is never addressed again. A peer
	# the transport does not hold (nothing to disconnect) needs no mark.
	var link: MultiplayerPeer = multiplayer.multiplayer_peer
	if link != null and multiplayer.get_peers().has(peer_id):
		transport.mark_disconnecting(peer_id)
		link.disconnect_peer(peer_id)
	# Compact BEFORE announcing the departure, as the
	# disconnect path does, so a listener of net_peer_left (the lobby republishing
	# its data) already reads the closed-up slot ids.
	net_roster.compact()
	Events.net_peer_left.emit(peer_id, slot_id, reason)
	_broadcast_roster()
	_chat.system_line(_CHAT_LEFT_FORMAT % kicked_name)


## Client: tells the host this instance is ready to start.
func set_local_ready(ready: bool) -> void:
	if is_client():
		_rpc_set_ready.rpc_id(HOST_PEER_ID, ready)
	elif _mode == Mode.HOST:
		set_peer_ready(HOST_PEER_ID, ready)


func all_peers_ready() -> bool:
	# DECISION: the host's own entry mirrors its Ready toggle like
	# any peer's (seeded false), but pressing Start is the host's consent, so the
	# Start gate waits for every OTHER seated human only.
	return net_roster.all_ready()


## Measured round trip to `peer_id` in milliseconds, from Net's own ping RPC
## rather than any ENet statistic, so the number is identical over Steam.
func ping_ms(peer_id: int = 0) -> float:
	var target: int = peer_id
	if target == 0:
		if is_client():
			return _own_ping_ms
		target = local_peer_id()
	return net_roster.ping_of(target)


# --- Lobby data (spec 2.6: "Steam lobbies store match settings as lobby
# data"; over ENet the host broadcasts the same Dictionary reliably) ---------

## Host only: publishes the lobby settings. ui/lobby/Lobby.gd passes
## MatchConfig.to_dict(); the same Dictionary is also written into Steam lobby
## data.
func set_lobby_data(data: Dictionary) -> void:
	if not is_host():
		return
	_lobby_data = data.duplicate(true)
	Events.net_lobby_data_changed.emit(_lobby_data)
	# Same teardown hazard as _broadcast_roster().
	for peer_id: int in transport.broadcast_targets(multiplayer, is_host()):
		_rpc_lobby_data.rpc_id(peer_id, _lobby_data)
	# Tee the same Dictionary into Steam lobby data, under one JSON key.
	_steam.publish_match_config(_lobby_data)


## The last lobby data received, or what this host published. Clients read it
## to build their read-only view of the settings.
func lobby_data() -> Dictionary:
	return _lobby_data


# --- Steam session (spec 2.6) --------------------------------------------------
#
# Steam is a peer swap, not a new architecture: host_online()/join_lobby() are
# the Steam-shaped host_game()/join_game(), but Steam's own matchmaking calls
# are asynchronous (create_lobby/join_lobby fire a signal later), unlike
# ENet's synchronous create_server()/create_client(). These two therefore
# only kick the process off and return OK/a transport error immediately; the
# actual _mode transition and multiplayer.multiplayer_peer assignment happen
# in NetSteamSession once Steam answers.
# From that point on _rpc_handshake, the roster RPCs and _on_connected_to_
# server() run unmodified, because they only ever touch MultiplayerAPI, never
# a concrete peer type.

## Single owner of "which name does the local player go by".
## DECISION (names come from Steam, the name setting is the fallback):
## (1) while Steam is initialised and reports a non-empty persona name, the
## persona wins; (2) otherwise the typed/saved name (`typed`, the Settings name;
## "" when never set); (3) "" so the host seats "Player N". The result is still
## cleaned/sanitised by every caller and again by the host.
func resolve_local_name(typed: String) -> String:
	if steam_available():
		var persona: String = PlayerNames.clean(
			_steam.persona_name(), config.max_player_name_length
		)
		if persona != "":
			return persona
	return typed


## False whenever the addon was never installed in this checkout OR
## Steam.steamInitEx() has not yet succeeded (status != 0: client not running,
## out of date, or init_steam() not called yet). The two cases are logged with
## different messages but collapse to this one false for every UI purpose.
func steam_available() -> bool:
	return _steam.available()


## Calls Steam.steamInitEx() through steam_provider. Idempotent, safe for
## game/main/Main.gd to call unconditionally at boot even if something else
## already did. A no-op (not an error) when steam_provider is null, which
## only happens if this is called before _ready() has run.
func init_steam() -> void:
	_steam.init()


## True for the private local host a Vs bots game runs on (nobody can join).
func is_private_session() -> bool:
	return _private_session


## True only once host_online()/join_lobby() has produced a live
## SteamMultiplayerPeer: false offline, false mid-ENet-session, and false
## while a Steam lobby_created/lobby_joined callback is still pending.
func is_steam_session() -> bool:
	return _steam.is_live()


## Same contract as host_game(): starts a session and returns OK, or a
## transport error without creating anything. Unlike host_game(), OK here
## only means "the attempt started" — Steam's create_lobby() answers later
## through NetSteamSession._on_lobby_created(), which is what actually flips _mode to
## HOST. A caller that needs to know when hosting is actually live should
## watch Events.net_mode_changed.
func host_online(player_name: String = "") -> Error:
	return _steam.host_online(player_name)


## Same contract as join_game(), and the same asynchronous caveat as
## host_online(): the answer arrives later through NetSteamSession.
func join_lobby(lobby_id: int, player_name: String = "") -> Error:
	return _steam.join_lobby(lobby_id, player_name)


## Lobbies tagged with this build's {game, version} from the last
## refresh_lobby_list() answer. Each is
## {"lobby_id", "name", "players", "max", "map"} — the Steam-side equivalent
## of the LAN advert list (LanDiscovery.games()).
func discovered_lobbies() -> Array[Dictionary]:
	return _steam.discovered_lobbies()


## Asks Steam for the current lobby list, filtered to this game and this
## exact build version (spec 2.6). Pull-based, unlike LAN's push advert:
## ui/menus/MainMenu.gd calls this on a config.steam_lobby_list_refresh_s timer.
## Results arrive later as Events.net_steam_lobbies_discovered.
func refresh_lobby_list() -> void:
	_steam.refresh_lobby_list()


## Opens the Steam overlay's invite dialog for this session's lobby. A no-op
## off Steam, offline, or before the lobby actually exists.
func invite_friends() -> void:
	_steam.open_invite_overlay()


## Builds the Steam lobby session and turns its answers into Net state.
func _build_steam_session() -> void:
	_steam = NetSteamSession.new(SteamClient.new(), transport)
	_steam.config = config
	var seams: NetSteamSession.Seams = NetSteamSession.Seams.new()
	seams.is_offline = func() -> bool: return _mode == Mode.OFFLINE
	seams.is_host = is_host
	seams.leave_session = leave
	seams.lobby_data = lobby_data
	seams.build_version = build_version
	seams.local_name = resolve_local_name
	_steam.seams = seams
	_steam.host_ready.connect(_on_steam_host_ready)
	_steam.client_ready.connect(_on_steam_client_ready)
	_steam.request_failed.connect(Events.net_join_failed.emit)
	_steam.join_refused.connect(_fail_join)
	_steam.lobbies_discovered.connect(Events.net_steam_lobbies_discovered.emit)


func _on_steam_host_ready(peer: MultiplayerPeer, _lobby_id: int, host_name: String) -> void:
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.HOST
	_host_build_version = build_version()
	net_roster.add_host(host_name, _host_build_version, true)
	_reset_rejoin_state()
	Events.net_mode_changed.emit(_mode)
	mode_changed.emit(_mode)


## From here _on_connected_to_server() fires once the peer's own connection
## completes and runs the unmodified _rpc_handshake round trip.
func _on_steam_client_ready(peer: MultiplayerPeer, _lobby_id: int, local_name: String) -> void:
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.CLIENT
	net_roster.begin_client(PlayerNames.clean(local_name, config.max_player_name_length))
	_join_deadline = _now() + config.connect_timeout + config.handshake_timeout
	Events.net_mode_changed.emit(_mode)
	mode_changed.emit(_mode)


## Seconds --host-online's smoke test waits for Steam's async lobby_created
## before reporting the lobby id, and then for one requestLobbyList() round
## trip before reporting discovered_lobbies(). Diagnostic-only timing (not a
## live gameplay knob), so it stays a file const here rather than a NetConfig
## field.
const _SMOKE_LOBBY_WAIT_S: float = 5.0
const _SMOKE_LIST_WAIT_S: float = 6.0

## The windowed single-PC Steam smoke test, reached only
## through --host-online (see _apply_command_line_args()'s DECISION above).
## Never run by any automated test or by normal play; prints exactly what
## that acceptance step needs onto stdout so the check can be read off a
## captured log. Fire-and-forget: apply_command_line() does not await this.
##
## NOTE: with config.steam_lobby_type at its FriendsOnly default,
## discovered_lobbies() below is expected to print [] on a single Steam
## account; the same lobby is found when steam_lobby_type is Public (2), and
## lobby_member_count()/lobby_owner() confirm the lobby is real either way.
## Steamworks' RequestLobbyList() does not return a FriendsOnly lobby to a
## search from the owner's own account (it is scoped to the owner's
## *friends*), so this part needs a two-PC run.
func _run_steam_smoke_host_online(player_name: String) -> void:
	var mgr: Object = Engine.get_singleton(&"GDExtensionManager")
	print("NET_SMOKE loaded_extensions=%s" % [mgr.call("get_loaded_extensions")])
	init_steam()
	print("NET_SMOKE steam_available=%s" % steam_available())
	var err: Error = host_online(player_name)
	print("NET_SMOKE host_online_result=%d" % err)
	Events.net_join_failed.connect(func(join_error: int, detail: String) -> void:
		print("NET_SMOKE net_join_failed error=%d detail=%s" % [join_error, detail])
	)
	await get_tree().create_timer(_SMOKE_LOBBY_WAIT_S).timeout
	print("NET_SMOKE mode=%d is_steam_session=%s lobby_id=%d" % [_mode, _steam.is_live(), _steam.lobby_id()])
	if _steam.lobby_id() != 0:
		print("NET_SMOKE lobby_member_count=%d lobby_owner=%d" % [
			steam_provider.lobby_member_count(_steam.lobby_id()), steam_provider.lobby_owner(_steam.lobby_id())
		])
	refresh_lobby_list()
	await get_tree().create_timer(_SMOKE_LIST_WAIT_S).timeout
	print("NET_SMOKE discovered_lobbies=%s" % [discovered_lobbies()])


# --- LAN discovery (spec 2.6) -----------------------------------------------

## Starts listening on config.discovery_port for hosts advertising themselves.
## Results arrive as Events.net_games_discovered.
func start_discovery() -> void:
	_lan.start_listening()


func stop_discovery() -> void:
	_lan.stop_listening()


# --- Lag / loss simulation --------------------------------------------------

## Turns the simulator on or off for this instance (see core/net/NetSim.gd).
## `lag_ms` is one-way. Configures this instance's own queue for outbound
## intents and cursors, and forwards to SnapshotSync so inbound snapshots get
## the same settings on its own queue; the two sides must not share one
## NetSim, or they would steal each other's payloads.
## DECISION: SnapshotSync is an autoload, so it is always safe to reach
## directly here rather than through a signal.
func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	_sim.configure(lag_ms, jitter_ms, loss)
	SnapshotSync.set_simulation(lag_ms, jitter_ms, loss)


# --- Debug stats ------------------------------------------------------------

## {"mode": int, "peers": int, "ping_ms": float, "snapshot_bps": float,
## "snapshot_last_bytes": int, "interp_delay_ms": float, "loss_pct": float,
## "sim_lag_ms": float, "sim_loss": float}. Refreshed at config.stats_hz and
## mirrored on Events.net_stats_updated; ui/debug/NetDebugOverlay.gd only reads it.
func stats() -> Dictionary:
	var loss_pct: float = 0.0
	var submitted: int = _sim.submitted_count()
	if submitted > 0:
		loss_pct = float(_sim.dropped_count()) / float(submitted) * 100.0
	return {
		"mode": _mode,
		"peers": net_roster.peers.size(),
		"ping_ms": ping_ms(),
		"snapshot_bps": float(_report.get("snapshot_bps", 0.0)),
		"snapshot_last_bytes": int(_report.get("snapshot_last_bytes", 0)),
		"interp_delay_ms": float(_report.get("interp_delay_ms", 0.0)),
		"loss_pct": loss_pct,
		"sim_lag_ms": config.sim_lag_ms,
		"sim_loss": config.sim_loss,
	}


## Lets SnapshotSync fold its own counters into stats() without the overlay
## needing to know either of them.
func report_stats(source: StringName, values: Dictionary) -> void:
	for key: String in values.keys():
		_report[key] = values[key]


# --- Command line (spec 2.6 "Testing") --------------------------------------

## Parses --host, --join=<ip[:port]>, --port=<n>, --headless-host,
## --host-online, --advertise (headless hosts opt in to LAN broadcast),
## --player-name=<s>, --sim-lag=<ms>, --sim-loss=<fraction> from OS
## command-line arguments after "--" and acts on them, then separately scans
## the full command line for Steam's "+connect_lobby <id>" launch convention,
## which OS.get_cmdline_user_args() (the tokens after Godot's "--") would
## never see. Called once by
## game/main/Main.gd so a headless instance needs no UI. Returns true when an
## argument put this instance into a session.
func apply_command_line() -> bool:
	if _apply_command_line_args(OS.get_cmdline_user_args()):
		return true
	return _apply_connect_lobby_args(OS.get_cmdline_args())


## The parsing/dispatch logic behind apply_command_line(), taking the argument
## list explicitly so a unit test can drive it without OS.get_cmdline_user_args()
## (there is no OS.set_cmdline_user_args() to fake it with). The parsing itself
## is NetCommandLine.parse(); this only applies the result.
func _apply_command_line_args(args: PackedStringArray) -> bool:
	var options: NetCommandLine.Options = NetCommandLine.parse(args)

	if options.has_simulation:
		set_simulation(options.sim_lag_ms, 0.0, options.sim_loss)

	# Host a Public Steam lobby so the Join > Steam list can find
	# it (FriendsOnly lobbies never appear in Steam's lobby search). Duplicated so
	# the shared net_config.tres resource is not mutated.
	if options.steam_public_lobby:
		config = config.duplicate() as NetConfig
		config.steam_lobby_type = NetConfig.STEAM_LOBBY_TYPE_PUBLIC

	var player_name: String = options.player_name

	if options.wants_host():
		# --match-config=<path> is applied here, inside the host branch, rather
		# than up with --sim-lag/--sim-loss above, so it is a no-op for --join.
		if options.has_match_config:
			_load_match_config_override(options.match_config_path)
		# DECISION: a --headless-host (bot training, soaks, h2h, ENet harness
		# hosts) does not broadcast on the LAN by default, so it never appears as "Host (1/8)" in
		# a Join browser; clients still connect by address. `--advertise` opts back in.
		host_game(options.port, player_name if player_name != "" else "Host", true, options.lan_visible())
		return true

	# DECISION: --host-online is a windowed single-PC Steam smoke test aid, not
	# a shipped player entry point: no menu button reaches it. It lets the test
	# be launched and observed from stdout with `godot --path . -- --host-online`
	# on a machine that has the addon installed and Steam running, without
	# game/main/Main.gd's Net.init_steam() call. It uses the same bare-flag
	# convention as --host/--headless-host.
	if options.host_online:
		_run_steam_smoke_host_online(player_name if player_name != "" else "SmokeHost")
		return true

	if options.has_join:
		join_game(options.join_address, options.join_port, player_name if player_name != "" else "Player")
		return true

	return false


## The MatchConfig `--match-config=<path>` loaded, or null if the flag was
## absent, the command line never reached the host branch (--join, or no
## role flag at all), or the path/resource was rejected. game/main/Main.gd's
## _build_headless_bot_config() reads this in place of its own preloaded
## `match_config` export when it is non-null.
func match_config_override() -> MatchConfig:
	return _match_config_override


## _apply_command_line_args()'s --match-config=<path> handler. A bad path or
## a resource of the wrong type never blocks --headless-host from starting —
## it logs a push_error and leaves _match_config_override null, which reads
## downstream as "no override". Resets to null on failure (rather than keeping
## the previous value) so one bad flag value is never masked by an earlier
## good one.
func _load_match_config_override(path: String) -> void:
	if not ResourceLoader.exists(path):
		push_error(
			"--match-config=%s: no resource at that path -- falling back to the default MatchConfig." % path
		)
		_match_config_override = null
		return
	var resource: Resource = load(path)
	if not (resource is MatchConfig):
		push_error(
			"--match-config=%s: resource is not a MatchConfig -- falling back to the default MatchConfig." % path
		)
		_match_config_override = null
		return
	_match_config_override = resource as MatchConfig


## The +connect_lobby scan (NetCommandLine.connect_lobby_id), separate from
## _apply_command_line_args() because that token has no "-" prefix. Takes its
## list explicitly so a unit test can drive it.
func _apply_connect_lobby_args(args: PackedStringArray) -> bool:
	var lobby_id: int = NetCommandLine.connect_lobby_id(args)
	if lobby_id <= 0:
		return false
	join_lobby(lobby_id, "Player")
	return true


# --- MultiplayerAPI signal handlers -----------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_handshake[id] = _now() + config.handshake_timeout
	# Deferred: ENetMultiplayerPeer's own per-peer table can lag one idle
	# frame behind the peer_connected signal, and get_peer() logs an engine
	# error for an id it doesn't have yet.
	call_deferred("_apply_peer_timeout", id)


func _on_peer_disconnected(id: int) -> void:
	transport.unmark_disconnecting(id)
	_pending_handshake.erase(id)
	# No bucket outlives its connection: a rejoin starts full.
	_forget_peer_services(id)
	if _mode != Mode.HOST:
		return
	if not net_roster.has_peer(id):
		return
	var left_name: String = net_roster.name_of_peer(id)
	# A seated peer dropping mid-match keeps a reservation on
	# its slot for as long as the seat policy calls it reclaimable (its
	# disconnect grace); quoting the token on the next handshake gets it back.
	var slot_id: int = net_roster.remove(id, net_roster.match_in_progress)
	# In the lobby the seats close up behind the leaver, in the
	# same roster broadcast (a no-op mid-match).
	net_roster.compact()
	_broadcast_roster()
	_chat.system_line(_CHAT_LEFT_FORMAT % left_name)
	# DECISION: ENet's peer_disconnected carries no reason, and distinguishing
	# a graceful client leave() from a dropped connection would need its own
	# wire message. Reported uniformly as TIMEOUT; the grace period
	# (Match.on_peer_left) reacts the same way either way, so this has no
	# gameplay impact.
	Events.net_peer_left.emit(id, slot_id, LeaveReason.TIMEOUT)


func _on_connected_to_server() -> void:
	if _mode != Mode.CLIENT:
		return
	# Only the host that issued the token may see it.
	_rpc_handshake.rpc_id(HOST_PEER_ID, build_version(), net_roster.pending_join_name, quoted_rejoin_token())


## The token the handshake quotes: the stored one only when it came from the
## host this connection is going to, otherwise "".
func quoted_rejoin_token() -> String:
	return _rejoin_token if _rejoin_scope == _current_join_scope() else ""


func _current_join_scope() -> String:
	if _steam.is_live():
		return "steam:%d" % _steam.lobby_id()
	return _join_scope


func _on_connection_failed() -> void:
	if _mode != Mode.CLIENT:
		return
	_fail_join(JoinError.TRANSPORT, "connection failed")


func _on_server_disconnected() -> void:
	if _mode != Mode.CLIENT:
		return
	Events.net_peer_left.emit(HOST_PEER_ID, slot_of_peer(HOST_PEER_ID), LeaveReason.HOST_SHUTDOWN)
	leave(false)


# --- Handshake & roster RPCs -------------------------------------------------

## `rejoin_token` is what _rpc_join_accepted handed this player on an earlier
## join, or "". It has a default so the RPC still binds for a sender that
## omits it; the build check runs inside the roster's decision.
##
## The roster gates it first (raw string lengths, then a per-sender HANDSHAKE
## bucket) and HandshakePolicy decides; a capped or flooded handshake gets no reply.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_handshake(build: String, player_name: String, rejoin_token: String = "") -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_apply_handshake(sender, build, player_name, rejoin_token,
		net_roster.handle_handshake(sender, build, player_name, rejoin_token, _now()))


## Acts on a handshake decision: refuse (reply and close), seat the newcomer, give a
## returning peer its slot back, or do nothing for a dropped one.
func _apply_handshake(sender: int, build: String, player_name: String, rejoin_token: String, decision: HandshakePolicy.Decision) -> void:
	match decision.kind:
		HandshakePolicy.Decision.Kind.REFUSE:
			_reject_peer(sender, decision.error)
		HandshakePolicy.Decision.Kind.RECLAIM:
			_accept_peer(sender, build, player_name, decision.slot_id, rejoin_token)
		HandshakePolicy.Decision.Kind.ACCEPT:
			_accept_peer(sender, build, player_name, decision.slot_id)


## Seats `peer_id` in `slot_id` (-1 = spectator). `token` is a
## reconnecting peer's existing rejoin token, reused so a second drop also
## works; a new peer gets a fresh one.
##
## Ordering: the joiner hears _rpc_join_accepted and the
## roster *before* Events.net_peer_joined fires, because net/MatchNet.gd
## answers that event with a mid-match world replay (rpc_id, reliable, the
## same ordered channel), and the replay's net_match_start builds the
## joiner's world against Net.local_slot() -- which must already be the seat
## assigned here.
func _accept_peer(peer_id: int, build: String, player_name: String, slot_id: int, token: String = "") -> void:
	net_roster.accept(peer_id, build, player_name, slot_id, token)
	var checked_name: String = net_roster.name_of_peer(peer_id)
	_pending_handshake.erase(peer_id)
	_rpc_join_accepted.rpc_id(peer_id, slot_id, HOST_PEER_ID, net_roster.token_of(peer_id))
	_broadcast_roster()
	Events.net_peer_joined.emit(peer_id, slot_id, checked_name)
	_chat.send_history(peer_id)
	_chat.system_line(_CHAT_JOINED_FORMAT % checked_name)


func _reject_peer(peer_id: int, error: int) -> void:
	_pending_handshake.erase(peer_id)
	# A refused peer lingers for the grace frames below; mark it so NetFanout
	# broadcasts skip it like a kicked peer.
	transport.mark_disconnecting(peer_id)
	_rpc_join_refused.rpc_id(peer_id, error)
	# Two frames' grace before closing the connection: rpc_id() only queues
	# the packet, and disconnect_peer(force=false)'s own flush-then-close
	# only covers what ENet has already been handed, so closing on the same
	# frame it was queued can race the refusal actually reaching the wire.
	# A caller that frees this Node (e.g. leave()) right after rejecting a
	# peer should give the scene tree a frame or two to let this finish
	# first, since resuming an awaited coroutine on a freed instance logs an
	# engine error.
	await get_tree().process_frame
	await get_tree().process_frame
	# The refused peer usually hangs up first: its _fail_join() calls leave()
	# the moment the refusal lands, and on loopback the host has processed that
	# disconnect before these two frames are up. disconnect_peer() on an id the
	# transport no longer holds logs an engine error, so only close what is
	# still open.
	if multiplayer.multiplayer_peer and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## True while kick_peer() has asked the transport to disconnect `peer_id` and it
## has not dropped out of get_peers() yet. A send to it logs an engine error, so
## per-peer senders outside this file (net/MatchNet.gd) skip it.
func is_peer_disconnecting(peer_id: int) -> bool:
	return transport.is_peer_disconnecting(multiplayer, peer_id)


func _broadcast_roster() -> void:
	if not is_host():
		return
	var entries: Array[Dictionary] = []
	for peer_id: int in net_roster.peers.keys():
		entries.append((net_roster.peers[peer_id] as Dictionary).duplicate())
	# The host's own copy of the roster changed right here; tell
	# ui/lobby/Lobby.gd directly rather than waiting on a lobby-data republish.
	Events.net_roster_changed.emit(entries)
	for peer_id: int in transport.broadcast_targets(multiplayer, is_host()):
		_rpc_roster_update.rpc_id(peer_id, entries)
	_adverts.update_players(net_roster.peers.size())


@rpc("authority", "call_remote", "reliable")
func _rpc_roster_update(roster: Array) -> void:
	if is_host():
		return
	var updated: Dictionary = {}
	var typed_roster: Array[Dictionary] = []
	for entry: Variant in roster:
		var data: Dictionary = LobbySeats.entry_from_wire(entry)
		if data.is_empty():
			continue
		updated[int(data[LobbySeats.FIELD_PEER_ID])] = data
		typed_roster.append(data)
	net_roster.peers = updated
	var mine: int = local_peer_id()
	if net_roster.has_peer(mine):
		_local_slot = net_roster.slot_of_peer(mine)
	# The client-side mirror of the emit above, so a client's ui/lobby/Lobby.gd
	# updates the moment this RPC lands rather than on the next
	# net_lobby_data_changed republish.
	Events.net_roster_changed.emit(typed_roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_accepted(slot_id: int, _host_peer_id: int, rejoin_token: String = "") -> void:
	if is_host():
		return
	if rejoin_token.length() <= REJOIN_TOKEN_MAX_CHARS:
		_rejoin_token = rejoin_token
		_rejoin_scope = _current_join_scope()
	_local_slot = slot_id
	net_roster.joined_accepted = true
	# Same check the host ran on the name it was sent, so this event carries the
	# very string the roster will show.
	Events.net_peer_joined.emit(
		local_peer_id(), slot_id, PlayerNames.sanitize(net_roster.pending_join_name, config.max_player_name_length, slot_id)
	)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_refused(error: int) -> void:
	if is_host():
		return
	_fail_join(error)


func _fail_join(error: int, detail: String = "") -> void:
	leave(false)
	Events.net_join_failed.emit(error, detail)


# --- Lobby-only joining ------------------------------------------------------

## Host only. Whether _rpc_handshake may still seat a new peer. A peer that
## handshakes while this is false is refused with JoinError.MATCH_IN_PROGRESS
## and disconnected, gets no slot, and the existing roster is not touched or
## re-broadcast.
##
## host_game() and leave() reset it to true, so a fresh session always accepts.
##
## Mid-match, game/main/Main.gd keeps it true while the running
## MatchConfig.allow_mid_match_join is on; set_match_in_progress() then routes
## the handshake through HandshakePolicy (open seat, spectator, or a
## rejoin token's reserved slot -- the last ignores this flag).
##
## DECISION (autoload/Net.gd): a flag the match flow flips, not a subscription
## to Events.match_state_changed. That signal carries Match.State ints, and
## deciding which value is "lobby" would make this file name a gameplay
## concept (Net must not name Match). Match already depends on Net
## (Net.is_host()), so the dependency keeps its direction. Wired in
## game/main/Main.gd's _on_match_state_changed() as
## `Net.set_accepting_joins(to_state == Match.State.LOBBY)`.
##
## The transport stays open on purpose: set_refuse_new_connections(true) would
## fail the late joiner's connection at the ENet layer, which surfaces as
## JoinError.TRANSPORT or TIMEOUT, not a message the lobby can explain.
## Refusing in the handshake costs one reliable RPC and the same two-frame
## disconnect every other refusal pays.
func set_accepting_joins(accepting: bool) -> void:
	net_roster.accepting_joins = accepting


func accepting_joins() -> bool:
	return net_roster.accepting_joins


## Host only. game/main/Main.gd calls this with true when a match
## world is (re)built (LOBBY -> LOADING) and with false on a real return to
## the lobby. Every call drops the rejoin reservations, so a slot reserved in
## one match can never be reclaimed in the next. Going back to the lobby also
## gives each spectator a real lobby slot again, so the next Start counts it
## as a player, and clears every ready flag.
##
## Like set_accepting_joins(), a flag the match flow flips rather than a
## subscription to a gameplay signal: this file must not name Match.
func set_match_in_progress(active: bool) -> void:
	var was_active: bool = net_roster.match_in_progress
	net_roster.set_match_phase(active)
	if active or not was_active or not is_host():
		return
	# Spectators get a real lobby slot again, a player who left for good during the
	# match left a hole (nothing compacts mid-match) that closes now so Start is not
	# blocked on a seat nobody can fill, and nobody is ready (every lobby view reads
	# the flag).
	if net_roster.return_to_lobby():
		_broadcast_roster()


func match_in_progress() -> bool:
	return net_roster.match_in_progress


## Host only: installs the gameplay side of mid-match
## admission (see _pick_open_seat / _can_reclaim_seat). Either Callable may be
## invalid: then every late joiner spectates and no slot can be reclaimed.
func set_seat_policy(pick_open_seat: Callable, can_reclaim_seat: Callable) -> void:
	net_roster.pick_open_seat = pick_open_seat
	net_roster.can_reclaim_seat = can_reclaim_seat


## Client only: the rejoin token the host issued on the last accepted join
## ("" before any). Test and debug read-out; nothing gameplay reads it.
func rejoin_token() -> String:
	return _rejoin_token


func _reset_rejoin_state() -> void:
	net_roster.reset_rejoin_state()
	# Per-session host state that must not outlive its peers (called wherever a
	# session starts or ends: host_game, the Steam lobby host, leave).
	_lobby.reset()
	_chat.reset()
	ChatMute.clear()
	transport.clear_disconnecting()


# --- Ready state --------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	_lobby.on_set_ready(multiplayer.get_remote_sender_id(), ready)


# --- Loading-screen ready gate ----------------------------------------------
#
# Every human player presses ready (ui_accept: Enter,
# Space or the gamepad's A) on the loading screen and the host starts the
# countdown once all of them have (core/rules/LoadingReadyGate.gd holds the rule,
# autoload/match/MatchLifecycle.gd the per-match state). Net is only the
# transport: it never names Match, so the host-side handoff and the mirror both
# go over the Events bus (net_loading_ready_received / loading_ready_changed /
# loading_gate_opened), the way net_peer_joined does.

## Local player pressed ready. Client: sends the intent to the host (which takes
## the peer id from the transport, never from the payload, so there is nothing
## to spoof). Host and offline: hands it to the lifecycle directly under the
## local peer id (offline that is Net.HOST_PEER_ID, which stands for every
## local human -- one press on the shared device readies all of them).
func request_loading_ready() -> void:
	if is_client():
		if not transport.is_link_up(multiplayer):
			return
		_rpc_loading_ready.rpc_id(HOST_PEER_ID)
		return
	Events.net_loading_ready_received.emit(local_peer_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_loading_ready() -> void:
	_lobby.on_loading_ready(multiplayer.get_remote_sender_id())


## Host: mirrors the lifecycle's ready sets to every client.
func _on_loading_ready_changed(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
	if _mode != Mode.HOST:
		return
	for peer_id: int in transport.broadcast_targets(multiplayer, is_host()):
		_rpc_loading_ready_state.rpc_id(peer_id, ready_ids, required_ids)


## Host: tells every client the gate opened.
func _on_loading_gate_opened() -> void:
	if _mode != Mode.HOST:
		return
	for peer_id: int in transport.broadcast_targets(multiplayer, is_host()):
		_rpc_loading_gate_open.rpc_id(peer_id)


@rpc("authority", "call_remote", "reliable")
func _rpc_loading_ready_state(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
	if _mode != Mode.CLIENT:
		return
	# Wire limit: a seated peer list can never be longer than the session itself.
	if ready_ids.size() > config.max_peers or required_ids.size() > config.max_peers:
		return
	for peer_id: int in ready_ids:
		if peer_id < HOST_PEER_ID:
			return
	for peer_id: int in required_ids:
		if peer_id < HOST_PEER_ID:
			return
	Events.loading_ready_changed.emit(ready_ids, required_ids)


@rpc("authority", "call_remote", "reliable")
func _rpc_loading_gate_open() -> void:
	if _mode != Mode.CLIENT:
		return
	Events.loading_gate_opened.emit()


# --- Lobby seat preferences -------------------------------------------------
#
# The host owns every seat's picks; a peer may change only its OWN colour and
# team, and does so by sending this intent. Net
# is transport only: it takes the peer id from the connection, refuses anything
# that is not a plain in-range request from a seated peer in the lobby, and hands
# the survivor to the lobby over Events.net_seat_pref_requested. The lobby (the
# host-side players panel, through LobbySeats.apply_human_pref) applies it with the
# real team cap, resolves colour swaps and republishes; Net mutates no lobby or
# match state itself, and the client UI follows the next lobby-data echo instead
# of updating optimistically.

## Local player asks to change its own seat: `color_index` is a palette index
## (0..LobbySeats.palette_size() - 1), `team_pick` is MatchConfig.TEAM_PICK_RANDOM
## (0) or a lobby team number (1..MatchConfig.TEAM_PICK_MAX); LobbySeats.UNCHANGED
## (-1) leaves that field as it is. Client: sends the intent to the host. Host and
## offline: runs the same checks locally under local_peer_id() (offline that is
## HOST_PEER_ID, the one local human), without the flood limit.
func request_seat_pref(color_index: int = LobbySeats.UNCHANGED, team_pick: int = LobbySeats.UNCHANGED) -> void:
	if is_client():
		if not NetLobbyIntents.seat_pref_in_range(color_index, team_pick):
			return
		if not transport.is_link_up(multiplayer):
			return
		_rpc_request_seat_pref.rpc_id(HOST_PEER_ID, color_index, team_pick)
		return
	_lobby.on_local_seat_pref(local_peer_id(), color_index, team_pick)


## `Variant` parameters on purpose: this is an any_peer RPC, so the arguments are
## whatever the sender put on the wire, and a typed signature would let the engine
## coerce (a float becomes an int, a bool a 0/1) before the host could refuse it.
## The sender is get_remote_sender_id(); the payload names no peer, so there is
## nothing to spoof.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_seat_pref(color_index: Variant, team_pick: Variant) -> void:
	_lobby.on_seat_pref(multiplayer.get_remote_sender_id(), color_index, team_pick)


# --- Player chat ---------------------------------------------------------------

## UI entry point (Events.chat_send_requested). A client cleans the text (bounds the
## wire cost) and submits it to the host; the host runs the same checks on its own
## line. Offline and the private local bot host send nothing.
func send_chat(text: String) -> void:
	if _mode == Mode.HOST:
		_chat.on_submit(local_peer_id(), text)
	elif _mode == Mode.CLIENT and net_roster.joined_accepted and _client_connected():
		var cleaned: String = ChatRules.clean(text, chat_config.max_chars)
		if cleaned != "":
			_rpc_chat_submit.rpc_id(HOST_PEER_ID, cleaned)


func _client_connected() -> bool:
	return transport.is_link_up(multiplayer)


## `Variant` on purpose (any_peer): the engine must not coerce a float or bool before
## the host can refuse it. The sender is the transport's id; the payload names nobody.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_chat_submit(payload: Variant) -> void:
	_chat.on_submit(multiplayer.get_remote_sender_id(), payload)


@rpc("authority", "call_remote", "reliable")
func _rpc_chat_line(line: Dictionary) -> void:
	_chat.accept_line(multiplayer.get_remote_sender_id(), line)


@rpc("authority", "call_remote", "reliable")
func _rpc_chat_history(lines: Array) -> void:
	_chat.accept_history(multiplayer.get_remote_sender_id(), lines)


@rpc("authority", "call_remote", "reliable")
func _rpc_chat_notice(code: int) -> void:
	_chat.accept_notice(multiplayer.get_remote_sender_id(), code)


# --- Lobby data RPC ----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_data(data: Dictionary) -> void:
	if is_host():
		return
	_lobby_data = data
	Events.net_lobby_data_changed.emit(_lobby_data)


# --- Ping -------------------------------------------------------------------

@rpc("authority", "call_remote", "unreliable")
func _rpc_ping(sent_at_ms: int) -> void:
	if is_host():
		return
	_rpc_pong.rpc_id(HOST_PEER_ID, sent_at_ms)


@rpc("any_peer", "call_remote", "unreliable")
func _rpc_pong(sent_at_ms: int) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if not net_roster.peers.has(sender):
		return
	_ping.on_pong(sender, sent_at_ms, Time.get_ticks_msec())


@rpc("authority", "call_remote", "unreliable")
func _rpc_report_ping(value: float) -> void:
	if is_host():
		return
	_own_ping_ms = value


## NetPing measured a new average for `peer_id`: the roster mirrors it and the peer hears it.
func _on_ping_changed(peer_id: int, ms: float) -> void:
	if not net_roster.peers.has(peer_id):
		return
	net_roster.peers[peer_id][LobbySeats.FIELD_PING_MS] = ms
	if not is_peer_disconnecting(peer_id):
		_rpc_report_ping.rpc_id(peer_id, ms)


# --- Internal helpers -------------------------------------------------------

## Builds the three collaborators over one flood gate; each sends through a Callable
## that names the RPC, so none holds the MultiplayerAPI.
func _build_session_services() -> void:
	_flood = PeerFloodGate.new(FloodLimits.from_config(config))
	var lobby_seams: NetLobbyIntents.Seams = NetLobbyIntents.Seams.new()
	lobby_seams.now_s = _now
	lobby_seams.is_host = is_host
	lobby_seams.broadcast_roster = _broadcast_roster
	lobby_seams.loading_ready = func(peer_id: int) -> void: Events.net_loading_ready_received.emit(peer_id)
	lobby_seams.seat_pref = func(peer_id: int, color_index: int, team_pick: int) -> void:
		Events.net_seat_pref_requested.emit(peer_id, color_index, team_pick)
	_lobby = NetLobbyIntents.new(net_roster, config, _flood, lobby_seams)
	var chat_seams: NetChatService.Seams = NetChatService.Seams.new()
	chat_seams.is_chat_host = func() -> bool: return _mode == Mode.HOST and not _private_session
	chat_seams.is_chat_client = func() -> bool: return _mode == Mode.CLIENT
	chat_seams.now_s = _now
	chat_seams.peer_info = func(peer_id: int) -> Dictionary: return net_roster.peers.get(peer_id, {})
	chat_seams.send_to_peer = _send_chat
	chat_seams.targets = func() -> Array: return Array(transport.broadcast_targets(multiplayer, is_host()))
	chat_seams.is_peer_disconnecting = transport.is_marked_disconnecting
	chat_seams.color_of = _chat_color_of
	chat_seams.local_peer_id = local_peer_id
	chat_seams.in_match = func() -> bool: return net_roster.match_in_progress
	chat_seams.max_name_length = config.max_player_name_length
	_chat = NetChatService.new(chat_config, chat_seams)
	_chat.line_accepted.connect(Events.chat_line_received.emit)
	_chat.history_accepted.connect(Events.chat_history_received.emit)
	_chat.notice_accepted.connect(Events.chat_notice.emit)
	var ping_seams: NetPing.Seams = NetPing.Seams.new()
	ping_seams.targets = _ping_targets
	ping_seams.send_ping = func(peer_id: int, sent_at_ms: int) -> void: _rpc_ping.rpc_id(peer_id, sent_at_ms)
	_ping = NetPing.new(config, _flood, ping_seams)
	_ping.ping_changed.connect(_on_ping_changed)


## A leaver (or kicked peer) is forgotten once by every collaborator and the roster gate.
func _forget_peer_services(peer_id: int) -> void:
	_flood.forget_peer(peer_id)
	net_roster.forget_flood(peer_id)
	_lobby.forget_peer(peer_id)
	_chat.forget_peer(peer_id)
	_ping.forget_peer(peer_id)


func _send_chat(peer_id: int, method: StringName, args: Array) -> void:
	match method:
		NetChatService.METHOD_LINE:
			_rpc_chat_line.rpc_id(peer_id, args[0])
		NetChatService.METHOD_HISTORY:
			_rpc_chat_history.rpc_id(peer_id, args[0])
		NetChatService.METHOD_NOTICE:
			_rpc_chat_notice.rpc_id(peer_id, args[0])


## Palette index of the sender's lobby seat; the slot (or 0) when none is published.
func _chat_color_of(peer_id: int, slot_id: int) -> int:
	var seats: Variant = _lobby_data.get(_CHAT_LOBBY_SEATS_KEY)
	if typeof(seats) == TYPE_DICTIONARY:
		var index: int = LobbySeats.color_of(seats as Dictionary, peer_id)
		if index >= 0:
			return index
	return maxi(slot_id, 0)


## Seated remote peers, none while the transport cannot be addressed (same teardown
## hazard as _broadcast_roster()).
func _ping_targets() -> Array:
	var result: Array = []
	if not transport.can_broadcast(multiplayer, is_host()):
		return result
	for peer_id: int in transport.broadcast_targets(multiplayer, is_host()):
		if peer_id != HOST_PEER_ID and net_roster.peers.has(peer_id):
			result.append(peer_id)
	return result


func _tick_handshake_timeouts(now: float) -> void:
	if _pending_handshake.is_empty():
		return
	var expired: Array[int] = []
	for peer_id: int in _pending_handshake.keys():
		if now > float(_pending_handshake[peer_id]):
			expired.append(peer_id)
	for peer_id: int in expired:
		_reject_peer(peer_id, JoinError.TIMEOUT)


## Configures the dead-peer detection of the link to `id` (NetTransport owns how).
func _apply_peer_timeout(id: int) -> void:
	transport.apply_peer_timeout(multiplayer, _peer, id, is_host(), config)


## What the lobby reads. IDLE = not tried.
func upnp_state() -> int:
	return _adverts.router_state()


## "XXXXX-XXXXX" once the router opened the port, else "".
func upnp_join_code() -> String:
	return _adverts.join_code()


## The UDP port a manual router forward must target (the fallback hint).
func host_port() -> int:
	return _host_port


## DECISION: the real backend needs a windowed, non-agent autoload; headless hosts
## (bot matches, GUT) never reach a router. NetHostAdverts only asks for a backend when
## the session is advertised, so bot hosts (lan_visible false) and private sessions
## (advertise false) never get here.
func _upnp_backend() -> UpnpBackend:
	if upnp_backend_factory.is_valid():
		return upnp_backend_factory.call() as UpnpBackend
	if not _real_upnp or AgentProbe.is_active() or DisplayServer.get_name() == "headless":
		return null
	return UpnpBackendReal.new()


## Quit: the mapping must not outlive the process (blocking, bounded by one router round trip).
func _exit_tree() -> void:
	if _adverts != null:
		_adverts.shutdown()


func _on_lan_advert_changed(_info: Dictionary) -> void:
	Events.net_games_discovered.emit(_lan.games())


func _on_lan_advert_expired(_address: String, _port: int) -> void:
	Events.net_games_discovered.emit(_lan.games())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
