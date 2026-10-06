class_name RadialPull
## Radial attraction module for pull-based effects (Magnet, Black hole).
##
## `pull` applies mass-proportional acceleration toward center with a configurable
## falloff curve. Includes `friction_compensation` term to overcome friction on
## static surfaces. Bodies reaching `core_radius_m` trigger an optional callback.
## No kg*m/s force cap (per-def strength is directly in acceleration).
##
## Depends on: RadialPullTuning, Block


## Body meta set once on_captured fired, so it fires once per body.
const CAPTURED_META: StringName = &"radial_pull_captured"

## Distances below this have no usable pull direction.
const EPSILON: float = 0.0001


## A callback that returns nothing (null) counts as accepted; only an explicit false refuses.
static func _accepted(result: Variant) -> bool:
	return not (result is bool and not bool(result))


## Applies radial pull to all bodies within range, with mass-proportional acceleration.
## Acceleration per body = `t.accel_mps2 * falloff` + `t.friction_compensation`.
## Bodies in `exclude` (RID list) and failing `filter(body)` are skipped.
## When a body enters `t.core_radius_m`, calls `on_captured(body)` if provided
## (return false to refuse the capture: the body is not marked and is retried).
## Returns the affected bodies.
static func pull(space: PhysicsDirectSpaceState3D, center: Vector3, t: RadialPullTuning, exclude: Array[RID], filter: Callable, delta: float, on_captured: Callable = Callable()) -> Array[RigidBody3D]:
	var affected: Array[RigidBody3D] = []
	if space == null or t == null or t.radius_m <= 0.0:
		return affected
	var candidates: Array[RigidBody3D] = ExplosionFx.query_bodies(space, center, t.radius_m, exclude)
	for body: RigidBody3D in candidates:
		if filter.is_valid() and not bool(filter.call(body)):
			continue
		var to_center: Vector3 = center - body.global_position
		var distance: float = to_center.length()
		if on_captured.is_valid() and distance <= t.core_radius_m:
			if body.has_meta(CAPTURED_META):
				continue
			# The flag is set only once the callback accepted the body: a callback
			# returning false (dissolve refused: no registry/sandbox) leaves the body
			# unmarked, so it keeps being pulled and the capture is retried.
			if _accepted(on_captured.call(body)):
				body.set_meta(CAPTURED_META, true)
				continue
		if distance <= EPSILON:
			continue
		var ratio: float = clampf(distance / t.radius_m, 0.0, 1.0)
		var falloff: float = pow(1.0 - ratio, maxf(t.falloff_exponent, 0.0))
		var accel: float = t.accel_mps2 * falloff + t.friction_compensation
		# Mass-proportional: impulse = m * a * dt, so the acceleration is mass independent.
		SpecialPhysics.wake_and_impulse(body, (to_center / distance) * accel * body.mass * delta)
		affected.append(body)
	return affected
