extends GutTest
## SoakCheck is the soak gate's rule book (SOAK_PLAN section 6.2): each check turns observation
## objects into violations. These tests pin, for every invariant, that it fires just past its
## tolerance and stays quiet at and inside it, using the real SoakConfig defaults.

const KILL_PLANE_Y: float = -40.0
const PHYSICS_HZ: int = 60
## Fraction-of-tick budget of the default config at 60 Hz, in milliseconds.
const BUDGET_MS: float = 1000.0 / 60.0
const HOST: StringName = &"host"
const CLIENT: StringName = &"client"

var _config: SoakConfig = load("res://config/soak/soak_config.tres") as SoakConfig


func _config_with(changes: Dictionary) -> SoakConfig:
	var config: SoakConfig = _config.duplicate() as SoakConfig
	for key: Variant in changes:
		config.set(key, changes[key])
	return config


func _ids(violations: Array[SoakCheck.Violation]) -> Array[StringName]:
	var ids: Array[StringName] = []
	for violation: SoakCheck.Violation in violations:
		ids.append(violation.invariant)
	return ids


func _first(violations: Array[SoakCheck.Violation], invariant: StringName) -> SoakCheck.Violation:
	for violation: SoakCheck.Violation in violations:
		if violation.invariant == invariant:
			return violation
	return null


func _count(violations: Array[SoakCheck.Violation], invariant: StringName) -> int:
	var found: int = 0
	for violation: SoakCheck.Violation in violations:
		if violation.invariant == invariant:
			found += 1
	return found


# --- physics ---------------------------------------------------------------------------------


func _body(id: int, origin: Vector3, owner_slot: int = 0) -> SoakCheck.BodyObs:
	var body: SoakCheck.BodyObs = SoakCheck.BodyObs.new()
	body.id = id
	body.transform = Transform3D(Basis.IDENTITY, origin)
	body.owner_slot = owner_slot
	return body


func _physics(
	bodies: Array[SoakCheck.BodyObs],
	awake: int = 0,
	total: int = 0,
	is_host: bool = true,
	config: SoakConfig = _config,
	kill_plane_y: float = KILL_PLANE_Y
) -> Array[SoakCheck.Violation]:
	return SoakCheck.physics(bodies, awake, total, kill_plane_y, is_host, config)


func test_no_bodies_is_sound() -> void:
	assert_eq(_physics([]).size(), 0)


func test_a_body_above_the_kill_plane_margin_is_sound() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, 5.0, 0.0))]
	assert_eq(_physics(bodies, 0, 1).size(), 0)


func test_a_body_just_inside_the_margin_is_sound() -> void:
	# kill plane -40 plus the default 1 m margin: -38.99 is still above the line.
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -38.99, 0.0))]
	assert_eq(_physics(bodies, 0, 1).size(), 0)


func test_a_body_exactly_on_the_margin_line_is_sound() -> void:
	# The rule is "lower than kill_plane_y + margin", so the line itself is not a violation.
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -39.0, 0.0))]
	assert_eq(_physics(bodies, 0, 1).size(), 0)


func test_a_body_just_past_the_margin_is_a_violation() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(1204, Vector3(1.0, -39.01, 2.0), 3)]
	var found: Array[SoakCheck.Violation] = _physics(bodies, 0, 1)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	if found.is_empty():
		return
	var violation: SoakCheck.Violation = found[0]
	assert_eq(violation.invariant, &"physics.below_kill_plane")
	assert_eq(violation.severity, SoakCheck.SEVERITY_FAIL)
	assert_eq(violation.subject, "1204", "The subject is the body id.")
	assert_almost_eq(violation.value, -39.01, 0.001)
	assert_almost_eq(violation.limit, -39.0, 0.001)


func test_a_far_fallen_body_is_a_violation() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(9, Vector3(0.0, -400.0, 0.0))]
	assert_has(_ids(_physics(bodies, 0, 1)), &"physics.below_kill_plane")


func test_the_margin_comes_from_the_config() -> void:
	var wide: SoakConfig = _config_with({"kill_plane_margin_m": 3.0})
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -37.5, 0.0))]
	assert_eq(_physics(bodies, 0, 1, true, wide).size(), 1, "-37.5 is below -40 + 3.")
	assert_eq(_physics(bodies, 0, 1, true, _config).size(), 0, "-37.5 is above -40 + 1.")
	var bodies_inside: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -36.5, 0.0))]
	assert_eq(_physics(bodies_inside, 0, 1, true, wide).size(), 0)


