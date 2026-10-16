extends GutTest
## Bontago-1pi.194 (owner decision Bontago-9s9 b): a lapsed home claim fades
## slowly instead of resetting.

const HOLD: float = 20.0
const RATE: float = 0.25
const STEP: float = 0.1
const HOLES_ON_S: float = 2.0
const HOLES_OFF_S: float = 2.0
const BOUND_S: float = 120.0


func _objective() -> EliminationObjective:
	var objective: EliminationObjective = EliminationObjective.new(PackedInt32Array([0, 1]), HOLD, RATE)
	objective.reset(2)
	return objective


func test_brief_lapse_keeps_most_progress_and_claim_completes() -> void:
	var objective: EliminationObjective = _objective()
	objective.step_claims({1: 0}, 10.0)
	objective.step_claims({}, 2.0)
	assert_almost_eq(objective.claim_held(1), 9.5, 0.001, "2 s gap loses only 0.5 s")
	assert_eq(objective.capturing_team(), 0)
	assert_eq(objective.step_claims({1: 0}, 10.0).size(), 0)
	assert_eq(objective.step_claims({1: 0}, 0.5), PackedInt32Array([1]))


func test_long_lapse_decays_to_zero_and_clears_claim() -> void:
	var objective: EliminationObjective = _objective()
	objective.step_claims({1: 0}, 5.0)
	objective.step_claims({}, 19.0)
	assert_gt(objective.claim_held(1), 0.0)
	objective.step_claims({}, 2.0)
	assert_eq(objective.claim_held(1), 0.0)
	assert_eq(objective.capture_progress(), 0.0)
	assert_eq(objective.capturing_team(), ModeObjective.NO_TEAM)
	objective.step_claims({1: 0}, 5.0)
	assert_almost_eq(objective.claim_held(1), 5.0, 0.001, "restarts from zero")


func test_attacker_change_resets_even_while_decaying() -> void:
	var objective: EliminationObjective = _objective()
	objective.step_claims({1: 0}, 10.0)
	objective.step_claims({}, 1.0)
	objective.step_claims({1: 1}, 1.0)
	assert_almost_eq(objective.claim_held(1), 1.0, 0.001)
	assert_eq(objective.capturing_team(), 1)


func test_temporary_holes_pattern_completes_within_bound() -> void:
	var objective: EliminationObjective = _objective()
	var t: float = 0.0
	var done: bool = false
	var cycle: float = HOLES_ON_S + HOLES_OFF_S
	while t < BOUND_S and not done:
		var pressured: bool = fmod(t, cycle) < HOLES_ON_S
		var pressure: Dictionary = {1: ModeObjective.NO_TEAM} if pressured else {}
		done = objective.step_claims(pressure, STEP).has(1)
		t += STEP
	assert_true(done, "claim completes with 2 s on / 2 s off holes")
	assert_lt(t, BOUND_S)


