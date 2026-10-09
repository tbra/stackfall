class_name JumpingBeanEffect
extends SpecialEffect
## Jumping Bean special (spec 2.6: "Jumping Bean creates a hole between random
## hops"; docs/GIFT_EFFECTS_PLAN.md section 3 and 4 row E, Bontago-1pi.85.12).
##
## Lifecycle: needs_landing() makes SpecialBehavior run a LandedProbe and call
## physics_tick() only once the carrier has landed. The old `block.sleeping` gate
## is gone: on a tilting disc with an awake island Jolt never sleeps the body, so
## the bean never started and the fuse ended it silently. Once landed, every
## hop_interval_s of landed time (frame-rate independent: driven by
## behavior.landed_age()) the bean punches a territory hole at the position it is
## about to leave through HolePunch (a no-op under HoleMode.OFF, owner decision
## Bontago-z4h; the dissolve of blocks over the hole is HoleDissolver's job) and
## kicks itself into the next hop. The effect ends effect_lifetime_s() after
## landing; detonate() is a no-op because the hopping already ran tick by tick.
##
## DECISION: each hop is a velocity kick via Block.kick(), never a position
## teleport (a teleport would fight net/SnapshotSync's interpolation). The body is
## released from the StableBlockManager freeze first (wake_for_impulse()), since a
## STATIC-frozen body would ignore the kick.
##
## DECISION: the hole is punched at the pre-hop position ("between hops" reads as
## the gap the bean leaves behind). A bean that hops off the disc keeps going and
## burns at the kill plane like any other block.
##
## DECISION: a SpecialDef's `effect` is one shared Resource reused by every block,
## so this effect keeps no mutable per-block state; the next-hop time lives in
## block.set_meta(), keyed by a unique StringName, like every timed sibling. The
## RNG that picks hop directions is shared across blocks (not reproducible, and
## nothing needs it to be).
##
## DECISION (config/specials/jumping_bean.tres): arm_impulse is 10.0 and
## fuse_timeout_s 20.0, kept from review fix Bontago-1en.8. impact_triggers()
## vetoes decel-based impact activation entirely (Bontago-1en.22), so a hop's own
## landing can never trigger the bean; a nearby explosion still chains into it.

## Vertical speed (m/s) applied straight up on every hop.
@export var hop_impulse: float = 11.0

## Horizontal speed (m/s) applied in a random direction on every hop, one physics
## tick AFTER the vertical kick (Bontago-1pi.85.28: written while still touching the
## disc, the contact friction ate it and the bean hopped straight up).
@export var hop_horizontal_speed: float = 11.0

## Seconds from landing to the FIRST hop (Bontago-1pi.85.28: the owner saw ~5 s idle).
@export var first_hop_delay_s: float = 0.6

## Seconds between the following hops.
@export var hop_interval_s: float = 1.8

## Radius (m) of the hole punched at the position each hop leaves behind.
@export var hole_radius_m: float = 2.5

## Seconds the punched hole stays open (never closes under HoleMode.PERMANENT).
@export var hole_open_s: float = 3.0

## Seconds the bean keeps hopping after it lands; the fuse backstop is derived
## from it by SpecialBehavior (SpecialTuning.fuse_backstop_margin_s on top).
@export var lifetime_s: float = 24.0

## Probability (0..1) that a hop heads roughly at the disc centre; otherwise the bearing is
## uniform over the full circle, so an off-disc hop stays possible (owner 2026-10-07).
@export_range(0.0, 1.0) var centre_weight: float = 0.65

## Half-width (degrees) of the random cone around the inward bearing for a centre-weighted hop.
@export var centre_spread_deg: float = 70.0

## Bean-specific landing probe (Bontago-1pi.85.28): a bouncing/rolling bean on a tilting
## disc never drops below LandedProbe's default 0.5 m/s, so it only "landed" at the 5 s
## timeout. Looser speed, shorter hold and a 1 s ceiling start the hopping promptly.
@export var landed: LandedTuning = LandedTuning.new()

## block.set_meta() key: landed-age from which the next hop may start (while grounded).
## Seeded to first_hop_delay_s, reset to touchdown + hop_interval_s after every hop.
const _READY_AT_META: StringName = &"bean_ready_at"

## block.set_meta() key: set at take-off, cleared at the next touchdown.
const _AIRBORNE_META: StringName = &"bean_airborne"

## block.set_meta() key: the horizontal velocity (Vector3) still owed to the current hop,
## added on the first tick after the vertical kick, once the bean has left the disc.
const _PENDING_HORIZONTAL_META: StringName = &"bean_pending_horizontal"

## Unit-test seam: when valid, replaces the physics contact query (Callable(Block) -> bool),
## since a stub Block has no collision to probe. Never set in the shipped def.
var contact_override: Callable = Callable()

## Shared across every block using this effect instance (see the class DECISION).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Waits for LandedProbe (SpecialBehavior) instead of Jolt `sleeping`.
func needs_landing() -> bool:
	return true


## The hopping window, measured from landing.
func effect_lifetime_s() -> float:
	return lifetime_s


