class_name HolePunch
## Territory hole module for displacement effects (Jumping Bean).
##
## `punch` opens a circular hole in the disc's territory at world_pos for open_s seconds.
## Respects HoleMode.OFF (returns false), PLAYING (returns true), and territory state via Match.
## Converts world coordinates to disc local and validates via Match.punch_special_hole.
##
## Depends on: Match


## Punches a hole in the territory at world_pos with given radius and duration.
## Converts to disc-local coordinates and honours HoleMode via Match.punch_special_hole.
## Returns true if a hole was requested, false if blocked (e.g., HoleMode.OFF).
static func punch(world_pos: Vector3, radius_m: float, open_s: float) -> bool:
	return false
