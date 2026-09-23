class_name VolcanoEffect
extends SpecialEffect
## Volcano special (spec 2.6: "erupts, launching a spray of small lava-orb
## blocks that each explode"). See docs/M4_SPECIALS_PACKAGES.md's P4-VOLCANO
## package. Follows that doc's "timed-effect pattern" for the eruption window
## (physics_tick()/wants_early_trigger() gated on elapsed-since-armed, exactly
## like EarthquakeEffect.gd/PropellerEffect.gd), but instead of shaking/
## tilting the field, each tick spawns however many of this eruption's own
## lava orbs are "due" by simulation time -- so exactly `orb_count` orbs spawn
## over `eruption_duration_s`, frame-rate independent. `detonate()` is a
## no-op: the eruption already ran, tick by tick, in physics_tick() (the same
## reasoning as every other P5 timed effect).
##
## DECISION (game/specials/VolcanoEffect.gd, docs/M4_SPECIALS_PACKAGES.md
## P4-VOLCANO): a SpecialDef's `effect` is one shared Resource instance reused
## by every block spawned with this special during a match (autoload/match/
## MatchPlacement.gd's _attach_pending_special() binds the same cached,
## un-duplicated def/effect to a fresh SpecialBehavior each time) -- so this
## effect keeps NO mutable per-block eruption state on itself. "Orb count for
## this eruption", "seconds since armed" and "orbs spawned so far" all live in
## block.set_meta()/get_meta(), exactly the timed-effect pattern's own seam
## (RocketEffect.gd/PropellerEffect.gd). Two blocks sharing this very instance
## therefore keep fully independent eruptions, one per block. The RNG used to
## pick each eruption's orb_count and each orb's cone direction (_rng below)
## IS shared across every block using this instance -- docs/M4_SPECIALS_
## PACKAGES.md's own P4-VOLCANO brief explicitly allows this ("RNG on the
## shared instance is fine"), unlike the per-block meta state above.
##
## DECISION (game/specials/VolcanoEffect.gd, P4-VOLCANO): "the volcano's own
## explosion_impulse-equivalent" the brief asks each orb's blast impulse to be
## a fraction of has no dedicated export of its own anywhere in this package's
## contract or docs/M4_SPECIALS_PACKAGES.md's tunables table (unlike Bomb/
## Rocket, which each declare their own `explosion_impulse`) -- and that same
## table describes `orb_explosion_radius`/`orb_explosion_impulse_fraction` as
## "orb split of one spec number" (singular), naming no second number. Reads
## as: `orb_impulse` (the eruption's own single spec 2.6 number, already an
## impulse-flavoured launch magnitude) IS that one spec number, and this
## package's `orb_explosion_radius`/`orb_explosion_impulse_fraction` split it
## into an orb's own blast radius and blast-impulse fraction. So each orb's
## `VolcanoOrbEffect.explosion_impulse` is set to `orb_impulse *
## orb_explosion_impulse_fraction` (6.0 * 0.5 = 3.0 by default) -- see
## _orb_special_def() below -- rather than adding a new, contract-silent
## export.
##
## DECISION (game/specials/VolcanoEffect.gd, P4-VOLCANO): the contract's own
## export list (tuning, eruption_duration_s, min/max_orb_count, orb_impulse,
## cone_angle_deg, orb_explosion_radius, orb_explosion_impulse_fraction) names
## no spawn-clearance value, but CLAUDE.md's "no magic numbers -- every
## tunable value belongs in a Resource" rules out a bare literal for one.
## `orb_spawn_clearance_m` below fills that gap as one more @export. (Prior
## revision note, corrected by review Bontago-1en.3: this was misattributed
## to "the contract's own prose" quoting text that does not actually appear
## in docs/M4_SPECIALS_PACKAGES.md or this package's dispatch brief -- the
## gap is CLAUDE.md's tunables rule alone, not a quoted spec line.)
##
## FIX (game/specials/VolcanoEffect.gd, Bontago-1en.3 review): the field used
## to be `orb_spawn_height_offset_m` (1.0 m) added directly to
## `block.global_position`, which is always the shape's *bottom*-face centre
## (game/BlockFactory.gd's own convention) -- correct only for a single-cube
## shape. A special can be bound to any shape (a pillar/L4 stacks cells up to
## y=2, top ~2.5 m above that bottom centre), so on those shapes the old
## formula spawned an orb *inside* the volcano's own collision box: Jolt
## depenetration then kicked it, and since VolcanoOrbEffect's arm_delay is 0,
## the kick's impact speed could detonate that orb immediately and chain
## back into the still-erupting volcano. _spawn_orb() below now measures the
## block's actual current collision top (_collision_top_y(), read from its
## live CollisionShape3D children, exact for any shape/orientation, mirroring
## how game/GhostPreview.gd's _rotated_top_offset() finds a *held* shape's
## rotated top from BlockShape.cells) and adds `orb_spawn_clearance_m` above
## that as a small clearance gap, not a spawn-height offset from the block's
## origin. Default dropped from 1.0 m to 0.25 m accordingly -- the old 1.0 m
## was sized to clear a cube's whole height from its *origin*; measured from
## the real top instead, a much smaller clearance already keeps the orb's own
## small collision box clear.

