class_name LandedProbe
extends RefCounted
## Landing detection probe for timed effects (Jumping Bean, Propeller, Anvil, Magnet).
##
## Replaces the unreliable Jolt `sleeping` check with a velocity-based detector.
## A block is considered "landed" when linear speed falls below `t.landed_speed_mps`
## for `t.landed_hold_s` seconds, OR after a first contact plus `t.landed_timeout_s`
## ceiling (whichever comes first). Tracks elapsed time since landing via `landed_age()`.
##
## Depends on: LandedTuning, Block


## Updates probe state each physics tick. Call once per tick while the block is active.
func update(block: Block, delta: float) -> void:
	pass


## Returns true if the block has landed according to the tuned criteria.
func has_landed() -> bool:
	return false


## Returns seconds elapsed since the block was first detected as landed.
## Returns 0.0 if not yet landed.
func landed_age() -> float:
	return 0.0
