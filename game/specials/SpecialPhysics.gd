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
## can't make a single query scan unbounded results.
const MAX_QUERY_RESULTS: int = 128

## Sphere-queries real RigidBody3D bodies within `radius` of `center` and
## returns each distinct body exactly once (see `_query_unique_bodies()`'s own
## doc comment for the multi-shape dedupe this relies on). Skips anything that
## isn't a RigidBody3D (the disk's AnimatableBody3D -- a kinematic
## StaticBody3D subtype per game/Field.gd's own doc comment -- and the kill
## plane's Area3D, which collide_with_areas = false already excludes) and any
## RID listed in `exclude`.
##
## Shared by `explode()` (impulse + wake) and `query_bodies_in_range()`
## (query-only, no impulse/wake/mark_script_kick) so the sphere-query and
## per-body dedupe logic exists in exactly one place.
static func _query_unique_bodies(
	space_state: PhysicsDirectSpaceState3D, center: Vector3, radius: float, exclude: Array[RID]
) -> Array[RigidBody3D]:
	var hit_bodies: Array[RigidBody3D] = []
	if space_state == null or radius <= 0.0:
		return hit_bodies

	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	# DECISION (game/specials/SpecialPhysics.gd): the brief asks for a
	# collision mask naming "the placed-block layer", but nothing in this
	# project sets a distinguishing physics layer -- grep across game/,
	# config/, core/ turns up none, and game/PlayerController.gd already
	# recorded the same finding (its own "Ghost-vs-placed-block collision"
	# DECISION) rather than editing project.godot's physics layers, which
	# neither that package nor this one owns (tools/bootstrap_project.gd
	# does). So this filters by node type below (`as RigidBody3D`), exactly
	# that precedent's technique, on the engine's default mask (every body
	# still collides on layer/mask 1). Filed under Unresolved for a future
	# dedicated layer.
	params.exclude = exclude

	var overlaps: Array[Dictionary] = space_state.intersect_shape(params, MAX_QUERY_RESULTS)
	# DECISION (game/specials/SpecialPhysics.gd): intersect_shape() returns one
	# Dictionary per overlapping CollisionShape3D, not per body, and
	# BlockFactory.build() gives every placed block one CollisionShape3D per
	# cell (game/BlockFactory.gd lines ~86-93: domino has 2, slab6 has 6). Left
	# undeduplicated, a multi-cell block within range would be returned once
	# per one of its own cells -- up to 6x the intended per-body effect (an
	# explosion impulse, or a Magnet/Glue/Gravity-well hit count). Track
	# visited bodies by instance id (RigidBody3D has no Comparable identity
	# other than object identity/RID) and skip every shape after a body's
	# first, so each distinct body is returned exactly once -- matching a
	# body-level sphere query the way spec 3.5 describes it.
	var seen_body_ids: Dictionary = {}
	for overlap: Dictionary in overlaps:
		var body: RigidBody3D = overlap.get("collider") as RigidBody3D
		if body == null:
			continue
		var rid: RID = overlap.get("rid") as RID
		if exclude.has(rid):
			continue  # belt-and-suspenders: params.exclude should already drop these

		var body_id: int = body.get_instance_id()
		if seen_body_ids.has(body_id):
			continue
		seen_body_ids[body_id] = true
		hit_bodies.append(body)

	return hit_bodies


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

		body.sleeping = false
		body.apply_impulse(direction * magnitude)
		# Review fix (Bontago-xtq.17 SHOULD-FIX 1): an airborne block's
		# explosion knockback can flip its vertical velocity from falling to
		# rising exactly like a real bounce would -- mark it as a script kick
		# so Block._integrate_forces() doesn't scale it by
		# PhysicsTuning.rebound_damping on top of this function's own falloff/
		# clamp. `body` is only known as a plain RigidBody3D here (this
		# function is Block-agnostic, see its own class doc), so cast rather
		# than call kick()/mark_script_kick() unconditionally.
		var kicked_block: Block = body as Block
		if kicked_block != null:
			kicked_block.mark_script_kick()
		hit_bodies.append(body)

	return hit_bodies
