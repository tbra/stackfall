class_name JumpingBeanEffect
extends SpecialEffect
## Jumping Bean special (spec 2.6, installed-tutorial evidence: "Jumping Bean
## creates a hole between random hops"). See docs/M4_SPECIALS_PACKAGES.md's
## P5-BEAN package, which depends on P5-HOLE's Match.punch_special_hole()/
## MatchTerritory.punch_special_hole(). Follows that doc's "timed-effect
## pattern" the same way PropellerEffect.gd/AnvilEffect.gd's settle-gate
## does: physics_tick() is a no-op until the block first settles
## (block.sleeping), then every hop_interval_s of simulated time thereafter
## (frame-rate independent, driven by behavior.age(), not tick count) it
## punches a hole at the position the block is about to leave and kicks it
## into a new hop. wants_early_trigger() flips once elapsed-since-first-
## settle reaches lifetime_s; detonate() is a no-op -- the hopping already
## ran, tick by tick, in physics_tick(), exactly like every other P5 timed
## effect (Propeller/Anvil/Volcano/Earthquake).
##
## DECISION (game/specials/JumpingBeanEffect.gd, P5-BEAN): each hop is a
## velocity kick (linear_velocity), never a position teleport -- a teleport
## would fight game/net/SnapshotSync's interpolation of a replicated body's
## position, the same reasoning RocketEffect.gd/VolcanoEffect.gd's own
## launches already follow.
##
## DECISION (game/specials/JumpingBeanEffect.gd, P5-BEAN, spec 2.6 "a hole
## between hops"): the hole is punched at the position the bean is ABOUT TO
## LEAVE (computed before the velocity kick), not the not-yet-known landing
## spot -- "between hops" reads as the gap it leaves behind, not a blind
## guess at where it's headed.
##
## DECISION (game/specials/JumpingBeanEffect.gd, P5-BEAN): a bean that hops
## off the disk's own edge is allowed to keep going. Match.punch_special_hole()
## (autoload/match/MatchTerritory.gd) already clamps its cell scan to
## [0, res-1] for a world_pos outside the disk, so an off-disk punch is a
## harmless no-op there; the bean block itself just falls and eventually
## burns like any other block that leaves the play area
## (game/Block.gd/Field.gd's own kill-plane handling) -- nothing here needs
## to keep it on the disk.
##
## DECISION (config/specials/jumping_bean.tres, review fix Bontago-1en.8):
## fuse_timeout_s is 20.0 here, NOT the 6.0 every sibling .tres shares.
## SpecialBehavior.advance()'s last line force-triggers ANY special once
## `age() >= arm_delay + fuse_timeout_s`, independent of that special's own
## effect logic -- at the shared 6.0, that is age 6.4s, which is reached
## long before this bean's own lifetime_s (12.0s, itself measured from FIRST
## SETTLE -- after arm_delay and whatever fall time preceded it, so the real
## wall-clock trigger age is even later than 12.4s). The Bean is the one P5
## effect whose own intended duration (lifetime_s) exceeds every other
## special's shared fuse -- Rocket/Bomb/Volcano/Earthquake/Anvil/Propeller
## all finish (explode, stop shaking, stop lifting) well inside 6.4s, so the
## shared fuse never fires early for them; the Bean is meant to keep hopping
## for 12 full seconds after it first lands, so its fuse must clear
## lifetime_s (plus arm_delay and the fall time before the first settle)
## with real margin, not just barely exceed the old 6.4s. 20.0 gives that
## margin (arm_delay + 20.0 = 20.4s vs. arm_delay + lifetime_s = 12.4s at the
## earliest, i.e. from an instant fall) without being so large the fuse
## stops meaning anything as a last-resort safety net. See
## tests/unit/test_jumping_bean_effect.gd's
## test_real_jumping_bean_tres_def_does_not_fuse_trigger_before_lifetime_s
## (fails before this fix, at the old 6.0 value).
##
## DECISION (config/specials/jumping_bean.tres, review fix Bontago-1en.8,
## SHOULD-FIX): arm_impulse is 10.0 here, not the 5.0 every sibling .tres
## shares. A hop's own landing carries roughly
## sqrt(hop_impulse^2 + hop_horizontal_speed^2) = sqrt(6.0^2 + 3.0^2) ~= 6.7
## m/s on a level landing, and a real BlockFactory-built cube physically
## dropped and hopped (tests/unit/test_jumping_bean_effect.gd's
## test_real_physics_hop_landing_does_not_prematurely_impact_trigger)
## measured a one-tick deceleration of ~6.55 (mass 1.0) on its first hop's
## own landing at the shared 5.0 threshold -- enough to impact-trigger the
## bean off its own hop, cutting its intended 12s lifetime down to a single
## hop, well before hop_interval_s even lets it hop again. The Bean's impact
## trigger is a pure "player smashed something into it" early-out (spec 2.6:
## "impact can still trigger it early") -- its own locomotion should never
## satisfy that path. 10.0 clears the observed ~6.55-6.7 hop-landing range
## with real margin while staying well under an actual nearby explosion
## (Bomb's own explosion_impulse = 18.0, Rocket's = 14.0, both before
## falloff -- SpecialTuning.max_explosion_impulse's clamp is 30.0), so a
## player detonating something next to a Jumping Bean can still trigger it
## early, same as every other special. This also means the bean's initial
## landing (settling for the first time) never "activates" it via impact
## either -- acceptable, since settling is what starts its own hop timer
## regardless (wants_early_trigger()/physics_tick()'s settle gate above).
##
## DECISION (game/specials/JumpingBeanEffect.gd, P5-BEAN, matches
## VolcanoEffect.gd's own precedent): a SpecialDef's `effect` is one shared
## Resource instance reused by every block spawned with this special during
## a match (autoload/match/MatchPlacement.gd's _attach_pending_special()
## binds the same cached, un-duplicated def/effect to a fresh
## SpecialBehavior each time) -- so this effect keeps NO mutable per-block
## state on itself. "Settled yet"/"seconds since first settle"/"next hop
## due at" all live in block.set_meta()/get_meta(), keyed by unique
## StringNames, the same seam every P5 sibling uses. The RNG that picks each
## hop's horizontal direction (_rng below) IS shared across every block
## using this instance, same as VolcanoEffect.gd's own _rng -- nothing
## downstream needs a hop direction to be reproducible (host-authoritative,
## replicated to clients the same way any other special's resulting
## velocity already is).

