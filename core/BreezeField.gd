class_name BreezeField
extends RefCounted
## Pure Breeze rules (Bontago-470.2): where and how strongly gusts spawn, a
## gust's envelope and falloff, and the acceleration it applies to one block.
## No scene tree. Reuses core/WindField.gd's height response and dv clamp
## through BreezeTuning (a StormTuning).

## Chance a spawn attempt at `height_m` above the disc succeeds.
static func spawn_probability(height_m: float, tuning: BreezeTuning) -> float:
	return lerpf(tuning.low_spawn_probability, 1.0, WindField.height_factor(height_m, tuning))


## 0..1 strength of a gust born at `height_m` (global strength applies later).
static func gust_strength(height_m: float, tuning: BreezeTuning) -> float:
	return lerpf(tuning.low_strength_factor, 1.0, WindField.height_factor(height_m, tuning))


## Smooth 0 -> 1 -> 0 over the gust's life.
static func envelope(age_s: float, duration_s: float) -> float:
	if duration_s <= 0.0:
		return 0.0
	return sin(PI * clampf(age_s / duration_s, 0.0, 1.0))


## Smooth 1 at the centre to 0 at the radius.
static func falloff(distance_m: float, radius_m: float) -> float:
	if radius_m <= 0.0:
		return 0.0
	var t: float = clampf(1.0 - distance_m / radius_m, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## Heading (unit x,z) of a gust from its wire angle.
static func heading(angle_rad: float) -> Vector2:
	return Vector2(cos(angle_rad), sin(angle_rad))


## The push direction on a block at `rel` (block minus gust centre, x,z): the
## heading turned by swirl_deg toward the side the block is on.
static func push_direction(angle_rad: float, rel_x: float, rel_z: float, tuning: BreezeTuning) -> Vector2:
	var dir: Vector2 = heading(angle_rad)
	var side: float = signf(dir.x * rel_z - dir.y * rel_x)
	return dir.rotated(deg_to_rad(tuning.swirl_deg) * side)


## Acceleration (m/s^2, horizontal vector) one gust applies to a block at
## `block_pos`, `age_s` into its life; ZERO outside the sphere or below the
## Breeze threshold height. Already clamped per tick like Storm's.
static func gust_accel(gust: Dictionary, age_s: float, block_pos: Vector3, surface_y: float, delta: float, tuning: BreezeTuning) -> Vector3:
	var center: Vector3 = Vector3(float(gust["x"]), float(gust["y"]), float(gust["z"]))
	var rel: Vector3 = block_pos - center
	var radius: float = float(gust["r"])
	var weight: float = falloff(rel.length(), radius)
	if weight <= 0.0:
		return Vector3.ZERO
	weight *= envelope(age_s, float(gust["d"])) * clampf(float(gust["s"]), 0.0, 1.0)
	var magnitude: float = WindField.accel_at(block_pos.y - surface_y, 1.0, weight, delta, tuning) * tuning.strength
	if delta > 0.0:
		magnitude = minf(magnitude, tuning.max_dv_per_tick / delta)
	if magnitude <= 0.0:
		return Vector3.ZERO
	var dir: Vector2 = push_direction(float(gust["a"]), rel.x, rel.z, tuning)
	return Vector3(dir.x, 0.0, dir.y) * magnitude
