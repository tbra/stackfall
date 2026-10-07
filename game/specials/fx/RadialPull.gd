class_name RadialPull
## Radial attraction module for pull-based effects (Magnet, Black hole).
##
## `pull` applies mass-proportional acceleration toward center with a configurable
## falloff curve. Includes `friction_compensation` term to overcome friction on
## static surfaces. Capture is NOT done here (see BlackHoleField._sweep_capture).
## No kg*m/s force cap (per-def strength is directly in acceleration).
##
## Depends on: RadialPullTuning, Block


## Body meta BlackHoleField sets once a body was captured (dissolve accepted).
const CAPTURED_META: StringName = &"radial_pull_captured"

## Distances below this have no usable pull direction.
const EPSILON: float = 0.0001


## Applies radial pull to all bodies within range, with mass-proportional acceleration.
## Acceleration per body = `t.accel_mps2 * falloff` + `t.friction_compensation`.
## Bodies in `exclude` (RID list) and failing `filter(body)` are skipped.
## radius_scale shrinks the reach (BlackHoleField growth). Returns the affected bodies.
static func pull(space: PhysicsDirectSpaceState3D, center: Vector3, t: RadialPullTuning, exclude: Array[RID], filter: Callable, delta: float, radius_scale: float = 1.0) -> Array[RigidBody3D]:
	var affected: Array[RigidBody3D] = []
	var radius: float = t.radius_m * radius_scale if t != null else 0.0
	if space == null or radius <= 0.0:
		return affected
	var candidates: Array[RigidBody3D] = ExplosionFx.query_bodies(space, center, radius, exclude)
	for body: RigidBody3D in candidates:
		if filter.is_valid() and not bool(filter.call(body)):
			continue
		var to_center: Vector3 = center - body.global_position
		var distance: float = to_center.length()
		if distance <= EPSILON:
			continue
		var ratio: float = clampf(distance / radius, 0.0, 1.0)
		var falloff: float = pow(1.0 - ratio, maxf(t.falloff_exponent, 0.0))
		var accel: float = t.accel_mps2 * falloff + t.friction_compensation
		# Mass-proportional: impulse = m * a * dt, so the acceleration is mass independent.
		SpecialPhysics.wake_and_impulse(body, (to_center / distance) * accel * body.mass * delta)
		affected.append(body)
	return affected
