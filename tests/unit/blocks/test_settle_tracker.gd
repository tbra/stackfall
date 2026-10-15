extends GutTest
## core/physics/SettleTracker.gd (Bontago-e7o B): pure still-window accounting.

var _tracker: SettleTracker


func before_each() -> void:
	_tracker = SettleTracker.new()
	_tracker.window_s = 10.0
	_tracker.move_epsilon_m = 0.005
	_tracker.rotation_epsilon = 0.01
	_tracker.fast_speed_mps = 0.5
	_tracker.neighbour_radius_m = 2.0


func test_first_sight_credits_nothing() -> void:
	assert_eq(_tracker.observe(1, Transform3D.IDENTITY, 5.0), 0.0)


func test_still_time_accumulates_and_completes_the_window() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	_tracker.observe(1, Transform3D.IDENTITY, 6.0)
	assert_false(_tracker.is_window_complete(1))
	_tracker.observe(1, Transform3D.IDENTITY, 4.0)
	assert_true(_tracker.is_window_complete(1))


func test_small_drift_within_epsilon_keeps_the_window() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	var nudged: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.004, 0.0, 0.0))
	assert_eq(_tracker.observe(1, nudged, 3.0), 3.0)


func test_move_beyond_epsilon_resets_the_timer_and_anchor() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	_tracker.observe(1, Transform3D.IDENTITY, 8.0)
	var moved: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.02, 0.0, 0.0))
	assert_eq(_tracker.observe(1, moved, 1.0), 0.0)
	assert_eq(_tracker.observe(1, moved, 2.0), 2.0, "the new pose is the new anchor")


func test_rotation_beyond_epsilon_resets_the_timer() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	var turned: Transform3D = Transform3D(Basis(Vector3.UP, 0.05), Vector3.ZERO)
	assert_eq(_tracker.observe(1, turned, 4.0), 0.0)


func test_blocks_are_tracked_independently_and_reset_forgets_one() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	_tracker.observe(2, Transform3D.IDENTITY, 0.5)
	_tracker.observe(1, Transform3D.IDENTITY, 3.0)
	assert_eq(_tracker.still_seconds(2), 0.0)
	_tracker.reset(1)
	assert_eq(_tracker.still_seconds(1), 0.0)
	assert_eq(_tracker.tracked_count(), 1)


func test_prune_drops_dead_ids() -> void:
	_tracker.observe(1, Transform3D.IDENTITY, 0.5)
	_tracker.observe(2, Transform3D.IDENTITY, 0.5)
	_tracker.prune({2: true})
	assert_eq(_tracker.tracked_count(), 1)


func test_fast_speed_and_neighbour_radius() -> void:
	assert_true(_tracker.is_fast(0.6 * 0.6))
	assert_false(_tracker.is_fast(0.4 * 0.4))
	var fast: PackedVector3Array = PackedVector3Array([Vector3(1.5, 0.0, 0.0)])
	assert_true(_tracker.has_fast_neighbour(Vector3.ZERO, fast))
	assert_false(_tracker.has_fast_neighbour(Vector3(5.0, 0.0, 0.0), fast))
	assert_false(_tracker.has_fast_neighbour(Vector3.ZERO, PackedVector3Array()))
