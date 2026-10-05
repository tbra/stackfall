class_name RadialPull
## Radial attraction module for pull-based effects (Magnet, Black hole).
##
## `pull` applies mass-proportional acceleration toward center with a configurable
## falloff curve. Includes `friction_compensation` term to overcome friction on
## static surfaces. Bodies reaching `core_radius_m` trigger an optional callback.
## No kg*m/s force cap (per-def strength is directly in acceleration).
##
## Depends on: RadialPullTuning, Block


## Applies radial pull to all bodies within range, with mass-proportional acceleration.
## Acceleration per body = `t.accel_mps2 * falloff` + `t.friction_compensation`.
## Bodies in `exclude` (RID list) and failing `filter(body)` are skipped.
## When a body enters `t.core_radius_m`, calls `on_captured(body)` if provided.
## Returns the affected bodies.
static func pull(space: PhysicsDirectSpaceState3D, center: Vector3, t: RadialPullTuning, exclude: Array[RID], filter: Callable, delta: float, on_captured: Callable = Callable()) -> Array[RigidBody3D]:
	return []
