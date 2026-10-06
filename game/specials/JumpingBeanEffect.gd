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
@export var hop_impulse: float = 6.5

## Horizontal speed (m/s) applied in a random direction on every hop.
@export var hop_horizontal_speed: float = 3.5

## Seconds between hops, counted from landing.
@export var hop_interval_s: float = 1.2

## Radius (m) of the hole punched at the position each hop leaves behind.
@export var hole_radius_m: float = 1.4

## Seconds the punched hole stays open (never closes under HoleMode.PERMANENT).
@export var hole_open_s: float = 2.5

## Seconds the bean keeps hopping after it lands; the fuse backstop is derived
## from it by SpecialBehavior (SpecialTuning.fuse_backstop_margin_s on top).
@export var lifetime_s: float = 14.0

## block.set_meta() key: landed-age at which the NEXT hop is due. Seeded to
## hop_interval_s on the first landed tick, advanced by hop_interval_s per hop, so
## exactly one hop fires per interval whatever the caller's delta.
const _NEXT_HOP_META: StringName = &"bean_next_hop_at"

## Shared across every block using this effect instance (see the class DECISION).
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Waits for LandedProbe (SpecialBehavior) instead of Jolt `sleeping`.
func needs_landing() -> bool:
	return true


## The hopping window, measured from landing.
func effect_lifetime_s() -> float:
	return lifetime_s


## Fires every hop that is due by landed time. Only called once landed.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if not block.has_meta(_NEXT_HOP_META):
		block.set_meta(_NEXT_HOP_META, hop_interval_s)
	var next_hop_at: float = float(block.get_meta(_NEXT_HOP_META))
	var elapsed: float = behavior.landed_age()
	while elapsed >= next_hop_at and hop_interval_s > 0.0:
		_hop(block)
		next_hop_at += hop_interval_s
	block.set_meta(_NEXT_HOP_META, next_hop_at)


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
## HoleMode.OFF / live-match / host gates), then kicks the bean up and sideways.
func _hop(block: Block) -> void:
	HolePunch.punch(block.global_position, hole_radius_m, hole_open_s)
	var angle: float = _rng.randf_range(0.0, TAU)
	var horizontal: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * hop_horizontal_speed
	block.wake_for_impulse()
	if block.is_freeze_static():
		return
	# kick(), not a bare `linear_velocity =` write: see Block.kick() (a hop kicked
	# during a residual downward velocity must not read as a damped bounce).
	block.kick(Vector3.UP * hop_impulse + horizontal)
	block.wake()
