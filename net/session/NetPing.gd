class_name NetPing
extends RefCounted
## Ping/pong/stats of the Net autoload. The host never trusts a client-sent
## timestamp: the echo is checked against what it sent. STUB: default bodies log
## and report no ping; Net does not call it yet.


func _init(_config: NetConfig, _flood: PeerFloodGate) -> void:
	pass


## Send due pings at `now_ms`.
func tick(_now_ms: int) -> void:
	push_error("NetPing.tick: not implemented")


## Host: a pong from `sender`; clamps rtt to [0, ping_rtt_max_ms] and drops stale echoes.
func on_pong(_sender: int, _sent_at_ms: int, _now_ms: int) -> void:
	push_error("NetPing.on_pong: not implemented")


## Averaged RTT in ms for `peer_id`, 0.0 when unknown.
func ping_ms(_peer_id: int) -> float:
	push_error("NetPing.ping_ms: not implemented")
	return 0.0
