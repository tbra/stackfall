extends GutTest
## net/Interpolator.gd (spec 3.4 "Client interpolation", docs/M3a_PLAN.md P2).
##
## "Render 100 ms behind the host (the delay adjusts to measured jitter),
## interpolating between the two surrounding snapshots. If snapshots are late,
## extrapolate for at most 100 ms."
##
## The clock is injected — `now` and `delta` are arguments — so every case
## below is a scripted stream with no waiting and no tree.
##
## **The test's clock model.** `_now` is the client's wall clock and only
## `_render()` advances it, exactly as only `_physics_process` advances the
## real one. `_deliver()` hands over a snapshot that arrived at `_now`, with an
## optional offset standing in for link jitter. The host clock is accumulated
## as a float and rounded to whole milliseconds per snapshot, because that is
## what SnapshotSync puts on the wire: at 30 Hz the steps are 33/33/34, not a
## clean 33.333, and any assertion tighter than that grid is testing rounding.

const NET_ID: int = 7
const OTHER_ID: int = 8
## The client renders at 60 Hz from a 30 Hz stream; that 2:1 ratio is the whole
## reason physics interpolation has something to smooth.
const RENDER_STEP: float = 1.0 / 60.0
## Where the host clock starts, so nothing accidentally passes at time zero.
const HOST_EPOCH_MS: float = 10000.0
const RNG_SEED: int = 20260918

var _config: NetConfig = null
var _interp: Interpolator = null
var _now: float = 0.0
var _host_time: float = 0.0
var _sequence: int = 0
var _rng: RandomNumberGenerator = null


func before_each() -> void:
	# A duplicate, so a test that retunes a field cannot leak into the next one
	# (CLAUDE.md / NetConfig: callers that mutate it duplicate() first).
	_config = (preload("res://config/net_config.tres") as NetConfig).duplicate() as NetConfig
	_interp = Interpolator.new(_config)
	_now = 0.0
	_host_time = HOST_EPOCH_MS
	_sequence = 0
	_rng = RandomNumberGenerator.new()
	_rng.seed = RNG_SEED


func _interval_ms() -> float:
	return 1000.0 / _config.snapshot_hz


func _interval_s() -> float:
	return 1.0 / _config.snapshot_hz


## Host time of the snapshot that _deliver() will send next.
func _host_ms() -> int:
	return int(round(_host_time))


## Delivers one snapshot carrying `bodies` ({net_id: [position, rotation,
## sleeping?]}) as having arrived `arrival_offset_ms` off the regular beat.
func _deliver(bodies: Dictionary, arrival_offset_ms: float = 0.0) -> void:
	_sequence += 1
	var host_ms: int = _host_ms()
	_interp.note_snapshot(_sequence, host_ms, _now + arrival_offset_ms / 1000.0)
	for key: Variant in bodies.keys():
		var pose: Array = bodies[key] as Array
		_interp.push_sample(
			int(key), host_ms, pose[0] as Vector3, pose[1] as Quaternion,
			pose.size() > 2 and bool(pose[2])
		)
	_host_time += _interval_ms()


## A snapshot the link swallowed: the host sent it, so the sequence and the
## clock both move, but nothing arrives.
func _drop_one() -> void:
	_sequence += 1
	_host_time += _interval_ms()


## A body sliding along +x at 1 m per snapshot, so the pose at any render time
## is a number the test can predict exactly.
func _slide(step: int) -> Dictionary:
	return {NET_ID: [Vector3(float(step), 0.0, 0.0), Quaternion.IDENTITY]}


## Advances the render clock by `seconds` in 60 Hz steps, as a client does.
func _render(seconds: float) -> void:
	var remaining: float = seconds
	while remaining > 1e-9:
		var step: float = minf(RENDER_STEP, remaining)
		_interp.advance(step)
		_now += step
		remaining -= step


func _pose() -> Dictionary:
	return _interp.sample_at_render_time(NET_ID)


func _drawn_x() -> float:
	return (_pose()["position"] as Vector3).x


## Runs a clean stream of `count` snapshots, delivering one and then rendering
## one interval, which is the steady state everything else perturbs.
func _run_clean(count: int, first_step: int = 0) -> void:
	for step: int in range(count):
		_deliver(_slide(first_step + step))
		_render(_interval_s())


# --- The render clock -------------------------------------------------------

func test_a_clean_stream_renders_exactly_the_base_delay_behind() -> void:
	_run_clean(30)
	assert_almost_eq(
		_interp.delay_ms(), _config.base_interp_delay_ms, 0.5, "the delay stays at the base"
	)
	assert_almost_eq(
		_interp.render_lag_ms(),
		_config.base_interp_delay_ms,
		1.0,
		"and the render clock sits exactly that far behind the host"
	)


