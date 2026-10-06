class_name SpecialPhysics
extends RefCounted
## Explosion impulse query helper (spec 3.5 "Explosions"; docs/M4_SPECIALS_
## PACKAGES.md P3-SH). A prerequisite for Rocket, Bomb and Volcano: none of
## those effects live here, this is just the shared sphere-query-and-push
## primitive spec 3.5 describes. Pure physics-world query + impulse
## application, no rules, no team/ownership check -- orchestrator decision
## 2026-09-23 item 1: explosions are team-agnostic for M4 ("the anvil hurt
## everyone" is original evidence; targeting is a later remake option).

## Per-call cap on how many overlapping colliders one intersect_shape() query
## returns (Godot's own max_results argument). Spec 3.5's max_active_blocks
## = 600 bounds the whole match; this is a much smaller per-explosion safety
## bound so one blast at the centre of a dense, legally-overlapping pile
## can't make a single query scan unbounded results. Read by
## ExplosionFx.query_bodies(), which owns the query loop.
const MAX_QUERY_RESULTS: int = 128

## Sphere-queries real RigidBody3D bodies within `radius` of `center` and
## returns each distinct body exactly once. Skips anything that isn't a
## RigidBody3D (the disk's AnimatableBody3D, a kinematic StaticBody3D subtype per
## game/Field.gd's own doc comment; the kill plane's Area3D is excluded by
## collide_with_areas = false) and any RID listed in `exclude`.
##
## Bontago-1pi.85.10 fix: this used to be its own capped single `intersect_shape`
## call. The disc is one ConcavePolygonShape3D and `intersect_shape` returns one hit
## per triangle, so a query near the floor filled its MAX_QUERY_RESULTS cap with disc
## triangles and missed blocks resting on the disc (reproduced with 24 cubes on a real
## Field: query_bodies_in_range()/explode() found only 5 of them).
## The one implementation of the multi-pass, per-body-deduplicated query is
## ExplosionFx.query_bodies(); this delegates so Magnet, Black hole, the legacy
## `explode()` below and the new ExplosionFx.blast() cannot drift apart again.
##
## Shared by `explode()` (impulse + wake) and `query_bodies_in_range()`
## (query-only, no impulse/wake/mark_script_kick).
static func _query_unique_bodies(
	space_state: PhysicsDirectSpaceState3D, center: Vector3, radius: float, exclude: Array[RID]
) -> Array[RigidBody3D]:
	return ExplosionFx.query_bodies(space_state, center, radius, exclude)


## Query-only sibling of `explode()` (docs/M8_PLAN.md "Interface stubs" item
## 1). Sphere-queries real RigidBody3D bodies within `radius` of `center`,
## deduped per-body exactly like `explode()`, but applies no impulse, no wake
## and no `mark_script_kick()` -- purely a read of "what bodies are in range
## right now". Consumed by the Magnet (P1), Glue (P3) and Gravity well (P4)
## specials. `owner_filter`, when a valid Callable, is called as
## `owner_filter.call(body)` for each deduped body and the body is dropped
## when it returns false; ownership semantics (e.g. `body.owner_slot !=
## mover.owner_slot` for Magnet, `==` for Glue) live entirely in the caller --
## this function and `explode()` both stay team-agnostic, per the class's own
## top-of-file DECISION.
static func query_bodies_in_range(
	space_state: PhysicsDirectSpaceState3D,
	center: Vector3,
	radius: float,
	exclude: Array[RID],
	owner_filter: Callable = Callable()
) -> Array[RigidBody3D]:
	var hit_bodies: Array[RigidBody3D] = []
	if radius <= 0.0:
		return hit_bodies

	var candidates: Array[RigidBody3D] = _query_unique_bodies(space_state, center, radius, exclude)
	for body: RigidBody3D in candidates:
		if owner_filter.is_valid() and not owner_filter.call(body):
			continue
		hit_bodies.append(body)

	return hit_bodies


