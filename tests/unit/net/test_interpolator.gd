extends GutTest
## net/Interpolator.gd (spec 2.6 "Client interpolation").
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
	_config = (preload("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
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
	var out: Interpolator.Pose = Interpolator.Pose.new()
	var ok: bool = _interp.pose_into(NET_ID, out)
	return {"ok": ok, "position": out.position, "rotation": out.rotation, "sleeping": out.sleeping}


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
	# The host clock projected forward from the newest snapshot (one interval
	# rendered since it arrived) is the host time the next snapshot will carry.
	var projected_host_ms: float = float(_host_ms())
	assert_almost_eq(
		projected_host_ms - _interp.render_time_ms(),
		_config.base_interp_delay_ms,
		1.0,
		"and the render clock sits exactly that far behind the host"
	)


# --- Interpolation ----------------------------------------------------------

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
	gut.p("INTERPOLATOR calm_delay_ms=%.2f jittery_delay_ms=%.2f" % [calm, jittery])
	assert_gt(jittery, calm + 5.0, "measured jitter pushes the delay up")
	assert_lte(jittery, _config.max_interp_delay_ms, "and never past max_interp_delay_ms")

	_run_clean(200, 100)
	assert_lt(_interp.delay_ms(), calm + 2.0, "a calm stream decays it back to the base")


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
	assert_true(_interp.pose_into(NET_ID, Interpolator.Pose.new()), "the body is still tracked")


# --- Unknown net_ids --------------------------------------------------------

func test_an_unknown_net_id_is_counted_and_changes_nothing() -> void:
	# An unreliable snapshot can overtake the reliable spawn
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
	assert_false(_interp.pose_into(OTHER_ID, Interpolator.Pose.new()), "and is not tracked")

	# Once the spawn lands, the next snapshot picks it up — at most one
	# interval later, which is the whole cost of dropping instead of buffering.
	spawned[OTHER_ID] = true
	assert_true(
		_interp.push_sample(OTHER_ID, 1033, Vector3.ONE, Quaternion.IDENTITY, false),
		"the next snapshot carries it again"
	)
	assert_eq(_interp.dropped_unknown_count(), 1, "the counter does not keep climbing")

