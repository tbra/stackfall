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

@export var config: NetConfig = preload("res://config/net_config.tres")

var _mode: Mode = Mode.OFFLINE
## The peer this instance created, generic MultiplayerPeer only — never typed
## or cast to ENetMultiplayerPeer outside _make_host_peer()/_make_client_peer().
var _peer: MultiplayerPeer = null

## peer_id -> {"peer_id", "slot_id", "name", "ready", "ping_ms", "build"}. On
## the host this is the source of truth; on a client it is a mirror kept in
## sync by _rpc_roster_update.
var _peers: Dictionary = {}
## peer_id -> RTT samples (ms), host only, averaged into _peers[id].ping_ms.
var _ping_samples: Dictionary = {}
## Host only: peer_id -> deadline (seconds, _now()) by which the peer must
## have sent its handshake, or it is dropped.
var _pending_handshake: Dictionary = {}
var _next_slot_id: int = 1

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

var _sim: NetSim = NetSim.new()
## Cross-package stats reported via report_stats(), folded into stats().
var _report: Dictionary = {}

var _ping_accum: float = 0.0
var _stats_accum: float = 0.0


func _ready() -> void:
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


func _process(delta: float) -> void:
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

## Starts a listen server on `port` (0 means config.game_port) and begins LAN
## advertising. The host takes slot 0. Returns OK or a transport error.
func host_game(port: int = 0, player_name: String = "") -> Error:
	if _mode != Mode.OFFLINE:
		leave()
	var use_port: int = port if port > 0 else config.game_port
	var peer: MultiplayerPeer = _make_host_peer(use_port)
	if peer == null:
		return ERR_CANT_CREATE

	multiplayer.multiplayer_peer = peer
	_peer = peer
	_mode = Mode.HOST
	_host_port = use_port
	_host_build_version = build_version()
	_peers.clear()
	_peers[HOST_PEER_ID] = {
		"peer_id": HOST_PEER_ID,
		"slot_id": 0,
		"name": player_name,
		"ready": true,
		"ping_ms": 0.0,
		"build": _host_build_version,
	}
	_next_slot_id = 1
	Events.net_mode_changed.emit(_mode)
	_start_lan_advertising(player_name)
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
	_pending_join_name = player_name
	_joined_accepted = false
	_join_deadline = _now() + config.connect_timeout + config.handshake_timeout
	Events.net_mode_changed.emit(_mode)
	return OK


## Leaves whatever session is running and returns to OFFLINE. Safe to call
## when already offline. The host disconnects everyone with
## LeaveReason.HOST_SHUTDOWN first.
func leave() -> void:
	if _mode == Mode.OFFLINE:
		return
	if _mode == Mode.HOST:
		for peer_id: int in _peers.keys():
			if peer_id != HOST_PEER_ID:
				Events.net_peer_left.emit(peer_id, int(_peers[peer_id].get("slot_id", -1)), LeaveReason.HOST_SHUTDOWN)

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
	Events.net_mode_changed.emit(_mode)


func mode() -> Mode:
	return _mode


## True on the host **and offline**. This is the single predicate that gates
## host-only work (Match's solve and feed, Field's kill plane, SnapshotSync's
## sender). Never branch on multiplayer.is_server() directly: with no peer set
## its answer depends on engine internals, and it says nothing about M3b.
func is_host() -> bool:
	return _mode == Mode.HOST or _mode == Mode.OFFLINE


func is_client() -> bool:
	return _mode == Mode.CLIENT


func is_offline() -> bool:
	return _mode == Mode.OFFLINE


## This instance's multiplayer peer id, or HOST_PEER_ID when offline.
func local_peer_id() -> int:
	if _mode == Mode.OFFLINE:
		return HOST_PEER_ID
	return multiplayer.get_unique_id()


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
		return int(_peers[a].get("slot_id", -1)) < int(_peers[b].get("slot_id", -1))
	)
	var result: PackedInt32Array = PackedInt32Array()
	for id: int in ids:
		result.append(id)
	return result


## {"peer_id": int, "slot_id": int, "name": String, "ready": bool,
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
	return int(_peers[peer_id].get("slot_id", -1))


## Inverse of slot_of_peer(). -1 for an unclaimed slot (an empty seat, or a
## bot's from M5).
func peer_of_slot(slot_id: int) -> int:
	for peer_id: int in _peers.keys():
		if int(_peers[peer_id].get("slot_id", -1)) == slot_id:
			return peer_id
	return -1


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
	return slot_id == local_slot()


## Host only: marks a peer ready in the lobby, or drops it from the session.
func set_peer_ready(peer_id: int, ready: bool) -> void:
	if not is_host() or not _peers.has(peer_id):
		return
	_peers[peer_id]["ready"] = ready
	_broadcast_roster()


func kick_peer(peer_id: int, reason: LeaveReason = LeaveReason.KICKED) -> void:
	if not is_host() or not _peers.has(peer_id):
		return
	var slot_id: int = int(_peers[peer_id].get("slot_id", -1))
	_peers.erase(peer_id)
	_ping_samples.erase(peer_id)
	_pending_handshake.erase(peer_id)
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)
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
		if not bool(_peers[peer_id].get("ready", false)):
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
	return float(_peers[target].get("ping_ms", 0.0))


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
	_rpc_lobby_data.rpc(_lobby_data)
	if _lan.is_advertising():
		_lan.update_advert({"map": str(_lobby_data.get("map_variant", 0))})


