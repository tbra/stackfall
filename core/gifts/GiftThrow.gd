class_name GiftThrow
extends RefCounted
## Pure host-side rules for how a held gift leaves the hand. No scene tree. Every active mode is camera-aimed: the intent carries the
## activating player's camera forward in the existing throw RPC's `velocity` slot; the host
## validates it (finite, length band), normalises it and derives everything else (GiftAim).
## - THROW (Bomb, Magnet, Jumping Bean): ballistic arc, GiftAim.throw_velocity.
## - AIMED (Rocket, Paintball): straight gravity-free flight along the aim.
## - NONE: every other gift is only dropped in place; a throw is refused.

enum Mode { NONE, THROW, AIMED }


## How a held gift leaves the hand: mode, launch velocity, spawn point and facing.
class Plan extends RefCounted:
	var mode: Mode = Mode.NONE
	var velocity: Vector3 = Vector3.ZERO
	var spawn_origin: Vector3 = Vector3.ZERO
	## faced_basis is valid only when faces (a null-vs-IDENTITY pair, not a Variant).
	var faces: bool = false
	var faced_basis: Basis = Basis.IDENTITY
	var range_scale: float = 1.0


static func mode_for(def: SpecialDef) -> Mode:
	if def == null:
		return Mode.NONE
	if def.aimed_launch:
		return Mode.AIMED
	if def.throwable:
		return Mode.THROW
	return Mode.NONE


## Whether holding a gift in `mode` draws a trajectory preview: only the ballistic
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


## How `def` leaves the hand for a camera-aimed release at `origin` (the unit `aim` is already
## validated by the caller): launch velocity (ballistic THROW scaled by `range_scale`, AIMED left
## at rest for the effect), spawn point on the camera line (the caller muzzle-matches an AIMED faced gift,
## BlockFactory being a game/ class) and the faced pose. A malformed aim or a NONE def gives a plan with no launch.
static func launch_plan(def: SpecialDef, mode: Mode, aim: Vector3, origin: Vector3,
		surface_y: float, range_scale: float, tuning: SpecialTuning, _shape: BlockShape) -> Plan:
	var plan: Plan = Plan.new()
	plan.mode = mode
	plan.spawn_origin = origin
	plan.range_scale = range_scale
	if GiftAim.unit_forward(aim) == Vector3.ZERO or (def != null and mode == Mode.NONE):
		return plan
	# An unresolved def (spawns as a plain block) takes the same ballistic throw.
	var ballistic: bool = def == null or mode == Mode.THROW
	var speed_cap: float = tuning.throw_max_speed
	if ballistic:
		plan.velocity = GiftAim.throw_velocity(aim, tuning, range_scale)
		speed_cap *= GiftAim.speed_factor(range_scale)
	plan.velocity = plan.velocity.limit_length(speed_cap)
	plan.spawn_origin = GiftAim.spawn_point(origin, aim, surface_y, tuning)
	var faced: Variant = launch_facing_basis(def, mode, aim, plan.velocity)
	if faced != null:
		plan.faces = true
		plan.faced_basis = faced as Basis
	return plan


## The basis a thrown/launched Rocket or Magnet carrier spawns with (nose along its flight line),
## or null when the gift keeps the upright spawn pose.
static func launch_facing_basis(def: SpecialDef, mode: Mode, aim: Vector3, velocity: Vector3) -> Variant:
	if def == null or def.effect == null or not def.effect.faces_launch(mode, aim, velocity):
		return null
	return def.effect.launch_facing(mode, aim, velocity)
