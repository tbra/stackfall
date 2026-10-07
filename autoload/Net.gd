extends Node
## NetworkManager: transport selection, host/join, LAN discovery, peer registry
## (spec 3.4, docs/M3a_PLAN.md P1).
##
## Gameplay code only ever talks to MultiplayerAPI; this node decides whether
## the peer underneath is ENet (LAN, direct IP, tests — M3a) or Steam (M3b).
## **Swapping the transport must be a change to _make_host_peer() /
## _make_client_peer() and nothing else** — no other file in the project may
## name ENetMultiplayerPeer, an IP address, or a port.
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
## mode including M2's hot-seat, and is_host() is true in it, so rule code
## written as `if not Net.is_host(): return` behaves identically offline.
enum Mode { OFFLINE, HOST, CLIENT }

## Why a join attempt failed. The lobby shows a message per case.
enum JoinError { NONE, TIMEOUT, VERSION_MISMATCH, SERVER_FULL, MATCH_IN_PROGRESS, REFUSED, TRANSPORT }

## Why a peer left, carried on Events.net_peer_left.
enum LeaveReason { GRACEFUL, TIMEOUT, KICKED, HOST_SHUTDOWN }

## Peer id of the listen-server host. Godot fixes this at 1; named here so no
## other file writes the literal.
const HOST_PEER_ID: int = 1

## Key the LAN advert carries so a stray UDP broadcast on 47777 is ignored.
const DISCOVERY_MAGIC: StringName = &"stackfall"

## Steam's public test app ("Spacewar"), passed directly into
## Steam.steamInitEx() (docs/M3b_RESEARCH.md's spike: no steam_appid.txt is
## needed once the app id is passed as an argument). Named here, not in
## net/SteamClient.gd, per docs/M3b_PLAN.md's tunables table.
const STEAM_APP_ID_EXPECTED: int = 480

## Bontago-8or.11: size of a rejoin token (random bytes; hex doubles it) and
## the longest token string the handshake will even look up. Architecture,
## not tunables, like HOST_PEER_ID.
const REJOIN_TOKEN_BYTES: int = 16
const REJOIN_TOKEN_MAX_CHARS: int = 64

@export var config: NetConfig = preload("res://config/net_config.tres")

var _mode: Mode = Mode.OFFLINE
## The peer this instance created, generic MultiplayerPeer only — never typed
## or cast to ENetMultiplayerPeer outside _make_host_peer()/_make_client_peer().
var _peer: MultiplayerPeer = null

## peer_id -> {"peer_id", "slot_id", "name", "name_auto", "ready", "ping_ms", "build"}. On
## the host this is the source of truth; on a client it is a mirror kept in
## sync by _rpc_roster_update.
var _peers: Dictionary = {}
## peer_id -> RTT samples (ms), host only, averaged into _peers[id].ping_ms.
var _ping_samples: Dictionary = {}
## Host only: peer_id -> deadline (seconds, _now()) by which the peer must
## have sent its handshake, or it is dropped.
var _pending_handshake: Dictionary = {}
## Host only: peer ids kick_peer() has asked the transport to disconnect that
## are still listed in multiplayer.get_peers() (ENet drops them only once the
## disconnect completes, a poll later). Sending to one logs the engine error
## "Unable to send packet on channel 0, max channels: 0" (Bontago-1pi.57), so
## every host-side fan-out goes through _broadcast_targets(), which skips them.
var _disconnecting_peers: Dictionary = {}
## Host only (Bontago-1pi.53): peer_id -> {"tokens": float, "at": float}, the
## request_seat_pref flood bucket of each peer that sent one (size and refill:
## NetConfig.seat_pref_burst / seat_pref_refill_per_s). Dropped with the
## peer (_on_peer_disconnected) and with the session (_reset_rejoin_state).
var _seat_pref_buckets: Dictionary = {}
var _next_slot_id: int = 1
## Host only: whether _rpc_handshake may still seat a new peer. True in the
## lobby, false once the match flow leaves it (see set_accepting_joins()).
var _accepting_joins: bool = true
## Bontago-1pi.83: true for a private loopback host (host_game(..., advertise=false), the
## Vs bots session); lets the lobby badge say so instead of "LAN". Cleared by leave().
var _private_session: bool = false

## -- Mid-match join and reconnect (Bontago-8or.11, spec 3.4 "Late join /
## reconnect") ------------------------------------------------------------
## Host only: true while the match flow is past the lobby (game/Main.gd sets
## it next to set_accepting_joins()). Decides which seat a handshake gets: the
## next lobby slot, or a seat-policy choice / spectator seat mid-match.
var _match_in_progress: bool = false
## Host only: peer_id -> the rejoin token issued to it in _rpc_join_accepted.
## Never part of the roster (that is broadcast to every client): a token is a
## bearer credential for its slot.
var _tokens: Dictionary = {}
## Host only: rejoin token -> slot_id held by a peer that dropped while a
## match was running. A handshake quoting the token reclaims that slot if the
## seat policy still calls it reclaimable (inside its NetConfig.
## disconnect_grace). Cleared whenever a match (re)starts or ends.
var _reservations: Dictionary = {}
## Host only (installed by game/Main.gd): () -> int. The open human seat a new
## mid-match joiner may take, or -1 to seat it as a spectator. Net never
## decides this itself: "open" is a gameplay question (a living human slot no
## peer holds and no departed peer has reserved).
var _pick_open_seat: Callable = Callable()
## Host only (installed by game/Main.gd): (slot_id: int) -> bool. Whether a
## returning peer may reclaim `slot_id` (still inside its disconnect grace).
var _can_reclaim_seat: Callable = Callable()
## Client only: the token the host issued on our last accepted join. Survives
## a connection loss on purpose (leave(false)), so a dropped player who joins
## the same host again (the direct-IP field, the LAN browser or the Steam
## lobby) quotes it and gets its slot back. A deliberate leave() clears it, and
## it is only ever sent to the host it came from (_rejoin_scope). DECISION
## (Bontago-8or.11): memory only -- a crashed and
## restarted client has no token and rejoins as a new late joiner. Persisting
## it would write a bearer credential to disk for a window that is only
## NetConfig.disconnect_grace long.
var _rejoin_token: String = ""
## Which host issued _rejoin_token: "enet:<address>:<port>" or "steam:<lobby>".
var _rejoin_scope: String = ""
## Last peer id local_peer_id() read from a live transport (Bontago-fca.30).
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
var _joined_accepted: bool = false
var _pending_join_name: String = ""
var _join_deadline: float = 0.0
## Client only: this instance's own ping to the host, reported down by the
## host (the host measures the RTT; the client cannot measure it itself).
var _own_ping_ms: float = 0.0

var _lobby_data: Dictionary = {}
var _lan: LanDiscovery

## `--match-config=<res path>` (Bontago-3k0, deferred from Bontago-keo.19):
## host-only override for the MatchConfig a `--headless-host` match starts
## from. Null (the ordinary case) means "no override" -- game/Main.gd's own
## _build_headless_bot_config() then falls back to its preloaded
## config/match_defaults.tres exactly as before this flag existed. Set only
## from inside _apply_command_line_args()'s host branch (see
## _load_match_config_override() below), never touched by --join, so a client
## passing this flag by accident is silently ignored -- this is a host-only
## concern (spec 3.4: only the host's MatchConfig ever matters).
var _match_config_override: MatchConfig = null

## docs/M3b_PLAN.md P1: the Steam-facing seam, exactly the net_provider/
## match_provider pattern ui/MainMenu.gd, ui/Lobby.gd and
## ui/NetDebugOverlay.gd already use. Set to a real SteamClient in _ready();
## tests overwrite it with a FakeSteam.
var steam_provider: Variant = null
## True only once host_online()/join_lobby() has an active peer (see
## is_steam_session()); reset in leave().
var _steam_session: bool = false
## The Steam lobby id this session created or joined, or 0. Needed by
## set_lobby_data()'s Steam tee, invite_friends() and leave()'s teardown.
var _steam_lobby_id: int = 0
## host_online()/join_lobby()'s player_name argument, read back once the
## async lobby_created/lobby_joined callback actually seats this instance
## (Steam's own calls are not synchronous the way ENet's create_server/
## create_client are).
var _steam_pending_name: String = ""
## Cache backing discovered_lobbies(); refreshed by _on_steam_lobby_match_list.
var _discovered_lobbies: Array[Dictionary] = []
## Which steam_provider instance _wire_steam_signals() has already connected
## to, so swapping in a FakeSteam after _ready() (every P1 test does this)
## gets its own signals wired the next time host_online()/join_lobby()/
## refresh_lobby_list()/init_steam() runs, without double-connecting the same
## provider repeatedly.
var _steam_signals_wired: Variant = null
## init_steam() is idempotent (game/Main.gd may call it once at boot); this
## is the guard.
var _steam_initialized: bool = false
## True only once steam_provider's init_result reports status 0 (steamInitEx
## actually succeeded). Both steam_available() and the two _make_steam_*_peer()
## factories require this — see the crash this guards against, documented at
## _make_steam_host_peer().
var _steam_ready: bool = false
## Bontago-mv0.2.6 (independent-review finding B): _mode stays OFFLINE for the
## whole time a host_online()/join_lobby() Steam answer is pending, so a
## second call in the meantime used to sail past the "if _mode != Mode.OFFLINE:
## leave()" guard and issue a second Steam request. Both entry points refuse a
## second call outright while a request of the *current* generation (see
## below) is still outstanding — _steam_request_pending() at the bottom of
## this block is the single predicate both use.
##
## Bontago-mv0.4: a single pending bool fixed the case above but broke
## leave() -> host_online()/join_lobby() done twice before the first
## attempt's own answer lands: the second call set the (single, shared) flag
## true again, so the FIRST attempt's late answer was consumed by
## _on_steam_lobby_created()/_on_steam_lobby_joined() as if it were the
## SECOND attempt's own answer — and the second attempt's real, later answer
## was then dropped as stale in its place (see `bd show Bontago-mv0.4`).
## GodotSteam's lobby_created/lobby_joined signals carry no per-call id to
## tell two outstanding requests' eventual answers apart, so a bool alone
## cannot distinguish them once a second request is in flight.
##
## Fixed with a monotonically increasing generation, bumped by leave(), plus
## a FIFO queue of the generation each still-unanswered host_online()/
## join_lobby() call was issued under. Every lobby_created/lobby_joined
## answer pops the oldest still-outstanding entry and compares it against the
## *current* generation:
## - equal: this is the live attempt's own answer.
## - not equal: this answer belongs to an attempt leave() already cancelled.
##   A stale success (result/response == OK) is never left orphaned — its
##   lobby is handed straight to steam_provider.leave_lobby() — and the live
##   attempt (if any) stays pending, unaffected.
## DECISION: GodotSteam's signals carry no call-correlation id, so "which
## queued generation an answer resolves" is necessarily FIFO-by-issue-order,
## not true per-call identity — matching Steamworks' own practical ordering
## for same-typed calls from one local client (docs/M3b_RESEARCH.md). This
## still guarantees the two invariants that matter: no lobby is ever
## orphaned, and exactly one attempt can ever become the live session.
var _steam_request_generation: int = 0
## FIFO queue (oldest first) of the generation each still-unanswered
## host_online()/join_lobby() call was issued under. See
## _steam_request_generation's doc comment above.
var _steam_pending_generations: Array[int] = []
## Bontago-1pi.48: parallel to _steam_pending_generations — the lobby id each
## pending join_lobby() targets, or _STEAM_CREATE_REQUEST (-1: Steam lobby ids
## are positive) for host_online().
## lobby_created resolves the oldest pending create, lobby_joined the pending
## join for its own lobby id, so the creator's LobbyEnter echo (below) can never
## be consumed as some other request's answer.
var _steam_pending_targets: Array[int] = []
const _STEAM_CREATE_REQUEST: int = -1
## Bontago-1pi.48: every lobby this process created (live or abandoned).
## Steamworks answers a successful CreateLobby with lobby_created AND a
## lobby_joined (LobbyEnter_t) for the creator; that echo is not a join answer
## and must never reach the stray-answer leave_lobby() (it used to: the host
## left, and so destroyed, its own fresh lobby). One int per created lobby.
var _steam_created_lobbies: Dictionary = {}
## Tests only: _make_steam_host_peer() hands this out instead of building a
## SteamMultiplayerPeer (never built for a FakeSteam provider, crash safety),
## so a FakeSteam test can reach the live Steam HOST state.
var steam_host_peer_override: MultiplayerPeer = null
## Bontago-1pi.48 diagnostics: seconds between `STEAM SELFCHECK` lines while a
## Steam session is live (diagnostic cadence, not a gameplay knob).
const STEAM_SELFCHECK_PERIOD_S: float = 10.0
var _steam_selfcheck_accum: float = 0.0


