extends GutTest
## core/net/SnapshotSelector.gd: the host's per-body resend decision for
## sleeping bodies. A sleeper is drift-tested (needs_check) only when it was
## never sent, its sleeping flag flipped since its last remember_sent, or the
## disc transform changed since the previous begin_tick (exact compare).
## moved_since_sent compares against the last SENT pose with the
## NetConfig.resend_* epsilons, so sub-epsilon creep accumulates.
##
## Only the public interface is used: begin_tick, needs_check,
## moved_since_sent, remember_sent, forget, reset.

const ID_A: int = 11
const ID_B: int = 12
const FAR: float = 100.0
## Per-tick creep, as a fraction of the resend epsilon.
const CREEP_FRACTION: float = 0.3

var _config: NetConfig = null
var _selector: SnapshotSelector = null
var _disc: Transform3D = Transform3D.IDENTITY
var _pose: Vector3 = Vector3(1.0, 2.0, 3.0)
var _rot: Quaternion = Quaternion.IDENTITY


func before_each() -> void:
	# Duplicate so a test that retunes an epsilon cannot leak into the next one.
	_config = (preload("res://config/net/net_config.tres") as NetConfig).duplicate() as NetConfig
	_selector = SnapshotSelector.new(_config)
	_disc = Transform3D(Basis(Quaternion(Vector3.RIGHT, 0.1)), Vector3(0.0, 0.5, 0.0))
	_pose = Vector3(1.0, 2.0, 3.0)
	_rot = Quaternion.IDENTITY


## A selector with `ids` remembered as sleeping at the fixture pose, past its
## first begin_tick so the disc is "unchanged" on the next call.
func _settled(ids: Array[int]) -> void:
	_selector.begin_tick(_disc)
	for id: int in ids:
		_selector.remember_sent(id, _pose, _rot, true)
	_selector.begin_tick(_disc)


# --- (a) never sent ---------------------------------------------------------

func test_a_never_sent_body_needs_a_check_and_counts_as_moved() -> void:
	_selector.begin_tick(_disc)
	assert_true(_selector.needs_check(ID_A, true), "a sleeper never sent needs a check")
	assert_true(_selector.moved_since_sent(ID_A, _pose, _rot), "with no last-sent pose it counts as moved")
	_selector.begin_tick(_disc)
	assert_true(_selector.needs_check(ID_A, true), "an unchanged disc does not excuse a never-sent body")


func test_remembering_one_body_does_not_settle_another() -> void:
	_settled([ID_A])
	assert_false(_selector.needs_check(ID_A, true), "the remembered body is quiet")
	assert_true(_selector.needs_check(ID_B, true), "a body never sent is not")


# --- (b) unmoved sleeper, unchanged disc ------------------------------------

func test_an_unmoved_sleeper_with_an_unchanged_disc_needs_no_check() -> void:
	_settled([ID_A])
	assert_false(_selector.needs_check(ID_A, true), "second equal begin_tick: no check")
	_selector.begin_tick(_disc)
	assert_false(_selector.needs_check(ID_A, true), "and it stays quiet tick after tick")
	assert_false(_selector.moved_since_sent(ID_A, _pose, _rot), "the same pose is not movement")


func test_the_first_begin_tick_counts_as_a_disc_change() -> void:
	_selector.remember_sent(ID_A, _pose, _rot, true)
	_selector.begin_tick(_disc)
	assert_true(_selector.needs_check(ID_A, true), "the first tick has no previous disc to equal")
	_selector.begin_tick(_disc)
	assert_false(_selector.needs_check(ID_A, true), "the second equal tick does")


# --- (c) disc change: every sleeper, exact compare --------------------------

func _assert_disc_change_checks_every_sleeper(changed: Transform3D, label: String) -> void:
	_selector = SnapshotSelector.new(_config)
	_settled([ID_A, ID_B])
	_selector.begin_tick(changed)
	assert_true(_selector.needs_check(ID_A, true), "%s: first sleeper needs a check" % label)
	assert_true(_selector.needs_check(ID_B, true), "%s: second sleeper needs a check" % label)
	_selector.begin_tick(changed)
	assert_false(_selector.needs_check(ID_A, true), "%s: once the disc holds still it is quiet again" % label)
	assert_false(_selector.needs_check(ID_B, true), "%s: for every body" % label)


func test_a_changed_disc_origin_checks_every_sleeper() -> void:
	var changed: Transform3D = _disc
	changed.origin += Vector3(0.0, 0.0, 0.25)
	_assert_disc_change_checks_every_sleeper(changed, "origin")


func test_a_changed_disc_rotation_checks_every_sleeper() -> void:
	var changed: Transform3D = _disc
	changed.basis = Basis(Quaternion(Vector3.FORWARD, 0.2))
	_assert_disc_change_checks_every_sleeper(changed, "rotation")


func test_a_changed_disc_scale_checks_every_sleeper() -> void:
	var changed: Transform3D = _disc
	changed.basis = _disc.basis.scaled(Vector3(1.0, 1.0, 1.5))
	_assert_disc_change_checks_every_sleeper(changed, "scale")


