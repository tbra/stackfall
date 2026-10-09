class_name HolePunch
## Territory hole module for displacement effects (Jumping Bean).
##
## `punch` opens a circular hole in the disc's territory at a world position.
## Gates (all host-side): authority, live play (PLAYING or SUDDEN_DEATH via
## MatchPhase.is_live()), HoleMode != OFF, a Field and a positive
## radius. Match.punch_special_hole re-checks the same rules.
##
## Depends on: MatchContext, MatchPhase


## Returns true if a hole was requested, false if any gate blocked it.
static func punch(world_pos: Vector3, radius_m: float, open_s: float) -> bool:
	if not world_pos.is_finite() or not is_finite(radius_m) or not is_finite(open_s):
		return false
	if radius_m <= 0.0 or open_s <= 0.0:
		return false
	var ctx: MatchContext = MatchContext.current()
	if not ctx.has_authority() or not MatchPhase.is_live(ctx.state()):
		return false
	var config: MatchConfig = ctx.config()
	if config == null or config.hole_mode == MatchConfig.HoleMode.OFF:
		return false
	var field: FieldBody = ctx.field()
	if field == null:
		return false
	ctx.punch_special_hole(field.disk_local_from_world(world_pos), radius_m, open_s)
	return true