func test_the_kill_plane_comes_from_the_argument() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -20.0, 0.0))]
	assert_eq(_physics(bodies, 0, 1, true, _config, -10.0).size(), 1, "-20 is below -10 + 1.")
	assert_eq(_physics(bodies, 0, 1, true, _config, -40.0).size(), 0)


func test_a_client_checks_the_kill_plane_too() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(1, Vector3(0.0, -60.0, 0.0))]
	assert_has(_ids(_physics(bodies, 0, 1, false)), &"physics.below_kill_plane")


func test_every_fallen_body_is_reported_once_and_sound_ones_not_at_all() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [
		_body(1, Vector3(0.0, -50.0, 0.0)),
		_body(2, Vector3(0.0, 3.0, 0.0)),
		_body(3, Vector3(0.0, -45.0, 0.0)),
	]
	var found: Array[SoakCheck.Violation] = _physics(bodies, 0, 3)
	assert_eq(_count(found, &"physics.below_kill_plane"), 2)
	var subjects: Array[String] = []
	for violation: SoakCheck.Violation in found:
		subjects.append(violation.subject)
	subjects.sort()
	assert_eq(subjects, ["1", "3"] as Array[String])


func test_a_nan_origin_is_non_finite() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(5, Vector3(NAN, 1.0, 0.0))]
	var found: Array[SoakCheck.Violation] = _physics(bodies, 0, 1)
	var violation: SoakCheck.Violation = _first(found, &"physics.non_finite")
	assert_not_null(violation)
	if violation != null:
		assert_eq(violation.subject, "5")


func test_an_infinite_origin_component_is_non_finite() -> void:
	var bodies: Array[SoakCheck.BodyObs] = [_body(5, Vector3(0.0, 1.0, INF))]
	assert_has(_ids(_physics(bodies, 0, 1)), &"physics.non_finite")


func test_a_nan_basis_is_non_finite() -> void:
	var body: SoakCheck.BodyObs = _body(6, Vector3(0.0, 1.0, 0.0))
	body.transform = Transform3D(Basis(Vector3(NAN, 0.0, 0.0), Vector3.UP, Vector3.BACK), Vector3(0.0, 1.0, 0.0))
	var bodies: Array[SoakCheck.BodyObs] = [body]
	assert_has(_ids(_physics(bodies, 0, 1)), &"physics.non_finite")


func test_a_finite_pose_is_not_non_finite() -> void:
	var body: SoakCheck.BodyObs = _body(6, Vector3(3.0, 1.0, -2.0))
	body.transform = Transform3D(Basis(Vector3.UP, 1.2), body.transform.origin)
	var bodies: Array[SoakCheck.BodyObs] = [body]
	assert_eq(_count(_physics(bodies, 0, 1), &"physics.non_finite"), 0)


func test_awake_fraction_over_the_limit_on_the_host_is_a_violation() -> void:
	# 121 / 200 = 0.605 > 0.6 with exactly awake_check_min_bodies blocks.
	var found: Array[SoakCheck.Violation] = _physics([], 121, 200)
	var violation: SoakCheck.Violation = _first(found, &"physics.awake_fraction")
	assert_not_null(violation)
	if violation != null:
		assert_almost_eq(violation.value, 0.605, 0.001)
		assert_almost_eq(violation.limit, 0.6, 0.001)


func test_awake_fraction_at_the_limit_is_sound() -> void:
	assert_eq(_physics([], 120, 200).size(), 0, "120 / 200 is exactly awake_fraction_max.")


func test_awake_fraction_is_not_checked_below_the_min_body_count() -> void:
	assert_eq(_physics([], 199, 199).size(), 0, "199 blocks is under awake_check_min_bodies.")
	assert_eq(_physics([], 10, 10).size(), 0)


func test_awake_fraction_is_checked_from_the_min_body_count() -> void:
	assert_has(_ids(_physics([], 200, 200)), &"physics.awake_fraction")
	assert_has(_ids(_physics([], 1000, 1000)), &"physics.awake_fraction")


func test_awake_fraction_is_host_only() -> void:
	assert_eq(_physics([], 200, 200, false).size(), 0)


func test_awake_fraction_thresholds_come_from_the_config() -> void:
	var tight: SoakConfig = _config_with({"awake_fraction_max": 0.25, "awake_check_min_bodies": 10})
	assert_has(_ids(_physics([], 6, 20, true, tight)), &"physics.awake_fraction")
	assert_eq(_physics([], 5, 20, true, tight).size(), 0)
	assert_eq(_physics([], 9, 9, true, tight).size(), 0, "9 blocks is under the lowered minimum.")