func test_the_disc_compare_is_exact_with_no_epsilon() -> void:
	var nudged: Transform3D = _disc
	nudged.origin.y += 1e-6
	assert_ne(nudged, _disc, "fixture: the nudged disc really differs, far below any epsilon")
	_assert_disc_change_checks_every_sleeper(nudged, "1e-6 nudge")


# --- (d) sleep flip ---------------------------------------------------------

func test_a_sleep_flip_either_way_needs_a_check_with_an_unchanged_disc() -> void:
	_settled([ID_A])
	assert_true(_selector.needs_check(ID_A, false), "remembered asleep, now awake: flipped")

	_selector.remember_sent(ID_A, _pose, _rot, false)
	_selector.begin_tick(_disc)
	assert_true(_selector.needs_check(ID_A, true), "remembered awake, now asleep: flipped")

	_selector.remember_sent(ID_A, _pose, _rot, true)
	_selector.begin_tick(_disc)
	assert_false(_selector.needs_check(ID_A, true), "remembered again as asleep: quiet")


func test_a_sleep_flip_on_one_body_does_not_check_the_others() -> void:
	_settled([ID_A, ID_B])
	assert_true(_selector.needs_check(ID_A, false), "the flipped body needs a check")
	assert_false(_selector.needs_check(ID_B, true), "its neighbour does not")


func test_a_sleeper_that_settled_inside_the_epsilon_is_flagged_as_flipped() -> void:
	_selector.begin_tick(_disc)
	_selector.remember_sent(ID_A, _pose, _rot, false)
	_selector.begin_tick(_disc)
	var settled: Vector3 = _pose + Vector3(_config.resend_position_epsilon * 0.5, 0.0, 0.0)
	assert_false(_selector.moved_since_sent(ID_A, settled, _rot), "fixture: it moved less than the epsilon")
	assert_true(_selector.sleep_flipped(ID_A, true), "awake when last sent, asleep now: resend it")
	assert_false(_selector.sleep_flipped(ID_A, false), "still awake: no flip")
	_selector.remember_sent(ID_A, settled, _rot, true)
	assert_false(_selector.sleep_flipped(ID_A, true), "once sent as asleep the flip is consumed")
	assert_true(_selector.sleep_flipped(ID_B, true), "a never-sent body counts as flipped")


# --- (e) slow creep ---------------------------------------------------------

func test_position_creep_below_the_epsilon_stays_unsent_until_the_drift_adds_up() -> void:
	var step: float = _config.resend_position_epsilon * CREEP_FRACTION
	_settled([ID_A])
	var body: Vector3 = _pose
	var disc: Transform3D = _disc
	for tick: int in range(1, 4):
		disc.origin.x += 1e-4
		body.x += step
		_selector.begin_tick(disc)
		assert_true(_selector.needs_check(ID_A, true), "tick %d: the disc moved, so the sleeper is tested" % tick)
		assert_false(
			_selector.moved_since_sent(ID_A, body, _rot),
			"tick %d: %.4f of drift is under the epsilon %.4f" % [tick, step * float(tick), _config.resend_position_epsilon]
		)

	disc.origin.x += 1e-4
	body.x += step
	_selector.begin_tick(disc)
	assert_true(
		_selector.moved_since_sent(ID_A, body, _rot),
		"tick 4: the accumulated drift against the last SENT pose passed the epsilon"
	)

	_selector.remember_sent(ID_A, body, _rot, true)
	disc.origin.x += 1e-4
	body.x += step
	_selector.begin_tick(disc)
	assert_false(_selector.moved_since_sent(ID_A, body, _rot), "re-based: one more step is quiet again")


func test_rotation_creep_below_the_epsilon_stays_unsent_until_the_drift_adds_up() -> void:
	var step_rad: float = deg_to_rad(_config.resend_angle_epsilon * CREEP_FRACTION)
	_settled([ID_A])
	var disc: Transform3D = _disc
	var angle: float = 0.0
	for tick: int in range(1, 4):
		disc.origin.x += 1e-4
		angle += step_rad
		_selector.begin_tick(disc)
		assert_false(
			_selector.moved_since_sent(ID_A, _pose, Quaternion(Vector3.UP, angle)),
			"tick %d: under the angle epsilon" % tick
		)

	disc.origin.x += 1e-4
	angle += step_rad
	_selector.begin_tick(disc)
	var turned: Quaternion = Quaternion(Vector3.UP, angle)
	assert_true(_selector.moved_since_sent(ID_A, _pose, turned), "tick 4: accumulated rotation passed the epsilon")

	_selector.remember_sent(ID_A, _pose, turned, true)
	angle += step_rad
	assert_false(
		_selector.moved_since_sent(ID_A, _pose, Quaternion(Vector3.UP, angle)),
		"re-based on the sent rotation: quiet"
	)