## True while a request of the *current* generation is still outstanding —
## the single predicate host_online()/join_lobby() share for the ERR_BUSY
## guard above. False once leave() bumps the generation, even if an older
## generation's request is still genuinely in flight with Steam (those
## resolve as stale — see _steam_request_generation's doc comment).
## Bontago-1pi.48: --steam-lobby-debug prints the game/version data of at most this many
## unfiltered lobbies (a diagnostic sample size, not gameplay).
const LOBBY_DEBUG_SAMPLE_COUNT: int = 5


func _steam_request_pending() -> bool:
	return _steam_pending_generations.has(_steam_request_generation)

var _sim: NetSim = NetSim.new()
## Cross-package stats reported via report_stats(), folded into stats().
var _report: Dictionary = {}

var _ping_accum: float = 0.0
var _stats_accum: float = 0.0


func _ready() -> void:
	# Bontago-1pi.53 review F3: the shipped resource goes through the same clamps
	# every other config does, so a hand-edited net_config.tres (a zero
	# seat_pref_burst, a tiny packet cap) cannot lock clients out or break the wire.
	config.sanitize()
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
	steam_provider = SteamClient.new()
	# Bontago-1pi.32: the host mirrors the loading-screen ready gate to clients.
	Events.loading_ready_changed.connect(_on_loading_ready_changed)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)


func _process(delta: float) -> void:
	# Steamworks is a manual-dispatch API: every async Steam signal (lobby
	# creation, the lobby list, joins, invite-accepts) is queued internally
	# and never fires without this (see net/SteamClient.gd's run_callbacks()
	# doc comment for how this was found). Gated on _steam_ready, not
	# steam_available()/is_steam_session(), because a caller can legitimately
	# call refresh_lobby_list() or join_lobby() from the main menu before any
	# session exists — those need callbacks pumped too.
	if _steam_ready and steam_provider != null:
		steam_provider.run_callbacks()
	_tick_steam_selfcheck(delta)

	var now: float = _now()
	if _mode == Mode.HOST:
		_tick_handshake_timeouts(now)
		_tick_ping(delta)
	elif _mode == Mode.CLIENT:
		if not _joined_accepted and now > _join_deadline:
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
func host_game(port: int = 0, player_name: String = "", advertise: bool = true) -> Error:
	if _mode != Mode.OFFLINE:
		leave()
	var use_port: int = port if port > 0 else config.game_port
	if not advertise and port <= 0:
		use_port = AgentProbe.free_udp_port()
		if use_port == 0:
			return ERR_CANT_CREATE
	# Agent runs (AgentProbe: tool/bench scenes, --agent-probe) host on a random
	# free port unless one was given, so parallel benches and the ENet harness
	# never fight over the default port (session debrief 2026-10-01).
	if port <= 0 and AgentProbe.is_active() and not AgentProbe.has_cli_port(OS.get_cmdline_user_args()):
		var free_port: int = AgentProbe.free_udp_port()
		if free_port > 0:
			use_port = free_port
	var peer: MultiplayerPeer = _make_host_peer(use_port, "*" if advertise else "127.0.0.1")
	if peer == null:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.HOST
	_host_port = use_port
	_host_build_version = build_version()
	_peers.clear()
	# Bontago-1pi.49: the host's own name goes through the same check a joiner's
	# does, so an empty or oversized typed name is "Player 1" or cut, everywhere.
	var host_name: String = PlayerNames.sanitize(resolve_local_name(player_name), config.max_player_name_length, 0)
	_peers[HOST_PEER_ID] = LobbySeats.entry_to_wire(HOST_PEER_ID, 0, host_name, false, 0.0, _host_build_version)
	_next_slot_id = 1
	_accepting_joins = advertise
	_private_session = not advertise
	_reset_rejoin_state()
	Events.net_mode_changed.emit(_mode)
	# Agent runs must not appear in the owner's LAN browser.
	if advertise and not AgentProbe.is_active():
		_start_lan_advertising(host_name)
	return OK


## Connects to `address`:`port`. Emits Events.net_join_failed and returns to
## OFFLINE if the handshake is refused or times out.
func join_game(address: String, port: int = 0, player_name: String = "") -> Error:
	if _mode != Mode.OFFLINE:
		leave()
	var use_port: int = port if port > 0 else config.game_port
	var peer: MultiplayerPeer = _make_client_peer(address, use_port)
	if peer == null:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.CLIENT
	_peers.clear()
	# Bontago-1pi.49: cleaned here so a bad name is never sent; "" stays "" (the
	# host seats the joiner as "Player N"). The host re-checks it regardless.
	_pending_join_name = PlayerNames.clean(resolve_local_name(player_name), config.max_player_name_length)
	_join_scope = "enet:%s:%d" % [address, use_port]
	_joined_accepted = false
	_join_deadline = _now() + config.connect_timeout + config.handshake_timeout
	Events.net_mode_changed.emit(_mode)
	return OK


## Leaves whatever session is running and returns to OFFLINE. Safe to call
## when already offline. The host disconnects everyone with
## LeaveReason.HOST_SHUTDOWN first. A deliberate leave forgets the rejoin
## token; the connection-lost and failed-join paths pass false to keep it.
func leave(forget_rejoin: bool = true) -> void:
	# DECISION (Bontago-mv0.2.6 finding B, generation added for Bontago-mv0.4):
	# bumped unconditionally, before the OFFLINE early-return below, because a
	# pending host_online()/join_lobby() attempt never moves _mode off OFFLINE
	# until its Steam answer actually lands — so a caller cancelling mid-
	# attempt (e.g. leaving the menu while a lobby is still being created)
	# would otherwise never reach this function's own body at all. Once the
	# generation no longer matches what a still-outstanding request was
	# issued under, its late lobby_created/lobby_joined answer is treated as
	# stale by _on_steam_lobby_created()/_on_steam_lobby_joined() and
	# abandons whatever Steam lobby it produced instead of reviving a session
	# nothing is waiting for — even if a fresh host_online()/join_lobby() call
	# started a new (current-generation) request in the meantime.
	_steam_request_generation += 1
	if forget_rejoin:
		_rejoin_token = ""
		_rejoin_scope = ""
	if _mode == Mode.OFFLINE:
		return
	if _mode == Mode.HOST:
		for peer_id: int in _peers.keys():
			if peer_id != HOST_PEER_ID:
				Events.net_peer_left.emit(peer_id, int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1)), LeaveReason.HOST_SHUTDOWN)

	if _steam_session and steam_provider != null and _steam_lobby_id != 0:
		steam_provider.leave_lobby(_steam_lobby_id, "Net.leave()")

	_lan.stop_advertising()
	_lan.stop_listening()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peer = null
	_mode = Mode.OFFLINE
	_peers.clear()
	_ping_samples.clear()
	_pending_handshake.clear()
	_local_slot = 0
	_joined_accepted = false
	_own_ping_ms = 0.0
	_lobby_data = {}
	_accepting_joins = true
	_private_session = false
	_reset_rejoin_state()
	_steam_session = false
	_steam_lobby_id = 0
	_steam_pending_name = ""
	_steam_selfcheck_accum = 0.0
	Events.net_mode_changed.emit(_mode)


func mode() -> Mode:
	return _mode


## True on the host **and offline**. This is the single predicate that gates
## host-only work (Match's solve and feed, Field's kill plane, SnapshotSync's
## sender). Never branch on multiplayer.is_server() directly: with no peer set
## its answer depends on engine internals, and it says nothing about M3b.
func is_host() -> bool:
	return _mode == Mode.HOST or _mode == Mode.OFFLINE


## True when this session may send RPCs: not offline and the multiplayer peer is
## a connected, non-offline one. The single owner is NetFanout.can_send(); Net's
## private _can_send() below is a different, host-only question (are there
## connected remote peers to broadcast to).
func can_send() -> bool:
	return NetFanout.can_send(multiplayer, self)


func is_client() -> bool:
	return _mode == Mode.CLIENT


func is_offline() -> bool:
	return _mode == Mode.OFFLINE


## This instance's multiplayer peer id, or HOST_PEER_ID when offline.
func local_peer_id() -> int:
	if _mode == Mode.OFFLINE:
		return HOST_PEER_ID
	# Bontago-fca.30: while the transport is already closed (the server_disconnected
	# path emits net_peer_left before leave() runs, and listeners such as Sfx ask
	# "was that me?"), get_unique_id() is an engine error ("The multiplayer
	# instance isn't currently active"). Answer with the last live id instead.
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		return _last_local_peer_id
	_last_local_peer_id = multiplayer.get_unique_id()
	return _last_local_peer_id


## The game build version both ends compare during the handshake. Reads
## ProjectSettings' application/config/version, so bumping the version there is
## all it takes to refuse older builds (spec 3.4 "Version check").
func build_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


# --- Peer <-> slot registry -------------------------------------------------

## Every connected peer id including the host, in slot order.
func peer_ids() -> PackedInt32Array:
	var ids: Array = _peers.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		return int(_peers[a].get(LobbySeats.FIELD_SLOT_ID, -1)) < int(_peers[b].get(LobbySeats.FIELD_SLOT_ID, -1))
	)
	var result: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		result.append(id)
	return result


## {"peer_id": int, "slot_id": int, "name": String, "name_auto": bool (joiners
## only: the name is the host's "Player N" for the seat), "ready": bool,
## "ping_ms": float, "build": String}. Empty for an unknown peer.
func peer_info(peer_id: int) -> Dictionary:
	if not _peers.has(peer_id):
		return {}
	return (_peers[peer_id] as Dictionary).duplicate()


## Which PlayerSlot a peer holds, or -1. The host assigns these and broadcasts
## the roster; a client never invents one.
func slot_of_peer(peer_id: int) -> int:
	if not _peers.has(peer_id):
		return -1
	return int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))


## Inverse of slot_of_peer(). -1 for an unclaimed slot (an empty seat, or a
## bot's from M5). A negative slot_id is never a seat: spectators (Bontago-
## 8or.11) all hold -1, so it must not match the first of them.
func peer_of_slot(slot_id: int) -> int:
	if slot_id < 0:
		return -1
	for peer_id: int in _peers.keys():
		if int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1)) == slot_id:
			return peer_id
	return -1


## Bontago-1pi.49: the replicated name of the human peer seated at `slot_id`, or
## "" when no peer holds it (a bot, an empty seat, a departed player). Host and
## client read the same roster, so the loading screen and HUD show one name per
## slot on both sides; late joiners and rejoiners get theirs from the roster
## RPC the host already sends on every change.
func name_for_slot(slot_id: int) -> String:
	var peer_id: int = peer_of_slot(slot_id)
	if peer_id == -1 or not _peers.has(peer_id):
		return ""
	return String(_peers[peer_id].get(LobbySeats.FIELD_NAME, ""))


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
## for **every** slot in offline hot-seat, which is what keeps M2's strict
## alternation working unchanged.
func is_local_slot(slot_id: int) -> bool:
	if _mode == Mode.OFFLINE:
		return true
	# A spectator's local_slot() is -1 (Bontago-8or.11); no real slot is -1.
	return slot_id >= 0 and slot_id == local_slot()