## Vertical speed (m/s) applied straight up on every hop -- spec 2.6's
## Jumping Bean row, hop strength OPEN (docs/M4_SPECIALS_PACKAGES.md
## tunables table: 6.0).
@export var hop_impulse: float = 6.0

## Horizontal speed (m/s) applied in a random direction on every hop,
## alongside hop_impulse's vertical component -- tunables table: 3.0.
@export var hop_horizontal_speed: float = 3.0

## Seconds between hops, once settled -- tunables table: 1.5.
@export var hop_interval_s: float = 1.5

## Radius (meters) of the hole punched at the position each hop leaves
## behind -- tunables table: 1.0. Forwarded to Match.punch_special_hole()
## as-is; that call is itself a no-op under HoleMode.OFF (owner decision
## Bontago-z4h, enforced there, not trusted to this caller).
@export var hole_radius_m: float = 1.0

## Seconds the punched hole stays open before TerritoryRaster's own
## hole_close_delay decay reopens it (never, under HoleMode.PERMANENT) --
## tunables table: 2.0. Forwarded to Match.punch_special_hole() as-is.
@export var hole_open_s: float = 2.0

## Seconds since first settling before this special force-triggers on its
## own -- tunables table: 12.0.
@export var lifetime_s: float = 12.0

## block.set_meta() key marking "this block has settled once" -- the same
## settle-gate seam PropellerEffect.gd's _SETTLED_META uses, and for the
## same reason (its own review-fix doc comment): re-checking block.sleeping
## every tick would see it flip false the instant the hop's own velocity
## write wakes the body, and stop hopping after the very first one.
const _SETTLED_META: StringName = &"bean_settled"