func test_the_resend_epsilons_come_from_the_config() -> void:
	_config.resend_position_epsilon = 1.0
	_config.resend_angle_epsilon = 45.0
	_selector = SnapshotSelector.new(_config)
	_settled([ID_A])
	assert_false(_selector.moved_since_sent(ID_A, _pose + Vector3(0.5, 0.0, 0.0), _rot), "0.5 m is inside a 1 m epsilon")
	assert_true(_selector.moved_since_sent(ID_A, _pose + Vector3(1.5, 0.0, 0.0), _rot), "1.5 m is outside it")
	assert_false(_selector.moved_since_sent(ID_A, _pose, Quaternion(Vector3.UP, deg_to_rad(20.0))), "20 degrees is inside 45")
	assert_true(_selector.moved_since_sent(ID_A, _pose, Quaternion(Vector3.UP, deg_to_rad(70.0))), "70 degrees is outside it")


func test_movement_is_judged_per_body() -> void:
	_settled([ID_A, ID_B])
	assert_true(_selector.moved_since_sent(ID_A, _pose + Vector3(FAR, 0.0, 0.0), _rot), "one body moved a long way")
	assert_false(_selector.moved_since_sent(ID_B, _pose, _rot), "the other did not")


# --- (f) keyframe slice re-base ---------------------------------------------

func test_a_body_resent_by_the_keyframe_slice_is_rebased() -> void:
	_settled([ID_A])
	var drifted: Vector3 = _pose + Vector3(0.0, 0.0, FAR)
	assert_false(_selector.needs_check(ID_A, true), "no disc change and no flip: not drift-tested")
	assert_true(_selector.moved_since_sent(ID_A, drifted, _rot), "fixture: against the old sent pose it has moved")

	_selector.remember_sent(ID_A, drifted, _rot, true) # the keyframe slice sends it
	_selector.begin_tick(_disc)
	assert_false(_selector.needs_check(ID_A, true), "next tick it needs no check")
	assert_false(_selector.moved_since_sent(ID_A, drifted, _rot), "and the slice's pose is its new baseline")


# --- (g) forget -------------------------------------------------------------

func test_forget_makes_that_body_never_sent_and_leaves_the_others() -> void:
	_settled([ID_A, ID_B])
	_selector.forget(ID_A)
	assert_true(_selector.needs_check(ID_A, true), "the forgotten body needs a check again")
	assert_true(_selector.moved_since_sent(ID_A, _pose, _rot), "and counts as moved")
	assert_false(_selector.needs_check(ID_B, true), "the other keeps its state")
	assert_false(_selector.moved_since_sent(ID_B, _pose, _rot), "including its baseline")


func test_forgetting_an_unknown_body_is_harmless() -> void:
	_settled([ID_A])
	_selector.forget(9999)
	assert_false(_selector.needs_check(ID_A, true), "an unrelated body is unaffected")


# --- (h) reset --------------------------------------------------------------

func test_reset_makes_every_body_never_sent() -> void:
	_settled([ID_A, ID_B])
	_selector.reset()
	_selector.begin_tick(_disc)
	for id: int in [ID_A, ID_B]:
		assert_true(_selector.needs_check(id, true), "body %d needs a check after reset" % id)
		assert_true(_selector.moved_since_sent(id, _pose, _rot), "body %d counts as moved" % id)
	_selector.begin_tick(_disc)
	assert_true(_selector.needs_check(ID_A, true), "still never sent on an unchanged disc")


func test_the_begin_tick_after_reset_counts_as_a_disc_change() -> void:
	_settled([ID_A])
	_selector.reset()
	_selector.remember_sent(ID_A, _pose, _rot, true) # re-learned before the next tick
	_selector.begin_tick(_disc) # the same disc as before the reset
	assert_true(_selector.needs_check(ID_A, true), "the first tick after reset is a disc change")
	_selector.begin_tick(_disc)
	assert_false(_selector.needs_check(ID_A, true), "the second equal tick is not")


func test_a_move_exactly_at_the_position_epsilon_is_not_a_move() -> void:
	_config.resend_position_epsilon = 1.0
	_selector = SnapshotSelector.new(_config)
	_settled([ID_A])
	assert_false(_selector.moved_since_sent(ID_A, _pose + Vector3(1.0, 0.0, 0.0), _rot), "at the epsilon: not past it")
	assert_true(_selector.moved_since_sent(ID_A, _pose + Vector3(1.01, 0.0, 0.0), _rot), "just past it")


func test_a_turn_exactly_at_the_angle_epsilon_is_not_a_move() -> void:
	var turned: Quaternion = Quaternion(Vector3.UP, deg_to_rad(30.0))
	_config.resend_angle_epsilon = rad_to_deg(_rot.angle_to(turned))
	_selector = SnapshotSelector.new(_config)
	_settled([ID_A])
	assert_false(_selector.moved_since_sent(ID_A, _pose, turned), "at the epsilon: not past it")
	_config.resend_angle_epsilon *= 0.99
	assert_true(_selector.moved_since_sent(ID_A, _pose, turned), "just past a slightly smaller epsilon")
