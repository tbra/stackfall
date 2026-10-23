class_name NetSession
extends Node
## The session surface SessionPort types against (NET_PORTS_PLAN 1.1). The Net
## autoload extends this and overrides every method; the bodies here are neutral
## defaults that answer as an offline, empty session.
##
## Net cannot be named as a type (it is an autoload without a class_name, and a
## preload of it would fold Net and its collaborators into one dependency cycle),
## so the port takes this base instead. Keep the signatures identical to the
## overrides in autoload/Net.gd.

## This session's own mode change (hosting started/ended, joined, left).
signal mode_changed(mode: int)


func is_host() -> bool:
	return true


func is_client() -> bool:
	return false


func is_offline() -> bool:
	return true


func local_slot() -> int:
	return -1


func slot_of_peer(_peer_id: int) -> int:
	return -1


func peer_of_slot(_slot_id: int) -> int:
	return -1


func is_local_slot(_slot_id: int) -> bool:
	return false


func peer_ids() -> PackedInt32Array:
	return PackedInt32Array()


func peer_info(_peer_id: int) -> Dictionary:
	return {}


func is_peer_disconnecting(_peer_id: int) -> bool:
	return false


func kick_peer(_peer_id: int, _reason: NetIds.LeaveReason = NetIds.LeaveReason.KICKED) -> void:
	pass


func report_stats(_source: StringName, _values: Dictionary) -> void:
	pass
