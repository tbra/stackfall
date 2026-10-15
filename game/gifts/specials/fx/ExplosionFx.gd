class_name ExplosionFx
## Physics-based explosion module for blast effects (Bomb, Rocket, Volcano orbs).
##
## `blast` applies mass-proportional impulse in outward direction with upward bias,
## using a configurable falloff curve. Impulse is capped per delta-v (not kg*m/s),
## making strength independent of block mass. `chain` is a helper to trigger
## nearby specials in a chain reaction.
##
## Depends on: ExplosionTuning, SpecialPhysics, Block, SpecialBehavior


## Distances below this count as the epicentre (blast goes straight up).
const EPSILON: float = 0.0001


## Applies an explosion from center, imparting delta-v to each hit body.
## Delta-v per body = `t.peak_speed_mps * falloff(ratio, t.falloff_exponent)` along
## (outward + `t.upward_bias` up), clamped to `t.max_delta_v_mps`.
## Bodies in `exclude` (RID list) are skipped. Wakes STATIC-frozen blocks via
## SpecialPhysics.wake_and_impulse. Returns the affected bodies.
static func blast(space: PhysicsDirectSpaceState3D, center: Vector3, t: ExplosionTuning, exclude: Array[RID]) -> Array[RigidBody3D]:
	var hit: Array[RigidBody3D] = []
	if space == null or t == null or t.radius_m <= 0.0:
		return hit
	var candidates: Array[RigidBody3D] = query_bodies(space, center, t.radius_m, exclude)
	for body: RigidBody3D in candidates:
		var offset: Vector3 = body.global_position - center
		var distance: float = offset.length()
		var direction: Vector3 = Vector3.UP
		if distance > EPSILON:
			direction = offset / distance
		var ratio: float = clampf(distance / t.radius_m, 0.0, 1.0)
		var falloff: float = pow(1.0 - ratio, maxf(t.falloff_exponent, 0.0))
		var delta_v: float = clampf(t.peak_speed_mps * falloff, 0.0, t.max_delta_v_mps)
		if delta_v <= 0.0:
			continue
		var biased: Vector3 = (direction + Vector3.UP * t.upward_bias).normalized()
		# Mass-proportional impulse: the resulting delta-v is mass independent.
		SpecialPhysics.wake_and_impulse(body, biased * delta_v * body.mass)
		hit.append(body)
	return hit


## Chain trigger helper: triggers all specials within `radius` of `center` at the
## given `depth` in the chain. Respects max_chain_depth via behavior.
static func chain(behavior: SpecialBehavior, center: Vector3, radius: float, depth: int) -> void:
	if behavior == null:
		return
	behavior.trigger_others_in_range(center, radius, depth)


## Safety bound on query passes in `query_bodies` (disc, beacon, flags: a handful).
const MAX_QUERY_PASSES: int = 4

## Sphere-queries distinct RigidBody3D bodies within `radius` of `center`.
## The disc is one ConcavePolygonShape3D, and `intersect_shape` returns one hit per
## triangle, so a single capped query near the floor fills with disc triangles and
## misses blocks (reproduced: a resting block 6 m from an 8 m query was never found).
## Each pass therefore adds every non-RigidBody collider it saw to the exclude list and
## queries again, until a pass reports nothing new to exclude.
static func query_bodies(
	space: PhysicsDirectSpaceState3D, center: Vector3, radius: float, exclude: Array[RID]
) -> Array[RigidBody3D]:
	var bodies: Array[RigidBody3D] = []
	if space == null or radius <= 0.0:
		return bodies
	var shape: SphereShape3D = SphereShape3D.new()
	shape.radius = radius
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = shape
	params.transform = Transform3D(Basis.IDENTITY, center)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	var excluded: Array[RID] = exclude.duplicate()
	var seen: Dictionary = {}
	for _pass: int in MAX_QUERY_PASSES:
		params.exclude = excluded
		var overlaps: Array[Dictionary] = space.intersect_shape(params, SpecialPhysics.MAX_QUERY_RESULTS)
		var found_other: bool = false
		for overlap: Dictionary in overlaps:
			var body: RigidBody3D = overlap.get("collider") as RigidBody3D
			var rid: RID = overlap.get("rid") as RID
			if body == null:
				if not excluded.has(rid):
					excluded.append(rid)
					found_other = true
				continue
			var body_id: int = body.get_instance_id()
			if seen.has(body_id):
				continue
			seen[body_id] = true
			bodies.append(body)
		if not found_other:
			break
	return bodies
