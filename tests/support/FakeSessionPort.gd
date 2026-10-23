class_name FakeSessionPort
extends SessionPort
## Spy for SessionPort over a FakeNet: answers every method a net/ consumer asks the session
## port from the FakeNet's state, records the writes in `calls`, and adapts no real session
## (null adapter, follow_net false), so a port method added without an override here falls
## through to the null adapter and errors loudly instead of reaching the real Net;
## test_session_port.gd's conformance test fails first. It is the only direct subclass of
## SessionPort; a test needing another answer extends this class and overrides that method.

## One entry per recorded write, in order: {"method": StringName, "args": Array}.
var calls: Array[Dictionary] = []

var _fake: FakeNet = null


func _init(fake: FakeNet = null) -> void:
	super(null, PackedStringArray(), false)
	_fake = fake if fake != null else FakeNet.offline()


func is_valid() -> bool:
	return true


## The argument lists of every recorded call to `method_name`, in order.
func calls_to(method_name: StringName) -> Array[Array]:
	var found: Array[Array] = []
	for call: Dictionary in calls:
		if call["method"] == method_name:
			found.append(call["args"] as Array)
	return found


func is_host() -> bool:
	return _fake.is_host()


func is_client() -> bool:
	return _fake.is_client()


func is_offline() -> bool:
	return _fake.is_offline()


func local_slot() -> int:
	return _fake.local_slot()


func slot_of_peer(peer_id: int) -> int:
	return _fake.slot_of_peer(peer_id)


func peer_of_slot(slot_id: int) -> int:
	return _fake.peer_of_slot(slot_id)


func is_local_slot(slot_id: int) -> bool:
	return _fake.is_local_slot(slot_id)


func peer_ids() -> PackedInt32Array:
	return _fake.peer_ids()


func peer_info(peer_id: int) -> Dictionary:
	return _fake.peer_info(peer_id)


## FakeNet never has a peer mid-disconnect, like a session without the method.
func is_peer_disconnecting(_peer_id: int) -> bool:
	return false


func kick_peer(peer_id: int, reason: int) -> void:
	calls.append({"method": &"kick_peer", "args": [peer_id, reason]})
	_fake.kick_peer(peer_id, reason)


func report_stats(source: StringName, values: Dictionary) -> void:
	calls.append({"method": &"report_stats", "args": [source, values]})
	_fake.report_stats(source, values)