## Host only: marks a peer ready in the lobby, or drops it from the session.
func set_peer_ready(peer_id: int, ready: bool) -> void:
	if not is_host() or not _peers.has(peer_id):
		return
	_peers[peer_id][LobbySeats.FIELD_READY] = ready
	_broadcast_roster()


## Host only: clears every peer's ready flag (host included) and republishes the roster.
## Bontago-1pi.89: Net owns this rule -- the session returning to the lobby calls it (through
## set_match_in_progress(false)) -- and the Lobby's Ready toggle only shows the result; it no
## longer resets the flags itself on entry (Bontago-1pi.73's workaround).
func reset_ready_flags() -> void:
	if _clear_ready_flags():
		_broadcast_roster()


## Host only: clears every ready flag without broadcasting; whether any flag changed.
func _clear_ready_flags() -> bool:
	if not is_host():
		return false
	var changed: bool = false
	for peer_id: int in _peers.keys():
		if bool(_peers[peer_id].get(LobbySeats.FIELD_READY, false)):
			_peers[peer_id][LobbySeats.FIELD_READY] = false
			changed = true
	return changed


func kick_peer(peer_id: int, reason: LeaveReason = LeaveReason.KICKED) -> void:
	if not is_host() or not _peers.has(peer_id):
		return
	var slot_id: int = int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))
	_peers.erase(peer_id)
	_ping_samples.erase(peer_id)
	_pending_handshake.erase(peer_id)
	# A kicked peer forfeits its rejoin token: no reservation is made for it.
	_tokens.erase(peer_id)
	# Bontago-1pi.57: ENet keeps a disconnecting peer in get_peers() until the
	# disconnect completes a poll later, and a send to it logs an engine error.
	# Mark it before anything below can broadcast (the roster, and whatever a
	# net_peer_left listener republishes), so it is never addressed again. A peer
	# the transport does not hold (nothing to disconnect) needs no mark.
	var transport: MultiplayerPeer = multiplayer.multiplayer_peer
	if transport != null and multiplayer.get_peers().has(peer_id):
		_disconnecting_peers[peer_id] = true
		transport.disconnect_peer(peer_id)
	# Bontago-1pi.53 review F2: compact BEFORE announcing the departure, as the
	# disconnect path does, so a listener of net_peer_left (the lobby republishing
	# its data) already reads the closed-up slot ids.
	_compact_lobby_slots()
	Events.net_peer_left.emit(peer_id, slot_id, reason)
	_broadcast_roster()


## Client: tells the host this instance is ready to start.
func set_local_ready(ready: bool) -> void:
	if is_client():
		_rpc_set_ready.rpc_id(HOST_PEER_ID, ready)
	elif _mode == Mode.HOST:
		set_peer_ready(HOST_PEER_ID, ready)


func all_peers_ready() -> bool:
	if _peers.is_empty():
		return false
	for peer_id: int in _peers.keys():
		# DECISION (Bontago-1pi.67): the host's own entry mirrors its Ready toggle like
		# any peer's (seeded false), but pressing Start is the host's consent, so the
		# Start gate waits for every OTHER seated human only.
		if peer_id == HOST_PEER_ID:
			continue
		if not bool(_peers[peer_id].get(LobbySeats.FIELD_READY, false)):
			return false
	return true


## Measured round trip to `peer_id` in milliseconds, from Net's own ping RPC
## rather than any ENet statistic, so the number is identical over Steam.
func ping_ms(peer_id: int = 0) -> float:
	var target: int = peer_id
	if target == 0:
		if is_client():
			return _own_ping_ms
		target = local_peer_id()
	if not _peers.has(target):
		return 0.0
	return float(_peers[target].get(LobbySeats.FIELD_PING_MS, 0.0))


# --- Lobby data (spec 3.4: "Steam lobbies store match settings as lobby
# data"; over ENet the host broadcasts the same Dictionary reliably) ---------

## Host only: publishes the lobby settings. ui/Lobby.gd passes
## MatchConfig.to_dict(); M3b writes the same Dictionary into Steam lobby data
## with no change on this side of the call.
func set_lobby_data(data: Dictionary) -> void:
	if not is_host():
		return
	_lobby_data = data.duplicate(true)
	Events.net_lobby_data_changed.emit(_lobby_data)
	# Bontago-mv0.1.10 review: same teardown hazard as _broadcast_roster().
	for peer_id: int in _broadcast_targets():
		_rpc_lobby_data.rpc_id(peer_id, _lobby_data)
	if _lan.is_advertising():
		_lan.update_advert({"map": str(_lobby_data.get("map_variant", 0))})
	# docs/M3b_PLAN.md "Design notes": tee the same Dictionary into Steam
	# lobby data, under one JSON key, every time this is called — the exact
	# call site ui/Lobby.gd already has, so it needs no change of its own.
	if _steam_session and steam_provider != null and _steam_lobby_id != 0:
		steam_provider.set_lobby_data(
			_steam_lobby_id, String(SteamClient.KEY_MATCH_CONFIG), SteamClient.encode_match_config(_lobby_data)
		)


## The last lobby data received, or what this host published. Clients read it
## to build their read-only view of the settings.
func lobby_data() -> Dictionary:
	return _lobby_data


# --- Steam session (spec 3.4, docs/M3b_PLAN.md P1) --------------------------
#
# M3b is a peer swap, not a new architecture: host_online()/join_lobby() are
# the Steam-shaped host_game()/join_game(), but Steam's own matchmaking calls
# are asynchronous (create_lobby/join_lobby fire a signal later), unlike
# ENet's synchronous create_server()/create_client(). These two therefore
# only kick the process off and return OK/a transport error immediately; the
# actual _mode transition and multiplayer.multiplayer_peer assignment happen
# in _on_steam_lobby_created()/_on_steam_lobby_joined() once Steam answers.
# From that point on _rpc_handshake, the roster RPCs and _on_connected_to_
# server() all run completely unmodified (docs/M3b_PLAN.md "the version check
# needs no new code") because they only ever touch MultiplayerAPI, never a
# concrete peer type.

## False whenever the addon was never installed in this checkout (most
## worktrees; see docs/M3b_RESEARCH.md "Spike results") OR Steam.steamInitEx()
## has not yet succeeded (status != 0 — client not running, out of date, or
## init_steam() simply hasn't been called yet). docs/M3b_PLAN.md "Design
## notes": "addon not installed" and "status != 0" are logged with different
## messages but collapse to this one false for every UI purpose — the whole
## point being a caller never needs to ask which case it is.
## Bontago-1pi.100 single owner of "which name does the local player go by".
## DECISION (owner: names come from Steam, the name setting is the fallback):
## (1) while Steam is initialised and reports a non-empty persona name, the
## persona wins; (2) otherwise the typed/saved name (`typed`, the Settings name;
## "" when never set); (3) "" so the host seats "Player N". The result is still
## cleaned/sanitised by every caller and again by the host.
func resolve_local_name(typed: String) -> String:
	if steam_available():
		var persona: String = PlayerNames.clean(
			String(steam_provider.local_persona_name()), config.max_player_name_length
		)
		if persona != "":
			return persona
	return typed


func steam_available() -> bool:
	return steam_provider != null and bool(steam_provider.is_available()) and _steam_ready


## Calls Steam.steamInitEx() through steam_provider and emits
## Events.net_steam_status_changed once it answers. Idempotent — safe for
## game/Main.gd to call unconditionally at boot even if something else
## already did. A no-op (not an error) when steam_provider is null, which
## only happens if this is called before _ready() has run.
func init_steam() -> void:
	if _steam_initialized:
		return
	_steam_initialized = true
	_wire_steam_signals()
	if steam_provider == null:
		return
	steam_provider.init()


## True only once host_online()/join_lobby() has produced a live
## SteamMultiplayerPeer — false offline, false mid-ENet-session, and false
## while a Steam lobby_created/lobby_joined callback is still pending.
## True for the private local host a Vs bots game runs on (nobody can join).
func is_private_session() -> bool:
	return _private_session


func is_steam_session() -> bool:
	return _steam_session


## Same contract as host_game(): starts a session and returns OK, or a
## transport error without creating anything. Unlike host_game(), OK here
## only means "the attempt started" — Steam's create_lobby() answers later
## through _on_steam_lobby_created(), which is what actually flips _mode to
## HOST. A caller that needs to know when hosting is actually live should
## watch Events.net_mode_changed, exactly as every other caller of is_host()
## already must for the async multi-frame join handshake too.
func host_online(player_name: String = "") -> Error:
	_wire_steam_signals()
	if not steam_available():
		return ERR_UNAVAILABLE
	# Bontago-mv0.2.6 finding B: refuse a second concurrent attempt rather than
	# issue a second Steam create_lobby() request while the first is still
	# awaiting its own lobby_created answer — see _steam_request_generation's
	# doc comment for the orphaned-lobby / misattributed-answer races this
	# prevents.
	if _steam_request_pending():
		return ERR_BUSY
	if _mode != Mode.OFFLINE:
		leave()
	_steam_pending_generations.append(_steam_request_generation)
	_steam_pending_targets.append(_STEAM_CREATE_REQUEST)
	_steam_pending_name = player_name
	steam_provider.create_lobby(config.steam_lobby_type, config.max_peers)
	return OK


## Same contract as join_game(), and the same asynchronous caveat as
## host_online(): Steam's own join_lobby() answers later through
## _on_steam_lobby_joined().
func join_lobby(lobby_id: int, player_name: String = "") -> Error:
	_wire_steam_signals()
	if not steam_available():
		return ERR_UNAVAILABLE
	# Same guard as host_online() above, and for the same reason (Bontago-
	# mv0.2.6 finding B).
	if _steam_request_pending():
		return ERR_BUSY
	if _mode != Mode.OFFLINE:
		leave()
	_steam_pending_generations.append(_steam_request_generation)
	_steam_pending_targets.append(lobby_id)
	_steam_pending_name = player_name
	steam_provider.join_lobby(lobby_id)
	return OK


## Lobbies tagged with this build's {game, version} from the last
## refresh_lobby_list() answer. Each is
## {"lobby_id", "name", "players", "max", "map"} — the Steam-side equivalent
## of discovered_games().
func discovered_lobbies() -> Array[Dictionary]:
	return _discovered_lobbies.duplicate(true)


## Asks Steam for the current lobby list, filtered to this game and this
## exact build version (spec 3.4: "Compare the version when joining a
## lobby..."; a stale build should not even appear in the list). Pull-based,
## unlike LAN's push advert — ui/MainMenu.gd (P3) is expected to call this on
## a config.steam_lobby_list_refresh_s timer. Results arrive later as
## Events.net_steam_lobbies_discovered.
func refresh_lobby_list() -> void:
	_wire_steam_signals()
	if not steam_available():
		return
	# Bontago-1pi.105: Steam keeps one outstanding lobby list request; never overlap.
	if _lobby_list_pending != LobbyListPending.NONE and Time.get_ticks_msec() - _lobby_list_sent_msec < LOBBY_LIST_STALE_MSEC:
		_lobby_list_refresh_queued = true
		SteamClient.log_line("lobby search: refresh coalesced, a request is still pending")
		return
	var filters: Array[Dictionary] = [
		{"key": String(SteamClient.KEY_GAME), "value": String(DISCOVERY_MAGIC)},
		{"key": String(SteamClient.KEY_VERSION), "value": build_version()},
	]
	steam_provider.request_lobby_list(filters)
	_lobby_list_pending = LobbyListPending.FILTERED
	_lobby_list_sent_msec = Time.get_ticks_msec()


