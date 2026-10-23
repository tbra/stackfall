class_name NetTransport
extends RefCounted
## The transport boundary of the Net autoload: it builds the ENet and Steam
## peers, tunes ENet's dead-peer detection, answers "is the link up" and "which
## peers may a send address", and remembers the peers a kick (or a refusal) is
## still disconnecting. It is the only file besides net/SteamClient.gd that names
## ENetMultiplayerPeer / ENetPacketPeer or instantiates a SteamMultiplayerPeer
## (through ClassDB, never a static type: the GodotSteam addon is absent on most
## checkouts).
##
## Why the disconnecting set exists: ENet keeps a peer in get_peers() until its
## disconnect completes a poll or more later, and every packet addressed to it in
## that window logs an engine error ("Unable to send packet on channel 0, max
## channels: 0"). Net marks a kicked or refused peer here, and every host fan-out
## asks broadcast_targets() / can_broadcast() instead of reading get_peers().
##
## It holds no MultiplayerAPI: every query takes the caller's `api`, because a
## unit test (and split-screen) runs several Net instances on separate APIs.
## net/NetFanout.gd gives the same answers for nodes that only know the Net
## autoload through `is_peer_disconnecting()`; test_net_transport.gd pins the two
## to the same targets.

## ENet bind address of a public host (every interface) and of a private one
## (this machine only; a bot or sandbox host nothing outside can reach).
const BIND_ALL_INTERFACES: String = "*"
const BIND_LOOPBACK: String = "127.0.0.1"
## SteamMultiplayerPeer virtual port: this project runs exactly one Steam session
## per lobby, so the single default virtual port is all it ever needs.
const STEAM_VIRTUAL_PORT: int = 0
## Class name resolved through ClassDB when the addon is installed.
const STEAM_PEER_CLASS: StringName = &"SteamMultiplayerPeer"

## Tests only: a Callable returning a MultiplayerPeer that make_steam_host_peer()
## hands out instead of building a SteamMultiplayerPeer (which is never built for a
## FakeSteam provider, crash safety), so a FakeSteam test can reach the live Steam
## HOST state. Unset means the real path.
var steam_host_peer_factory: Callable = Callable()

## peer_id -> true: peers kick_peer() or a refusal has asked the transport to
## disconnect that get_peers() may still list.
var _disconnecting: Dictionary = {}


# --- Peer factories --------------------------------------------------------------

## An ENet server on `port` for up to `max_peers` connections. `private` binds
## loopback only. Null when ENet cannot create it.
func make_host_peer(port: int, max_peers: int, private: bool) -> MultiplayerPeer:
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	enet_peer.set_bind_ip(BIND_LOOPBACK if private else BIND_ALL_INTERFACES)
	# DECISION: ENet's own max_clients counts remote clients only, one fewer
	# than the lobby cap (which includes the host). Passed through unreduced on
	# purpose: this only widens ENet's own raw cap, giving a peer that arrives
	# exactly at the limit room to complete the ENet handshake and receive
	# _rpc_handshake's own SERVER_FULL refusal (with a reason the lobby can show)
	# instead of a bare transport-level connection_failed. The real cap is
	# enforced in _rpc_handshake.
	var err: Error = enet_peer.create_server(port, max_peers)
	if err != OK:
		push_warning("Net: create_server on port %d failed with error %d" % [port, err])
		return null
	return enet_peer


## An ENet client aimed at `address`:`port`. Null when ENet cannot create it.
func make_client_peer(address: String, port: int) -> MultiplayerPeer:
	var enet_peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = enet_peer.create_client(address, port)
	if err != OK:
		push_warning("Net: create_client to %s:%d failed with error %d" % [address, port, err])
		return null
	return enet_peer


## The Steam host peer, or null. SAFETY: calling SteamMultiplayerPeer.create_host()
## when the process's Steam context was never initialized (steamInitEx never
## called, or it failed) segfaults the engine (SIGSEGV inside steam_api64.dll).
## `steam_ready` is Net's own "Steam initialised" flag and `real_provider` is false
## for a FakeSteam, so ClassDB.instantiate(&"SteamMultiplayerPeer") is unreachable
## from any automated test. steam_host_peer_factory, when set, answers first.
func make_steam_host_peer(steam_ready: bool, real_provider: bool) -> MultiplayerPeer:
	if steam_host_peer_factory.is_valid():
		return steam_host_peer_factory.call() as MultiplayerPeer
	var peer: MultiplayerPeer = _new_steam_peer(steam_ready, real_provider)
	if peer == null:
		return null
	# Client traffic routes through the host (spec 2.6 "Model: Host-authoritative
	# listen server"), matching ENet's implicit star topology.
	var err: Variant = peer.call("create_host", STEAM_VIRTUAL_PORT)
	if int(err) != OK:
		push_warning("Net: SteamMultiplayerPeer create_host failed with error %d" % int(err))
		return null
	return peer


## The Steam client peer for the lobby owned by `host_steam_id`, or null (same
## safety gate as make_steam_host_peer()).
func make_steam_client_peer(host_steam_id: int, steam_ready: bool, real_provider: bool) -> MultiplayerPeer:
	var peer: MultiplayerPeer = _new_steam_peer(steam_ready, real_provider)
	if peer == null:
		return null
	var err: Variant = peer.call("create_client", host_steam_id, STEAM_VIRTUAL_PORT)
	if int(err) != OK:
		push_warning("Net: SteamMultiplayerPeer create_client failed with error %d" % int(err))
		return null
	return peer


