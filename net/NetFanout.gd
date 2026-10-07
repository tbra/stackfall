class_name NetFanout
extends RefCounted
## Bontago-1pi.59: the one way a host broadcast leaves a node in net/.
##
## Net.kick_peer() asks the transport to disconnect a peer, but ENet keeps it in
## multiplayer.get_peers() until the disconnect completes a poll or more later,
## and every send addressed to it in that window logs an engine error ("Condition
## p_channel >= peer->channelCount is true", once per packet; 1pi.57 fixed Net's
## own fan-outs). A plain rpc() addresses every listed peer, so each host
## broadcast in MatchNet, SnapshotSync and the weather / snow / breeze relays goes
## through broadcast() instead, which leaves the disconnecting peer out.
##
## DECISION: filter at the send rather than force the kick to finish first.
## Net.kick_peer() stays graceful (the kicked client still gets its disconnect
## reason), and one helper serves every broadcast site, ENet and Steam alike: it
## only reads MultiplayerAPI.get_peers() and Net.is_peer_disconnecting(), never a
## transport class. With nobody disconnecting broadcast() is the very rpc() it
## replaces (same packet count and bytes per peer); only while a kick is in flight
## does it fan out with rpc_id() to the remaining peers.


## The connected peers a broadcast may address: everything in `api.get_peers()`
## that `session` is not disconnecting. `session` is the Net autoload (or a test
## double); one without is_peer_disconnecting() never has a peer in that state.
static func targets(api: MultiplayerAPI, session: Variant) -> Array[int]:
	var ids: Array[int] = []
	if api == null or not api.has_multiplayer_peer():
		return ids
	var can_ask: bool = session != null and session.has_method(&"is_peer_disconnecting")
	for peer_id: int in api.get_peers():
		if can_ask and bool(session.is_peer_disconnecting(peer_id)):
			continue
		ids.append(peer_id)
	return ids


## True only when there is a live peer to talk to: `session` is not offline and
## `api` holds a connected peer that is not the engine's OfflineMultiplayerPeer.
## Offline (hot-seat, the sandbox, a unit test) every rpc() would error, so each
## replication layer becomes a no-op and Match runs exactly as it did offline.
##
## Godot installs an OfflineMultiplayerPeer by default, so has_multiplayer_peer()
## is true and the connection reads CONNECTED even with no session at all;
## rpc_id() onto it then fails with "p_peer_id == caller_id". Excluding that one
## class is not a transport assumption (CLAUDE.md): it is the engine's own
## stand-in for "no transport", and ENet and Steam are equally unaffected.
##
## DECISION (Bontago-fca.36.5): the one owner of this predicate. It lives here as
## a static helper beside broadcast() rather than only on the Net autoload
## because every caller (MatchNet, WeatherNet, SnowNet, BreezeNet) tests against
## its own node's MultiplayerAPI and an injectable `session` double; Net.can_send()
## delegates here. Host-ness has one owner too: Net.is_host() (callers go through
## their `_session()`).
static func can_send(api: MultiplayerAPI, session: Variant) -> bool:
	if session != null and bool(session.is_offline()):
		return false
	var peer: MultiplayerPeer = api.multiplayer_peer if api != null else null
	if peer == null or peer is OfflineMultiplayerPeer:
		return false
	return peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Calls `method` with `args` on `node`'s counterpart on every peer
## targets(node.multiplayer, session) lists. Callers keep their own "is this
## instance the host and is there a live transport" gate.
static func broadcast(node: Node, session: Variant, method: StringName, args: Array = []) -> void:
	var api: MultiplayerAPI = node.multiplayer
	var connected: PackedInt32Array = api.get_peers()
	var addressed: Array[int] = targets(api, session)
	if addressed.size() == connected.size():
		node.callv(&"rpc", [method] + args)
		return
	for peer_id: int in addressed:
		node.callv(&"rpc_id", [peer_id, method] + args)