## Fires a hop only from contact: the bean must be touching a surface and not rising, and
## its interval since the last landing must have elapsed. A hop due while the bean is still
## in the air simply waits for touchdown (flight time can exceed hop_interval_s).
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	_apply_pending_horizontal(block)
	var elapsed: float = behavior.landed_age()
	if not block.has_meta(_READY_AT_META):
		block.set_meta(_READY_AT_META, first_hop_delay_s)
	var grounded: bool = _is_grounded(block)
	if grounded and block.has_meta(_AIRBORNE_META) and not block.has_meta(_PENDING_HORIZONTAL_META):
		# Touchdown after a hop: the interval counts from here, not from take-off.
		block.remove_meta(_AIRBORNE_META)
		block.set_meta(_READY_AT_META, elapsed + hop_interval_s)
	if not grounded or block.has_meta(_AIRBORNE_META) or block.has_meta(_PENDING_HORIZONTAL_META):
		return
	if elapsed >= float(block.get_meta(_READY_AT_META)):
		_hop(block)
	# Bean-side guard (HoleDissolver is not ours): a grounded bean sitting over an open hole
	# cell would dissolve in it, so kick it out now (no new hole) instead of waiting.
	elif _is_over_open_hole(block):
		_kick(block)


## True when the bean touches a surface below it and is not moving upward (same downward
## test-motion as LandedProbe, since blocks run without contact_monitor).
func _is_grounded(block: Block) -> bool:
	if contact_override.is_valid():
		return bool(contact_override.call(block))
	if block.linear_velocity.y > landed.landed_speed_mps:
		return false
	var params: PhysicsTestMotionParameters3D = PhysicsTestMotionParameters3D.new()
	params.from = block.global_transform
	params.motion = Vector3.DOWN * landed.contact_probe_m
	var result: PhysicsTestMotionResult3D = PhysicsTestMotionResult3D.new()
	return PhysicsServer3D.body_test_motion(block.get_rid(), params, result)


## Landing probe thresholds for this bean (see `landed`).
func landed_tuning() -> LandedTuning:
	return landed


## Bontago-1en.22: vetoes the decel-based impact trigger (see class DECISION).
func impact_triggers(_block: Block, _behavior: SpecialBehavior) -> bool:
	return false


## True once landed for lifetime_s.
func wants_early_trigger(_block: Block, behavior: SpecialBehavior) -> bool:
	return behavior.has_landed() and behavior.landed_age() >= lifetime_s


## No-op: the hopping already ran, tick by tick, in physics_tick().
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## One hop: punches a hole at the pre-hop position (HolePunch applies the
## HoleMode.OFF / live-match / host gates), then kicks the bean up; the sideways part
## follows on the next tick (see _apply_pending_horizontal()).
func _hop(block: Block) -> void:
	HolePunch.punch(block.global_position, hole_radius_m, hole_open_s)
	_kick(block)


## Unit hop bearing in disk-local (x, z). With probability centre_weight: the inward
## direction (towards the origin) rotated by a uniform angle within +/- spread_deg;
## otherwise uniform over TAU. At the exact centre there is no inward bearing (uniform).
static func hop_direction(position_disk: Vector2, rng: RandomNumberGenerator,
		centre_weight: float, spread_deg: float) -> Vector2:
	var uniform_angle: float = rng.randf_range(0.0, TAU)
	if position_disk.length_squared() > 0.0 and rng.randf() < centre_weight:
		var spread: float = deg_to_rad(spread_deg)
		return (-position_disk).normalized().rotated(rng.randf_range(-spread, spread))
	return Vector2(cos(uniform_angle), sin(uniform_angle))


## Vertical kick now, horizontal part owed to the next tick.
func _kick(block: Block) -> void:
	var field: FieldBody = MatchContext.current().field()
	var position_disk: Vector2 = Vector2.ZERO
	if field != null:
		position_disk = field.disk_local_from_world(block.global_position)
	var dir: Vector2 = hop_direction(position_disk, _rng, centre_weight, centre_spread_deg)
	var horizontal: Vector3 = Vector3(dir.x, 0.0, dir.y)
	if field != null:
		horizontal = field.global_transform.basis * horizontal
		horizontal.y = 0.0
		horizontal = horizontal.normalized()
	horizontal *= hop_horizontal_speed
	block.wake_for_impulse()
	if block.is_freeze_static():
		return
	# kick(), not a bare `linear_velocity =` write: see Block.kick() (a hop kicked
	# during a residual downward velocity must not read as a damped bounce).
	block.kick(Vector3.UP * hop_impulse)
	block.set_meta(_PENDING_HORIZONTAL_META, horizontal)
	block.set_meta(_AIRBORNE_META, true)
	block.wake()


## Sets the horizontal part of the last hop once the bean is off the ground.
func _apply_pending_horizontal(block: Block) -> void:
	if not block.has_meta(_PENDING_HORIZONTAL_META):
		return
	var horizontal: Vector3 = block.get_meta(_PENDING_HORIZONTAL_META) as Vector3
	block.remove_meta(_PENDING_HORIZONTAL_META)
	# Replaces (not adds to) the sideways speed: hops never accumulate speed, and any
	# friction/bounce leftover from the take-off tick is discarded.
	block.kick(Vector3(horizontal.x, block.linear_velocity.y, horizontal.z))


## True when the bean's centre cell is an open hole and it is not rising.
func _is_over_open_hole(block: Block) -> bool:
	if block.linear_velocity.y > 0.0:
		return false
	var ctx: MatchContext = MatchContext.current()
	var field: FieldBody = ctx.field()
	var grid: CellGrid = ctx.cell_grid()
	var raster: TerritoryRaster = ctx.raster()
	if field == null or grid == null or raster == null:
		return false
	var cell: Vector2i = grid.world_to_cell(field.disk_local_from_world(block.global_position))
	if not grid.in_bounds(cell.x, cell.y):
		return false
	return raster.is_hole(cell.x, cell.y)