func test_the_render_clock_starts_at_the_delay_rather_than_at_zero() -> void:
	assert_false(_interp.has_stream(), "nothing has arrived yet")
	_deliver(_slide(0))
	assert_true(_interp.has_stream(), "the first snapshot starts the stream")
	assert_almost_eq(
		_interp.render_time_ms(),
		HOST_EPOCH_MS - _config.base_interp_delay_ms,
		1.0,
		"the clock is placed, not snapped there a frame later"
	)


func test_a_clean_stream_never_reports_loss() -> void:
	_run_clean(30)
	assert_eq(_interp.loss_fraction(), 0.0, "an unbroken sequence is lossless")


# --- Interpolation ----------------------------------------------------------

func test_the_drawn_pose_is_the_render_clock_mapped_onto_the_sample_line() -> void:
	# Sample k sits at x = k and at host time HOST_EPOCH_MS + k * interval, so
	# the pose the interpolator draws must be the render clock read off that
	# same line — which is what "interpolating between the two surrounding
	# snapshots" means, stated as an equation rather than a magic number.
	_run_clean(8)
	var pose: Dictionary = _pose()
	assert_true(bool(pose["ok"]), "the body has usable samples")
	var expected: float = (_interp.render_time_ms() - HOST_EPOCH_MS) / _interval_ms()
	assert_almost_eq(
		(pose["position"] as Vector3).x, expected, 0.05, "the drawn pose is the render clock"
	)
	# And that clock is base_interp_delay_ms behind the host, which _run_clean
	# left one interval past the newest sample: index 7, minus three intervals
	# of delay, plus the one interval rendered after the last delivery.
	assert_almost_eq(
		expected,
		7.0 - _config.base_interp_delay_ms / _interval_ms() + 1.0,
		0.1,
		"which is base_interp_delay_ms behind the host clock"
	)


func test_the_drawn_pose_advances_smoothly_and_monotonically() -> void:
	_run_clean(4)
	var previous: float = -INF
	var biggest_jump: float = 0.0
	for frame: int in range(120):
		_render(RENDER_STEP)
		if frame % 2 == 1:
			_deliver(_slide(4 + frame / 2))
		var x: float = _drawn_x()
		if previous > -INF:
			assert_gte(x, previous - 1e-4, "the body never moves backwards")
			biggest_jump = maxf(biggest_jump, absf(x - previous))
		previous = x
	gut.p("INTERPOLATOR clean_biggest_frame_jump=%.4f" % biggest_jump)
	# One snapshot is 1 m; a 60 Hz frame should cover about half of that and
	# never a whole interval's worth at once, which is what a snap looks like.
	assert_lt(biggest_jump, 0.75, "no frame jumps a whole snapshot's worth")


func test_rotation_is_slerped_not_snapped() -> void:
	var per_step: float = deg_to_rad(20.0)
	for step: int in range(10):
		_deliver({NET_ID: [Vector3.ZERO, Quaternion(Vector3.UP, per_step * float(step))]})
		_render(_interval_s())

	var previous: float = (_pose()["rotation"] as Quaternion).angle_to(Quaternion.IDENTITY)
	assert_gt(previous, 1e-3, "it left the first pose")
	assert_lt(previous, per_step * 9.0, "and has not reached the newest one")

	var biggest_jump: float = 0.0
	for frame: int in range(20):
		_render(RENDER_STEP)
		_deliver({NET_ID: [Vector3.ZERO, Quaternion(Vector3.UP, per_step * float(10 + frame))]})
		var angle: float = (_pose()["rotation"] as Quaternion).angle_to(Quaternion.IDENTITY)
		biggest_jump = maxf(biggest_jump, absf(angle - previous))
		previous = angle
	assert_lt(biggest_jump, per_step, "no frame turns a whole snapshot's worth at once")


func test_before_the_oldest_sample_it_holds_rather_than_extrapolating_backwards() -> void:
	_deliver({NET_ID: [Vector3(5.0, 0.0, 0.0), Quaternion.IDENTITY]})
	# The render clock starts a delay behind, which is before this only sample.
	var pose: Dictionary = _pose()
	assert_true(bool(pose["ok"]), "one sample is enough to draw something")
	assert_eq((pose["position"] as Vector3).x, 5.0, "it holds at the oldest sample")


# --- Jitter -----------------------------------------------------------------