## block.set_meta() key: behavior.age() at the tick this block first
## settled -- the timed-effect pattern's "<key>_start_age".
const _START_AGE_META: StringName = &"bean_start_age"

## block.set_meta() key: elapsed-since-first-settle at which the NEXT hop is
## due. Seeded to hop_interval_s on the settling tick (the first hop is due
## one full interval after settling, not immediately), then advanced by
## hop_interval_s every time a hop actually runs -- so exactly one hop fires
## per hop_interval_s of simulated time regardless of the caller's
## delta/frame rate (a coarse enough delta can make several hops due in one
## tick; the while loop in physics_tick() below fires each in turn).
const _NEXT_HOP_META: StringName = &"bean_next_hop_at"

## Shared across every block using this effect instance (see the class doc's
## own DECISION) -- picks each hop's random horizontal direction.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## No-op until the block has settled once (Jolt's own `sleeping` flag, the
## same settle test AnvilEffect.gd/PropellerEffect.gd use) -- spec 2.6 reads
## as "hops around", which needs a resting point to hop FROM first. Once
## settled, fires every hop that is due by elapsed simulation time, each one
## punching a hole at the pre-hop position and then kicking the block into
## its next hop.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if not block.has_meta(_SETTLED_META):
		if not block.sleeping:
			return
		block.set_meta(_SETTLED_META, true)
		block.set_meta(_START_AGE_META, behavior.age())
		block.set_meta(_NEXT_HOP_META, hop_interval_s)

	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	var next_hop_at: float = float(block.get_meta(_NEXT_HOP_META))
	while elapsed >= next_hop_at:
		_hop(block)
		next_hop_at += hop_interval_s
	block.set_meta(_NEXT_HOP_META, next_hop_at)


## True once elapsed-since-first-settled reaches lifetime_s. False while
## still airborne (never settled, no start-age meta yet) -- an impact strong
## enough to satisfy SpecialBehavior's own arm_impulse check can still
## trigger this earlier, same as every other special.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(_START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	return elapsed >= lifetime_s


## No-op: the hopping already ran, tick by tick, in physics_tick() above --
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern note ("detonate()
## becomes a no-op for every P5 special"). Kept for SpecialEffect's contract.
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## One hop: punches a hole at the block's current (pre-hop) position, then
## kicks it up and sideways. Null-Field guard mirrors PropellerEffect.gd/
## AnvilEffect.gd's own (e.g. an isolated unit test that never called
## Match.register_world()) -- but here, per the dispatch brief, a missing
## Field skips BOTH the punch and the kick rather than doing one without the
## other: there is no disk-local position to punch at, and punching a hole
## without ever moving the bean (or moving it without ever punching where it
## stood) would be a hop that only half-happened. physics_tick()'s own
## elapsed-time bookkeeping still advances _NEXT_HOP_META regardless (see
## its own doc comment), so a later tick that DOES have a field keeps the
## same simulated-time cadence rather than firing a burst of catch-up hops.
func _hop(block: Block) -> void:
	var field: Field = Match.field()
	if field == null:
		return
	var local: Vector2 = field.disk_local_from_world(block.global_position)
	Match.punch_special_hole(local, hole_radius_m, hole_open_s)

	var angle: float = _rng.randf_range(0.0, TAU)
	var horizontal: Vector3 = Vector3(cos(angle), 0.0, sin(angle)) * hop_horizontal_speed
	block.linear_velocity = Vector3.UP * hop_impulse + horizontal
	block.sleeping = false