## Reaches config/special_tuning.tres the same way BombEffect.gd/
## RocketEffect.gd do -- see BombEffect.gd's own field comment for the full
## DECISION. Also handed to every orb's own VolcanoOrbEffect (_orb_special_def()
## below) so an orb's explosion respects the same max_explosion_impulse clamp.
@export var tuning: SpecialTuning = preload("res://config/special_tuning.tres")

## Seconds the eruption runs, once armed, before this special force-triggers
## on its own -- spec 2.6's Volcano row (docs/M4_SPECIALS_PACKAGES.md tunables
## table: 3.0).
@export var eruption_duration_s: float = 3.0

## Fewest lava orbs one eruption spawns (tunables table: 8).
@export var min_orb_count: int = 8

## Most lava orbs one eruption spawns (tunables table: 14).
@export var max_orb_count: int = 14

## Launch speed (m/s) each lava orb leaves the volcano at, and (see the
## DECISION above) the single spec 2.6 number `orb_explosion_radius`/
## `orb_explosion_impulse_fraction` split an orb's own blast out of --
## tunables table: 6.0.
@export var orb_impulse: float = 6.0

## Half-angle, in degrees, of the cone around world-up each orb's launch
## direction is drawn from -- tunables table: 35.0.
@export var cone_angle_deg: float = 35.0

## Each orb's own explosion radius in meters, once it detonates -- tunables
## table: 1.5, NEW ("orb split of one spec number").
@export var orb_explosion_radius: float = 1.5

## Fraction of `orb_impulse` an orb's own explosion impulse uses -- tunables
## table: 0.5, NEW ("orb split of one spec number"). See the DECISION above.
@export var orb_explosion_impulse_fraction: float = 0.5

## Meters of clearance an orb spawns *above* the erupting block's own actual
## collision top (see _collision_top_y() below), not above its origin -- so
## it never spawns inside the volcano's own collision box regardless of
## shape/orientation. NEW, see the DECISION/FIX above. Renamed from
## `orb_spawn_height_offset_m` (Bontago-1en.3 review fix).
@export var orb_spawn_clearance_m: float = 0.25

## Cached lava-orb shape (NIT, Bontago-1en.3 review): preload() resolves once
## at parse time and is shared by every _spawn_orb() call, instead of the
## previous revision's `load("res://config/blocks/cube.tres")` running the
## resource loader again for every single orb of every eruption.
@export var orb_shape: BlockShape = preload("res://config/blocks/cube.tres")

## The 8 sign combinations of a box's local half-extents -- used by
## _collision_top_y()/_shape_local_corners() below to find a BoxShape3D's
## world-space corners, the same technique game/GhostPreview.gd's own
## _CORNER_SIGNS/_rotated_top_offset() use against BlockShape.cells.
const _CORNER_SIGNS: Array[Vector3] = [
	Vector3(-1.0, -1.0, -1.0), Vector3(1.0, -1.0, -1.0), Vector3(-1.0, 1.0, -1.0), Vector3(1.0, 1.0, -1.0),
	Vector3(-1.0, -1.0, 1.0), Vector3(1.0, -1.0, 1.0), Vector3(-1.0, 1.0, 1.0), Vector3(1.0, 1.0, 1.0),
]

## block.set_meta() key: behavior.age() at the tick this block first armed --
## the timed-effect pattern's "<key>_start_age".
const _START_AGE_META: StringName = &"volcano_start_age"

## block.set_meta() key: this eruption's own orb_count, drawn once on the
## first armed tick and cached so every later tick reads the same value.
const _ORB_COUNT_META: StringName = &"volcano_orb_count"

## block.set_meta() key: how many of this eruption's orbs have been spawned
## so far -- physics_tick() spawns the difference between this and however
## many are "due" by elapsed simulation time each tick.
const _SPAWNED_META: StringName = &"volcano_orbs_spawned"

