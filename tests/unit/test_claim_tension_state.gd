extends GutTest
## core/audio/ClaimTensionState.gd (Bontago-1pi.114): local-player-relative
## claim tension and interrupt detection.

const MINE: int = 1
const RIVAL: int = 2

var _config: AudioConfig
var _state: ClaimTensionState


func before_each() -> void:
	_config = (load("res://config/audio_config.tres") as AudioConfig).duplicate() as AudioConfig
	_config.claim_interrupt_min_interval_s = 0.0
	_state = ClaimTensionState.new(_config)


func test_level_zero_before_start_and_rises_monotonically() -> void:
	_state.update(MINE, _config.claim_tension_start_progress * 0.5, MINE, true)
	assert_eq(_state.level(), 0.0)
	var previous: float = 0.0
	for step: int in range(1, 11):
		_state.update(MINE, float(step) / 10.0, MINE, true)
		assert_gte(_state.level(), previous)
		previous = _state.level()
	assert_almost_eq(_state.level(), 1.0, 0.0001, "full hold is full tension")


func test_level_plateaus_at_one_when_progress_stays_full() -> void:
	_state.update(MINE, 1.0, MINE, true)
	var first: float = _state.level()
	_state.update(MINE, 1.0, MINE, true)
	assert_eq(_state.level(), first)
	assert_lte(first, 1.0)


func test_rival_is_quieter_than_mine() -> void:
	_state.update(MINE, 0.8, MINE, true)
	var mine_level: float = _state.level()
	assert_true(_state.is_mine())
	_state.reset()
	_state.update(RIVAL, 0.8, MINE, true)
	assert_false(_state.is_mine())
	assert_almost_eq(_state.level(), mine_level * _config.claim_rival_tension_scale, 0.0001)


func test_break_after_min_progress_gives_exactly_one_interrupt() -> void:
	_state.update(MINE, _config.claim_interrupt_min_progress + 0.1, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	var info: Dictionary = _state.take_interrupt()
	assert_true(bool(info["was_mine"]))
	assert_gte(float(info["peak"]), _config.claim_interrupt_min_progress)
	assert_true(_state.take_interrupt().is_empty(), "consumed once")
	_state.update(-1, 0.0, MINE, true)
	assert_true(_state.take_interrupt().is_empty(), "no second interrupt while idle")
	assert_eq(_state.level(), 0.0)


func test_flicker_below_min_progress_does_not_interrupt() -> void:
	_state.update(MINE, _config.claim_interrupt_min_progress * 0.5, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	assert_true(_state.take_interrupt().is_empty())


func test_break_when_match_not_live_does_not_interrupt() -> void:
	_state.update(MINE, 0.9, MINE, true)
	_state.update(-1, 0.0, MINE, false)
	assert_true(_state.take_interrupt().is_empty())


func test_win_clears_pending_interrupt() -> void:
	_state.update(MINE, 1.0, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	_state.mark_won()
	assert_true(_state.take_interrupt().is_empty(), "a win never stings")
	assert_eq(_state.level(), 0.0)


func test_rival_break_reports_not_mine() -> void:
	_state.update(RIVAL, 0.6, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	assert_false(bool(_state.take_interrupt()["was_mine"]))


func test_team_takeover_counts_as_break_of_previous_holder() -> void:
	_state.update(MINE, 0.7, MINE, true)
	_state.update(RIVAL, 0.02, MINE, true)
	var info: Dictionary = _state.take_interrupt()
	assert_true(bool(info["was_mine"]))
	assert_false(_state.is_mine())
	assert_eq(_state.level(), 0.0)


func test_interrupt_rate_limited() -> void:
	_config.claim_interrupt_min_interval_s = 5.0
	_state.update(MINE, 0.6, MINE, true, 10.0)
	_state.update(-1, 0.0, MINE, true, 10.0)
	assert_false(_state.take_interrupt().is_empty())
	_state.update(MINE, 0.6, MINE, true, 11.0)
	_state.update(-1, 0.0, MINE, true, 11.0)
	assert_true(_state.take_interrupt().is_empty(), "inside the interval")
	_state.update(MINE, 0.6, MINE, true, 20.0)
	_state.update(-1, 0.0, MINE, true, 20.0)
	assert_false(_state.take_interrupt().is_empty())


func test_reset_clears_everything() -> void:
	_state.update(MINE, 0.9, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	_state.reset()
	assert_eq(_state.level(), 0.0)
	assert_eq(_state.progress(), 0.0)
	assert_true(_state.take_interrupt().is_empty())
