class_name SessionPort
extends RefCounted
## Typed adapter over the Net autoload (or a test double such as FakeNet): the
## one surface the net/ nodes use to ask "who is the host, which slot does this
## peer hold, may I send to it".
##
## DECISION: autoload scripts have no class_name, so this adapter makes the one
## dynamic call per method; consumers get typed returns and never write
## has_method. The conformance check is a runtime one (is_valid() plus a single
## push_error), not an assert, so it survives release builds. A consumer calls
## is_valid() when it binds a port and refuses to bind an invalid one.
##
## DECISION: the adapted object is an Object, not a Node. The repo's own doubles
## (FakeNet) are RefCounted, and nothing here needs the scene tree.
##
## The surface is exactly what the net/ nodes call on `_session()` / `_net()`
## today (MatchNet, MatchEventApplier, SnapshotSync, WeatherNet, SnowNet,
## BreezeNet, NetFanout); nothing else.

## Every method the adapted object must have. `is_peer_disconnecting` is not
## listed: FakeNet and the NetFanout doubles never implemented it, and "a
## session without it never has a peer in that state" is NetFanout's contract.
const REQUIRED_METHODS: Array[StringName] = [
	&"is_host",
	&"is_client",
	&"is_offline",
	&"local_slot",
	&"slot_of_peer",
	&"peer_of_slot",
	&"is_local_slot",
	&"peer_ids",
	&"peer_info",
	&"kick_peer",
	&"report_stats",
]

const OPTIONAL_DISCONNECTING_METHOD: StringName = &"is_peer_disconnecting"

var _session: Object = null
var _valid: bool = false
var _can_ask_disconnecting: bool = false


func _init(session_node: Object) -> void:
	_session = session_node
	var missing: Array[StringName] = []
	if session_node == null:
		push_error("SessionPort: the adapted session object is null")
		return
	for method_name: StringName in REQUIRED_METHODS:
		if not session_node.has_method(method_name):
			missing.append(method_name)
	_can_ask_disconnecting = session_node.has_method(OPTIONAL_DISCONNECTING_METHOD)
	if not missing.is_empty():
		push_error("SessionPort: %s lacks %s" % [_describe(session_node), missing])
		return
	_valid = true


## True when the adapted object has every REQUIRED_METHODS entry.
func is_valid() -> bool:
	return _valid


## Net.is_host(): true on the host and offline.
func is_host() -> bool:
	return bool(_session.call(&"is_host"))


func is_client() -> bool:
	return bool(_session.call(&"is_client"))


func is_offline() -> bool:
	return bool(_session.call(&"is_offline"))


func local_slot() -> int:
	return int(_session.call(&"local_slot"))


func slot_of_peer(peer_id: int) -> int:
	return int(_session.call(&"slot_of_peer", peer_id))


func peer_of_slot(slot_id: int) -> int:
	return int(_session.call(&"peer_of_slot", slot_id))


func is_local_slot(slot_id: int) -> bool:
	return bool(_session.call(&"is_local_slot", slot_id))


func peer_ids() -> PackedInt32Array:
	return _session.call(&"peer_ids") as PackedInt32Array


func peer_info(peer_id: int) -> Dictionary:
	return _session.call(&"peer_info", peer_id) as Dictionary


## False for a session that cannot answer (see REQUIRED_METHODS).
func is_peer_disconnecting(peer_id: int) -> bool:
	if not _can_ask_disconnecting:
		return false
	return bool(_session.call(OPTIONAL_DISCONNECTING_METHOD, peer_id))


## `reason` is a Net.LeaveReason value (see timeout_leave_reason()).
func kick_peer(peer_id: int, reason: int) -> void:
	_session.call(&"kick_peer", peer_id, reason)


## Folds a subsystem's counters into the session's stats() under `source`.
func report_stats(source: StringName, values: Dictionary) -> void:
	_session.call(&"report_stats", source, values)


## The host's peer id (Net.HOST_PEER_ID), so consumers stop naming Net.*.
func host_peer_id() -> int:
	return Net.HOST_PEER_ID


## Net.LeaveReason.TIMEOUT, the reason MatchNet quotes when it drops a joiner
## whose world replay never acked.
func timeout_leave_reason() -> int:
	return int(Net.LeaveReason.TIMEOUT)


static func _describe(node: Object) -> String:
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path
	return node.get_class()