## Opens the Steam overlay's invite dialog for this session's lobby. A no-op
## off Steam, offline, or before the lobby actually exists.
func invite_friends() -> void:
	if not steam_available() or not _steam_session or _steam_lobby_id == 0:
		return
	steam_provider.activate_invite_overlay(_steam_lobby_id)


## Connects to steam_provider's signals exactly once per provider instance.
## Called at the top of every entry point that can kick off Steam work
## (host_online, join_lobby, refresh_lobby_list, init_steam) rather than only
## in _ready(), because every P1/P3 test overwrites `steam_provider` with a
## FakeSteam *after* the node's own _ready() already ran — connecting only
## once in _ready() would leave that replacement's signals unwired.
func _wire_steam_signals() -> void:
	if steam_provider == null or steam_provider == _steam_signals_wired:
		return
	steam_provider.init_result.connect(_on_steam_init_result)
	steam_provider.lobby_created.connect(_on_steam_lobby_created)
	steam_provider.lobby_match_list.connect(_on_steam_lobby_match_list)
	steam_provider.lobby_joined.connect(_on_steam_lobby_joined)
	steam_provider.lobby_join_requested.connect(_on_steam_lobby_join_requested)
	_steam_signals_wired = steam_provider


func _on_steam_init_result(status: int, verbal: String) -> void:
	_steam_ready = status == 0
	Events.net_steam_status_changed.emit(_steam_ready, verbal)


## Pops the oldest still-outstanding host_online()/join_lobby() request's
## generation and reports whether this answer is stale (leave() already
## bumped past it — see _steam_request_generation's doc comment). A stale
## success (`ok`) is handed straight to steam_provider.leave_lobby() so it is
## never orphaned; a stale failure is simply dropped. Shared by
## _on_steam_lobby_created() and _on_steam_lobby_joined() below.
## Bontago-1pi.48: `index` is the pending entry this answer resolves (see
## _steam_pending_index()), or -1 when no request matches it.
func _consume_steam_answer_is_stale(index: int, ok: bool, lobby_id: int) -> bool:
	if index < 0 or index >= _steam_pending_generations.size():
		# Defensive: host_online()/join_lobby() always push a generation
		# before issuing the Steam call, so this should not happen in
		# practice — treat a stray answer the same as stale so a success is
		# never orphaned.
		if ok:
			steam_provider.leave_lobby(lobby_id, "stray answer: no pending request matches it")
		return true
	var answer_generation: int = _steam_pending_generations[index]
	_steam_pending_generations.remove_at(index)
	_steam_pending_targets.remove_at(index)
	if answer_generation != _steam_request_generation:
		if ok:
			steam_provider.leave_lobby(lobby_id, "stale answer: leave() cancelled its request")
		return true
	return false


## Oldest pending entry whose target is `target` (a join's lobby id, or
## _STEAM_CREATE_REQUEST), or -1.
func _steam_pending_index(target: int) -> int:
	return _steam_pending_targets.find(target)


## Oldest pending join_lobby() entry whatever its target, or -1.
func _steam_first_pending_join_index() -> int:
	for i: int in _steam_pending_targets.size():
		if _steam_pending_targets[i] != _STEAM_CREATE_REQUEST:
			return i
	return -1


## Bontago-1pi.48: true for Steam's LobbyEnter echo of a lobby this process
## created (or a repeat enter of the lobby it is already in) — a success no
## join_lobby() asked for. Arrives after lobby_created in every probe log, but
## the order is not relied on: an echo while a create is still pending counts.
func _is_own_lobby_enter_echo(lobby_id: int, response: int) -> bool:
	if response != 1 or _steam_pending_index(lobby_id) >= 0:
		return false
	if _steam_created_lobbies.has(lobby_id):
		return true
	if _steam_session and lobby_id == _steam_lobby_id:
		return true
	return _steam_pending_index(_STEAM_CREATE_REQUEST) >= 0


func _on_steam_lobby_created(result: int, lobby_id: int) -> void:
	SteamClient.log_line("lobby_created: result=%d lobby_id=%d" % [result, lobby_id])
	if result == 1:
		_steam_created_lobbies[lobby_id] = true
	# Bontago-mv0.2.6 finding B / Bontago-mv0.4: consume this request's
	# generation first; a stale answer abandons whatever lobby Steam actually
	# created rather than let the guard below silently drop it and orphan it.
	if _consume_steam_answer_is_stale(_steam_pending_index(_STEAM_CREATE_REQUEST), result == 1, lobby_id):
		return
	if _mode != Mode.OFFLINE:
		return
	# Steamworks EResult k_EResultOK == 1. DECISION: a well-known, stable
	# Steamworks constant (unchanged since the SDK's introduction; also the
	# value GodotSteam's own docs describe for this exact signal), not
	# re-verified against isteamclient.h/steamtypes.h in this checkout — no
	# Steamworks SDK headers are bundled in the downloaded GDExtension zip
	# (see docs/M3b_RESEARCH.md "Spike results").
	if result != 1:
		Events.net_join_failed.emit(JoinError.TRANSPORT, "Steam lobby creation failed (result %d)" % result)
		return

	var host_name: String = PlayerNames.sanitize(
		resolve_local_name(_steam_pending_name), config.max_player_name_length, 0
	)
	# Tag the lobby *before* attempting to instantiate the transport peer.
	# ClassDB.instantiate(&"SteamMultiplayerPeer") succeeding is explicitly
	# unverifiable by GUT (docs/M3b_PLAN.md "Testing without Steam" /"Known
	# limitations") on any checkout that hasn't installed the addon, but the
	# lobby-data write itself only needs steam_provider, so ordering it first
	# keeps this half of host_online()'s contract testable with FakeSteam
	# alone regardless of whether the addon is present.
	steam_provider.set_lobby_data(lobby_id, String(SteamClient.KEY_GAME), String(DISCOVERY_MAGIC))
	steam_provider.set_lobby_data(lobby_id, String(SteamClient.KEY_VERSION), build_version())
	steam_provider.set_lobby_data(lobby_id, String(SteamClient.KEY_MAP), "")
	steam_provider.set_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME), host_name)
	steam_provider.set_lobby_data(
		lobby_id, String(SteamClient.KEY_MATCH_CONFIG), SteamClient.encode_match_config(_lobby_data)
	)

	steam_provider.set_lobby_joinable(lobby_id, true)
	SteamClient.log_line("lobby readback: game=%s version=%s" % [
		steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME)),
		steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION))])

	var peer: MultiplayerPeer = _make_steam_host_peer()
	if peer == null:
		Events.net_join_failed.emit(JoinError.TRANSPORT, "SteamMultiplayerPeer unavailable")
		steam_provider.leave_lobby(lobby_id, "host peer unavailable")
		return

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.HOST
	_steam_session = true
	_steam_lobby_id = lobby_id
	_host_build_version = build_version()
	_peers.clear()
	_peers[HOST_PEER_ID] = LobbySeats.entry_to_wire(HOST_PEER_ID, 0, host_name, false, 0.0, _host_build_version)
	_next_slot_id = 1
	_accepting_joins = true
	_reset_rejoin_state()
	_steam_selfcheck_accum = 0.0
	Events.net_mode_changed.emit(_mode)


func _on_steam_lobby_joined(lobby_id: int, response: int) -> void:
	# Bontago-1pi.48 root cause: Steam also sends the creator a lobby_joined for
	# its own new lobby. With the create already answered, the stray-answer
	# branch below used to leave_lobby() it, so every game-hosted lobby died
	# instantly and was never found by another account's search.
	if _is_own_lobby_enter_echo(lobby_id, response):
		SteamClient.log_line("lobby_joined: lobby=%d is this process's own lobby enter (creator echo); ignored" % lobby_id)
		return
	var index: int = _steam_pending_index(lobby_id)
	if index < 0:
		# DECISION: an answer whose lobby id matches no pending join resolves
		# the oldest pending join (the pre-1pi.48 FIFO rule), never a create.
		index = _steam_first_pending_join_index()
	# Same stale-answer handling as _on_steam_lobby_created() above, and for
	# the same reason (Bontago-mv0.2.6 finding B / Bontago-mv0.4).
	if _consume_steam_answer_is_stale(index, response == 1, lobby_id):
		return
	if _mode != Mode.OFFLINE:
		return
	# Steamworks EChatRoomEnterResponse k_EChatRoomEnterResponseSuccess == 1.
	# Same DECISION/caveat as _on_steam_lobby_created()'s EResult check above.
	if response != 1:
		_fail_join(JoinError.REFUSED, "could not join Steam lobby (response %d)" % response)
		return
	var owner_id: int = steam_provider.lobby_owner(lobby_id)
	var peer: MultiplayerPeer = _make_steam_client_peer(owner_id)
	if peer == null:
		# Bontago-mv0.2.6 (independent-review finding A): Steam's own
		# lobby_joined already made this instance a lobby member (response ==
		# 1) by the time the transport peer fails to construct, but neither
		# _steam_session nor _steam_lobby_id is set yet at this point (those
		# only flip once the peer actually succeeds, below) — leave()'s own
		# teardown reads both, and its very first line returns immediately
		# while _mode is still OFFLINE (it only transitions to CLIENT further
		# down), so routing this failure through leave() would need the mode
		# transition to happen *before* peer construction is known to have
		# succeeded, which is a bigger reshuffle than this fix warrants.
		# DECISION: call steam_provider.leave_lobby() directly here instead,
		# mirroring _on_steam_lobby_created()'s matching peer==null branch
		# above (which already does exactly this for the host side) rather
		# than restructure leave()'s guard — same fix shape, same file, no new
		# teardown path.
		steam_provider.leave_lobby(lobby_id, "client peer unavailable")
		_fail_join(JoinError.TRANSPORT, "SteamMultiplayerPeer unavailable")
		return
	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.CLIENT
	_steam_selfcheck_accum = 0.0
	_steam_session = true
	_steam_lobby_id = lobby_id
	_peers.clear()
	_pending_join_name = PlayerNames.clean(
		resolve_local_name(_steam_pending_name), config.max_player_name_length
	)
	_joined_accepted = false
	_join_deadline = _now() + config.connect_timeout + config.handshake_timeout
	Events.net_mode_changed.emit(_mode)
	# From here _on_connected_to_server() (already wired in _ready()) fires
	# once the SteamMultiplayerPeer's own connection completes, and runs the
	# unmodified _rpc_handshake round trip — no Steam-specific code needed.


enum LobbyListPending { NONE, FILTERED, DEBUG }
## A lobby list request this old is presumed lost, so a new refresh may go out.
const LOBBY_LIST_STALE_MSEC: int = 15000
var _lobby_list_pending: LobbyListPending = LobbyListPending.NONE
var _lobby_list_refresh_queued: bool = false
var _lobby_list_sent_msec: int = 0
## `--steam-lobby-debug`; a var so tests can toggle it.
var steam_lobby_debug: bool = OS.get_cmdline_user_args().has("--steam-lobby-debug")


