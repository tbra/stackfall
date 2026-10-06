class_name GiftThrow
extends RefCounted
## Bontago-1pi.85.16 (owner answer 1pi.85.1, docs/GIFT_EFFECTS_PLAN.md section 2/7): pure host-side
## rules for how a held gift leaves the hand. No scene tree.
##
## - THROW (Bomb, Magnet, Jumping Bean): fixed trajectory. The host ignores the client's drag
##   length/speed and keeps only its horizontal heading; speed and loft are SpecialTuning's.
## - AIMED (Rocket, Paintball): not thrown. The intent carries the activating player's camera
##   forward in the existing throw RPC's `velocity` slot (RPC unchanged); the host validates it
##   (finite, length band) and normalises it. Which effect consumes it is the caller's job.
## - NONE: every other gift is only dropped in place; a throw is refused.

enum Mode { NONE, THROW, AIMED }


static func mode_for(def: SpecialDef) -> Mode:
	if def == null:
		return Mode.NONE
	if def.aimed_launch:
		return Mode.AIMED
	if def.throwable:
		return Mode.THROW
	return Mode.NONE


## The fixed-trajectory launch velocity for `client_velocity`'s horizontal heading, or
## Vector3.ZERO when that heading is unusable (non-finite or no horizontal part).
static func fixed_velocity(client_velocity: Vector3, tuning: SpecialTuning) -> Vector3:
	if not client_velocity.is_finite():
		return Vector3.ZERO
	var heading: Vector3 = Vector3(client_velocity.x, 0.0, client_velocity.z)
	if heading.length() < tuning.gift_aim_min_horizontal:
		return Vector3.ZERO
	var direction: Vector3 = (heading.normalized() + Vector3.UP * tuning.gift_throw_loft_ratio).normalized()
	return direction * tuning.gift_throw_speed_mps


## A client-sent aim direction as a unit vector, or Vector3.ZERO when malformed (non-finite,
## zero or outside the accepted length band).
static func sanitize_aim(direction: Vector3, tuning: SpecialTuning) -> Vector3:
	if not direction.is_finite():
		return Vector3.ZERO
	var length: float = direction.length()
	if length < tuning.gift_aim_min_length or length > tuning.gift_aim_max_length:
		return Vector3.ZERO
	return direction / length
