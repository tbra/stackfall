class_name ImpactReplicator
extends RefCounted
## Impact batching on the host and delayed playback on a client. Stub: the bodies are filled in
## by the M5 implementation.


## Records one impact for the next batch.
func collect(_speed: float, _position: Vector3, _now_ms: int) -> void:
	push_error("ImpactReplicator.collect is not implemented")


## The batch to send; empty means nothing to send.
func flush(_now_ms: int) -> PackedByteArray:
	push_error("ImpactReplicator.flush is not implemented")
	return PackedByteArray()


## Queues a received batch; false when it is malformed or refused.
func receive(_packet: PackedByteArray, _now_ms: int) -> bool:
	push_error("ImpactReplicator.receive is not implemented")
	return false


## Impacts due at `view_ms`, each as an Array row.
func drain(_view_ms: float) -> Array[Array]:
	push_error("ImpactReplicator.drain is not implemented")
	return []
