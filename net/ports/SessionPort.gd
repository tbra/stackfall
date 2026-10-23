class_name SessionPort
extends RefCounted
## Typed adapter over the Net autoload (or a test double such as FakeNet): the
## one surface the net/ nodes use to ask "who is the host, which slot does this
## peer hold, may I send to it".
##
## DECISION: a real session (Net, or another instance of it) is reached through its
## class_name NetSession base with typed calls; only test doubles that are not a NetSession
## still take the dynamic path (TRANSITIONAL, removed by NP-F-S). Consumers get typed returns
## and never write has_method. The conformance check is a runtime one (is_valid() plus a single
## push_error), not an assert, so it survives release builds. A consumer calls
## is_valid() when it binds a port and refuses to bind an invalid one.
##
## DECISION: the adapted object is an Object, not a Node. The repo's own doubles
## (FakeNet) are RefCounted, and nothing here needs the scene tree.
##
## The surface is exactly what the net/ nodes call on `_session()` / `_net()`
## today (MatchNet, MatchEventApplier, SnapshotSync, WeatherNet, SnowNet,
## BreezeNet, NetFanout); nothing else.

## Forwards the adapted session's own mode_changed (hosting started/ended, joined,
## left); a double without that signal simply never emits it.
signal mode_changed(mode: int)

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
## Set when the adapted object is a NetSession (the Net autoload or an isolated
## Net instance): every forwarder then takes the typed path.
var _typed: NetSession = null
var _valid: bool = false
var _can_ask_disconnecting: bool = false
var _bound: Dictionary = {}
var _reported: Dictionary = {}


## `required` is the subset of REQUIRED_METHODS the consumer actually calls
## (empty = all of them). A narrow test double then binds as long as it answers
## that subset; a name that is not a REQUIRED_METHODS entry makes the port invalid.
## `follow_net` false skips the null push_error and the mode_changed hookup (spies).
func _init(session_node: Object = null, required: PackedStringArray = PackedStringArray(), follow_net: bool = true) -> void:
	_session = session_node
	if session_node == null:
		if follow_net:
			push_error("SessionPort: the adapted session object is null")
		return
	if follow_net and session_node.has_signal(&"mode_changed"):
		session_node.connect(&"mode_changed", mode_changed.emit)
	_typed = session_node as NetSession
	if _typed != null:
		_valid = true
		return
	# TRANSITIONAL (removed by NP-F-S): non-NetSession doubles keep the dynamic path.
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
	if _typed != null:
		return _typed.is_host()
	return bool(_call(&"is_host", [], false))


func is_client() -> bool:
	if _typed != null:
		return _typed.is_client()
	return bool(_call(&"is_client", [], false))


func is_offline() -> bool:
	if _typed != null:
		return _typed.is_offline()
	return bool(_call(&"is_offline", [], false))


func local_slot() -> int:
	if _typed != null:
		return _typed.local_slot()
	return int(_call(&"local_slot", [], -1))


func slot_of_peer(peer_id: int) -> int:
	if _typed != null:
		return _typed.slot_of_peer(peer_id)
	return int(_call(&"slot_of_peer", [peer_id], -1))


func peer_of_slot(slot_id: int) -> int:
	if _typed != null:
		return _typed.peer_of_slot(slot_id)
	return int(_call(&"peer_of_slot", [slot_id], -1))


func is_local_slot(slot_id: int) -> bool:
	if _typed != null:
		return _typed.is_local_slot(slot_id)
	return bool(_call(&"is_local_slot", [slot_id], false))


func peer_ids() -> PackedInt32Array:
	if _typed != null:
		return _typed.peer_ids()
	return _call(&"peer_ids", [], PackedInt32Array()) as PackedInt32Array


func peer_info(peer_id: int) -> Dictionary:
	if _typed != null:
		return _typed.peer_info(peer_id)
	return _call(&"peer_info", [peer_id], {}) as Dictionary


## False for a session that cannot answer (see REQUIRED_METHODS).
func is_peer_disconnecting(peer_id: int) -> bool:
	if _typed != null:
		return _typed.is_peer_disconnecting(peer_id)
	if not _can_ask_disconnecting:
		return false
	return bool(_session.call(OPTIONAL_DISCONNECTING_METHOD, peer_id))


## `reason` is a Net.LeaveReason value (see timeout_leave_reason()).
func kick_peer(peer_id: int, reason: int) -> void:
	if _typed != null:
		_typed.kick_peer(peer_id, reason as NetIds.LeaveReason)
		return
	_call(&"kick_peer", [peer_id, reason], null)


## Folds a subsystem's counters into the session's stats() under `source`.
func report_stats(source: StringName, values: Dictionary) -> void:
	if _typed != null:
		_typed.report_stats(source, values)
		return
	_call(&"report_stats", [source, values], null)


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
