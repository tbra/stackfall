class_name SessionPort
extends RefCounted
## Typed adapter over the Net autoload (or a test double such as FakeNet): the
## one surface the net/ nodes use to ask "who is the host, which slot does this
## peer hold, may I send to it".
##
## DECISION: the port wraps a NetSession (the Net autoload or an isolated instance of it)
## with typed calls, so consumers get typed returns and never write has_method. Tests use
## the FakeSessionPort spy, which adapts no session. A null session makes an invalid port
## (is_valid() false, silent); a consumer calls is_valid() when it binds a port and refuses
## to bind an invalid one.
##
## The surface is exactly what the net/ nodes call on `_session()` / `_net()`
## today (MatchNet, MatchEventApplier, SnapshotSync, WeatherNet, SnowNet,
## BreezeNet, NetFanout); nothing else.

## Forwards the adapted session's own mode_changed (hosting started/ended, joined,
## left); a spy never emits it on its own.
signal mode_changed(mode: int)

var _typed: NetSession = null


## `follow_net` false skips the mode_changed hookup (spies).
func _init(net: NetSession = null, follow_net: bool = true) -> void:
	_typed = net
	if net != null and follow_net:
		net.mode_changed.connect(mode_changed.emit)


## True when the port adapts a session.
func is_valid() -> bool:
	return _typed != null


## Net.is_host(): true on the host and offline.
func is_host() -> bool:
	return _typed.is_host()


func is_client() -> bool:
	return _typed.is_client()


func is_offline() -> bool:
	return _typed.is_offline()


func local_slot() -> int:
	return _typed.local_slot()


func slot_of_peer(peer_id: int) -> int:
	return _typed.slot_of_peer(peer_id)


func peer_of_slot(slot_id: int) -> int:
	return _typed.peer_of_slot(slot_id)


func is_local_slot(slot_id: int) -> bool:
	return _typed.is_local_slot(slot_id)


func peer_ids() -> PackedInt32Array:
	return _typed.peer_ids()


func peer_info(peer_id: int) -> Dictionary:
	return _typed.peer_info(peer_id)


func is_peer_disconnecting(peer_id: int) -> bool:
	return _typed.is_peer_disconnecting(peer_id)


## `reason` is a Net.LeaveReason value (see timeout_leave_reason()).
func kick_peer(peer_id: int, reason: int) -> void:
	_typed.kick_peer(peer_id, reason as NetIds.LeaveReason)


## Folds a subsystem's counters into the session's stats() under `source`.
func report_stats(source: StringName, values: Dictionary) -> void:
	_typed.report_stats(source, values)


## Net.LeaveReason.TIMEOUT, the reason MatchNet quotes when it drops a joiner
## whose world replay never acked.
func timeout_leave_reason() -> int:
	return int(NetIds.LeaveReason.TIMEOUT)
