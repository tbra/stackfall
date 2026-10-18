extends GutTest
## core/ambient/FlockPlanner.gd plans the occasional distant
## flocks; game/ambient/DistantBirds.gd schedules them (quiet gaps, one flight at a time
## per slot, birds parked between flights).

const SUNSET_PATH: String = "res://config/sky/themes/sunset.tres"
## Upper bound on a flight's length in 1 s steps; a flock that never lands trips it.
const MAX_FLIGHT_STEPS: int = 600
## Tolerance for the pinned values (printed with about 6 significant digits).
const PIN_TOLERANCE: float = 0.01


func _theme() -> SkyCycleDef:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	return SkyThemeMigration.cycle_from_themes(sunset, sunset, sunset)


func test_flock_sizes_are_one_or_within_the_configured_range() -> void:
	var theme: SkyCycleDef = _theme()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 3
	var singles: int = 0
	for _i: int in range(300):
		var count: int = FlockPlanner.pick_flock_size(theme, rng)
		assert_true(count == 1 or (count >= theme.bird_flock_size_min and count <= theme.bird_flock_size_max), "size %d" % count)
		if count == 1:
			singles += 1
	assert_gt(singles, 0, "sometimes a single bird")
	assert_lt(singles, 150, "but mostly flocks")


func test_flight_crosses_the_sky_past_the_disc() -> void:
	var theme: SkyCycleDef = _theme()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for _i: int in range(50):
		var flight: FlockPlanner.Flight = FlockPlanner.plan(theme, rng, 5)
		assert_gt(flight.duration_s, 20.0)
		assert_eq(flight.offsets.size(), 5)
		# Enters and leaves far away, and never comes near the play area.
		var enter: Vector3 = flight.start
		var leave: Vector3 = flight.start + flight.velocity * flight.duration_s
		assert_gt(Vector2(enter.x, enter.z).length(), theme.bird_distance_max_m)
		assert_gt(Vector2(leave.x, leave.z).length(), theme.bird_distance_max_m)
		var nearest: float = INF
		var steps: int = 40
		for step: int in range(steps + 1):
			var at: Vector3 = flight.start + flight.velocity * (flight.duration_s * float(step) / float(steps))
			nearest = minf(nearest, Vector2(at.x, at.z).length())
		assert_gt(nearest, MapDef.RADIUS_LARGE * 2.0, "the path never passes near the disc")
		assert_lt(nearest, theme.bird_distance_max_m + 20.0, "and passes through the sky it was asked for")


## The flight clock the shader reads. The node only advances it while a flock is in the air, so
## it moves exactly when something is flying and holds still while the sky is quiet.
func _flight_clock(birds: DistantBirds) -> float:
	var flocks: MultiMeshInstance3D = birds.get_node("Flocks") as MultiMeshInstance3D
	return (flocks.material_override as ShaderMaterial).get_shader_parameter(DistantBirds.CLOCK_PARAMETER) as float


## True when advancing `seconds` moved the flight clock, i.e. a flock was flying during it.
func _flocks_fly_during(birds: DistantBirds, seconds: float) -> bool:
	var before: float = _flight_clock(birds)
	birds.advance(seconds)
	return not is_equal_approx(_flight_clock(birds), before)


func test_scheduler_launches_flies_and_goes_quiet_again() -> void:
	var theme: SkyCycleDef = _theme()
	theme.bird_seed = 5
	theme.bird_first_delay_min_s = 5.0
	theme.bird_first_delay_max_s = 5.0
	theme.bird_gap_min_s = 100.0
	theme.bird_gap_max_s = 100.0
	var birds: DistantBirds = DistantBirds.new()
	add_child_autofree(birds)
	birds.configure_cycle(theme, true)
	assert_false(_flocks_fly_during(birds, 4.0), "quiet before the first delay")
	assert_true(_flocks_fly_during(birds, 1.5), "flocks launch once the first delay is up")
	var steps: int = 0
	while _flocks_fly_during(birds, 1.0) and steps < MAX_FLIGHT_STEPS:
		steps += 1
	assert_lt(steps, MAX_FLIGHT_STEPS, "every flock lands and the sky goes quiet")
	assert_false(_flocks_fly_during(birds, 60.0), "still quiet inside the long gap")
	assert_true(_flocks_fly_during(birds, 60.0), "another flock arrives after the gap")


## Literals captured from the pre-cycle planner (SkyThemeDef-based) on the sunset theme.
func test_plans_reproduce_the_pre_cycle_planner_for_pinned_seeds() -> void:
	var def: SkyCycleDef = _theme()
	var pinned: Array[Dictionary] = [
		{"seed": 3, "count": 5, "start": Vector3(600.456, 43.757484, 139.9849),
			"velocity": Vector3(-12.688333, -0.036892295, 4.146373), "size": 4.48822832107544},
		{"seed": 42, "count": 1, "start": Vector3(-594.062, -32.131645, 201.27956),
			"velocity": Vector3(9.297143, 1.049588, -7.524942), "size": 3.76828408241272},
	]
	for entry: Dictionary in pinned:
		var rng: RandomNumberGenerator = RandomNumberGenerator.new()
		rng.seed = entry["seed"] as int
		var count: int = FlockPlanner.pick_flock_size(def, rng)
		assert_eq(count, entry["count"] as int)
		var flight: FlockPlanner.Flight = FlockPlanner.plan(def, rng, count)
		assert_lt(flight.start.distance_to(entry["start"] as Vector3), PIN_TOLERANCE)
		assert_lt(flight.velocity.distance_to(entry["velocity"] as Vector3), PIN_TOLERANCE)
		assert_almost_eq(flight.size_m, entry["size"] as float, PIN_TOLERANCE)


func test_legacy_configure_matches_configure_cycle() -> void:
	var sunset: SkyThemeDef = load(SUNSET_PATH) as SkyThemeDef
	var old_birds: DistantBirds = DistantBirds.new()
	add_child_autofree(old_birds)
	old_birds.configure(sunset, true)
	assert_true(old_birds.visible, "the legacy entry point still shows the sunset birds")
	old_birds.configure(null, true)
	assert_false(old_birds.visible)
