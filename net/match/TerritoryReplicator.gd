class_name TerritoryReplicator
extends RefCounted
## Territory raster and circle replication: the host encodes full and diff packets, a client
## applies them. Stub: the bodies are filled in by the M5 implementation.


## Full raster and circle packet; empty on the stub.
func encode_full() -> PackedByteArray:
	push_error("TerritoryReplicator.encode_full is not implemented")
	return PackedByteArray()


## Diff since the last encoded packet; empty means nothing changed.
func encode_diff() -> PackedByteArray:
	push_error("TerritoryReplicator.encode_diff is not implemented")
	return PackedByteArray()


## Applies a received packet; false when it is malformed or refused.
func apply(_packet: PackedByteArray) -> bool:
	push_error("TerritoryReplicator.apply is not implemented")
	return false


## Makes the next encode_diff produce a full packet.
func force_full() -> void:
	push_error("TerritoryReplicator.force_full is not implemented")