func test_zero_blocks_does_not_divide_by_zero() -> void:
	assert_eq(_physics([], 0, 0).size(), 0)


# --- territory -------------------------------------------------------------------------------


func _board(shares: Array[float], owned: Array[int], in_disk: int) -> SoakCheck.TerritoryObs:
	var board: SoakCheck.TerritoryObs = SoakCheck.TerritoryObs.new()
	board.shares = PackedFloat32Array(shares)
	board.owned_cells = PackedInt32Array(owned)
	board.in_disk_cells = in_disk
	return board


func _clean_board() -> SoakCheck.TerritoryObs:
	return _board([0.3, 0.2], [3000, 2000], 10000)


func _territory(
	board: SoakCheck.TerritoryObs,
	homes: Array[SoakCheck.HomeObs] = [],
	config: SoakConfig = _config
) -> Array[SoakCheck.Violation]:
	return SoakCheck.territory(board, homes, config)


func _home(slot: int, foreign_for_s: float) -> SoakCheck.HomeObs:
	var home: SoakCheck.HomeObs = SoakCheck.HomeObs.new()
	home.slot = slot
	home.team = slot
	home.foreign_for_s = foreign_for_s
	return home


func test_a_consistent_board_is_sound() -> void:
	assert_eq(_territory(_clean_board()).size(), 0)


func test_an_empty_board_is_sound() -> void:
	assert_eq(_territory(_board([], [], 0)).size(), 0)


func test_shares_of_zero_and_one_are_in_range() -> void:
	assert_eq(_territory(_board([1.0, 0.0], [10000, 0], 10000)).size(), 0)


func test_a_share_above_one_breaks_the_range() -> void:
	var found: Array[SoakCheck.Violation] = _territory(_board([1.5], [15000], 10000))
	assert_has(_ids(found), &"territory.share_range")


func test_a_negative_share_breaks_the_range() -> void:
	var found: Array[SoakCheck.Violation] = _territory(_board([-0.1, 0.5], [-1000, 5000], 10000))
	assert_has(_ids(found), &"territory.share_range")


func test_a_share_sum_just_inside_the_slack_is_sound() -> void:
	# 1 + 0.002 is the limit; 1.0015 is inside it. in_disk is large so the recount stays exact.
	assert_eq(_territory(_board([0.5, 0.5015], [50000, 50150], 100000)).size(), 0)


func test_a_share_sum_just_past_the_slack_is_a_violation() -> void:
	var found: Array[SoakCheck.Violation] = _territory(_board([0.5, 0.5025], [50000, 50250], 100000))
	var violation: SoakCheck.Violation = _first(found, &"territory.share_range")
	assert_not_null(violation)
	if violation != null:
		assert_almost_eq(violation.value, 1.0025, 0.0001)
		assert_almost_eq(violation.limit, 1.002, 0.0001)


func test_a_share_sum_exactly_at_one_plus_eps_is_sound() -> void:
	# Binary-exact numbers so the sum equals the limit with no rounding: 0.5 + 0.625 = 1 + 0.125.
	var roomy: SoakConfig = _config_with({"share_sum_eps": 0.125})
	assert_eq(_territory(_board([0.5, 0.625], [4000, 5000], 8000), [], roomy).size(), 0)
	var over: Array[SoakCheck.Violation] = _territory(_board([0.5, 0.75], [4000, 6000], 8000), [], roomy)
	assert_has(_ids(over), &"territory.share_range")


func test_the_share_sum_slack_comes_from_the_config() -> void:
	var board: SoakCheck.TerritoryObs = _board([0.5, 0.51], [5000, 5100], 10000)
	assert_has(_ids(_territory(board)), &"territory.share_range")
	var roomy: SoakConfig = _config_with({"share_sum_eps": 0.05})
	assert_eq(_territory(board, [], roomy).size(), 0)


func test_an_owned_cell_count_that_matches_the_share_is_sound() -> void:
	assert_eq(_territory(_board([0.25, 0.25], [2500, 2500], 10000)).size(), 0)


func test_an_owned_cell_count_that_drifted_from_the_share_is_a_violation() -> void:
	# Team 1 holds 2000 cells by the bytes but the share says 0.3 of 10000 = 3000.
	var found: Array[SoakCheck.Violation] = _territory(_board([0.3, 0.3], [3000, 2000], 10000))
	assert_eq(_count(found, &"territory.owned_cells_recount"), 1, "Only the drifted team.")
	var violation: SoakCheck.Violation = _first(found, &"territory.owned_cells_recount")
	if violation != null:
		assert_eq(violation.subject, "1", "The subject is the team index.")


