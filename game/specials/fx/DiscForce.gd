class_name DiscForce
## Disc tilt module for impulse-based effects (Anvil, Propeller, Earthquake).
##
## `apply` tilts the disc toward/away from a position (sign +1 lowers, -1 raises).
## `shake` applies oscillating tilt with configurable amplitude and frequency.
## Both work with Field's tilt system via configurable strength and duration.
##
## Depends on: DiscForceTuning, Field


## Applies a tilt impulse toward (sign +1) or away from (sign -1) world_pos over delta time.
## Strength and duration are configured in `t`. Used by Anvil (sign +1) and Propeller (sign -1).
static func apply(field: Field, world_pos: Vector3, sign: float, t: DiscForceTuning, delta: float) -> void:
	pass


## Applies an oscillating tilt with configurable amplitude and frequency.
## `elapsed` is seconds since the shake started. Used by Earthquake.
static func shake(field: Field, t: DiscForceTuning, elapsed: float, delta: float) -> void:
	pass
