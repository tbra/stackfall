class_name HolePunch
## Territory hole module for displacement effects (Jumping Bean).
##
## `punch` opens a circular hole in the disc's territory at a world position.
## Gates (all host-side): authority, live play (PLAYING or SUDDEN_DEATH via
## MatchAutoload.is_live()), HoleMode != OFF, a Field and a positive
## radius. Match.punch_special_hole re-checks the same rules.
##
## Depends on: Match


## Returns true if a hole was requested, false if any gate blocked it.
static func punch(world_pos: Vector3, radius_m: float, open_s: float) -> bool:
	if not world_pos.is_finite() or not is_finite(radius_m) or not is_finite(open_s):
		return false
	if radius_m <= 0.0 or open_s <= 0.0:
		return false
	if not Match._is_host() or not MatchAutoload.is_live(Match.state()):
		return false
	if Match.config == null or Match.config.hole_mode == MatchConfig.HoleMode.OFF:
		return false
	var field: Field = Match.field()
	if field == null:
		return false
	Match.punch_special_hole(field.disk_local_from_world(world_pos), radius_m, open_s)
	return true