## Shared across every block using this effect instance (see the class doc's
## DECISION) -- picks each eruption's orb_count and each orb's cone direction.
## Never reseeded explicitly: host-authoritative spawns replicate their
## resulting position/velocity to clients the same way any other special
## projectile does (Match.spawn_special_projectile()'s own
## BlockFactory.build -> Events.block_placed -> replicate_spawn pipeline), so
## nothing downstream needs this draw to be reproducible.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Built once (see the class doc's own DECISION on "built once") and reused
## by every orb this effect instance ever spawns, across every block/eruption
## that shares it -- one VolcanoOrbEffect, one wrapping SpecialDef, cached
## lazily on first use rather than at resource-load time (this Resource may
## be duplicated from a .tres before tuning/orb_impulse/... are actually set,
## so building it eagerly in _init() could freeze stale numbers).
var _orb_def: SpecialDef = null


## Every armed tick: on the very first one, seed this block's own start-age
## and draw its eruption's orb_count; every tick after, spawn however many
## orbs are "due" by elapsed simulation time (elapsed / (eruption_duration_s /
## orb_count)), so exactly orb_count orbs spawn over the whole window
## regardless of the caller's delta/frame rate.
func physics_tick(block: Block, behavior: SpecialBehavior, _delta: float) -> void:
	if not block.has_meta(_START_AGE_META):
		block.set_meta(_START_AGE_META, behavior.age())
		block.set_meta(_ORB_COUNT_META, _rng.randi_range(min_orb_count, max_orb_count))
		block.set_meta(_SPAWNED_META, 0)

	var orb_count: int = int(block.get_meta(_ORB_COUNT_META))
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	var slice_s: float = eruption_duration_s / float(orb_count) if orb_count > 0 else eruption_duration_s
	var due: int = orb_count if slice_s <= 0.0 else clampi(int(floor(elapsed / slice_s)), 0, orb_count)

	# FIX (game/specials/VolcanoEffect.gd, Bontago-1en.3 review): _spawn_orb()
	# now returns the spawned Block, or null if Match.spawn_special_projectile()
	# refused (off-host, not PLAYING, or no field -- docs/M4_SPECIALS_
	# PACKAGES.md's own "handle it without error"). The previous revision
	# incremented `spawned` unconditionally, so a spawn failure silently lost
	# that orb forever: `due` (driven by simulation time alone) kept climbing
	# regardless, `spawned` kept pace with it either way, and by the time the
	# window closed both read `orb_count` even though fewer real Blocks ever
	# existed. Only a *successful* spawn now advances `spawned`; a failure
	# breaks out of this tick's loop so the meta count stays exactly equal to
	# the number of real Blocks spawned so far, and the next tick (while the
	# eruption window is still open) retries the still-missing orb(s).
	# DECISION: an orb still "due" when the eruption window fully closes
	# (wants_early_trigger() -> true -> SpecialBehavior.trigger() ->
	# detonate(), a no-op) is simply never spawned -- there is no later tick
	# left to retry it on. Acceptable: this only fires for the same host-down/
	# not-PLAYING/no-field conditions that already make every other special
	# projectile spawn silently no-op elsewhere in this package.
	var spawned: int = int(block.get_meta(_SPAWNED_META))
	while spawned < due:
		var orb: Block = _spawn_orb(block)
		if orb == null:
			break
		spawned += 1
	block.set_meta(_SPAWNED_META, spawned)


## True once elapsed-since-armed reaches eruption_duration_s. An impact
## strong enough to satisfy SpecialBehavior's own arm_impulse check can still
## trigger this earlier, same as every other special.
func wants_early_trigger(block: Block, behavior: SpecialBehavior) -> bool:
	if not block.has_meta(_START_AGE_META):
		return false
	var elapsed: float = behavior.age() - float(block.get_meta(_START_AGE_META))
	return elapsed >= eruption_duration_s


## No-op: the eruption already ran, tick by tick, in physics_tick() above --
## docs/M4_SPECIALS_PACKAGES.md's timed-effect pattern note ("detonate()
## becomes a no-op for every P5 special"; Volcano follows the same pattern
## even though it lands with P3-P4's dependencies rather than P5's).
func detonate(_block: Block, _behavior: SpecialBehavior, _chain_depth: int) -> void:
	pass


## Draws one orb's launch direction inside a cone_angle_deg half-angle cone
## around world-up: azimuth uniform over the full circle, polar angle uniform
## over [0, cone_angle_deg] (biased toward the cone's edge in solid-angle
## terms, same simple approach RocketEffect/PropellerEffect's own directional
## picks use elsewhere in this package's siblings -- exact distribution is
## spec-OPEN, "roughly upward" is all 2.6 asks for).
func _random_cone_direction() -> Vector3:
	var azimuth: float = _rng.randf_range(0.0, TAU)
	var polar: float = deg_to_rad(_rng.randf_range(0.0, cone_angle_deg))
	var sin_polar: float = sin(polar)
	return Vector3(sin_polar * cos(azimuth), cos(polar), sin_polar * sin(azimuth))