func test_the_recount_slack_is_a_share_fraction_of_the_disk() -> void:
	# 3010 of 10000 is 0.301: 0.001 away from 0.3, inside share_sum_eps 0.002.
	assert_eq(_territory(_board([0.3], [3010], 10000)).size(), 0)
	# 3030 of 10000 is 0.303: 0.003 away, outside.
	var found: Array[SoakCheck.Violation] = _territory(_board([0.3], [3030], 10000))
	assert_has(_ids(found), &"territory.owned_cells_recount")


func test_a_recount_exactly_eps_from_the_share_is_sound() -> void:
	# Binary-exact: 5000 / 8000 = 0.625 is 0.125 from the share 0.5, exactly share_sum_eps.
	var roomy: SoakConfig = _config_with({"share_sum_eps": 0.125})
	assert_eq(_territory(_board([0.5], [5000], 8000), [], roomy).size(), 0)
	var found: Array[SoakCheck.Violation] = _territory(_board([0.5], [5400], 8000), [], roomy)
	assert_has(_ids(found), &"territory.owned_cells_recount")


func test_the_recount_slack_comes_from_the_config() -> void:
	var loose: SoakConfig = _config_with({"share_sum_eps": 0.05})
	assert_eq(_territory(_board([0.3], [3300], 10000), [], loose).size(), 0, "0.03 is within 0.05.")
	assert_has(_ids(_territory(_board([0.3], [3300], 10000))), &"territory.owned_cells_recount")


func test_a_home_flag_foreign_for_less_than_the_grace_is_sound() -> void:
	var homes: Array[SoakCheck.HomeObs] = [_home(0, 0.0), _home(1, 0.99)]
	assert_eq(_territory(_clean_board(), homes).size(), 0)


func test_a_home_flag_foreign_for_exactly_the_grace_is_sound() -> void:
	var homes: Array[SoakCheck.HomeObs] = [_home(2, 1.0)]
	assert_eq(_territory(_clean_board(), homes).size(), 0, "Only 'longer than' the grace counts.")


func test_a_home_flag_foreign_past_the_grace_is_a_violation() -> void:
	var homes: Array[SoakCheck.HomeObs] = [_home(0, 0.2), _home(2, 1.01)]
	var found: Array[SoakCheck.Violation] = _territory(_clean_board(), homes)
	assert_eq(found.size(), 1)
	var violation: SoakCheck.Violation = _first(found, &"territory.home_foreign")
	assert_not_null(violation)
	if violation != null:
		assert_eq(violation.subject, "2", "The subject is the slot.")
		assert_almost_eq(violation.value, 1.01, 0.001)
		assert_almost_eq(violation.limit, 1.0, 0.001)


func test_the_home_grace_comes_from_the_config() -> void:
	var patient: SoakConfig = _config_with({"home_foreign_grace_s": 5.0})
	var homes: Array[SoakCheck.HomeObs] = [_home(0, 3.0)]
	assert_eq(_territory(_clean_board(), homes, patient).size(), 0)
	assert_eq(_territory(_clean_board(), homes, _config).size(), 1)


func test_a_failed_fresh_solve_is_a_violation_when_it_was_checked() -> void:
	var board: SoakCheck.TerritoryObs = _clean_board()
	board.fresh_solve_checked = true
	board.fresh_solve_matches = false
	assert_has(_ids(_territory(board)), &"territory.fresh_solve")


func test_a_matching_fresh_solve_is_sound() -> void:
	var board: SoakCheck.TerritoryObs = _clean_board()
	board.fresh_solve_checked = true
	board.fresh_solve_matches = true
	assert_eq(_territory(board).size(), 0)


func test_a_mismatch_is_ignored_when_the_fresh_solve_was_not_run() -> void:
	var board: SoakCheck.TerritoryObs = _clean_board()
	board.fresh_solve_checked = false
	board.fresh_solve_matches = false
	assert_eq(_territory(board).size(), 0)


# --- authority -------------------------------------------------------------------------------


func _intents(
	slot: int,
	sent: int,
	accepted: int,
	refused: int,
	auto_drops: int,
	blocks_placed: int
) -> SoakCheck.IntentObs:
	var obs: SoakCheck.IntentObs = SoakCheck.IntentObs.new()
	obs.slot = slot
	obs.sent = sent
	obs.accepted = accepted
	obs.refused = refused
	obs.auto_drops = auto_drops
	obs.blocks_placed = blocks_placed
	obs.prev_sent = sent
	obs.prev_accepted = accepted
	obs.prev_refused = refused
	return obs


