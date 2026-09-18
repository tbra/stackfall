class_name FakeNet
extends RefCounted
## Test double for the Net autoload (docs/M3a_PLAN.md).
##
## GUT cannot double a plain autoload — addons/gut/test.gd's double_singleton
## only recognises Godot's own engine singletons — so autoload/Match.gd and
## net/MatchNet.gd read their session state through a seam
## (set_net_provider / set_providers) that defaults to the real Net. This
## scripts the handful of answers the host gates and the intent checks need:
## whether this instance is the host, which slot a peer holds, and which slots
## are driven by local input.
##
## It deliberately implements no transport. P1 owns the real thing; the point
## here is to put Match and MatchNet into the CLIENT and multi-peer states a
## single-process unit test can otherwise never reach.

var mode: int = 0  ## Net.Mode: 0 OFFLINE, 1 HOST, 2 CLIENT

## peer_id -> slot_id. The host's own peer (Net.HOST_PEER_ID) is normally in
## here too, holding slot 0.
var slots_by_peer: Dictionary = {}
## Slots this instance's own input drives. Offline that is every slot, which
## is what keeps M2's hot-seat working unchanged.
var local_slots: Array[int] = []
var names_by_peer: Dictionary = {}


static func host(peer_slots: Dictionary = {}, local: Array[int] = []) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	fake.mode = 1
	fake.slots_by_peer = peer_slots
	fake.local_slots = local
	return fake


static func client(local_slot_id: int) -> FakeNet:
	var fake: FakeNet = FakeNet.new()
	fake.mode = 2
	fake.local_slots = [local_slot_id]
	return fake


static func offline() -> FakeNet:
	return FakeNet.new()


func is_host() -> bool:
	return mode != 2


func is_client() -> bool:
	return mode == 2


func is_offline() -> bool:
	return mode == 0


func slot_of_peer(peer_id: int) -> int:
	return int(slots_by_peer.get(peer_id, -1))


func peer_of_slot(slot_id: int) -> int:
	for peer_id: Variant in slots_by_peer.keys():
		if int(slots_by_peer[peer_id]) == slot_id:
			return int(peer_id)
	return -1


func local_slot() -> int:
	return local_slots[0] if local_slots.size() > 0 else -1


func is_local_slot(slot_id: int) -> bool:
	if is_offline():
		return true
	return local_slots.has(slot_id)


func peer_ids() -> PackedInt32Array:
	var ids: PackedInt32Array = PackedInt32Array()
	for peer_id: Variant in slots_by_peer.keys():
		ids.append(int(peer_id))
	return ids


func peer_info(peer_id: int) -> Dictionary:
	return {
		"peer_id": peer_id,
		"slot_id": slot_of_peer(peer_id),
		"name": String(names_by_peer.get(peer_id, "Player")),
		"ready": true,
		"ping_ms": 0.0,
		"build": "",
	}
