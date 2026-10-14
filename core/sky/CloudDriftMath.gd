class_name CloudDriftMath
extends RefCounted
## Bontago-mp0.92: pure rules of the shared cloud drift (no scene tree). Every cloud layer's
## motion is the integrated wind (CloudDriftState.offset) times the clump's own rate, so
## layers at different depths slide at different speeds and the cloud shadows follow the
## very same vector.

const KIND_UPPER: StringName = &"upper"
const KIND_SEA: StringName = &"sea"
const KIND_BANK: StringName = &"bank"
const KIND_FAR: StringName = &"far"
## Salt keeping the calm-heading draw independent of the other seed users.
const HEADING_SALT: int = 15485863
const HEADING_RES: int = 10000


## Depth multiplier of a layer kind (nearer = faster).
static func layer_rate(kind: StringName, config: CloudDriftConfig) -> float:
	match kind:
		KIND_UPPER:
			return config.upper_rate
		KIND_BANK:
			return config.bank_rate
		KIND_FAR:
			return config.far_rate
	return config.sea_rate


## Calm unit wind (x, z) of a match: the configured heading varied by the sky variation seed.
static func calm_heading(seed_value: int, config: CloudDriftConfig) -> Vector2:
	var unit: float = float(absi(hash(seed_value * HEADING_SALT + HEADING_SALT)) % HEADING_RES) / float(HEADING_RES)
	var degrees: float = config.calm_heading_deg + (unit * 2.0 - 1.0) * config.calm_heading_jitter_deg
	var angle: float = deg_to_rad(degrees)
	return Vector2(cos(angle), sin(angle))


## Speed multiplier for a storm amount 0..1 (1 calm, storm_speed_mult at full storm).
static func speed_multiplier(storm_amount: float, config: CloudDriftConfig) -> float:
	return lerpf(1.0, config.storm_speed_mult, clampf(storm_amount, 0.0, 1.0))


## Unit wind the clouds head for: the calm heading, or the storm wind once a storm is up.
static func target_heading(calm: Vector2, storm_wind: Vector2, storm_amount: float) -> Vector2:
	if storm_wind.length_squared() <= 0.0 or storm_amount <= 0.0:
		return calm
	return storm_wind.normalized()


## Turns unit `current` toward unit `target` by the exponential `rate` over `delta` along the
## shorter arc (no pass through zero when they oppose).
static func follow_heading(current: Vector2, target: Vector2, rate: float, delta: float) -> Vector2:
	var from_angle: float = current.angle()
	var diff: float = angle_difference(from_angle, target.angle())
	var weight: float = 1.0 - exp(-maxf(rate, 0.0) * maxf(delta, 0.0))
	var angle: float = from_angle + diff * weight
	return Vector2(cos(angle), sin(angle))


## Per-clump displacement (m) from the integrated wind `offset` (m per m/s of clump speed).
static func clump_shift(offset: Vector2, clump_speed_mps: float) -> Vector2:
	return offset * clump_speed_mps


## One axis of the square domain wrap: `centre + shift` folded into [-domain, domain).
static func wrap_axis(centre: float, shift: float, domain: float) -> float:
	var span: float = 2.0 * maxf(domain, 0.001)
	return fposmod(centre + shift + domain, span) - domain


## Where a clump rest position `centre` (x, z) is after `shift`, wrapped in the domain.
static func wrapped_position(centre: Vector2, shift: Vector2, domain: float) -> Vector2:
	return Vector2(wrap_axis(centre.x, shift.x, domain), wrap_axis(centre.y, shift.y, domain))


## Visibility 0..1 of a clump at wrapped `position`: dissolves toward the domain edge (so the
## wrap is hidden) and, for clumps below the disc (`exclusion_m` > 0), inside the exclusion
## radius around the disc axis (so none enters the play volume).
static func visibility(position: Vector2, domain: float, exclusion_m: float, config: CloudDriftConfig) -> float:
	var edge: float = domain - maxf(absf(position.x), absf(position.y))
	var weight: float = smoothstep(0.0, maxf(config.edge_fade_m, 0.001), edge)
	if exclusion_m > 0.0:
		weight *= smoothstep(exclusion_m, exclusion_m + maxf(config.exclusion_fade_m, 0.001), position.length())
	return weight