func _authority(slots: Array[SoakCheck.IntentObs], fuzz_slot: int = -1) -> Array[SoakCheck.Violation]:
	return SoakCheck.authority(slots, fuzz_slot, _config)


func test_no_slots_is_sound() -> void:
	assert_eq(_authority([]).size(), 0)


func test_counters_that_obey_the_identities_are_sound() -> void:
	# 10 sent: 6 accepted, 4 refused. 7 blocks = 6 accepted + 1 auto drop.
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 10, 6, 4, 1, 7)]
	assert_eq(_authority(slots).size(), 0)


func test_more_blocks_than_accepted_plus_auto_drops_is_a_spawn_violation() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 10, 6, 4, 1, 8)]
	var found: Array[SoakCheck.Violation] = _authority(slots)
	assert_eq(found.size(), 1)
	var violation: SoakCheck.Violation = _first(found, &"authority.spawn_identity")
	assert_not_null(violation)
	if violation != null:
		assert_eq(violation.subject, "1", "The subject is the slot.")
		assert_almost_eq(violation.value, 8.0, 0.001)
		assert_almost_eq(violation.limit, 7.0, 0.001)


func test_fewer_blocks_than_accepted_plus_auto_drops_is_a_spawn_violation() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 10, 6, 4, 1, 6)]
	assert_has(_ids(_authority(slots)), &"authority.spawn_identity")


func test_auto_drops_count_towards_the_spawn_identity() -> void:
	# Without the auto drop term, 7 blocks against 6 accepted would break the identity.
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 6, 6, 0, 1, 7)]
	assert_eq(_authority(slots).size(), 0)


func test_only_the_slot_that_broke_the_identity_is_reported() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(0, 4, 4, 0, 0, 4), _intents(1, 4, 4, 0, 0, 9), _intents(2, 0, 0, 0, 0, 0)]
	var found: Array[SoakCheck.Violation] = _authority(slots)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].subject, "1")


func test_accepted_plus_refused_equal_to_sent_is_sound() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 8, 5, 3, 0, 5)]
	assert_eq(_authority(slots).size(), 0)


func test_accepted_plus_refused_above_sent_is_a_counter_violation() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 5, 3, 3, 0, 3)]
	var found: Array[SoakCheck.Violation] = _authority(slots)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"authority.counter_identity")
	assert_eq(found[0].subject, "1")


func test_a_sent_count_that_went_down_is_a_counter_violation() -> void:
	var obs: SoakCheck.IntentObs = _intents(1, 9, 3, 3, 0, 3)
	obs.prev_sent = 10
	assert_has(_ids(_authority([obs] as Array[SoakCheck.IntentObs])), &"authority.counter_identity")


func test_an_accepted_count_that_went_down_is_a_counter_violation() -> void:
	var obs: SoakCheck.IntentObs = _intents(1, 10, 3, 3, 0, 3)
	obs.prev_accepted = 4
	assert_has(_ids(_authority([obs] as Array[SoakCheck.IntentObs])), &"authority.counter_identity")


func test_a_refused_count_that_went_down_is_a_counter_violation() -> void:
	var obs: SoakCheck.IntentObs = _intents(1, 10, 3, 3, 0, 3)
	obs.prev_refused = 4
	assert_has(_ids(_authority([obs] as Array[SoakCheck.IntentObs])), &"authority.counter_identity")


func test_counters_that_grew_since_the_last_sample_are_sound() -> void:
	var obs: SoakCheck.IntentObs = _intents(1, 10, 6, 4, 0, 6)
	obs.prev_sent = 4
	obs.prev_accepted = 2
	obs.prev_refused = 1
	assert_eq(_authority([obs] as Array[SoakCheck.IntentObs]).size(), 0)


func test_an_accepted_fuzz_intent_is_a_violation() -> void:
	# The slot's own books balance (1 accepted, 1 block), so only the fuzz rule fires.
	var slots: Array[SoakCheck.IntentObs] = [_intents(0, 0, 0, 0, 0, 0), _intents(1, 5, 1, 4, 0, 1)]
	var found: Array[SoakCheck.Violation] = _authority(slots, 1)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"authority.fuzz_accepted")
	assert_eq(found[0].subject, "1")
	assert_almost_eq(found[0].value, 1.0, 0.001)
	assert_almost_eq(found[0].limit, 0.0, 0.001)


