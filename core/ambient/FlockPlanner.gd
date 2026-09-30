class_name FlockPlanner
extends RefCounted
## Bontago-470.5: pure planning for the occasional distant bird flocks (no scene
## tree; unit-tested in tests/unit/test_flock_planner.gd). A flight is a
## near-straight path through the sky: it enters from the far path ring, passes
## the disc axis at its closest-approach distance and leaves the far side. The
## per-bird motion (glide, flap bursts, bank, sway) is shader-side.

## Maximum yaw skew (degrees) of a flight path away from a pure tangent.
const PATH_SKEW_MAX_DEG: float = 12.0
## V formation: wing-tip offset per rank as fractions of the spacing, plus
## random jitter as a fraction of the spacing.
const V_SIDE_FRACTION: float = 0.6
const V_BACK_FRACTION: float = 0.8
const FORMATION_JITTER_FRACTION: float = 0.12
const V_HEIGHT_JITTER_FRACTION: float = 0.03
## Loose cluster: width/depth (fractions of spacing per sqrt(bird)) and height.
const LOOSE_WIDTH_FRACTION: float = 1.4
const LOOSE_DEPTH_FRACTION: float = 1.6
const LOOSE_HEIGHT_FRACTION: float = 0.25
## Sway amplitude of the whole flock's lateral weave (m), min/max.
const SWAY_MIN_M: float = 8.0
const SWAY_MAX_M: float = 30.0


class Flight:
	extends RefCounted
	## World position where the flock's leader enters (start of the path).
	var start: Vector3 = Vector3.ZERO
	## Flock velocity (m/s), shared by every bird.
	var velocity: Vector3 = Vector3.ZERO
	var duration_s: float = 0.0
	var size_m: float = 1.0
	var sway_m: float = 0.0
	var phase: float = 0.0
	## Per bird: (right m, up m, back m) offset from the leader in the flight frame.
	var offsets: PackedVector3Array = PackedVector3Array()
	var closest_distance_m: float = 0.0
	var is_v: bool = false

	func position_at(time_s: float) -> Vector3:
		return start + velocity * time_s


## Number of birds in a flock: 1 with `bird_single_chance`, else uniformly
## bird_flock_size_min..max.
static func pick_flock_size(theme: SkyThemeDef, rng: RandomNumberGenerator) -> int:
	if rng.randf() < theme.bird_single_chance:
		return 1
	var low: int = maxi(theme.bird_flock_size_min, 1)
	return rng.randi_range(low, maxi(theme.bird_flock_size_max, low))


## Plans one flight of `count` birds.
static func plan(theme: SkyThemeDef, rng: RandomNumberGenerator, count: int) -> Flight:
	var flight: Flight = Flight.new()
	var azimuth: float = rng.randf() * TAU
	var closest: float = rng.randf_range(theme.bird_distance_min_m, maxf(theme.bird_distance_max_m, theme.bird_distance_min_m))
	var radial: Vector3 = Vector3(cos(azimuth), 0.0, sin(azimuth))
	var tangent: Vector3 = Vector3(-radial.z, 0.0, radial.x) * (1.0 if rng.randf() < 0.5 else -1.0)
	var skew: float = deg_to_rad(rng.randf_range(-PATH_SKEW_MAX_DEG, PATH_SKEW_MAX_DEG))
	var heading: Vector3 = tangent.rotated(Vector3.UP, skew)
	var path_radius: float = maxf(theme.bird_path_radius_m, closest + 1.0)
	# The closest-approach point stays at `closest` from the axis; the path
	# extends both ways until it leaves the path ring.
	var centre: Vector3 = radial * closest
	var half_length: float = sqrt(maxf(path_radius * path_radius - closest * closest, 1.0))
	var speed: float = rng.randf_range(theme.bird_speed_min_mps, maxf(theme.bird_speed_max_mps, theme.bird_speed_min_mps))
	var climb: float = rng.randf_range(-theme.bird_climb_max_mps, theme.bird_climb_max_mps)
	var altitude: float = rng.randf_range(theme.bird_altitude_min_m, maxf(theme.bird_altitude_max_m, theme.bird_altitude_min_m))
	flight.duration_s = 2.0 * half_length / speed
	flight.velocity = heading * speed + Vector3.UP * climb
	flight.start = centre - heading * half_length
	flight.start.y = altitude - climb * flight.duration_s * 0.5
	flight.size_m = rng.randf_range(theme.bird_size_min_m, maxf(theme.bird_size_max_m, theme.bird_size_min_m))
	flight.sway_m = rng.randf_range(SWAY_MIN_M, SWAY_MAX_M)
	flight.phase = rng.randf() * TAU
	flight.closest_distance_m = closest
	flight.is_v = count >= 3 and rng.randf() < theme.bird_v_chance
	flight.offsets = formation(count, theme.bird_spacing_m, flight.is_v, rng)
	return flight


## Per-bird (right, up, back) offsets: a V (leader plus alternating wing ranks)
## or a loose cluster; a lone bird sits at the origin.
static func formation(count: int, spacing: float, v_shape: bool, rng: RandomNumberGenerator) -> PackedVector3Array:
	var offsets: PackedVector3Array = PackedVector3Array()
	for index: int in range(count):
		if index == 0:
			offsets.append(Vector3.ZERO)
			continue
		var jitter: float = spacing * FORMATION_JITTER_FRACTION
		if v_shape:
			var rank: int = (index + 1) >> 1
			var side: float = 1.0 if index % 2 == 1 else -1.0
			offsets.append(Vector3(
				side * float(rank) * spacing * V_SIDE_FRACTION + rng.randf_range(-jitter, jitter),
				rng.randf_range(-1.0, 1.0) * spacing * V_HEIGHT_JITTER_FRACTION * float(rank),
				float(rank) * spacing * V_BACK_FRACTION + rng.randf_range(-jitter, jitter)))
		else:
			var reach: float = sqrt(float(count))
			offsets.append(Vector3(
				rng.randf_range(-1.0, 1.0) * spacing * LOOSE_WIDTH_FRACTION * reach * 0.5,
				rng.randf_range(-1.0, 1.0) * spacing * LOOSE_HEIGHT_FRACTION,
				rng.randf() * spacing * LOOSE_DEPTH_FRACTION * reach * 0.5))
	return offsets
