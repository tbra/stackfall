extends GutTest
## Bontago-470.5: core/ambient/FlockPlanner.gd plans the occasional distant
## flocks; vfx/DistantBirds.gd schedules them (quiet gaps, one flight at a time
## per slot, birds parked between flights).

const SUNSET_PATH: String = "res://config/sky_themes/sunset.tres"


func _theme() -> SkyThemeDef:
	return load(SUNSET_PATH) as SkyThemeDef


func test_flock_sizes_are_one_or_within_the_configured_range() -> void:
	var theme: SkyThemeDef = _theme()
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
	var theme: SkyThemeDef = _theme()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 11
	for _i: int in range(50):
		var flight: FlockPlanner.Flight = FlockPlanner.plan(theme, rng, 5)
		assert_gt(flight.duration_s, 20.0)
		assert_eq(flight.offsets.size(), 5)
		# Enters and leaves far away, and never comes near the play area.
		var enter: Vector3 = flight.position_at(0.0)
		var leave: Vector3 = flight.position_at(flight.duration_s)
		assert_gt(Vector2(enter.x, enter.z).length(), theme.bird_distance_max_m)
		assert_gt(Vector2(leave.x, leave.z).length(), theme.bird_distance_max_m)
		var nearest: float = INF
		var steps: int = 40
		for step: int in range(steps + 1):
			var at: Vector3 = flight.position_at(flight.duration_s * float(step) / float(steps))
			nearest = minf(nearest, Vector2(at.x, at.z).length())
		assert_gt(nearest, MapDef.RADIUS_LARGE * 2.0, "the path never passes near the disc")
		assert_lt(nearest, theme.bird_distance_max_m + 20.0, "and passes through the sky it was asked for")


func test_v_formation_alternates_sides_behind_the_leader() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 1
	var offsets: PackedVector3Array = FlockPlanner.formation(5, 10.0, true, rng)
	assert_eq(offsets[0], Vector3.ZERO)
	assert_lt(offsets[1].x * offsets[2].x, 0.0, "wings alternate sides")
	for index: int in range(1, 5):
		assert_gt(offsets[index].z, 0.0, "followers trail the leader")


func test_scheduler_launches_flies_and_goes_quiet_again() -> void:
	var theme: SkyThemeDef = _theme().duplicate() as SkyThemeDef
	theme.bird_seed = 5
	theme.bird_first_delay_min_s = 5.0
	theme.bird_first_delay_max_s = 5.0
	theme.bird_gap_min_s = 100.0
	theme.bird_gap_max_s = 100.0
	var birds: DistantBirds = DistantBirds.new()
	add_child_autofree(birds)
	birds.configure(theme, true)
	assert_eq(birds.active_flock_count(), 0)
	birds.advance(4.0)
	assert_eq(birds.active_flock_count(), 0, "quiet before the first delay")
	birds.advance(1.5)
	assert_eq(birds.active_flock_count(), theme.bird_flock_count, "each slot launches once its delay is up")
	var flight: FlockPlanner.Flight = birds.flight_of(0)
	assert_not_null(flight)
	assert_gte(birds.birds_in_slot(0), 1)
	assert_lte(birds.birds_in_slot(0), theme.bird_flock_size_max)
	var longest: float = 0.0
	for slot: int in range(birds.slot_count()):
		longest = maxf(longest, birds.flight_of(slot).duration_s)
	birds.advance(longest + 1.0)
	assert_eq(birds.active_flock_count(), 0, "flocks leave and the sky goes quiet")
	birds.advance(60.0)
	assert_eq(birds.active_flock_count(), 0, "still inside the long gap")
	birds.advance(60.0)
	assert_gt(birds.active_flock_count(), 0, "another flock arrives after the gap")


func test_low_or_disabled_has_no_scheduler() -> void:
	var birds: DistantBirds = DistantBirds.new()
	add_child_autofree(birds)
	birds.configure(_theme(), false)
	assert_eq(birds.slot_count(), 0)
	birds.advance(1000.0)
	assert_eq(birds.active_flock_count(), 0)