func test_slot_zero_can_be_the_fuzz_slot() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(0, 5, 1, 4, 0, 1), _intents(1, 5, 5, 0, 0, 5)]
	var found: Array[SoakCheck.Violation] = _authority(slots, 0)
	assert_eq(_count(found, &"authority.fuzz_accepted"), 1)


func test_a_fuzz_slot_with_nothing_accepted_is_sound() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 40, 0, 40, 0, 0)]
	assert_eq(_authority(slots, 1).size(), 0)


func test_accepted_intents_on_other_slots_are_not_fuzz_violations() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(0, 5, 5, 0, 0, 5), _intents(1, 40, 0, 40, 0, 0)]
	assert_eq(_authority(slots, 1).size(), 0)


func test_without_a_fuzz_slot_accepted_intents_are_fine() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(1, 5, 5, 0, 0, 5)]
	assert_eq(_authority(slots, -1).size(), 0)


func test_a_fuzz_slot_missing_from_the_observations_is_sound() -> void:
	var slots: Array[SoakCheck.IntentObs] = [_intents(0, 5, 5, 0, 0, 5)]
	assert_eq(_authority(slots, 4).size(), 0)


# --- budget ----------------------------------------------------------------------------------


func _curve(budget_ms: float = BUDGET_MS) -> TickBudgetCurve:
	return TickBudgetCurve.new(
		_config.curve_bands,
		_config.curve_band_half_width_fraction,
		budget_ms,
		_config.curve_bucket_ms,
		_config.curve_max_ms
	)


func _fill(curve: TickBudgetCurve, band_centre: int, ticks: int, cost_ms: float) -> void:
	for _i: int in ticks:
		curve.record(cost_ms, band_centre)


func _budget(
	role: StringName,
	curve: TickBudgetCurve,
	sim_rate: float = 60.0,
	hz: int = PHYSICS_HZ,
	snapshot_bps: float = 0.0,
	monitor_us: int = 0,
	config: SoakConfig = _config
) -> Array[SoakCheck.Violation]:
	return SoakCheck.budget(role, curve, sim_rate, hz, snapshot_bps, monitor_us, config)


func test_an_empty_curve_and_healthy_numbers_are_sound() -> void:
	assert_eq(_budget(HOST, _curve()).size(), 0)
	assert_eq(_budget(CLIENT, _curve()).size(), 0)


func test_a_band_p99_over_budget_fails_the_host_invariant() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 600, 20.05)
	var found: Array[SoakCheck.Violation] = _budget(HOST, curve)
	assert_eq(found.size(), 1)
	var violation: SoakCheck.Violation = _first(found, &"budget.host_tick_p99")
	assert_not_null(violation)
	if violation != null:
		assert_almost_eq(violation.value, 20.05, 0.2)
		assert_almost_eq(violation.limit, BUDGET_MS, 0.01)


func test_a_band_p99_over_budget_fails_the_client_invariant() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 600, 20.05)
	var found: Array[SoakCheck.Violation] = _budget(CLIENT, curve)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.client_tick_p99")


func test_a_band_p99_within_budget_is_sound() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 3000, 5.05)
	assert_eq(_budget(HOST, curve).size(), 0)


func test_a_band_under_curve_min_ticks_is_not_a_verdict() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 599, 40.05)
	assert_eq(_budget(HOST, curve).size(), 0, "599 ticks is 'not reached'.")


func test_a_band_with_exactly_curve_min_ticks_is_a_verdict() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 600, 40.05)
	assert_eq(_budget(HOST, curve).size(), 1)


func test_the_min_ticks_threshold_comes_from_the_config() -> void:
	var lenient: SoakConfig = _config_with({"curve_min_ticks": 50})
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 1000, 50, 40.05)
	assert_eq(_budget(HOST, curve, 60.0, PHYSICS_HZ, 0.0, 0, lenient).size(), 1)
	var fewer: TickBudgetCurve = _curve()
	_fill(fewer, 1000, 49, 40.05)
	assert_eq(_budget(HOST, fewer, 60.0, PHYSICS_HZ, 0.0, 0, lenient).size(), 0)


func test_p99_is_judged_not_the_mean_or_the_max() -> void:
	# 5 slow ticks in 600 is under 1 %, so the p99 stays cheap even though the max is not.
	var rare: TickBudgetCurve = _curve()
	_fill(rare, 1000, 595, 5.05)
	_fill(rare, 1000, 5, 30.05)
	assert_eq(_budget(HOST, rare).size(), 0)
	# 10 slow ticks in 600 is over 1 %, so the p99 is slow although the mean is cheap.
	var common: TickBudgetCurve = _curve()
	_fill(common, 1000, 590, 5.05)
	_fill(common, 1000, 10, 30.05)
	assert_eq(_budget(HOST, common).size(), 1)


