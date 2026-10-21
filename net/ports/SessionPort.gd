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
var _bound: Dictionary = {}
var _reported: Dictionary = {}


## `required` is the subset of REQUIRED_METHODS the consumer actually calls
## (empty = all of them). A narrow test double then binds as long as it answers
## that subset; a name that is not a REQUIRED_METHODS entry makes the port invalid.
func _init(session_node: Object, required: PackedStringArray = PackedStringArray()) -> void:
	_session = session_node
	if session_node == null:
		push_error("SessionPort: the adapted session object is null")
		return
	var wanted: Array[StringName] = _wanted(required)
	var unknown: Array[StringName] = []
	var missing: Array[StringName] = []
	for method_name: StringName in wanted:
		if not REQUIRED_METHODS.has(method_name):
			unknown.append(method_name)
		elif not session_node.has_method(method_name):
			missing.append(method_name)
	_can_ask_disconnecting = session_node.has_method(OPTIONAL_DISCONNECTING_METHOD)
	if not unknown.is_empty():
		push_error("SessionPort: %s is not a port method: %s" % [_describe(session_node), unknown])
		return
	if not missing.is_empty():
		push_error("SessionPort: %s lacks %s" % [_describe(session_node), missing])
		return
	for method_name: StringName in wanted:
		_bound[method_name] = true
	_valid = true


## True when the adapted object has every method the port was bound to.
func is_valid() -> bool:
	return _valid


## Net.is_host(): true on the host and offline.
func is_host() -> bool:
	return bool(_call(&"is_host", [], false))


func is_client() -> bool:
	return bool(_call(&"is_client", [], false))


func is_offline() -> bool:
	return bool(_call(&"is_offline", [], false))


func local_slot() -> int:
	return int(_call(&"local_slot", [], -1))


func slot_of_peer(peer_id: int) -> int:
	return int(_call(&"slot_of_peer", [peer_id], -1))


func peer_of_slot(slot_id: int) -> int:
	return int(_call(&"peer_of_slot", [slot_id], -1))


func is_local_slot(slot_id: int) -> bool:
	return bool(_call(&"is_local_slot", [slot_id], false))


func peer_ids() -> PackedInt32Array:
	return _call(&"peer_ids", [], PackedInt32Array()) as PackedInt32Array


func peer_info(peer_id: int) -> Dictionary:
	return _call(&"peer_info", [peer_id], {}) as Dictionary


## False for a session that cannot answer (see REQUIRED_METHODS).
func is_peer_disconnecting(peer_id: int) -> bool:
	if not _can_ask_disconnecting:
		return false
	return bool(_session.call(OPTIONAL_DISCONNECTING_METHOD, peer_id))


## `reason` is a Net.LeaveReason value (see timeout_leave_reason()).
func kick_peer(peer_id: int, reason: int) -> void:
	_call(&"kick_peer", [peer_id, reason], null)


## Folds a subsystem's counters into the session's stats() under `source`.
func report_stats(source: StringName, values: Dictionary) -> void:
	_call(&"report_stats", [source, values], null)


## The host's peer id (Net.HOST_PEER_ID), so consumers stop naming Net.*.
func host_peer_id() -> int:
	return NetRoster.HOST_PEER_ID


## Net.LeaveReason.TIMEOUT, the reason MatchNet quotes when it drops a joiner
## whose world replay never acked.
func timeout_leave_reason() -> int:
	return int(NetIds.LeaveReason.TIMEOUT)


static func _describe(node: Object) -> String:
	if node == null:
		return "null"
	var script: Script = node.get_script() as Script
	if script != null and not script.resource_path.is_empty():
		return script.resource_path
	return node.get_class()


## Forwards to the adapted object. A method the bind already verified goes
## straight through; any other one is checked, and a missing one logs once and
## answers `fallback` (the documented default) instead of crashing.
func _call(method_name: StringName, args: Array, fallback: Variant) -> Variant:
	if _bound.has(method_name):
		return _session.callv(method_name, args)
	if _session == null or not _session.has_method(method_name):
		if not _reported.has(method_name):
			_reported[method_name] = true
			push_error("SessionPort: %s has no %s (outside the bound subset); answering the default" % [_describe(_session), method_name])
		return fallback
	_bound[method_name] = true
	return _session.callv(method_name, args)


static func _wanted(required: PackedStringArray) -> Array[StringName]:
	var names: Array[StringName] = []
	if required.is_empty():
		names.assign(REQUIRED_METHODS)
		return names
	for entry: String in required:
		names.append(StringName(entry))
	return names
