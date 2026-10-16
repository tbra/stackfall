extends GutTest
## core/audio/ClaimTensionState.gd (Bontago-1pi.114): local-player-relative
## claim tension and interrupt detection.

const MINE: int = 1
const RIVAL: int = 2

var _config: AudioConfig
var _state: ClaimTensionState


func before_each() -> void:
	_config = (load("res://config/audio/audio_config.tres") as AudioConfig).duplicate() as AudioConfig
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


func test_rival_break_reports_not_mine() -> void:
	_state.update(RIVAL, 0.6, MINE, true)
	_state.update(-1, 0.0, MINE, true)
	assert_false(bool(_state.take_interrupt()["was_mine"]))


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