func test_each_reached_band_over_budget_is_its_own_violation() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 250, 700, 3.05)
	_fill(curve, 500, 700, 25.05)
	_fill(curve, 1000, 700, 25.05)
	_fill(curve, 1500, 100, 90.05)
	var found: Array[SoakCheck.Violation] = _budget(CLIENT, curve)
	assert_eq(_count(found, &"budget.client_tick_p99"), 2, "Bands 500 and 1000; 1500 not reached.")


func test_the_budget_follows_the_physics_rate() -> void:
	# At 30 Hz a tick may take 33.3 ms, so a 20 ms p99 is sound there but not at 60 Hz.
	var slow_hz_budget: float = _config.tick_budget_fraction * 1000.0 / 30.0
	var curve: TickBudgetCurve = _curve(slow_hz_budget)
	_fill(curve, 1000, 600, 20.05)
	assert_eq(_budget(HOST, curve, 30.0, 30).size(), 0)
	var strict: TickBudgetCurve = _curve(BUDGET_MS)
	_fill(strict, 1000, 600, 20.05)
	assert_eq(_budget(HOST, strict, 60.0, 60).size(), 1)


func test_the_budget_follows_the_budget_fraction() -> void:
	var half: SoakConfig = _config_with({"tick_budget_fraction": 0.5})
	var curve: TickBudgetCurve = _curve(0.5 * BUDGET_MS)
	_fill(curve, 1000, 600, 10.05)
	assert_eq(_budget(HOST, curve, 60.0, PHYSICS_HZ, 0.0, 0, half).size(), 1, "10 ms > 8.33 ms.")
	var whole: TickBudgetCurve = _curve(BUDGET_MS)
	_fill(whole, 1000, 600, 10.05)
	assert_eq(_budget(HOST, whole).size(), 0, "10 ms < 16.67 ms.")


func test_a_sim_rate_below_the_minimum_is_a_violation() -> void:
	# sim_rate_min 0.99 of 60 Hz is 59.4 frames per second.
	var found: Array[SoakCheck.Violation] = _budget(HOST, _curve(), 59.3)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.sim_rate")
	assert_almost_eq(found[0].value, 59.3, 0.001)
	assert_almost_eq(found[0].limit, 59.4, 0.01)


func test_a_sim_rate_at_or_above_the_minimum_is_sound() -> void:
	assert_eq(_budget(HOST, _curve(), 59.5).size(), 0)
	assert_eq(_budget(HOST, _curve(), 60.0).size(), 0)
	assert_eq(_budget(CLIENT, _curve(), 61.0).size(), 0)


func test_a_sim_rate_exactly_at_the_floor_is_sound() -> void:
	# 0.99 x 100 Hz = 99 frames per second, exact in binary floating point.
	assert_eq(_budget(HOST, _curve(), 99.0, 100).size(), 0)
	assert_eq(_budget(HOST, _curve(), 98.9, 100).size(), 1)


func test_the_sim_rate_floor_follows_the_physics_rate() -> void:
	assert_eq(_budget(HOST, _curve(), 59.0, 30).size(), 0, "59 fps is plenty at 30 Hz.")
	assert_eq(_budget(HOST, _curve(), 29.0, 30).size(), 1, "29 fps is below 0.99 x 30.")


func test_a_stalled_sim_is_a_violation() -> void:
	assert_has(_ids(_budget(CLIENT, _curve(), 0.0)), &"budget.sim_rate")


func test_snapshot_bytes_per_second_at_the_cap_are_sound() -> void:
	assert_eq(_budget(HOST, _curve(), 60.0, PHYSICS_HZ, 5.0e6).size(), 0)
	assert_eq(_budget(HOST, _curve(), 60.0, PHYSICS_HZ, 0.0).size(), 0)


func test_snapshot_bytes_per_second_over_the_cap_are_a_violation() -> void:
	var found: Array[SoakCheck.Violation] = _budget(HOST, _curve(), 60.0, PHYSICS_HZ, 5.0e6 + 1000.0)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.snapshot_bps")
	assert_almost_eq(found[0].value, 5.001e6, 1.0)
	assert_almost_eq(found[0].limit, 5.0e6, 1.0)


func test_snapshot_bytes_are_judged_on_the_host_only() -> void:
	var found: Array[SoakCheck.Violation] = _budget(CLIENT, _curve(), 60.0, PHYSICS_HZ, 9.0e6)
	assert_eq(_count(found, &"budget.snapshot_bps"), 0, "SOAK_PLAN 6.2 lists snapshot_bps as host.")