## Wakes `body` and applies `impulse` to it, in the one place every special
## that hits an arbitrary RigidBody3D with an impulse (explode() below,
## MagnetEffect.physics_tick()) should do it from (Bontago-8or.16 P5b).
##
## DECISION (game/specials/SpecialPhysics.gd): a block long enough at rest
## gets frozen to FREEZE_MODE_STATIC by game/StableBlockManager.gd (spec 3.5's
## "stable-block optimization"), and RigidBody3D silently ignores
## apply_impulse()/`sleeping = false` on a STATIC body -- so without first
## calling Block.wake_for_impulse(), an explosion, Magnet pull or Anvil hit
## against a long-stable stack would do nothing at all. `body` is only
## guaranteed to be a plain RigidBody3D by this class's own Block-agnostic
## contract (top-of-file DECISION) -- only a Block actually has
## wake_for_impulse()/mark_script_kick(), so both are gated behind the `as
## Block` cast and a no-op for any other RigidBody3D (e.g. this file's own
## test fixtures). wake_for_impulse() only ever releases
## Block.FREEZE_REASON_STABLE (see its own doc comment on game/Block.gd) --
## a block still held frozen by some other reason (e.g. a future Freeze
## special) stays frozen and apply_impulse() below remains a no-op for it,
## exactly as before this fix; unsticking StableBlockManager's own
## auto-freeze is all this helper is asked to do.
static func wake_and_impulse(body: RigidBody3D, impulse: Vector3) -> void:
	var kicked_block: Block = body as Block
	if kicked_block != null:
		kicked_block.wake_for_impulse()
		# Bontago-8or.2: a block still held by the Freeze special ignores the
		# impulse entirely (no pending kick left behind for after release).
		if kicked_block.is_freeze_static():
			return
	if kicked_block != null:
		kicked_block.wake()
	else:
		body.sleeping = false
	# DECISION (Bontago-1pi.85.10): a CENTRAL impulse. apply_impulse(impulse) acts at the body's
	# origin, which for a Block is the middle of its bottom face, below the centre of mass, so a
	# horizontal blast on a block lying on the disc spun it onto an edge and the floor contact ate
	# about 40% of the horizontal speed while adding a spurious pop upward (measured: a cube 2.2 m
	# from a 12 m/s Bomb left at 2.9 m/s outward instead of 4.7). The linear delta-v
	# (impulse / mass) is the same either way; only the unwanted torque goes.
	body.apply_central_impulse(impulse)
	# Review fix (Bontago-xtq.17 SHOULD-FIX 1): an airborne block's knockback
	# can flip its vertical velocity from falling to rising exactly like a
	# real bounce would -- mark it as a script kick so Block._integrate_
	# forces() doesn't scale it by PhysicsTuning.rebound_damping on top of
	# the caller's own falloff/clamp.
	if kicked_block != null:
		kicked_block.mark_script_kick()


## Sphere-queries real RigidBody3D bodies within `radius` of `center`, wakes
## each, and applies an outward impulse with spec 3.5's falloff, clamped to
## `max_impulse`. See `_query_unique_bodies()` for the shared sphere-query +
## dedupe this builds on. Returns the bodies actually hit.
static func explode(
	space_state: PhysicsDirectSpaceState3D,
	center: Vector3,
	radius: float,
	impulse: float,
	max_impulse: float,
	exclude: Array[RID] = []
) -> Array[RigidBody3D]:
	var hit_bodies: Array[RigidBody3D] = []
	var candidates: Array[RigidBody3D] = _query_unique_bodies(space_state, center, radius, exclude)

	for body: RigidBody3D in candidates:
		var offset: Vector3 = body.global_position - center
		var distance: float = offset.length()
		var direction: Vector3
		if distance <= 0.0001:
			# DECISION (game/specials/SpecialPhysics.gd): a body exactly at
			# the epicentre has no well-defined outward direction; pick a
			# fixed one (straight up) rather than a random or zero vector,
			# so the same input is always deterministic and still gives the
			# body a real push instead of none.
			direction = Vector3.UP
		else:
			direction = offset / distance

		# DECISION (game/specials/SpecialPhysics.gd): clamp the falloff's
		# distance ratio to [0, 1] before squaring. Spec 3.5's formula is
		# `pow(1.0 - d/radius, 2.0)`, which is exact for a point at the
		# query sphere's centre or edge; intersect_shape() can still return
		# a wide body whose *origin* sits just past `radius` while one edge
		# of its own collision shape still overlaps the query sphere. Left
		# unclamped, `d/radius` slightly above 1.0 still yields a small
		# positive (squared) push rather than the intended near-zero one --
		# clamping keeps the falloff monotonic and zero exactly at the edge
		# without changing any in-radius result (ratio already in [0, 1]
		# there).
		var ratio: float = clampf(distance / radius, 0.0, 1.0)
		var falloff: float = pow(1.0 - ratio, 2.0)
		var magnitude: float = clampf(impulse * falloff, 0.0, max_impulse)

		# wake_and_impulse() releases Block.FREEZE_REASON_STABLE first (see its
		# own doc comment above) so a long-stable, STATIC-frozen block still
		# receives this impulse instead of silently ignoring it (Bontago-
		# 8or.16 P5b), then applies the impulse and marks a script kick the
		# same way this function always has.
		wake_and_impulse(body, direction * magnitude)
		hit_bodies.append(body)

	return hit_bodies
