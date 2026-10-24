class_name WorldReplaySeams
extends RefCounted
## Spy Seams for a MatchWorldReplay built through its public constructor: the host's sends land on
## `send` and the clock is `now`. The MatchNet-bound parts (raster keyframe) stay
## empty; the spawn rows use the public six-argument net_block_spawned wire shape.


static func make(send: Callable, now: Callable) -> MatchWorldReplay.Seams:
	var seams: MatchWorldReplay.Seams = MatchWorldReplay.Seams.new()
	seams.send_to_peer = send
	seams.now_s = now
	seams.clear_cursor = func(_slot_id: int) -> void: pass
	seams.spawn_args = func(block: BlockBody, net_id: int) -> Array:
		return [
			net_id, block.shape_id, block.owner_slot, block.global_position,
			block.global_transform.basis.orthonormalized().get_rotation_quaternion(), block.gift_id,
		]
	seams.glued_ids = func() -> Array: return []
	seams.territory_args = func() -> Array: return []
	seams.replay_acknowledged = func() -> void: pass
	return seams