func test_injected_jitter_raises_the_delay_and_it_decays_back() -> void:
	_run_clean(20)
	var calm: float = _interp.delay_ms()
	assert_almost_eq(calm, _config.base_interp_delay_ms, 0.5, "a clean link sits at the base")

	for step: int in range(80):
		# Up to 30 ms of arrival jitter. A packet can be late but never early,
		# so the offset is one-sided, which is what a real link does.
		_deliver(_slide(20 + step), _rng.randf_range(0.0, 30.0))
		_render(_interval_s())
	var jittery: float = _interp.delay_ms()
	gut.p("INTERPOLATOR calm_delay_ms=%.2f jittery_delay_ms=%.2f jitter_ms=%.2f" % [
		calm, jittery, _interp.jitter_ms()
	])
	assert_gt(jittery, calm + 5.0, "measured jitter pushes the delay up")
	assert_lte(jittery, _config.max_interp_delay_ms, "and never past max_interp_delay_ms")

	_run_clean(200, 100)
	assert_lt(_interp.delay_ms(), calm + 2.0, "a calm stream decays it back to the base")


func test_the_delay_is_always_inside_its_configured_bounds() -> void:
	for step: int in range(80):
		_deliver(_slide(step), 500.0 if step % 3 == 0 else 0.0)
		_render(_interval_s())
	assert_gte(_interp.delay_ms(), _config.min_interp_delay_ms, "at least min_interp_delay_ms")
	assert_lte(_interp.delay_ms(), _config.max_interp_delay_ms, "at most max_interp_delay_ms")


func test_lost_snapshots_are_counted_as_loss_and_not_as_jitter() -> void:
	_run_clean(20)
	var clean_delay: float = _interp.delay_ms()

	for step: int in range(90):
		# Every other snapshot never arrives: the sequence skips and the gap
		# doubles, but the link is not jittery and the delay must not move.
		if step % 2 == 0:
			_drop_one()
		else:
			_deliver(_slide(20 + step))
		_render(_interval_s())
	gut.p("INTERPOLATOR loss_fraction=%.3f delay_ms=%.2f clean_delay_ms=%.2f" % [
		_interp.loss_fraction(), _interp.delay_ms(), clean_delay
	])
	assert_almost_eq(_interp.loss_fraction(), 0.5, 0.1, "half the sequence is missing")
	assert_almost_eq(_interp.delay_ms(), clean_delay, 3.0, "loss alone does not inflate the delay")


# --- Stalls and extrapolation ----------------------------------------------

func test_a_stall_extrapolates_for_at_most_the_configured_window_then_holds() -> void:
	_run_clean(6)
	var at_stall: float = _drawn_x()

	# 200 ms of silence: the render clock keeps running, so it walks past the
	# newest sample and extrapolation takes over.
	_render(0.2)
	var extrapolated: float = _drawn_x()
	assert_gt(extrapolated, at_stall, "it kept moving instead of freezing at once")

	# The newest sample is x = 5; the cap is max_extrapolation_ms worth of the
	# last segment, whose span is a whole number of milliseconds off the 33.333
	# ideal, so the bound carries that grid rather than pretending it is exact.
	var cap: float = _config.max_extrapolation_ms / floor(_interval_ms())
	assert_lte(extrapolated - 5.0, cap + 1e-3, "it never ran more than max_extrapolation_ms on")

	# Another 200 ms with nothing arriving must change nothing at all.
	_render(0.2)
	assert_almost_eq(_drawn_x(), extrapolated, 1e-4, "past the cap it holds, not drifts")
	_render(1.0)
	assert_almost_eq(_drawn_x(), extrapolated, 1e-4, "and keeps holding indefinitely")


func test_the_stream_resumes_after_a_stall_without_a_visible_snap() -> void:
	_run_clean(6)
	# The host kept simulating through the stall, and so did its clock: six
	# more snapshots' worth of both were lost on the wire.
	for step: int in range(6):
		_drop_one()
	_render(0.2)
	var previous: float = _drawn_x()

	var biggest_jump: float = 0.0
	for step: int in range(40):
		_deliver(_slide(12 + step))
		for frame: int in range(2):
			_render(RENDER_STEP)
			var x: float = _drawn_x()
			biggest_jump = maxf(biggest_jump, absf(x - previous))
			previous = x
	gut.p("INTERPOLATOR post_stall_biggest_frame_jump=%.4f" % biggest_jump)
	# A frame is half a snapshot of motion. Anything approaching a whole
	# snapshot in one frame is the snap the acceptance criterion forbids.
	assert_lt(biggest_jump, 1.0, "no single frame teleports the body")


func test_a_sleeping_body_is_never_extrapolated() -> void:
	_deliver({NET_ID: [Vector3(0.0, 0.0, 0.0), Quaternion.IDENTITY, false]})
	_deliver({NET_ID: [Vector3(1.0, 0.0, 0.0), Quaternion.IDENTITY, true]})
	_render(0.5)
	assert_eq(_drawn_x(), 1.0, "a body the host says is asleep holds where it slept")


# --- Buffer rules -----------------------------------------------------------