## The last lobby data received, or what this host published. Clients read it
## to build their read-only view of the settings.
func lobby_data() -> Dictionary:
	return _lobby_data


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
## `lag_ms` is one-way. Affects outbound intents and cursors here; SnapshotSync
## applies the same settings to inbound snapshots.
func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	_sim.configure(lag_ms, jitter_ms, loss)


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
## --player-name=<s>, --sim-lag=<ms>, --sim-loss=<fraction> from OS
## command-line arguments after "--" and acts on them. Called once by
## game/Main.gd so a headless instance needs no UI. Returns true when an
## argument put this instance into a session.
func apply_command_line() -> bool:
	return _apply_command_line_args(OS.get_cmdline_user_args())


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

	var port: int = int(options.get("port", 0))
	var player_name: String = String(options.get("player-name", ""))

	if flags.has("host") or flags.has("headless-host"):
		host_game(port, player_name if player_name != "" else "Host")
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


# --- Transport (the only place ENetMultiplayerPeer may be named) -----------

func _make_host_peer(port: int) -> MultiplayerPeer:
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
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


# --- MultiplayerAPI signal handlers -----------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_handshake[id] = _now() + config.handshake_timeout
	# Deferred: ENetMultiplayerPeer's own per-peer table can lag one idle
	# frame behind the peer_connected signal, and get_peer() logs an engine
	# error for an id it doesn't have yet.
	call_deferred("_apply_peer_timeout", id)


func _on_peer_disconnected(id: int) -> void:
	_pending_handshake.erase(id)
	if _mode != Mode.HOST:
		return
	if not _peers.has(id):
		return
	var slot_id: int = int(_peers[id].get("slot_id", -1))
	_peers.erase(id)
	_ping_samples.erase(id)
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
	_rpc_handshake.rpc_id(HOST_PEER_ID, build_version(), _pending_join_name)


func _on_connection_failed() -> void:
	if _mode != Mode.CLIENT:
		return
	_fail_join(JoinError.TRANSPORT, "connection failed")


func _on_server_disconnected() -> void:
	if _mode != Mode.CLIENT:
		return
	Events.net_peer_left.emit(HOST_PEER_ID, slot_of_peer(HOST_PEER_ID), LeaveReason.HOST_SHUTDOWN)
	leave()


# --- Handshake & roster RPCs -------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_handshake(build: String, player_name: String) -> void:
	if not is_host():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	if _peers.has(sender):
		return
	if build != _host_build_version:
		_reject_peer(sender, JoinError.VERSION_MISMATCH)
		return
	if _peers.size() >= config.max_peers:
		_reject_peer(sender, JoinError.SERVER_FULL)
		return
	_accept_peer(sender, build, player_name)


func _accept_peer(peer_id: int, build: String, player_name: String) -> void:
	var slot_id: int = _next_slot_id
	_next_slot_id += 1
	_peers[peer_id] = {
		"peer_id": peer_id,
		"slot_id": slot_id,
		"name": player_name,
		"ready": false,
		"ping_ms": 0.0,
		"build": build,
	}
	_ping_samples[peer_id] = []
	_pending_handshake.erase(peer_id)
	Events.net_peer_joined.emit(peer_id, slot_id, player_name)
	_rpc_join_accepted.rpc_id(peer_id, slot_id, HOST_PEER_ID)
	_broadcast_roster()


func _reject_peer(peer_id: int, error: int) -> void:
	_pending_handshake.erase(peer_id)
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
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.disconnect_peer(peer_id)


func _broadcast_roster() -> void:
	if not is_host():
		return
	var roster: Array[Dictionary] = []
	for peer_id: int in _peers.keys():
		roster.append((_peers[peer_id] as Dictionary).duplicate())
	_rpc_roster_update.rpc(roster)
	if _lan.is_advertising():
		_lan.update_advert({"players": _peers.size()})


@rpc("authority", "call_remote", "reliable")
func _rpc_roster_update(roster: Array) -> void:
	if is_host():
		return
	var updated: Dictionary = {}
	for entry: Variant in roster:
		var data: Dictionary = entry as Dictionary
		updated[int(data.get("peer_id", -1))] = data
	_peers = updated
	var mine: int = local_peer_id()
	if _peers.has(mine):
		_local_slot = int(_peers[mine].get("slot_id", -1))


@rpc("authority", "call_remote", "reliable")
func _rpc_join_accepted(slot_id: int, _host_peer_id: int) -> void:
	if is_host():
		return
	_local_slot = slot_id
	_joined_accepted = true
	Events.net_peer_joined.emit(local_peer_id(), slot_id, _pending_join_name)


@rpc("authority", "call_remote", "reliable")
func _rpc_join_refused(error: int) -> void:
	if is_host():
		return
	_fail_join(error)


func _fail_join(error: int, detail: String = "") -> void:
	leave()
	Events.net_join_failed.emit(error, detail)


# --- Ready state --------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_ready(ready: bool) -> void:
	if not is_host():
		return
	set_peer_ready(multiplayer.get_remote_sender_id(), ready)


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
	for peer_id: int in _peers.keys():
		if peer_id != HOST_PEER_ID:
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
	_rpc_report_ping.rpc_id(sender, float(_peers[sender]["ping_ms"]))


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
	_peers[peer_id]["ping_ms"] = total / samples.size()


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
