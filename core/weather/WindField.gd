class_name WindField
extends RefCounted
## Pure wind rules (Bontago-22y.4): direction, gust and the height response.
## No scene tree; the host effect and the client presentation both call these
## NOTE (470.1): typed on StormTuning (the Storm rename). A future always-on
## Breeze reuses these rules by extending StormTuning with its own numbers.
## with the replicated match seed so they agree on the wind.

## Salts splitting a seed into independent phases. Architecture only.
const PHASE_SALT_A: int = 7919
const PHASE_SALT_B: int = 104729
const PHASE_SALT_C: int = 1299709
const PHASE_RES: int = 10000
## Weight of the second gust harmonic; the first takes the rest.
const HARMONIC_WEIGHT: float = 0.35
## The second gust harmonic runs at this multiple of the base gust frequency.
const HARMONIC_RATIO: float = 2.7


static func _phase(seed_value: int, salt: int) -> float:
	return float(absi(hash(seed_value * salt + salt)) % PHASE_RES) / float(PHASE_RES)


## Seed for one event: the schedule seed mixed with the event's ordinal, so
## every event blows from its own direction yet every peer agrees.
static func event_seed(match_seed: int, event_index: int) -> int:
	return hash(match_seed * PHASE_SALT_C + event_index * PHASE_SALT_B + event_index)


## Base heading (radians about +Y, on the XZ plane) for a match seed.
static func base_angle(seed_value: int) -> float:
	return _phase(seed_value, PHASE_SALT_A) * TAU


## Horizontal unit direction (x, z) at `elapsed` seconds into the event.
static func direction(seed_value: int, elapsed: float, tuning: StormTuning) -> Vector2:
	var veer: float = 0.0
	if tuning.veer_period_s > 0.0:
		veer = deg_to_rad(tuning.veer_amplitude_deg) * sin(
			TAU * (elapsed / tuning.veer_period_s + _phase(seed_value, PHASE_SALT_B)))
	var angle: float = base_angle(seed_value) + veer
	return Vector2(cos(angle), sin(angle))


## Gust multiplier in [1 - gust_amplitude, 1]: smooth and seeded.
static func gust(seed_value: int, elapsed: float, tuning: StormTuning) -> float:
	if tuning.gust_period_s <= 0.0:
		return 1.0
	var t: float = elapsed / tuning.gust_period_s
	var wave: float = (1.0 - HARMONIC_WEIGHT) * sin(TAU * (t + _phase(seed_value, PHASE_SALT_C))) \
		+ HARMONIC_WEIGHT * sin(TAU * (t * HARMONIC_RATIO + _phase(seed_value, PHASE_SALT_A)))
	var unit: float = clampf(0.5 + 0.5 * wave, 0.0, 1.0)
	return 1.0 - tuning.gust_amplitude * (1.0 - unit)


## 0 at/below the threshold, 1 at/above the cap, monotonic between.
static func height_factor(height_m: float, tuning: StormTuning) -> float:
	if height_m <= tuning.threshold_height_m:
		return 0.0
	var span: float = tuning.cap_height_m - tuning.threshold_height_m
	if span <= 0.0:
		return 1.0
	return pow(clampf((height_m - tuning.threshold_height_m) / span, 0.0, 1.0), tuning.height_exponent)


## Acceleration magnitude (m/s^2) on a block at `height_m`, already clamped so
## one tick never changes velocity by more than max_dv_per_tick.
static func accel_at(height_m: float, intensity: float, gust_mult: float, delta: float, tuning: StormTuning) -> float:
	var accel: float = tuning.max_accel * clampf(intensity, 0.0, 1.0) * gust_mult * height_factor(height_m, tuning)
	if delta > 0.0:
		accel = minf(accel, tuning.max_dv_per_tick / delta)
	return accel