func _new_steam_peer(steam_ready: bool, real_provider: bool) -> MultiplayerPeer:
	if not steam_ready or not real_provider:
		return null
	if not ClassDB.class_exists(STEAM_PEER_CLASS):
		return null
	var peer: MultiplayerPeer = ClassDB.instantiate(STEAM_PEER_CLASS) as MultiplayerPeer
	if peer == null:
		return null
	peer.set("server_relay", true)
	return peer


# --- Dead-peer detection ---------------------------------------------------------

## Applies NetConfig's peer_timeout_limit/min/max triple to the ENet link to
## `peer_id`. MultiplayerAPI relays every peer's connect/disconnect to every other
## peer, but only the host holds a direct ENet connection to each remote id (a
## client's own peer only ever has one, to the host), and ENet's per-peer table can
## lag one frame behind peer_connected. get_peer() on an id this instance does not
## hold logs an engine error, so this only touches a link `peer` really has. A
## non-ENet peer (Steam) is left alone.
func apply_peer_timeout(api: MultiplayerAPI, peer: MultiplayerPeer, peer_id: int, is_host: bool, config: NetConfig) -> void:
	var enet: ENetMultiplayerPeer = peer as ENetMultiplayerPeer
	if enet == null or api == null:
		return
	if not (is_host or peer_id == MultiplayerPeer.TARGET_PEER_SERVER):
		return
	if not api.get_peers().has(peer_id):
		return
	var link: ENetPacketPeer = enet.get_peer(peer_id)
	if link != null:
		link.set_timeout(config.peer_timeout_limit, config.peer_timeout_min_ms, config.peer_timeout_max_ms)


# --- Link state ------------------------------------------------------------------

## True while `api` holds a peer whose connection is established.
func is_link_up(api: MultiplayerAPI) -> bool:
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## True when `api` holds no peer or one that is fully disconnected (a peer still
## CONNECTING is not down: its id is not valid yet but it is a live attempt).
func is_link_down(api: MultiplayerAPI) -> bool:
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	return peer == null or peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED


## ENet marks a remote peer ZOMBIE/DISCONNECTING as soon as its disconnect command
## arrives, but get_peers() keeps listing it until its own queued DISCONNECT event
## is dispatched (several clients leaving at host shutdown, or one peer's event
## running a roster broadcast first). Sending then logs "Unable to send packet on
## channel 0, max channels: 0". Non-ENet transports have no such view and are
## always treated as sendable.
func is_peer_sendable(api: MultiplayerAPI, peer_id: int) -> bool:
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	var enet: ENetMultiplayerPeer = peer as ENetMultiplayerPeer
	if enet == null:
		return true
	# get_peer() on an id the transport does not hold logs an engine error.
	if not api.get_peers().has(peer_id):
		return false
	var link: ENetPacketPeer = enet.get_peer(peer_id)
	if link == null:
		return false
	return link.get_state() == ENetPacketPeer.STATE_CONNECTED


# --- Disconnecting peers ---------------------------------------------------------

## Remembers that `peer_id` is being disconnected, so no send addresses it again.
func mark_disconnecting(peer_id: int) -> void:
	_disconnecting[peer_id] = true


## Forgets the mark (the peer is gone from the transport).
func unmark_disconnecting(peer_id: int) -> void:
	_disconnecting.erase(peer_id)


## Forgets every mark (session start and end).
func clear_disconnecting() -> void:
	_disconnecting.clear()


## True when `peer_id` was marked by mark_disconnecting() and not yet unmarked.
func is_marked_disconnecting(peer_id: int) -> bool:
	return _disconnecting.has(peer_id)


## True while a send to `peer_id` would hit a closing link: marked, or already
## shown by ENet as not connected. This is the answer Net.is_peer_disconnecting()
## gives NetFanout.
func is_peer_disconnecting(api: MultiplayerAPI, peer_id: int) -> bool:
	return _disconnecting.has(peer_id) or not is_peer_sendable(api, peer_id)


# --- Send targets ----------------------------------------------------------------

## Host only: the connected peers a broadcast may address, every entry of
## api.get_peers() that is not disconnecting. Empty for a non-host, while the link
## is down or not connected, or when no remote peer is left. Fan-out sites send
## with rpc_id() to each of these rather than a plain rpc(), which would also
## address a disconnecting peer. Equal to NetFanout.targets() on a connected host.
func broadcast_targets(api: MultiplayerAPI, is_host: bool) -> Array[int]:
	var targets: Array[int] = []
	if not is_host or not is_link_up(api):
		return targets
	for peer_id: int in api.get_peers():
		if not is_peer_disconnecting(api, peer_id):
			targets.append(peer_id)
	return targets


## Whether a host broadcast can reach the wire right now. A late disconnect signal
## can run a roster broadcast while the transport is mid-teardown (peer closed or
## nulled, or open with zero connected remotes); forcing the RPC then raises "Trying
## to call an RPC while no multiplayer peer is active" or ENet's own "Unable to
## send packet" error.
func can_broadcast(api: MultiplayerAPI, is_host: bool) -> bool:
	return not broadcast_targets(api, is_host).is_empty()
