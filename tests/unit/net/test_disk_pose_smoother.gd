extends GutTest
## game/net/DiskPoseSmoother.gd: the client-side presentation of the host's
## disk pose (spec 2.6 "Disk state ... sent every snapshot"). The 2-sample
## bracket, the late/duplicate rule, the extrapolation cap and hold, and the
## convergence offset that keeps a stall from snapping the mirrored disc.
## Pure, so no Field, registry or peer is needed; render time is an argument.

var _config: NetConfig = preload("res://config/net/net_config.tres")
var _smoother: DiskPoseSmoother = null


func before_each() -> void:
	_smoother = DiskPoseSmoother.new(_config)


func _tilt(degrees: float) -> Quaternion:
	return Quaternion(Vector3.RIGHT, deg_to_rad(degrees))


func test_no_pose_is_drawable_before_the_first_sample() -> void:
	assert_false(bool(_smoother.pose_at(1000.0)["ok"]), "ok is false until a sample arrives")


func test_a_lone_sample_is_the_pose_at_any_render_time() -> void:
	_smoother.push_sample(1000, Vector3(1.0, 2.0, 3.0), _tilt(5.0))
	for render_ms: float in [0.0, 1000.0, 1050.0]:
		var pose: Dictionary = _smoother.pose_at(render_ms)
		assert_true(bool(pose["ok"]), "a lone sample is drawable")
		assert_eq(pose["position"] as Vector3, Vector3(1.0, 2.0, 3.0), "held at %s ms" % render_ms)


func test_pose_blends_between_two_bracketing_samples() -> void:
	var tilt_a: Quaternion = _tilt(2.0)
	var tilt_b: Quaternion = _tilt(8.0)
	_smoother.push_sample(1000, Vector3.ZERO, tilt_a)
	_smoother.push_sample(1033, Vector3(1.0, 0.0, 0.0), tilt_b)

	var mid: Dictionary = _smoother.pose_at(1016.5) # strictly mid-bracket (1000 .. 1033)
	assert_true(bool(mid["ok"]), "a two-sample bracket is drawable")
	var mid_x: float = (mid["position"] as Vector3).x
	assert_gt(mid_x, 0.001, "the blend is not equal to the older endpoint")
	assert_lt(mid_x, 0.999, "the blend is not equal to the newer endpoint")
	var mid_rotation: Quaternion = mid["rotation"] as Quaternion
	assert_gt(mid_rotation.angle_to(tilt_a), deg_to_rad(0.01), "the blended tilt is not the older endpoint")
	assert_gt(mid_rotation.angle_to(tilt_b), deg_to_rad(0.01), "the blended tilt is not the newer endpoint")

	var quarter_x: float = (_smoother.pose_at(1008.25)["position"] as Vector3).x
	var three_quarter_x: float = (_smoother.pose_at(1024.75)["position"] as Vector3).x
	assert_lt(quarter_x, mid_x, "the blend is monotone across the bracket")
	assert_lt(mid_x, three_quarter_x, "the blend is monotone across the bracket")


func test_render_time_before_the_bracket_holds_the_older_sample() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(2.0))
	_smoother.push_sample(1033, Vector3(1.0, 0.0, 0.0), _tilt(8.0))
	assert_eq(_smoother.pose_at(900.0)["position"] as Vector3, Vector3.ZERO, "held at the older sample")


func test_a_late_or_duplicate_sample_is_dropped() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(2.0))
	_smoother.push_sample(1033, Vector3(1.0, 0.0, 0.0), _tilt(8.0))
	_smoother.push_sample(1033, Vector3(9.0, 0.0, 0.0), _tilt(30.0)) # duplicate time
	_smoother.push_sample(1010, Vector3(7.0, 0.0, 0.0), _tilt(20.0)) # late
	var at_newest: Dictionary = _smoother.pose_at(1033.0)
	assert_almost_eq((at_newest["position"] as Vector3).x, 1.0, 0.0001, "the newest sample is unchanged")
	var mid_x: float = (_smoother.pose_at(1016.5)["position"] as Vector3).x
	assert_lt(mid_x, 0.999, "the bracket was not reordered by the stale samples")


func test_extrapolation_continues_the_segment_up_to_the_cap() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(0.0))
	_smoother.push_sample(1100, Vector3(1.0, 0.0, 0.0), _tilt(0.0))
	# 50 ms past the newest sample on a 1 m / 100 ms segment: 0.5 m further.
	var pose: Dictionary = _smoother.pose_at(1150.0)
	assert_almost_eq((pose["position"] as Vector3).x, 1.5, 0.0001, "velocity carried 50 ms past newest")


func test_past_the_cap_the_pose_holds() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(0.0))
	_smoother.push_sample(1100, Vector3(1.0, 0.0, 0.0), _tilt(0.0))
	var capped_x: float = 1.0 + _config.max_extrapolation_ms / 100.0
	var at_cap: float = (_smoother.pose_at(1100.0 + _config.max_extrapolation_ms)["position"] as Vector3).x
	var far_past: float = (_smoother.pose_at(1100.0 + _config.max_extrapolation_ms * 5.0)["position"] as Vector3).x
	assert_almost_eq(at_cap, capped_x, 0.0001, "the cap is exact")
	assert_almost_eq(far_past, capped_x, 0.0001, "past the cap the pose holds")


func test_leaving_the_hold_eases_back_in_instead_of_snapping() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(0.0))
	_smoother.push_sample(1100, Vector3(1.0, 0.0, 0.0), _tilt(0.0))
	var held: Vector3 = _smoother.pose_at(1100.0 + _config.max_extrapolation_ms * 4.0)["position"] as Vector3
	# A late snapshot lands far from the held pose and render time catches up.
	_smoother.push_sample(1700, Vector3(5.0, 0.0, 0.0), _tilt(0.0))
	_smoother.push_sample(1800, Vector3(5.1, 0.0, 0.0), _tilt(0.0))
	var resumed: Vector3 = _smoother.pose_at(1750.0)["position"] as Vector3
	assert_lt(absf(resumed.x - held.x), 0.001, "the first pose after the hold is where the hold left off")
	for _i: int in range(600):
		_smoother.decay(1000.0 / 60.0)
	var settled: Vector3 = _smoother.pose_at(1750.0)["position"] as Vector3
	assert_gt(settled.x, 4.9, "the offset decays away and the raw pose shows")


func test_decay_is_a_no_op_while_there_is_no_offset() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(0.0))
	_smoother.push_sample(1100, Vector3(1.0, 0.0, 0.0), _tilt(0.0))
	var before: Vector3 = _smoother.pose_at(1050.0)["position"] as Vector3
	_smoother.decay(500.0)
	assert_eq(_smoother.pose_at(1050.0)["position"] as Vector3, before, "steady state is untouched")


func test_reset_forgets_every_sample() -> void:
	_smoother.push_sample(1000, Vector3.ZERO, _tilt(0.0))
	_smoother.reset()
	assert_false(bool(_smoother.pose_at(1000.0)["ok"]), "not drawable after reset")
	_smoother.push_sample(500, Vector3.ONE, _tilt(0.0))
	assert_true(bool(_smoother.pose_at(500.0)["ok"]), "an earlier host time is accepted again after reset")
