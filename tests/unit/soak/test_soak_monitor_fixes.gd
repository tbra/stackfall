extends GutTest
## The soak monitor fixes from the first calibration run: quaternion precision in the dump lines,
## a monitor-overhead budget that scales with the bodies a sample walks, and a client grace for a
## falling body held at its last snapshot below the kill plane.
##

const KILL_PLANE_Y: float = -40.0
const PHYSICS_HZ: int = 60
const PER_BODY_FIELD: String = "monitor_overhead_us_per_body"
const REAL_TILT_DEG: float = 1.0
const COMPONENT_ERROR_MAX: float = 0.00001
const SMALL_BODIES: int = 48
const LARGE_BODIES: int = 1516
## Measured by calibration: what a monitor sample cost at those body counts, in microseconds.
const MEASURED_US_SMALL: int = 753
const MEASURED_US_LARGE: int = 14915

var _config: SoakConfig = load("res://config/soak/soak_config.tres") as SoakConfig


func _parsed_q(line: String) -> Quaternion:
	for token: String in line.split(" "):
		if token.begins_with("q="):
			var parts: PackedStringArray = token.substr(2).split(",")
			assert_eq(parts.size(), 4, "q is x,y,z,w")
			return Quaternion(
				parts[0].to_float(), parts[1].to_float(), parts[2].to_float(), parts[3].to_float()
			)
	fail_test("no q token in %s" % line)
	return Quaternion.IDENTITY


# --- agree.pose_after_sleep: quaternion precision ---------------------------------------------


## The report reads these components as text; its angle maths is covered by tools/test_soak_report.py.
func _assert_q_close(read: Quaternion, written: Quaternion) -> void:
	assert_almost_eq(read.x, written.x, COMPONENT_ERROR_MAX, "x keeps the written value")
	assert_almost_eq(read.y, written.y, COMPONENT_ERROR_MAX, "y keeps the written value")
	assert_almost_eq(read.z, written.z, COMPONENT_ERROR_MAX, "z keeps the written value")
	assert_almost_eq(read.w, written.w, COMPONENT_ERROR_MAX, "w keeps the written value")


func test_body_line_keeps_a_one_degree_tilt_readable_near_identity() -> void:
	var tilted: Quaternion = Quaternion(Vector3.RIGHT, deg_to_rad(REAL_TILT_DEG))
	var moved: String = SoakLine.body(&"client", 1, 7, Vector3.ZERO, tilted, true)
	_assert_q_close(_parsed_q(moved), tilted)
	assert_ne(_parsed_q(moved), Quaternion.IDENTITY, "the tilt is not rounded away")


func test_identical_pose_written_twice_reads_as_the_same_components() -> void:
	var pose: Quaternion = Quaternion(Vector3.UP, deg_to_rad(0.4))
	var host: String = SoakLine.body(&"host", 1, 7, Vector3.ZERO, pose, true)
	var client: String = SoakLine.body(&"client", 1, 7, Vector3.ZERO, pose, true)
	assert_eq(_parsed_q(host), _parsed_q(client))


func test_small_drift_without_rotation_writes_the_same_quaternion() -> void:
	var pose: Quaternion = Quaternion(Vector3(1, 2, 3).normalized(), deg_to_rad(0.6))
	var host: String = SoakLine.body(&"host", 1, 7, Vector3.ZERO, pose, true)
	var client: String = SoakLine.body(&"client", 1, 7, Vector3(0.0015, 0.0, 0.0), pose, true)
	assert_eq(_parsed_q(host), _parsed_q(client), "moving does not change the logged rotation")


func test_body_line_stays_one_token_per_field_for_the_report() -> void:
	var line: String = SoakLine.body(
		&"host", 4, 9, Vector3(1.0, 2.0, 3.0), Quaternion(Vector3.UP, 0.3), false
	)
	var keys: Array[String] = []
	for token: String in line.split(" ").slice(1):
		keys.append(token.get_slice("=", 0))
	assert_eq(keys, ["role", "epoch", "id", "p", "q", "rest"] as Array[String])
	assert_eq(line.get_slice("=", 0), "SOAK_BODY role")


# --- budget.monitor_overhead scales with bodies ----------------------------------------------


