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

@warning_ignore_start("unused_parameter")


# --- Session lifecycle ------------------------------------------------------

## Starts a listen server on `port` (0 means config.game_port) and begins LAN
## advertising. The host takes slot 0. Returns OK or a transport error.
func host_game(port: int = 0, player_name: String = "") -> Error:
	return OK


## Connects to `address`:`port`. Emits Events.net_join_failed and returns to
## OFFLINE if the handshake is refused or times out.
func join_game(address: String, port: int = 0, player_name: String = "") -> Error:
	return OK


## Leaves whatever session is running and returns to OFFLINE. Safe to call
## when already offline. The host disconnects everyone with
## LeaveReason.HOST_SHUTDOWN first.
func leave() -> void:
	pass


func mode() -> Mode:
	return Mode.OFFLINE


## True on the host **and offline**. This is the single predicate that gates
## host-only work (Match's solve and feed, Field's kill plane, SnapshotSync's
## sender). Never branch on multiplayer.is_server() directly: with no peer set
## its answer depends on engine internals, and it says nothing about M3b.
func is_host() -> bool:
	return true


func is_client() -> bool:
	return false


func is_offline() -> bool:
	return true


## This instance's multiplayer peer id, or HOST_PEER_ID when offline.
func local_peer_id() -> int:
	return HOST_PEER_ID


## The game build version both ends compare during the handshake. Reads
## ProjectSettings' application/config/version, so bumping the version there is
## all it takes to refuse older builds (spec 3.4 "Version check").
func build_version() -> String:
	return ""


# --- Peer <-> slot registry -------------------------------------------------

## Every connected peer id including the host, in slot order.
func peer_ids() -> PackedInt32Array:
	return PackedInt32Array()


## {"peer_id": int, "slot_id": int, "name": String, "ready": bool,
## "ping_ms": float, "build": String}. Empty for an unknown peer.
func peer_info(peer_id: int) -> Dictionary:
	return {}


## Which PlayerSlot a peer holds, or -1. The host assigns these and broadcasts
## the roster; a client never invents one.
func slot_of_peer(peer_id: int) -> int:
	return -1


## Inverse of slot_of_peer(). -1 for an unclaimed slot (an empty seat, or a
## bot's from M5).
func peer_of_slot(slot_id: int) -> int:
	return -1


## The slot this instance's local player controls. Offline this is
## Match.active_slot()'s business instead, so it returns 0.
func local_slot() -> int:
	return 0


## True when `slot_id` is driven by this instance's own input. The one check
## PlayerController and the HUD use to decide "is this me?"; it is also true
## for **every** slot in offline hot-seat, which is what keeps M2's strict
## alternation working unchanged.
func is_local_slot(slot_id: int) -> bool:
	return true


## Host only: marks a peer ready in the lobby, or drops it from the session.
func set_peer_ready(peer_id: int, ready: bool) -> void:
	pass


func kick_peer(peer_id: int, reason: LeaveReason = LeaveReason.KICKED) -> void:
	pass


## Client: tells the host this instance is ready to start.
func set_local_ready(ready: bool) -> void:
	pass


func all_peers_ready() -> bool:
	return false


## Measured round trip to `peer_id` in milliseconds, from Net's own ping RPC
## rather than any ENet statistic, so the number is identical over Steam.
func ping_ms(peer_id: int = 0) -> float:
	return 0.0


# --- Lobby data (spec 3.4: "Steam lobbies store match settings as lobby
# data"; over ENet the host broadcasts the same Dictionary reliably) ---------

## Host only: publishes the lobby settings. ui/Lobby.gd passes
## MatchConfig.to_dict(); M3b writes the same Dictionary into Steam lobby data
## with no change on this side of the call.
func set_lobby_data(data: Dictionary) -> void:
	pass


## The last lobby data received, or what this host published. Clients read it
## to build their read-only view of the settings.
func lobby_data() -> Dictionary:
	return {}


# --- LAN discovery (spec 3.4) -----------------------------------------------

## Starts listening on config.discovery_port for hosts advertising themselves.
## Results arrive as Events.net_games_discovered.
func start_discovery() -> void:
	pass


func stop_discovery() -> void:
	pass


## Games seen within config.discovery_entry_ttl, newest advert first. Each is
## {"name", "address", "port", "version", "players", "max", "map"}.
func discovered_games() -> Array[Dictionary]:
	return []


# --- Lag / loss simulation --------------------------------------------------

## Turns the simulator on or off for this instance (see core/net/NetSim.gd).
## `lag_ms` is one-way. Affects outbound intents and cursors here; SnapshotSync
## applies the same settings to inbound snapshots.
func set_simulation(lag_ms: float, jitter_ms: float, loss: float) -> void:
	pass


## The live simulator, so SnapshotSync and the debug overlay share one set of
## settings and one set of counters.
func simulation() -> NetSim:
	return null


func simulation_enabled() -> bool:
	return false


# --- Debug stats (spec Part 4 M3's overlay) ---------------------------------

## {"mode": int, "peers": int, "ping_ms": float, "snapshot_bps": float,
## "snapshot_last_bytes": int, "interp_delay_ms": float, "loss_pct": float,
## "sim_lag_ms": float, "sim_loss": float}. Refreshed at config.stats_hz and
## mirrored on Events.net_stats_updated; ui/NetDebugOverlay.gd only reads it.
func stats() -> Dictionary:
	return {}


## Lets SnapshotSync fold its own counters into stats() without the overlay
## needing to know either of them.
func report_stats(source: StringName, values: Dictionary) -> void:
	pass


# --- Command line (spec 3.4 "Testing") --------------------------------------

## Parses --host, --join=<ip[:port]>, --port=<n>, --headless-host,
## --player-name=<s>, --sim-lag=<ms>, --sim-loss=<fraction> from OS
## command-line arguments after "--" and acts on them. Called once by
## game/Main.gd so a headless instance needs no UI. Returns true when an
## argument put this instance into a session.
func apply_command_line() -> bool:
	return false


@warning_ignore_restore("unused_parameter")
