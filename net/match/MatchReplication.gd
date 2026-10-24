class_name MatchReplication
extends RefCounted
## Territory, impacts and match-start, both directions (interface stub: bodies land with the
## MatchNet cut). Owns the TerritoryReplicator and ImpactReplicator.

const NOT_IMPLEMENTED: String = "MatchReplication: not implemented"

class Seams extends RefCounted:
	## () -> bool
	var can_send: Callable = Callable()
	## (method: StringName, args: Array) -> void
	var broadcast: Callable = Callable()
	## (peer_id: int, method: StringName, args: Array) -> bool
	var send_to_peer: Callable = Callable()
	## () -> Array[int]
	var peer_ids: Callable = Callable()
	## (peer_id: int) -> bool
	var is_replay_pending: Callable = Callable()
	## () -> int
	var now_ms: Callable = Callable()
	## () -> int : the snapshot interpolation delay while SnapshotSync runs, else 0.
	var view_delay_ms: Callable = Callable()


## Seams are bound by MatchNet; the module touches no autoload.
@warning_ignore("unused_parameter")
func _init(seams: Seams, mirror: MatchEventMirror) -> void:
	pass


## First build and every rebind: swaps refs and rebuilds the replicators; KEEPS the start-sent flag.
@warning_ignore("unused_parameter")
func bind(session: SessionPort, host: MatchHostPort, replica: MatchReplicaPort, config: NetConfig) -> void:
	push_error(NOT_IMPLEMENTED)


## Host -> clients.
@warning_ignore("unused_parameter")
func send_spawn(block: BlockBody, net_id: int) -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func send_despawn(net_id: int, reason: String) -> void:
	push_error(NOT_IMPLEMENTED)


func send_territory() -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func send_match_event(event: StringName, args: Array) -> void:
	push_error(NOT_IMPLEMENTED)


## Owns the start-sent flag.
@warning_ignore("unused_parameter")
func send_match_start(match_config: MatchConfig) -> void:
	push_error(NOT_IMPLEMENTED)


func send_match_loading() -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func spawn_args(block: BlockBody, net_id: int) -> Array:
	push_error(NOT_IMPLEMENTED)
	return []


func territory_replay_args() -> Array:
	push_error(NOT_IMPLEMENTED)
	return []


## True = a new match is LOADING (caller runs reset_counters then replicate_match_start).
@warning_ignore("unused_parameter")
func on_match_state_changed(to_state: int) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


@warning_ignore("unused_parameter")
func on_block_impacted_at(speed: float, position: Vector3) -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func tick_host_feeds(delta: float) -> void:
	push_error(NOT_IMPLEMENTED)


## Client side.
@warning_ignore("unused_parameter")
func receive_territory(packet: PackedByteArray) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


@warning_ignore("unused_parameter")
func receive_impacts(packet: PackedByteArray) -> void:
	push_error(NOT_IMPLEMENTED)


func play_due_impacts() -> void:
	push_error(NOT_IMPLEMENTED)


func clear_impacts() -> void:
	push_error(NOT_IMPLEMENTED)


## Zeroes the cat accumulator and rebuilds the territory replicator; keeps impacts and the flag.
func reset() -> void:
	push_error(NOT_IMPLEMENTED)