func _budget(monitor_us: int, bodies: int, config: SoakConfig = _config) -> Array[SoakCheck.Violation]:
	var curve: TickBudgetCurve = TickBudgetCurve.new(
		config.curve_bands, config.curve_band_half_width_fraction, 1000.0 / PHYSICS_HZ,
		config.curve_bucket_ms, config.curve_max_ms
	)
	return SoakCheck.budget(
		&"host", curve, float(PHYSICS_HZ), PHYSICS_HZ, 0.0, monitor_us, config, bodies
	)


func _count_overhead(found: Array[SoakCheck.Violation]) -> int:
	var count: int = 0
	for v: SoakCheck.Violation in found:
		if v.invariant == &"budget.monitor_overhead":
			count += 1
	return count


func test_the_measured_calibration_costs_are_within_budget_at_their_body_counts() -> void:
	assert_eq(_count_overhead(_budget(MEASURED_US_SMALL, SMALL_BODIES)), 0)
	assert_eq(_count_overhead(_budget(MEASURED_US_LARGE, LARGE_BODIES)), 0, "14915 us at 1516 bodies is a normal sample")


func test_a_monitor_that_is_slow_per_body_is_still_caught() -> void:
	var per_body: int = _config.monitor_overhead_us_per_body
	var allowed: int = _config.monitor_overhead_us_max + per_body * LARGE_BODIES
	assert_eq(_count_overhead(_budget(allowed, LARGE_BODIES)), 0, "exactly the allowance is fine")
	assert_eq(_count_overhead(_budget(allowed + 1, LARGE_BODIES)), 1, "one us past it is a violation")


func test_the_limit_reported_grows_with_the_bodies() -> void:
	var per_body: int = _config.monitor_overhead_us_per_body
	assert_gt(per_body, 0, "a per-body allowance exists")
	var few: Array[SoakCheck.Violation] = _budget(1000000, SMALL_BODIES)
	var many: Array[SoakCheck.Violation] = _budget(1000000, LARGE_BODIES)
	assert_eq(few[0].limit, float(_config.monitor_overhead_us_max + per_body * SMALL_BODIES))
	assert_eq(many[0].limit, float(_config.monitor_overhead_us_max + per_body * LARGE_BODIES))


func test_a_sample_over_the_base_with_no_bodies_is_caught() -> void:
	assert_eq(_count_overhead(_budget(_config.monitor_overhead_us_max, 0)), 0)
	assert_eq(_count_overhead(_budget(_config.monitor_overhead_us_max + 1, 0)), 1)


# --- client physics.below_kill_plane grace ---------------------------------------------------


func _falling_body(below_for_s: float) -> SoakCheck.BodyObs:
	var body: SoakCheck.BodyObs = SoakCheck.BodyObs.new()
	body.id = 5
	body.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, KILL_PLANE_Y - 10.0, 0.0))
	body.below_for_s = below_for_s
	return body


func _below(body: SoakCheck.BodyObs, is_host: bool) -> int:
	var bodies: Array[SoakCheck.BodyObs] = [body]
	var count: int = 0
	for v: SoakCheck.Violation in SoakCheck.physics(bodies, 0, 1, KILL_PLANE_Y, is_host, _config):
		if v.invariant == &"physics.below_kill_plane":
			count += 1
	return count


func test_a_client_body_below_the_plane_for_less_than_the_grace_is_not_reported() -> void:
	var grace: float = _config.client_kill_grace_s
	assert_gt(grace, 0.0, "a grace is configured")
	assert_eq(_below(_falling_body(0.0), false), 0)
	assert_eq(_below(_falling_body(grace - 0.1), false), 0)


func test_a_client_body_below_the_plane_for_the_grace_or_longer_is_reported() -> void:
	var grace: float = _config.client_kill_grace_s
	assert_eq(_below(_falling_body(grace), false), 1)
	assert_eq(_below(_falling_body(grace + 10.0), false), 1)


func test_a_client_body_with_no_tracked_time_is_reported() -> void:
	var body: SoakCheck.BodyObs = SoakCheck.BodyObs.new()
	body.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, KILL_PLANE_Y - 10.0, 0.0))
	assert_eq(_below(body, false), 1, "an observation that carries no time gets no grace")


func test_a_host_body_below_the_plane_is_reported_whatever_the_grace() -> void:
	assert_eq(_below(_falling_body(0.0), true), 1)
	assert_eq(_below(_falling_body(_config.client_kill_grace_s - 0.1), true), 1)
