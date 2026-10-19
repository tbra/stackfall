class_name HandshakePolicy
extends RefCounted
## Pure join decision for a handshake: accept, refuse with a JoinError, or reclaim a
## reserved slot. Stub: the body arrives with the roster split.


class Decision extends RefCounted:
	enum Kind { ACCEPT, REFUSE, RECLAIM }
	var kind: int = Kind.ACCEPT
	## JoinError when REFUSE.
	var error: int = 0
	## Slot to give back when RECLAIM.
	var slot_id: int = -1


## request: {sender, build, name, token, already_seated}.
## host_state: {is_host, host_build, joins_open, match_in_progress, free_capacity,
## reservations: token -> slot, max_build_len, max_name_len}.
## Order of checks follows Net._rpc_handshake.
static func decide(request: Dictionary, host_state: Dictionary) -> Decision:
	assert(false, "HandshakePolicy.decide is a stub until N3")
	return Decision.new()
