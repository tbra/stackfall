class_name ClientReplayGate
extends RefCounted
## Client-side world gate and replay span (interface stub: bodies land with the MatchNet cut).

const NOT_IMPLEMENTED: String = "ClientReplayGate: not implemented"

## Refreshes the refs; KEEPS the awaiting/replay-span state.
@warning_ignore("unused_parameter")
func bind(session: SessionPort, config: NetConfig) -> void:
	push_error(NOT_IMPLEMENTED)


func awaiting_world() -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## Awaiting = client; ends any replay span.
@warning_ignore("unused_parameter")
func on_mode_changed(is_client: bool) -> void:
	push_error(NOT_IMPLEMENTED)


@warning_ignore("unused_parameter")
func on_match_start(replay_id: int, now_ms: int) -> void:
	push_error(NOT_IMPLEMENTED)


## True = send net_replay_ack.
@warning_ignore("unused_parameter")
func on_replay_end(replay_id: int) -> bool:
	push_error(NOT_IMPLEMENTED)
	return false


## Expiry at config.replay_ack_timeout.
@warning_ignore("unused_parameter")
func tick(now_ms: int) -> void:
	push_error(NOT_IMPLEMENTED)


## Idempotent.
func end_replay() -> void:
	push_error(NOT_IMPLEMENTED)