func _on_steam_lobby_match_list(lobby_ids: Array) -> void:
	if _lobby_list_pending == LobbyListPending.DEBUG:
		_lobby_list_pending = LobbyListPending.NONE
		var lines: PackedStringArray = PackedStringArray()
		for i: int in mini(LOBBY_DEBUG_SAMPLE_COUNT, lobby_ids.size()):
			var id: int = int(lobby_ids[i])
			lines.append("%d{owner=%d members=%d game=%s version=%s}" % [id, steam_provider.lobby_owner(id), steam_provider.lobby_member_count(id), steam_provider.get_lobby_data(id, String(SteamClient.KEY_GAME)), steam_provider.get_lobby_data(id, String(SteamClient.KEY_VERSION))])
		SteamClient.log_line("unfiltered debug search (answers the unfiltered request): %d lobbies visible; first: %s" % [lobby_ids.size(), " ".join(lines)])
		_drain_queued_lobby_refresh()
		return
	var was_filtered: bool = _lobby_list_pending == LobbyListPending.FILTERED
	_lobby_list_pending = LobbyListPending.NONE
	if was_filtered and steam_lobby_debug:
		# Sent only now, after the filtered answer, so Steam never cancels one for the other.
		steam_provider.request_unfiltered_debug_list()
		_lobby_list_pending = LobbyListPending.DEBUG
		_lobby_list_sent_msec = Time.get_ticks_msec()
	var result: Array[Dictionary] = []
	for raw_id: Variant in lobby_ids:
		var lobby_id: int = int(raw_id)
		var game: String = steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_GAME))
		var version: String = steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_VERSION))
		if game != String(DISCOVERY_MAGIC) or version != build_version():
			continue
		result.append({
			"lobby_id": lobby_id,
			"name": steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_HOST_NAME)),
			"players": steam_provider.lobby_member_count(lobby_id),
			"max": config.max_peers,
			"map": steam_provider.get_lobby_data(lobby_id, String(SteamClient.KEY_MAP)),
		})
	_discovered_lobbies = result
	Events.net_steam_lobbies_discovered.emit(result)
	# Bontago-1pi.48: one line per search so a failed Steam join can be diagnosed from godot.log.
	SteamClient.log_line("lobby search (answers the filtered request): %d lobbies returned, %d match game+version %s" % [lobby_ids.size(), result.size(), build_version()])
	_drain_queued_lobby_refresh()


func _drain_queued_lobby_refresh() -> void:
	if _lobby_list_refresh_queued and _lobby_list_pending == LobbyListPending.NONE:
		_lobby_list_refresh_queued = false
		refresh_lobby_list()


## Bontago-1pi.48 diagnostics: every STEAM_SELFCHECK_PERIOD_S while a Steam
## session is live, logs `STEAM [time] SELFCHECK ...` (members, owner vs me,
## member limit, all lobby data). A host that silently left its lobby reads
## members=0 / owner=0 here even though Net still believes it is hosting.
func _tick_steam_selfcheck(delta: float) -> void:
	if not _steam_session or _steam_lobby_id == 0 or steam_provider == null:
		return
	_steam_selfcheck_accum += delta
	if _steam_selfcheck_accum < STEAM_SELFCHECK_PERIOD_S:
		return
	_steam_selfcheck_accum = 0.0
	var role: String = "HOST" if _mode == Mode.HOST else "CLIENT"
	SteamClient.log_line("SELFCHECK role=%s %s" % [role, steam_provider.self_check_line(_steam_lobby_id)])


## The overlay's "Join Game" / invite-accept path when this game is already
## running (spec 3.4/research: "Invites arrive two ways and both must be
## handled"). The other way, `+connect_lobby` on a freshly launched process's
## command line, is handled by _apply_connect_lobby_args() below.

func _on_steam_lobby_join_requested(lobby_id: int, _friend_id: int) -> void:
	join_lobby(lobby_id, "")


## Seconds --host-online's smoke test waits for Steam's async lobby_created
## before reporting the lobby id, and then for one requestLobbyList() round
## trip before reporting discovered_lobbies(). Diagnostic-only timing (not a
## live gameplay knob — see tools/screenshot_main.gd's own local consts for
## the same reasoning), so it stays a file const here rather than a NetConfig
## field.
const _SMOKE_LOBBY_WAIT_S: float = 5.0
const _SMOKE_LIST_WAIT_S: float = 6.0

## docs/M3b_PLAN.md P1's "windowed single-PC Steam smoke test", reached only
## through --host-online (see _apply_command_line_args()'s DECISION above).
## Never run by any automated test or by normal play; prints exactly what
## that acceptance step needs onto stdout so the check can be read off a
## captured log. Fire-and-forget: apply_command_line() does not await this.
##
## NOTE for whoever reruns this: with config.steam_lobby_type at its
## FriendsOnly default (owner decision), discovered_lobbies() below is
## expected to print [] on a single Steam account — verified empirically
## (netcode-F2-smoke-public.log vs netcode-F2-smoke-fixed3.log in this
## worker's scratch directory): the exact same lobby is found immediately
## when steam_lobby_type is temporarily set to Public (2), and
## lobby_member_count()/lobby_owner() below always confirm the lobby is real
## either way. Steamworks' own RequestLobbyList() does not return a
## FriendsOnly lobby to a search from the owner's own account (it is scoped
## to the owner's *friends*, a genuinely different Steam identity) — this is
## the one part of this acceptance step that a single-PC/single-account
## smoke test cannot exercise, and needs the owner's two-PC run instead.
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
	print("NET_SMOKE mode=%d is_steam_session=%s lobby_id=%d" % [_mode, _steam_session, _steam_lobby_id])
	if _steam_lobby_id != 0:
		print("NET_SMOKE lobby_member_count=%d lobby_owner=%d" % [
			steam_provider.lobby_member_count(_steam_lobby_id), steam_provider.lobby_owner(_steam_lobby_id)
		])
	refresh_lobby_list()
	await get_tree().create_timer(_SMOKE_LIST_WAIT_S).timeout
	print("NET_SMOKE discovered_lobbies=%s" % [discovered_lobbies()])


# --- LAN discovery (spec 3.4) -----------------------------------------------

## Starts listening on config.discovery_port for hosts advertising themselves.
## Results arrive as Events.net_games_discovered.
func start_discovery() -> void:
	_lan.start_listening()


func stop_discovery() -> void:
	_lan.stop_listening()


## Games seen within config.discovery_entry_ttl, newest advert first. Each is
## {"name", "address", "port", "version", "players", "max", "map"}.
func discovered_games() -> Array[Dictionary]:
	return _lan.games()


# --- Lag / loss simulation --------------------------------------------------

## Turns the simulator on or off for this instance (see core/net/NetSim.gd).
## `lag_ms` is one-way. Configures this instance's own queue for outbound
## intents and cursors, and forwards to SnapshotSync so inbound snapshots get
## the same settings on its own queue — the two sides must not share one
## NetSim, or they would steal each other's payloads (docs/M3a_PLAN.md,
## integrator wiring). # DECISION: SnapshotSync is an autoload, so it is
## always safe to reach directly here rather than through a signal.
func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	_sim.configure(lag_ms, jitter_ms, loss)
	SnapshotSync.set_simulation(lag_ms, jitter_ms, loss)


## The live simulator, so SnapshotSync and the debug overlay share one set of
## settings and one set of counters.
func simulation() -> NetSim:
	return _sim


func simulation_enabled() -> bool:
	return not _sim.is_idle()


# --- Debug stats (spec Part 4 M3's overlay) ---------------------------------