func test_a_reordered_sample_is_rejected() -> void:
	assert_true(
		_interp.push_sample(NET_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false),
		"the first sample is accepted"
	)
	assert_true(
		_interp.push_sample(NET_ID, 1033, Vector3.ONE, Quaternion.IDENTITY, false),
		"a newer sample is accepted"
	)
	assert_false(
		_interp.push_sample(NET_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false),
		"a sample older than the newest buffered one is rejected"
	)
	assert_false(
		_interp.push_sample(NET_ID, 1033, Vector3.ZERO, Quaternion.IDENTITY, false),
		"and so is a duplicate of it"
	)
	assert_eq(_interp.buffered_count(NET_ID), 2, "neither disturbed the buffer")


func test_the_buffer_is_capped_at_interp_buffer_samples() -> void:
	for step: int in range(_config.interp_buffer_samples * 3):
		_interp.push_sample(NET_ID, 1000 + step * 33, Vector3.ZERO, Quaternion.IDENTITY, false)
	assert_eq(
		_interp.buffered_count(NET_ID),
		_config.interp_buffer_samples,
		"the oldest samples fall off the front"
	)


func test_a_reordered_snapshot_does_not_move_the_clock() -> void:
	_run_clean(6)
	var before: float = _interp.render_time_ms()
	var delay_before: float = _interp.delay_ms()
	_interp.note_snapshot(2, int(HOST_EPOCH_MS), _now)
	assert_eq(_interp.render_time_ms(), before, "an old sequence number changes no clock")
	assert_eq(_interp.delay_ms(), delay_before, "and no delay")


func test_tracked_ids_forget_and_clear() -> void:
	_interp.push_sample(NET_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false)
	_interp.push_sample(OTHER_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false)
	var ids: Array = Array(_interp.tracked_ids())
	ids.sort()
	assert_eq(ids, [NET_ID, OTHER_ID], "both bodies are tracked")

	_interp.forget(NET_ID)
	assert_eq(Array(_interp.tracked_ids()), [OTHER_ID], "a despawned body is forgotten")
	assert_eq(_interp.buffered_count(NET_ID), 0, "and holds nothing")
	assert_false(bool(_interp.sample_at_render_time(NET_ID)["ok"]), "and cannot be drawn")

	_interp.clear()
	assert_eq(_interp.tracked_ids().size(), 0, "clear() drops everything")
	assert_false(_interp.has_stream(), "and the stream starts over")


func test_an_unknown_body_reports_not_ok_rather_than_the_origin() -> void:
	var pose: Dictionary = _interp.sample_at_render_time(4242)
	assert_false(bool(pose["ok"]), "a body with no samples is not drawable")
	assert_eq(pose["position"], Vector3.ZERO, "the caller must not use this")


# --- Unknown net_ids --------------------------------------------------------

func test_an_unknown_net_id_is_counted_and_changes_nothing() -> void:
	# docs/M3a_PLAN.md: an unreliable snapshot can overtake the reliable spawn
	# RPC, so a sample may name a body the client has never seen.
	var spawned: Dictionary = {NET_ID: true}
	_interp.set_known_id_filter(func(net_id: int) -> bool: return spawned.has(net_id))

	assert_true(
		_interp.push_sample(NET_ID, 1000, Vector3.ZERO, Quaternion.IDENTITY, false),
		"a spawned body is buffered"
	)
	assert_false(
		_interp.push_sample(OTHER_ID, 1000, Vector3.ONE, Quaternion.IDENTITY, false),
		"a body whose spawn has not arrived is dropped"
	)
	assert_eq(_interp.dropped_unknown_count(), 1, "and counted")
	assert_eq(_interp.buffered_count(OTHER_ID), 0, "it buffered nothing")
	assert_eq(Array(_interp.tracked_ids()), [NET_ID], "and is not tracked")

	# Once the spawn lands, the next snapshot picks it up — at most one
	# interval later, which is the whole cost of dropping instead of buffering.
	spawned[OTHER_ID] = true
	assert_true(
		_interp.push_sample(OTHER_ID, 1033, Vector3.ONE, Quaternion.IDENTITY, false),
		"the next snapshot carries it again"
	)
	assert_eq(_interp.dropped_unknown_count(), 1, "the counter does not keep climbing")


func test_without_a_filter_every_id_is_known() -> void:
	assert_true(
		_interp.push_sample(999, 1000, Vector3.ZERO, Quaternion.IDENTITY, false),
		"an unset filter means the wire tests need no registry"
	)
	assert_eq(_interp.dropped_unknown_count(), 0, "and nothing is dropped")


func test_clear_resets_the_dropped_counter() -> void:
	_interp.set_known_id_filter(func(_net_id: int) -> bool: return false)
	_interp.push_sample(1, 1000, Vector3.ZERO, Quaternion.IDENTITY, false)
	assert_eq(_interp.dropped_unknown_count(), 1, "it counted one")
	_interp.clear()
	assert_eq(_interp.dropped_unknown_count(), 0, "and clear() resets it")
