class_name GiftThrow
extends RefCounted
## Bontago-1pi.85.16 / 85.29 (docs/GIFT_PLAYTEST2_PLAN.md): pure host-side rules for how a held
## gift leaves the hand. No scene tree. Every active mode is camera-aimed: the intent carries the
## activating player's camera forward in the existing throw RPC's `velocity` slot; the host
## validates it (finite, length band), normalises it and derives everything else (GiftAim).
## - THROW (Bomb, Magnet, Jumping Bean): ballistic arc, GiftAim.throw_velocity.
## - AIMED (Rocket, Paintball): straight gravity-free flight along the aim.
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


## Whether holding a gift in `mode` draws a trajectory preview (1pi.85.50): only the ballistic
## THROW arc; AIMED (Rocket, Paintball) shows none.
static func shows_preview(mode: Mode) -> bool:
	return mode == Mode.THROW


## A client-sent aim direction as a unit vector, or Vector3.ZERO when malformed (non-finite,
## zero or outside the accepted length band).
static func sanitize_aim(direction: Vector3, tuning: SpecialTuning) -> Vector3:
	if not direction.is_finite():
		return Vector3.ZERO
	var length: float = direction.length()
	if length < tuning.gift_aim_min_length or length > tuning.gift_aim_max_length:
		return Vector3.ZERO
	return direction / length