## {"mode": int, "peers": int, "ping_ms": float, "snapshot_bps": float,
## "snapshot_last_bytes": int, "interp_delay_ms": float, "loss_pct": float,
## "sim_lag_ms": float, "sim_loss": float}. Refreshed at config.stats_hz and
## mirrored on Events.net_stats_updated; ui/NetDebugOverlay.gd only reads it.
func stats() -> Dictionary:
	var loss_pct: float = 0.0
	var submitted: int = _sim.submitted_count()
	if submitted > 0:
		loss_pct = float(_sim.dropped_count()) / float(submitted) * 100.0
	return {
		"mode": _mode,
		"peers": _peers.size(),
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


# --- Command line (spec 3.4 "Testing") --------------------------------------

## Parses --host, --join=<ip[:port]>, --port=<n>, --headless-host,
## --host-online, --player-name=<s>, --sim-lag=<ms>, --sim-loss=<fraction>
## from OS command-line arguments after "--" and acts on them, then separately scans
## the full command line for Steam's own "+connect_lobby <id>" launch
## convention (docs/M3b_PLAN.md "Design notes": Valve's own argv convention,
## not this project's --flag=value one, so OS.get_cmdline_user_args() — the
## tokens after Godot's own "--" — would never see it). Called once by
## game/Main.gd so a headless instance needs no UI. Returns true when an
## argument put this instance into a session.
func apply_command_line() -> bool:
	if _apply_command_line_args(OS.get_cmdline_user_args()):
		return true
	return _apply_connect_lobby_args(OS.get_cmdline_args())


## The parsing/dispatch logic behind apply_command_line(), taking the argument
## list explicitly so a unit test can drive it without OS.get_cmdline_user_args()
## (there is no OS.set_cmdline_user_args() to fake it with).
func _apply_command_line_args(args: PackedStringArray) -> bool:
	var options: Dictionary = {}
	var flags: Dictionary = {}
	for raw: String in args:
		var text: String = raw
		while text.begins_with("-"):
			text = text.substr(1)
		var eq: int = text.find("=")
		if eq >= 0:
			options[text.substr(0, eq)] = text.substr(eq + 1)
		else:
			flags[text] = true

	if options.has("sim-lag") or options.has("sim-loss"):
		var lag: float = float(options.get("sim-lag", 0.0))
		var loss: float = float(options.get("sim-loss", 0.0))
		set_simulation(lag, 0.0, loss)

	# Bontago-1pi.48: host a Public Steam lobby so the Join > Steam list can find
	# it (FriendsOnly lobbies never appear in Steam's lobby search). Duplicated so
	# the shared net_config.tres resource is not mutated.
	if flags.has("steam-public-lobby"):
		config = config.duplicate() as NetConfig
		config.steam_lobby_type = NetConfig.STEAM_LOBBY_TYPE_PUBLIC

	var port: int = int(options.get("port", 0))
	var player_name: String = String(options.get("player-name", ""))

	if flags.has("host") or flags.has("headless-host"):
		# --match-config=<path> is parsed here, inside the host branch, rather
		# than up with --sim-lag/--sim-loss above, so it is a no-op for --join
		# (task brief: "host-only; ignore on --join") with no separate flags-
		# have("join") guard needed.
		if options.has("match-config"):
			_load_match_config_override(String(options["match-config"]))
		host_game(port, player_name if player_name != "" else "Host")
		return true

	# DECISION: --host-online is this package's own windowed single-PC Steam
	# smoke test aid (docs/M3b_PLAN.md P1 acceptance), not a shipped player
	# entry point — no menu button reaches it. It exists only so the smoke
	# test can be launched and observed from stdout with `godot --path .
	# -- --host-online` on a machine that already has the addon installed and
	# Steam running, without needing game/Main.gd's own
	# Net.init_steam() call (the integrator's not-yet-landed line, step 4 of
	# docs/M3b_PLAN.md's integration order) to already be wired in. Uses the
	# same existing bare-flag convention --host/--headless-host already do,
	# not a new parser shape.
	if flags.has("host-online"):
		_run_steam_smoke_host_online(player_name if player_name != "" else "SmokeHost")
		return true

	if options.has("join"):
		var address_spec: String = String(options["join"])
		var address: String = address_spec
		var join_port: int = port
		var colon: int = address_spec.rfind(":")
		if colon >= 0:
			address = address_spec.substr(0, colon)
			join_port = int(address_spec.substr(colon + 1))
		join_game(address, join_port, player_name if player_name != "" else "Player")
		return true

	return false


## The MatchConfig `--match-config=<path>` loaded, or null if the flag was
## absent, the command line never reached the host branch (--join, or no
## role flag at all), or the path/resource was rejected. game/Main.gd's
## _build_headless_bot_config() reads this in place of its own preloaded
## `match_config` export when it is non-null — the same
## duplicate-then-override seam that function already uses for --bots=/
## --players=, extended rather than replaced.
func match_config_override() -> MatchConfig:
	return _match_config_override


## _apply_command_line_args()'s --match-config=<path> handler. A bad path or
## a resource of the wrong type never blocks --headless-host from starting —
## it logs a push_error and leaves _match_config_override null, which reads
## downstream as "no override" (game/Main.gd falls back to
## config/match_defaults.tres exactly as if the flag had been omitted).
## Explicitly resets to null on failure (not "keep whatever was there
## before") so one bad flag value can never be masked by an earlier good one.
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


## The +connect_lobby scan, split out as its own sibling (rather than bolted
## onto _apply_command_line_args()'s "-"-stripping loop, which assumes every
## token has a "--"/"-" prefix and this one never does) so a unit test can
## drive it with a synthetic full argument list, the same way
## _apply_command_line_args() takes its own list explicitly — there is no
## OS.set_cmdline_args() to fake either call site with.
func _apply_connect_lobby_args(args: PackedStringArray) -> bool:
	for i: int in range(args.size() - 1):
		if args[i] != "+connect_lobby":
			continue
		var text: String = args[i + 1]
		if not text.is_valid_int():
			return false
		var lobby_id: int = int(text)
		if lobby_id <= 0:
			return false
		join_lobby(lobby_id, "Player")
		return true
	return false


# --- Transport (the only place ENetMultiplayerPeer/SteamMultiplayerPeer may be named) --

func _make_host_peer(port: int, bind_ip: String = "*") -> MultiplayerPeer:
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	enet_peer.set_bind_ip(bind_ip)
	# DECISION: ENet's own max_clients counts remote clients only, one fewer
	# than config.max_peers (which includes the host). Passed through
	# unreduced on purpose: this only widens ENet's own raw cap, giving a
	# peer that arrives exactly at the limit room to complete the ENet
	# handshake and receive _rpc_handshake's own SERVER_FULL refusal (with a
	# reason the lobby can show) instead of a bare transport-level
	# connection_failed. The real cap is enforced in _rpc_handshake.
	var err: Error = enet_peer.create_server(port, config.max_peers)
	if err != OK:
		push_warning("Net: create_server on port %d failed with error %d" % [port, err])
		return null
	return enet_peer


func _make_client_peer(address: String, port: int) -> MultiplayerPeer:
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = enet_peer.create_client(address, port)
	if err != OK:
		push_warning("Net: create_client to %s:%d failed with error %d" % [address, port, err])
		return null
	return enet_peer


## Sibling to _make_host_peer()/_make_client_peer() rather than a literal
## extension of them: Steam peer construction takes no port/address (the
## lobby, not an IP:port, is the rendezvous), so the parameter shapes cannot
## match. Still the only two functions in the file (besides the ENet pair
## above) that may name a concrete peer class — here reached purely through
## ClassDB, never a static `SteamMultiplayerPeer` type, so this file still
## parses in a checkout without the addon installed (docs/M3b_PLAN.md
## "Design notes"; ClassDB.class_exists(&"SteamMultiplayerPeer") verified
## true with the addon installed on this machine, false without it).
##
## SAFETY (found while writing this package's own regression tests, not in
## the plan): calling SteamMultiplayerPeer.create_host()/create_client() when
## the process's Steam context was never initialized (steamInitEx never
## called, or it failed) segfaults the engine — reproduced empirically on
## this machine (netcode-F-probe_peer_no_init.log: SIGSEGV inside
## steam_api64.dll). `not _steam_ready` guards the real, no-init case;
## `not (steam_provider is SteamClient)` guards the FakeSteam-driven case a
## GUT test always uses, so ClassDB.instantiate(&"SteamMultiplayerPeer") is
## architecturally unreachable from any automated test regardless of what a
## FakeSteam's signals claim — the exact thing docs/M3b_PLAN.md's "Testing
## without Steam" says GUT cannot verify either way.
func _make_steam_host_peer() -> MultiplayerPeer:
	if steam_host_peer_override != null:
		return steam_host_peer_override
	if not _steam_ready or not (steam_provider is SteamClient):
		return null
	if not ClassDB.class_exists(&"SteamMultiplayerPeer"):
		return null
	var obj: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	var peer: MultiplayerPeer = obj as MultiplayerPeer
	if peer == null:
		return null
	# server_relay = true: client traffic routes through the host (spec 3.4
	# "Model: Host-authoritative listen server"), matching ENet's implicit
	# star topology.
	peer.set("server_relay", true)
	# Virtual port 0: this project has exactly one Steam session per lobby,
	# so it never needs more than SteamMultiplayerPeer's one default channel
	# of virtual ports.
	var err: Variant = peer.call("create_host", 0)
	if int(err) != OK:
		push_warning("Net: SteamMultiplayerPeer create_host failed with error %d" % int(err))
		return null
	return peer


func _make_steam_client_peer(owner_steam_id: int) -> MultiplayerPeer:
	if not _steam_ready or not (steam_provider is SteamClient):
		return null
	if not ClassDB.class_exists(&"SteamMultiplayerPeer"):
		return null
	var obj: Object = ClassDB.instantiate(&"SteamMultiplayerPeer")
	var peer: MultiplayerPeer = obj as MultiplayerPeer
	if peer == null:
		return null
	peer.set("server_relay", true)
	var err: Variant = peer.call("create_client", owner_steam_id, 0)
	if int(err) != OK:
		push_warning("Net: SteamMultiplayerPeer create_client failed with error %d" % int(err))
		return null
	return peer


# --- MultiplayerAPI signal handlers -----------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_handshake[id] = _now() + config.handshake_timeout
	# Deferred: ENetMultiplayerPeer's own per-peer table can lag one idle
	# frame behind the peer_connected signal, and get_peer() logs an engine
	# error for an id it doesn't have yet.
	call_deferred("_apply_peer_timeout", id)


func _on_peer_disconnected(id: int) -> void:
	_disconnecting_peers.erase(id)
	_pending_handshake.erase(id)
	_seat_pref_buckets.erase(id)
	if _mode != Mode.HOST:
		return
	if not _peers.has(id):
		return
	var slot_id: int = int(_peers[id].get(LobbySeats.FIELD_SLOT_ID, -1))
	_peers.erase(id)
	_ping_samples.erase(id)
	# Bontago-8or.11: a seated peer dropping mid-match keeps a reservation on
	# its slot for as long as the seat policy calls it reclaimable (its
	# disconnect grace); quoting the token on the next handshake gets it back.
	var token: String = String(_tokens.get(id, ""))
	_tokens.erase(id)
	if _match_in_progress and slot_id >= 0 and token != "":
		_reservations[token] = slot_id
	# Bontago-1pi.53: in the lobby the seats close up behind the leaver, in the
	# same roster broadcast (a no-op mid-match).
	_compact_lobby_slots()
	_broadcast_roster()
	# DECISION: ENet's peer_disconnected carries no reason, and distinguishing
	# a graceful client leave() from a dropped connection would need its own
	# wire message. Reported uniformly as TIMEOUT; docs/M3a_PLAN.md's grace
	# period (P3's Match.on_peer_left) reacts the same way either way, so this
	# has no gameplay impact.
	Events.net_peer_left.emit(id, slot_id, LeaveReason.TIMEOUT)


func _on_connected_to_server() -> void:
	if _mode != Mode.CLIENT:
		return
	# Only the host that issued the token may see it.
	_rpc_handshake.rpc_id(HOST_PEER_ID, build_version(), _pending_join_name, quoted_rejoin_token())


## The token the handshake quotes: the stored one only when it came from the
## host this connection is going to, otherwise "".
func quoted_rejoin_token() -> String:
	return _rejoin_token if _rejoin_scope == _current_join_scope() else ""


func _current_join_scope() -> String:
	if _steam_session:
		return "steam:%d" % _steam_lobby_id
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

## `rejoin_token` (Bontago-8or.11) is what _rpc_join_accepted handed this
## player on an earlier join, or "". It has a default so the parameter list
## still binds for a sender that omits it; the build check refuses any real
## older build first anyway.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_handshake(build: String, player_name: String, rejoin_token: String = "") -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peers.has(sender):
		return
	if build != _host_build_version:
		_reject_peer(sender, JoinError.VERSION_MISMATCH)
		return
	if _match_in_progress:
		_handshake_mid_match(sender, build, player_name, rejoin_token)
		return
	# Spec 3.4: joining is lobby-only in M3a. Checked before capacity so a
	# late joiner learns the real reason — a full lobby is a different message.
	if not _accepting_joins:
		_reject_peer(sender, JoinError.MATCH_IN_PROGRESS)
		return
	if _peers.size() >= config.max_peers:
		_reject_peer(sender, JoinError.SERVER_FULL)
		return
	_accept_peer(sender, build, player_name, _take_next_lobby_slot())


## Bontago-8or.11: the handshake while a match runs. A token naming a slot
## that is still reclaimable wins first and skips _accepting_joins and the
## capacity check (its own departure freed the room): spec 3.4 lists
## reconnect separately from "Mid-match joins can be enabled in settings", and
## the disconnect grace exists precisely so a dropped player can come back.
## Anyone else is a new late joiner: refused unless the match allows
## mid-match joins, then seated in an open human slot or, failing that, as a
## spectator (slot -1).
##
## DECISION (Bontago-8or.11): a returning player whose grace already ran out
## (its slot was eliminated) is treated as a brand-new late joiner, not
## refused -- the eliminated slot is no longer theirs to reclaim, and the
## ordinary mid-match-join rules decide whether they may watch or take a seat.
func _handshake_mid_match(sender: int, build: String, player_name: String, rejoin_token: String) -> void:
	var reclaimed: int = _reclaimable_slot_for(rejoin_token)
	if reclaimed >= 0:
		_reservations.erase(rejoin_token)
		_accept_peer(sender, build, player_name, reclaimed, rejoin_token)
		return
	if not _accepting_joins:
		_reject_peer(sender, JoinError.MATCH_IN_PROGRESS)
		return
	# DECISION (Bontago-8or.11): spectators count against config.max_peers --
	# it is the transport's connection budget, not a player count.
	if _peers.size() >= config.max_peers:
		_reject_peer(sender, JoinError.SERVER_FULL)
		return
	var seat: int = -1
	if _pick_open_seat.is_valid():
		seat = int(_pick_open_seat.call())
	if seat >= 0 and (peer_of_slot(seat) != -1 or _reservations.values().has(seat)):
		# Defensive: a policy must never hand out a seat a live peer holds or a
		# departed peer has reserved.
		seat = -1
	_accept_peer(sender, build, player_name, seat)


## The slot `rejoin_token` reserves, if the seat policy still lets it be
## reclaimed and no live peer holds it; -1 otherwise (including an unknown or
## oversized token -- a new joiner's empty string in practice).
func _reclaimable_slot_for(rejoin_token: String) -> int:
	if rejoin_token.is_empty() or rejoin_token.length() > REJOIN_TOKEN_MAX_CHARS:
		return -1
	if not _reservations.has(rejoin_token):
		return -1
	var slot_id: int = int(_reservations[rejoin_token])
	if slot_id < 0 or peer_of_slot(slot_id) != -1:
		return -1
	if not _can_reclaim_seat.is_valid() or not bool(_can_reclaim_seat.call(slot_id)):
		return -1
	return slot_id


## The slot a lobby joiner (or a spectator returning to the lobby) is seated in.
##
## Bontago-1pi.53 (docs/LOBBY_REWORK_PLAN.md R4): the LOWEST free slot, not the next
## monotonic id, so a joiner never lands above a hole. (_compact_lobby_slots closes
## the holes a leaver makes; this keeps the invariant for every seating path.)
## "Free" = no roster entry holds it and no rejoin reservation names it. Mid-match
## the monotonic counter still applies (a slot a dropped player may reclaim, or
## one the match already built a PlayerSlot for, is never handed to someone else).
func _take_next_lobby_slot() -> int:
	if _match_in_progress:
		var next_id: int = _next_slot_id
		_next_slot_id += 1
		return next_id
	var taken: Dictionary = {}
	for peer_id: int in _peers.keys():
		var held: int = int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))
		if held >= 0:
			taken[held] = true
	for reserved: Variant in _reservations.values():
		taken[int(reserved)] = true
	var slot_id: int = 0
	while taken.has(slot_id):
		slot_id += 1
	return slot_id