## Builds and spawns one lava orb via Match.spawn_special_projectile() --
## host-only; off-host (or not PLAYING, or no field) this returns null and
## the caller (physics_tick()) handles that without error, per docs/M4_
## SPECIALS_PACKAGES.md's own brief ("Off-host spawn_special_projectile
## returns null -- handle it without error"). Returns the spawned Block (or
## null) rather than nothing, so physics_tick() above only counts real
## successes toward _SPAWNED_META (Bontago-1en.3 review fix).
##
## FIX (Bontago-1en.3 review): origin is now `_collision_top_y(block) +
## orb_spawn_clearance_m` on top of the block's own X/Z, not
## `block.global_position + UP * orb_spawn_height_offset_m` -- see the class
## doc's FIX/DECISION and orb_spawn_clearance_m's own doc comment for why the
## old formula spawned an orb inside a multi-cell shape's (pillar/L4) own
## collision.
func _spawn_orb(block: Block) -> Block:
	var direction: Vector3 = _random_cone_direction()
	var velocity: Vector3 = direction * orb_impulse
	var origin: Vector3 = Vector3(
		block.global_position.x,
		_collision_top_y(block) + orb_spawn_clearance_m,
		block.global_position.z
	)
	return Match.spawn_special_projectile(
		orb_shape, origin, Basis.IDENTITY, block.owner_slot, velocity, _orb_special_def(), tuning
	)


## The block's own current world-space top Y, read from its actual
## CollisionShape3D children (built by game/BlockFactory.gd, one per shape
## cell, already positioned/rotated by the block's live global_transform)
## rather than reconstructed from BlockShape.cells + a cached PhysicsTuning --
## exact for any shape/orientation a special happens to be bound to. Mirrors
## game/GhostPreview.gd's own _rotated_top_offset(), but against a spawned
## block's real collision boxes instead of a *held* shape's cells. Falls back
## to the block's own origin (global_position.y) if it somehow has no
## CollisionShape3D children, matching the previous revision's floor.
func _collision_top_y(block: Block) -> float:
	var max_y: float = -INF
	for child: Node in block.get_children():
		if not (child is CollisionShape3D):
			continue
		var collision: CollisionShape3D = child as CollisionShape3D
		if collision.shape == null:
			continue
		for corner: Vector3 in _shape_local_corners(collision.shape):
			max_y = maxf(max_y, (collision.global_transform * corner).y)
	return block.global_position.y if max_y == -INF else max_y


## Local-space extreme points of `shape` (in its own CollisionShape3D
## parent's local frame) worth transforming to world space to find a block's
## collision top -- BoxShape3D (every shipped BlockShape's own collision,
## game/BlockFactory.gd's `_make_collision_shape()`) needs all 8 corners;
## ConvexPolygonShape3D (that same function's dead sloped-cell branch, kept
## around per its own comment -- no shipped shape uses it today) already
## stores every vertex the hull needs, so its own points suffice unchanged.
## Empty for any other/null shape -- _collision_top_y() above then simply
## contributes nothing from that child.
func _shape_local_corners(shape: Shape3D) -> Array[Vector3]:
	if shape is BoxShape3D:
		var half: Vector3 = (shape as BoxShape3D).size * 0.5
		var corners: Array[Vector3] = []
		for sign_combo: Vector3 in _CORNER_SIGNS:
			corners.append(half * sign_combo)
		return corners
	if shape is ConvexPolygonShape3D:
		var points: PackedVector3Array = (shape as ConvexPolygonShape3D).points
		var out: Array[Vector3] = []
		for point: Vector3 in points:
			out.append(point)
		return out
	return []


## Lazily builds (once) the shared SpecialDef+VolcanoOrbEffect pair every
## lava orb this effect instance spawns is bound to -- see the class doc's
## own DECISION for why arm_delay is 0 and explosion_impulse is derived from
## orb_impulse rather than a new export.
func _orb_special_def() -> SpecialDef:
	if _orb_def != null:
		return _orb_def
	var orb_effect: VolcanoOrbEffect = VolcanoOrbEffect.new()
	orb_effect.tuning = tuning
	orb_effect.explosion_radius = orb_explosion_radius
	orb_effect.explosion_impulse = orb_impulse * orb_explosion_impulse_fraction
	var def: SpecialDef = SpecialDef.new()
	def.id = &"volcano_orb"
	def.arm_delay = 0.0
	def.effect = orb_effect
	_orb_def = def
	return _orb_def
