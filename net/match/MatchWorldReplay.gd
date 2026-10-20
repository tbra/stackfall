class_name MatchWorldReplay
extends RefCounted
## Mid-match join for the host: seats a peer who arrives after the match started, builds the world
## replay it is sent, tracks its acknowledgement and kicks a peer that never acknowledges.
##
## STUB: signatures only. Every method reports an error and returns a safe default until the
## implementation lands; nothing calls this class yet.


## Everything that leaves goes through `Seams` callables the facade binds (this class never touches
## a transport or reads the remote sender id).
class Seams extends RefCounted:
	## (peer_id: int, method: StringName, args: Array) -> bool : one addressed send.
	var send_to_peer: Callable = Callable()
	## () -> float : seconds, monotonic.
	var now_s: Callable = Callable()


var _session: Object = null
var _match: Object = null
var _config: NetConfig = null
var _seams: Seams = null


## `session_node` / `match_node` are the Net and Match autoloads (or test doubles).
func _init(session_node: Object, match_node: Object, config: NetConfig, seams: Seams) -> void:
	_session = session_node
	_match = match_node
	_config = config
	_seams = seams


## A peer was seated on `slot_id`: starts its replay when the match is already running.
func on_peer_joined(peer_id: int, slot_id: int, name: String) -> void:
	push_error("MatchWorldReplay.on_peer_joined is a stub (peer %d, slot %d, %s)" % [peer_id, slot_id, name])


## A peer left or was kicked: its pending replay is forgotten.
func on_peer_left(peer_id: int) -> void:
	push_error("MatchWorldReplay.on_peer_left is a stub (peer %d)" % peer_id)


## The ordered `[method: StringName, args: Array]` rows that rebuild the world for `peer_id`; the
## production sender `rpc_id`s each row.
func build_replay(peer_id: int, slot_id: int) -> Array[Array]:
	push_error("MatchWorldReplay.build_replay is a stub (peer %d, slot %d)" % [peer_id, slot_id])
	var rows: Array[Array] = []
	return rows


## The peer reports its replay applied. Ignored unless that replay id is the one pending.
func handle_replay_ack(sender: int, replay_id: int) -> void:
	push_error("MatchWorldReplay.handle_replay_ack is a stub (peer %d, replay %d)" % [sender, replay_id])


## True while `peer_id` has been sent a replay it has not acknowledged. Bound to the gateway's
## `Seams.is_replay_pending`.
func is_pending(peer_id: int) -> bool:
	push_error("MatchWorldReplay.is_pending is a stub (peer %d)" % peer_id)
	return false


## Kicks (through SessionPort.kick_peer) every peer whose replay is older than the timeout.
func tick_timeouts(now_s: float) -> void:
	push_error("MatchWorldReplay.tick_timeouts is a stub (now %f)" % now_s)