## Host only. Lobby phase only: moves every seated peer down so the slot ids run
## 0..n-1 with no hole, keeping their order (ascending old slot, peer id as the
## tie-break, so every run agrees). Spectators (slot -1) hold no seat and are left
## alone. Returns how many peers changed slot; the CALLER publishes the roster
## (_broadcast_roster), which is what carries the new peer -> slot map to every
## client (and to the host's own lobby through net_roster_changed).
##
## Bontago-1pi.53, P2 review finding 1: slot ids were never compacted, so after a
## player left the lobby the table had a hole below the highest human slot, and
## LobbySeats.start_blocker reported a slot conflict that blocked Start even with
## zero bots until someone rejoined. Never during a match: there a slot id is a
## PlayerSlot index the match already built, and a dropped player's rejoin token
## reserves it, so a mid-match leave keeps its hole (see _handshake_mid_match).
## The host never moves: it holds slot 0, the lowest, and local_slot() relies on it.
func _compact_lobby_slots() -> int:
	if _mode != Mode.HOST or _match_in_progress:
		return 0
	var seated: Array[Vector2i] = []
	for peer_id: int in _peers.keys():
		var held: int = int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1))
		if held >= 0:
			seated.append(Vector2i(held, peer_id))
	seated.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x < b.x if a.x != b.x else a.y < b.y
	)
	var moved: int = 0
	for index: int in range(seated.size()):
		if seated[index].x != index:
			_set_peer_slot(seated[index].y, index)
			moved += 1
	return moved


## Host only. Moves `peer_id` to `slot_id` (-1 = spectator). A name the host
## derived itself (the joiner sent none, so it holds the "Player N" fallback of
## the slot it was accepted into: "name_auto") is derived again for the new slot,
## so the label never goes stale and never collides with the next joiner's or a
## bot's "Player N" for the slot this peer vacated (Bontago-1pi.53 review F1). A
## name the player chose is never touched, even when it reads "Player 3".
func _set_peer_slot(peer_id: int, slot_id: int) -> void:
	var entry: Dictionary = _peers[peer_id]
	entry[LobbySeats.FIELD_SLOT_ID] = slot_id
	if bool(entry.get(LobbySeats.FIELD_NAME_AUTO, false)):
		entry[LobbySeats.FIELD_NAME] = PlayerNames.fallback_for_slot(slot_id)


## Seats `peer_id` in `slot_id` (-1 = spectator, Bontago-8or.11). `token` is a
## reconnecting peer's existing rejoin token, reused so a second drop also
## works; a new peer gets a fresh one.
##
## Bontago-8or.11 ordering: the joiner hears _rpc_join_accepted and the
## roster *before* Events.net_peer_joined fires, because net/MatchNet.gd
## answers that event with a mid-match world replay (rpc_id, reliable, the
## same ordered channel), and the replay's net_match_start builds the
## joiner's world against Net.local_slot() -- which must already be the seat
## assigned here.
func _accept_peer(peer_id: int, build: String, player_name: String, slot_id: int, token: String = "") -> void:
	if slot_id >= _next_slot_id:
		_next_slot_id = slot_id + 1
	var issued: String = token if token != "" else _new_rejoin_token()
	_tokens[peer_id] = issued
	# Bontago-1pi.49: the host owns the roster, so it validates the name a peer
	# claims (control characters, trim, max length, "Player N" if empty) before
	# anyone else sees it. Everything below uses the checked name.
	var typed_name: String = PlayerNames.clean(player_name, config.max_player_name_length)
	var name_auto: bool = typed_name == ""
	var checked_name: String = PlayerNames.fallback_for_slot(slot_id) if name_auto else typed_name
	# Bontago-1pi.53 review F1: name_auto is true when the joiner sent no usable name and
	# the name is the host's own "Player N" for the seat (see _set_peer_slot).
	_peers[peer_id] = LobbySeats.entry_to_wire(peer_id, slot_id, checked_name, false, 0.0, build, true, name_auto)
	_ping_samples[peer_id] = []
	_pending_handshake.erase(peer_id)
	_rpc_join_accepted.rpc_id(peer_id, slot_id, HOST_PEER_ID, issued)
	_broadcast_roster()
	Events.net_peer_joined.emit(peer_id, slot_id, checked_name)


## Unguessable, so a token is worth exactly one slot.
func _new_rejoin_token() -> String:
	return Crypto.new().generate_random_bytes(REJOIN_TOKEN_BYTES).hex_encode()


func _reject_peer(peer_id: int, error: int) -> void:
	_pending_handshake.erase(peer_id)
	# Bontago-1pi.59 review: a refused peer lingers for the grace frames below;
	# mark it so NetFanout broadcasts skip it like a kicked peer.
	_disconnecting_peers[peer_id] = true
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
	# still open (the same check _apply_peer_timeout() makes).
	if multiplayer.multiplayer_peer and multiplayer.get_peers().has(peer_id):
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


## Bontago-mv0.1.10: whether an RPC broadcast can actually reach the wire
## right now. _on_peer_disconnected can call _broadcast_roster() while the
## transport is mid-teardown — the multiplayer_peer already closed/nulled
## (leave()/host shutdown racing a late disconnect signal), or still open but
## down to zero connected remote peers (the last client just left). Either
## way there is nothing to send to, and forcing the RPC anyway either raises
## "Trying to call an RPC while no multiplayer peer is active" (peer null) or
## logs ENet's own "Unable to send packet on channel 0, max channels: 0" for
## a remote peer whose ENetPeer object already reports itself disconnected
## before Godot's own peer_disconnected signal/roster bookkeeping catches up.
func _can_send() -> bool:
	return not _broadcast_targets().is_empty()


## True while kick_peer() has asked the transport to disconnect `peer_id` and it
## has not dropped out of get_peers() yet. A send to it logs an engine error, so
## per-peer senders outside this file (net/MatchNet.gd) skip it.
func is_peer_disconnecting(peer_id: int) -> bool:
	return _disconnecting_peers.has(peer_id) or not _transport_peer_sendable(peer_id)


## Bontago-1pi.103: ENet marks a remote peer ZOMBIE/DISCONNECTING as soon as its
## disconnect command arrives, but get_peers() keeps listing it until its own
## queued DISCONNECT event is dispatched (several clients leaving at host
## shutdown, or one peer's event running a roster broadcast first). Sending then
## logs "Unable to send packet on channel 0, max channels: 0". Non-ENet
## transports have no such view and are always treated as sendable.
func _transport_peer_sendable(peer_id: int) -> bool:
	var enet: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return true
	var link: ENetPacketPeer = enet.get_peer(peer_id)
	if link == null:
		return false
	return link.get_state() == ENetPacketPeer.STATE_CONNECTED


## Host only: the connected peers a broadcast may address -- every entry of
## multiplayer.get_peers() except one kick_peer() is disconnecting (see
## _disconnecting_peers). Empty while the transport is down, not connected, or
## has no remote peer left. Fan-out sites send with rpc_id() to each of these
## rather than a plain rpc(), which would also address the disconnecting peer.
func _broadcast_targets() -> Array[int]:
	var targets: Array[int] = []
	if not is_host():
		return targets
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return targets
	for peer_id: int in multiplayer.get_peers():
		if not _disconnecting_peers.has(peer_id) and _transport_peer_sendable(peer_id):
			targets.append(peer_id)
	return targets


