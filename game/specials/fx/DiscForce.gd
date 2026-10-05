class_name DiscForce
## Disc tilt module for impulse-based effects (Anvil, Propeller, Earthquake).
##
## `apply` tilts the disc toward/away from a position (sign +1 lowers the
## landing side, -1 raises it); `shake` sweeps a small tilt kick around the
## disc. Both drive Field.apply_tilt_impulse(), which already no-ops while tilt
## is disabled or the Field is a client mirror, so callers need no extra gate.
##
## Depends on: DiscForceTuning, Field


## Tilt impulse toward (sign > 0) or away from (sign < 0) `world_pos`.
## Magnitude = `t.strength` per metre of disc-local distance from the centre.
## `delta > 0` scales it for per-tick use (Propeller: strength * distance *
## delta, i.e. strength is "per metre per second"); `delta <= 0` applies it
## once (Anvil's single landing kick). A position at the disc centre, a null
## field, a zero sign or a non-finite input is a no-op.
static func apply(field: Field, world_pos: Vector3, sign: float, t: DiscForceTuning, delta: float) -> void:
	if field == null or t == null or sign == 0.0 or not is_finite(sign) or not world_pos.is_finite():
		return
	var local: Vector2 = field.disk_local_from_world(world_pos)
	var distance: float = local.length()
	if distance <= 0.0:
		return
	var magnitude: float = t.strength * distance
	if delta > 0.0:
		magnitude *= delta
	field.apply_tilt_impulse(local / distance * signf(sign), magnitude * absf(sign))


## Direction (unit, disc-local) of the shake kick `elapsed` seconds in:
## the axis sweeps `t.shake_tilt_deg` degrees per second.
static func shake_direction(t: DiscForceTuning, elapsed: float) -> Vector2:
	return Vector2.from_angle(deg_to_rad(t.shake_tilt_deg) * elapsed)


## Sweeping tilt kick for Earthquake. `elapsed` is seconds since the shake
## started; nothing is applied once it passes `t.duration_s`. The kick per
## call is `t.shake_amplitude_m * delta` (amplitude = impulse units per second,
## so the result is frame-rate independent).
static func shake(field: Field, t: DiscForceTuning, elapsed: float, delta: float) -> void:
	if field == null or t == null or delta <= 0.0 or elapsed < 0.0 or elapsed > t.duration_s:
		return
	field.apply_tilt_impulse(shake_direction(t, elapsed), t.shake_amplitude_m * delta)