func test_the_snapshot_cap_comes_from_the_config() -> void:
	var tight: SoakConfig = _config_with({"snapshot_bps_max": 1000.0})
	assert_has(_ids(_budget(HOST, _curve(), 60.0, PHYSICS_HZ, 2000.0, 0, tight)), &"budget.snapshot_bps")


func test_monitor_cost_at_the_limit_is_sound() -> void:
	assert_eq(_budget(HOST, _curve(), 60.0, PHYSICS_HZ, 0.0, 2000).size(), 0)
	assert_eq(_budget(HOST, _curve(), 60.0, PHYSICS_HZ, 0.0, 412).size(), 0)


func test_monitor_cost_over_the_limit_is_a_violation() -> void:
	var found: Array[SoakCheck.Violation] = _budget(CLIENT, _curve(), 60.0, PHYSICS_HZ, 0.0, 2001)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.monitor_overhead")
	assert_almost_eq(found[0].value, 2001.0, 0.001)
	assert_almost_eq(found[0].limit, 2000.0, 0.001)


func test_independent_budget_breaches_are_all_reported() -> void:
	var curve: TickBudgetCurve = _curve()
	_fill(curve, 500, 700, 25.05)
	var found: Array[SoakCheck.Violation] = _budget(HOST, curve, 10.0, PHYSICS_HZ, 9.0e6, 5000)
	var ids: Array[StringName] = _ids(found)
	assert_has(ids, &"budget.host_tick_p99")
	assert_has(ids, &"budget.sim_rate")
	assert_has(ids, &"budget.snapshot_bps")
	assert_has(ids, &"budget.monitor_overhead")
	assert_eq(found.size(), 4)


# --- memory ----------------------------------------------------------------------------------


func _memory(
	mem_start: float, mem_end: float, bodies_start: int, bodies_end: int, orphans: int = 0, config: SoakConfig = _config
) -> Array[SoakCheck.Violation]:
	return SoakCheck.memory(mem_start, mem_end, bodies_start, bodies_end, orphans, config)


func test_memory_per_body_at_the_limit_is_sound() -> void:
	# 25 MB over 100 bodies is exactly mem_per_body_max_mb = 0.25.
	assert_eq(_memory(200.0, 225.0, 0, 100).size(), 0)


func test_memory_per_body_over_the_limit_is_a_violation() -> void:
	var found: Array[SoakCheck.Violation] = _memory(200.0, 225.5, 0, 100)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.memory_per_body")
	assert_almost_eq(found[0].value, 0.255, 0.0001)
	assert_almost_eq(found[0].limit, 0.25, 0.0001)


func test_memory_per_body_uses_the_growth_not_the_totals() -> void:
	# 1000 MB at the end but only 100 MB gained over 400 new bodies: 0.25 MB each.
	assert_eq(_memory(900.0, 1000.0, 100, 500).size(), 0)
	assert_eq(_memory(900.0, 1200.0, 100, 500).size(), 1, "300 MB over 400 bodies is 0.75 each.")


func test_memory_that_shrank_is_sound() -> void:
	assert_eq(_memory(500.0, 300.0, 0, 400).size(), 0)


func test_the_memory_limit_comes_from_the_config() -> void:
	var tight: SoakConfig = _config_with({"mem_per_body_max_mb": 0.01})
	assert_has(_ids(_memory(100.0, 110.0, 0, 100, 0, tight)), &"budget.memory_per_body")
	assert_eq(_memory(100.0, 110.0, 0, 100).size(), 0)


func test_no_orphan_nodes_is_sound() -> void:
	assert_eq(_memory(100.0, 100.0, 0, 0, 0).size(), 0)


func test_an_orphan_node_is_a_violation() -> void:
	var found: Array[SoakCheck.Violation] = _memory(100.0, 100.0, 0, 0, 1)
	assert_eq(found.size(), 1)
	if found.is_empty():
		return
	assert_eq(found[0].invariant, &"budget.orphan_nodes")
	assert_almost_eq(found[0].value, 1.0, 0.001)
	assert_almost_eq(found[0].limit, 0.0, 0.001)


func test_the_orphan_limit_comes_from_the_config() -> void:
	var lenient: SoakConfig = _config_with({"orphan_nodes_max": 5})
	assert_eq(_memory(100.0, 100.0, 0, 0, 5, lenient).size(), 0)
	assert_eq(_memory(100.0, 100.0, 0, 0, 6, lenient).size(), 1)