func _broadcast_roster() -> void:
	if not is_host():
		return
	var roster: Array[Dictionary] = []
	for peer_id: int in _peers.keys():
		roster.append((_peers[peer_id] as Dictionary).duplicate())
	# Bontago-mv0.6: the host's own copy of the roster (ready flags, joins,
	# leaves, kicks — every caller of _broadcast_roster()) changed right here;
	# tell ui/Lobby.gd directly rather than waiting on a lobby-data republish.
	Events.net_roster_changed.emit(roster)
	for peer_id: int in _broadcast_targets():
		_rpc_roster_update.rpc_id(peer_id, roster)
	if _lan.is_advertising():
		_lan.update_advert({"players": _peers.size()})


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
	_peers = updated
	var mine: int = local_peer_id()
	if _peers.has(mine):
		_local_slot = int(_peers[mine].get(LobbySeats.FIELD_SLOT_ID, -1))
	# Bontago-mv0.6: the client-side mirror of the emit above, so a client's
	# own ui/Lobby.gd updates the moment this RPC lands instead of on the
	# next unrelated net_lobby_data_changed republish.
	Events.net_roster_changed.emit(typed_roster)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_accepted(slot_id: int, _host_peer_id: int, rejoin_token: String = "") -> void:
	if is_host():
		return
	if rejoin_token.length() <= REJOIN_TOKEN_MAX_CHARS:
		_rejoin_token = rejoin_token
		_rejoin_scope = _current_join_scope()
	_local_slot = slot_id
	_joined_accepted = true
	# Same check the host ran on the name it was sent, so this event carries the
	# very string the roster will show (Bontago-1pi.49).
	Events.net_peer_joined.emit(
		local_peer_id(), slot_id, PlayerNames.sanitize(_pending_join_name, config.max_player_name_length, slot_id)
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

## Host only. Whether _rpc_handshake may still seat a new peer. Spec 3.4 makes
## joining lobby-only in M3a ("Mid-match joins can be enabled in settings" is a
## future setting; docs/M3a_PLAN.md "Known limitations": "the host refuses new
## connections once the match starts"). A peer that handshakes while this is
## false is refused with JoinError.MATCH_IN_PROGRESS and disconnected, gets no
## slot, and the existing roster is not touched or re-broadcast.
##
## host_game() and leave() reset it to true, so a fresh session always accepts.
##
## Bontago-8or.11: mid-match, game/Main.gd keeps it true while the running
## MatchConfig.allow_mid_match_join is on; set_match_in_progress() then routes
## the handshake through _handshake_mid_match() (open seat, spectator, or a
## rejoin token's reserved slot -- the last ignores this flag).
##
## DECISION (autoload/Net.gd, Bontago-mv0.1.8): a flag the match flow flips,
## not a subscription to Events.match_state_changed. That signal carries
## Match.State ints, and deciding which value is "lobby" would make this file
## name a gameplay concept (docs/M3a_PLAN.md P1: "Must NOT name a gameplay
## concept — no Match"). Match already depends on Net (Net.is_host()), so the
## dependency keeps its existing direction. Wire it where the state machine
## moves: `Net.set_accepting_joins(to_state == Match.State.LOBBY)` in
## game/Main.gd's _on_match_state_changed() (or Match._set_state()).
##
## The transport stays open on purpose. docs/M3a_PLAN.md suggests
## set_refuse_new_connections(true) once the match starts, but that fails the
## late joiner's connection at the ENet layer, which surfaces as
## JoinError.TRANSPORT or TIMEOUT — not a message the lobby can explain.
## Accepting the connection and refusing in the handshake costs one reliable
## RPC and the same two-frame disconnect every other refusal already pays.
func set_accepting_joins(accepting: bool) -> void:
	_accepting_joins = accepting


func accepting_joins() -> bool:
	return _accepting_joins


## Host only (Bontago-8or.11). game/Main.gd calls this with true when a match
## world is (re)built (LOBBY -> LOADING) and with false on a real return to
## the lobby. Every call drops the rejoin reservations, so a slot reserved in
## one match can never be reclaimed in the next. Going back to the lobby also
## gives each spectator a real lobby slot again, so the next Start counts it
## as a player, and clears every ready flag (Bontago-1pi.89).
##
## Like set_accepting_joins(), a flag the match flow flips rather than a
## subscription to a gameplay signal: this file must not name Match.
func set_match_in_progress(active: bool) -> void:
	_reservations.clear()
	var was_active: bool = _match_in_progress
	_match_in_progress = active
	if active or not was_active or not is_host():
		return
	var reseated: bool = false
	for peer_id: int in peer_ids():
		if int(_peers[peer_id].get(LobbySeats.FIELD_SLOT_ID, -1)) < 0:
			_set_peer_slot(peer_id, _take_next_lobby_slot())
			reseated = true
	# Bontago-1pi.53: a player who left for good during the match left a hole too
	# (nothing compacts mid-match); close it now the lobby is back, so Start is not
	# blocked on a seat nobody can fill.
	var compacted: bool = _compact_lobby_slots() > 0
	# Bontago-1pi.89: back in the lobby nobody is ready (every lobby view reads this flag).
	var cleared: bool = _clear_ready_flags()
	if reseated or compacted or cleared:
		_broadcast_roster()


func match_in_progress() -> bool:
	return _match_in_progress


## Host only (Bontago-8or.11): installs the gameplay side of mid-match
## admission (see _pick_open_seat / _can_reclaim_seat). Either Callable may be
## invalid: then every late joiner spectates and no slot can be reclaimed.
func set_seat_policy(pick_open_seat: Callable, can_reclaim_seat: Callable) -> void:
	_pick_open_seat = pick_open_seat
	_can_reclaim_seat = can_reclaim_seat


## Client only: the rejoin token the host issued on the last accepted join
## ("" before any). Test and debug read-out; nothing gameplay reads it.
func rejoin_token() -> String:
	return _rejoin_token


func _reset_rejoin_state() -> void:
	_match_in_progress = false
	_tokens.clear()
	_reservations.clear()
	# Per-session host state that must not outlive its peers (called wherever a
	# session starts or ends: host_game, the Steam lobby host, leave).
	_seat_pref_buckets.clear()
	_disconnecting_peers.clear()


# --- Ready state --------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not is_host():
		return
	set_peer_ready(multiplayer.get_remote_sender_id(), ready)


# --- Loading-screen ready gate (Bontago-1pi.32) -------------------------------
#
# Owner playtest 2026-10-03: every human player presses ready (ui_accept: Enter,
# Space or the gamepad's A) on the loading screen and the host starts the
# countdown once all of them have (core/LoadingReadyGate.gd holds the rule,
# autoload/match/MatchLifecycle.gd the per-match state). Net is only the
# transport: it never names Match, so the host-side handoff and the mirror both
# go over the Events bus (net_loading_ready_received / loading_ready_changed /
# loading_gate_opened), the way net_peer_joined already does.

## Local player pressed ready. Client: sends the intent to the host (which takes
## the peer id from the transport, never from the payload, so there is nothing
## to spoof). Host and offline: hands it to the lifecycle directly under the
## local peer id (offline that is Net.HOST_PEER_ID, which stands for every
## local human -- one press on the shared device readies all of them).
func request_loading_ready() -> void:
	if is_client():
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		_rpc_loading_ready.rpc_id(HOST_PEER_ID)
		return
	Events.net_loading_ready_received.emit(local_peer_id())


@rpc("any_peer", "call_remote", "reliable")
func _rpc_loading_ready() -> void:
	_handle_loading_ready(multiplayer.get_remote_sender_id())


## Host only. A ready intent from `sender` (the transport's peer id): refused
## unless it is a seated peer -- an unknown id, a peer still in the handshake and
## a spectator (slot -1) never reach the lifecycle. Phase, the required set and
## idempotence are the lifecycle's checks. Returns whether it was forwarded.
func _handle_loading_ready(sender: int) -> bool:
	if _mode != Mode.HOST or not _peers.has(sender) or slot_of_peer(sender) < 0:
		return false
	Events.net_loading_ready_received.emit(sender)
	return true


## Host: mirrors the lifecycle's ready sets to every client.
func _on_loading_ready_changed(ready_ids: PackedInt32Array, required_ids: PackedInt32Array) -> void:
	if _mode != Mode.HOST:
		return
	for peer_id: int in _broadcast_targets():
		_rpc_loading_ready_state.rpc_id(peer_id, ready_ids, required_ids)


## Host: tells every client the gate opened.
func _on_loading_gate_opened() -> void:
	if _mode != Mode.HOST:
		return
	for peer_id: int in _broadcast_targets():
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


# --- Lobby seat preferences (Bontago-1pi.53) ---------------------------------
#
# docs/LOBBY_REWORK_PLAN.md section 3: the host owns every seat's picks; a client
# may change only its OWN colour and team, and does so by sending this intent. Net
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
		if not _seat_pref_in_range(color_index, team_pick):
			return
		var peer: MultiplayerPeer = multiplayer.multiplayer_peer
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		_rpc_request_seat_pref.rpc_id(HOST_PEER_ID, color_index, team_pick)
		return
	_handle_seat_pref(local_peer_id(), color_index, team_pick, false)


## `Variant` parameters on purpose: this is an any_peer RPC, so the arguments are
## whatever the sender put on the wire, and a typed signature would let the engine
## coerce (a float becomes an int, a bool a 0/1) before the host could refuse it.
## The sender is get_remote_sender_id(); the payload names no peer, so there is
## nothing to spoof.
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_seat_pref(color_index: Variant, team_pick: Variant) -> void:
	_handle_seat_pref(multiplayer.get_remote_sender_id(), color_index, team_pick, true)


## Host only. A seat-preference intent from `sender` (the transport's peer id, or
## local_peer_id() for `remote` = false). Refused, in this order: not the host; a
## remote sender that is not a seated peer (an unknown id, a peer still in the
## handshake, a spectator at slot -1, a peer that already left); a match in
## progress; the sender's flood bucket is empty (every request from a seated peer
## drains it, valid or not); a non-int, out-of-range or no-op payload (nothing is
## clamped). Returns whether the event was emitted. `now` (seconds) is the clock
## for the bucket, a seam for tests; < 0 reads _now().
func _handle_seat_pref(sender: int, color_index: Variant, team_pick: Variant, remote: bool = true, now: float = -1.0) -> bool:
	if _mode == Mode.CLIENT:
		return false
	if remote and (_mode != Mode.HOST or not _peers.has(sender) or slot_of_peer(sender) < 0):
		return false
	if _match_in_progress:
		return false
	if remote and not _seat_pref_take_token(sender, now if now >= 0.0 else _now()):
		return false
	if typeof(color_index) != TYPE_INT or typeof(team_pick) != TYPE_INT:
		return false
	if not _seat_pref_in_range(int(color_index), int(team_pick)):
		return false
	Events.net_seat_pref_requested.emit(sender, int(color_index), int(team_pick))
	return true


## Wire sanity, not lobby rules: each field is UNCHANGED or inside the largest range
## it can ever take, and at least one field asks for something. The lobby applies
## the exact team cap (LobbySeats.apply_human_pref).
func _seat_pref_in_range(color_index: int, team_pick: int) -> bool:
	if color_index == LobbySeats.UNCHANGED and team_pick == LobbySeats.UNCHANGED:
		return false
	if color_index != LobbySeats.UNCHANGED and (color_index < 0 or color_index >= LobbySeats.palette_size()):
		return false
	if team_pick != LobbySeats.UNCHANGED and (team_pick < MatchConfig.TEAM_PICK_RANDOM or team_pick > MatchConfig.TEAM_PICK_MAX):
		return false
	return true


## Spends one token of `peer_id`'s bucket (a new peer starts full). False = empty.
func _seat_pref_take_token(peer_id: int, now: float) -> bool:
	var burst: float = float(config.seat_pref_burst)
	var tokens: float = burst
	if _seat_pref_buckets.has(peer_id):
		var bucket: Dictionary = _seat_pref_buckets[peer_id]
		var elapsed: float = maxf(now - float(bucket["at"]), 0.0)
		tokens = minf(burst, float(bucket["tokens"]) + elapsed * config.seat_pref_refill_per_s)
	var allowed: bool = tokens >= 1.0
	if allowed:
		tokens -= 1.0
	_seat_pref_buckets[peer_id] = {"tokens": tokens, "at": now}
	return allowed


# --- Lobby data RPC ----------------------------------------------------------

@rpc("authority", "call_remote", "reliable")
func _rpc_lobby_data(data: Dictionary) -> void:
	if is_host():
		return
	_lobby_data = data
	Events.net_lobby_data_changed.emit(_lobby_data)


# --- Ping ---------------------------------------------------------------

func _tick_ping(delta: float) -> void:
	_ping_accum += delta
	var interval: float = 1.0 / maxf(config.ping_hz, 0.001)
	if _ping_accum < interval:
		return
	_ping_accum = fmod(_ping_accum, interval)
	var now_ms: int = Time.get_ticks_msec()
	# Bontago-mv0.1.10 review: same teardown hazard as _broadcast_roster().
	if not _can_send():
		return
	for peer_id: int in _broadcast_targets():
		if peer_id != HOST_PEER_ID and _peers.has(peer_id):
			_rpc_ping.rpc_id(peer_id, now_ms)


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
	if not _peers.has(sender):
		return
	var rtt: float = float(Time.get_ticks_msec() - sent_at_ms)
	_record_ping_sample(sender, rtt)
	if is_peer_disconnecting(sender):
		return
	_rpc_report_ping.rpc_id(sender, float(_peers[sender][LobbySeats.FIELD_PING_MS]))


@rpc("authority", "call_remote", "unreliable")
func _rpc_report_ping(value: float) -> void:
	if is_host():
		return
	_own_ping_ms = value


func _record_ping_sample(peer_id: int, rtt: float) -> void:
	var samples: Array = _ping_samples.get(peer_id, [])
	samples.append(rtt)
	while samples.size() > config.ping_history:
		samples.pop_front()
	_ping_samples[peer_id] = samples
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	_peers[peer_id][LobbySeats.FIELD_PING_MS] = total / samples.size()


# --- Internal helpers --------------------------------------------------

func _tick_handshake_timeouts(now: float) -> void:
	if _pending_handshake.is_empty():
		return
	var expired: Array[int] = []
	for peer_id: int in _pending_handshake.keys():
		if now > float(_pending_handshake[peer_id]):
			expired.append(peer_id)
	for peer_id: int in expired:
		_reject_peer(peer_id, JoinError.TIMEOUT)


## Configures ENet's own dead-peer detection (NetConfig's peer_timeout_limit/
## min/max triple). Reached through the generic MultiplayerPeer/duck-typed call so
## ENetMultiplayerPeer/ENetPacketPeer are never named outside
## _make_host_peer()/_make_client_peer(), per this file's transport-isolation
## rule.
func _apply_peer_timeout(id: int) -> void:
	if _peer == null or not _peer.has_method("get_peer"):
		return
	# MultiplayerAPI relays every peer's connect/disconnect to every other
	# peer (so a client can see a sibling client's id), but only the host
	# holds a *direct* ENet connection to each remote id — a client's own
	# ENetMultiplayerPeer only ever has one, to the host. Calling get_peer()
	# for any other id logs an engine error, so only ever call it for a
	# connection this instance actually made itself.
	if not (is_host() or id == HOST_PEER_ID):
		return
	if not multiplayer.get_peers().has(id):
		return
	var packet_peer: Object = _peer.call("get_peer", id)
	if packet_peer and packet_peer.has_method("set_timeout"):
		packet_peer.call("set_timeout", config.peer_timeout_limit, config.peer_timeout_min_ms, config.peer_timeout_max_ms)


func _start_lan_advertising(player_name: String) -> void:
	var info: Dictionary = {
		"game": String(DISCOVERY_MAGIC),
		"version": build_version(),
		"name": player_name,
		"players": _peers.size(),
		"max": config.max_peers,
		"map": "",
		"port": _host_port,
	}
	_lan.start_advertising(info)


func _on_lan_advert_changed(_info: Dictionary) -> void:
	Events.net_games_discovered.emit(_lan.games())


func _on_lan_advert_expired(_address: String, _port: int) -> void:
	Events.net_games_discovered.emit(_lan.games())


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
