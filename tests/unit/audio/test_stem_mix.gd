extends GutTest
## core/audio/StemMix.gd: the adaptive two-stem rules (P7 plan 2.2). Contract tests that build the
## module from an AudioConfig: the tense flag flips at the threshold, falls back only below the
## release margin, and the stem volumes follow the flag. Values come from the config, not literals.

const CONFIG_PATH: String = "res://config/audio/audio_config.tres"
const SILENT_CEILING_DB: float = -60.0
const WIDE_THRESHOLD: float = 0.8
const WIDE_MARGIN: float = 0.3
const OTHER_VOLUME_DB: float = -20.0
const STEP: float = 0.01
const ZERO_MARGIN: float = 0.0

var _config: AudioConfig
var _mix: StemMix


func before_each() -> void:
	_config = (load(CONFIG_PATH) as AudioConfig).duplicate() as AudioConfig
	_mix = StemMix.new(_config)


func _release() -> float:
	return _config.music_tense_progress_threshold - _config.music_tense_release_margin


func _go_tense() -> void:
	_mix.on_progress(_config.music_tense_progress_threshold)


func test_shipped_config_has_usable_hysteresis() -> void:
	assert_gt(_config.music_tense_release_margin, 0.0, "the shipped margin is what the hysteresis tests rely on")
	assert_gt(_release(), 0.0)


func test_starts_calm_with_calm_stem_up() -> void:
	assert_false(_mix.is_tense())
	assert_eq(_mix.calm_db(), _config.music_volume_db)
	assert_lt(_mix.tense_db(), SILENT_CEILING_DB, "the tense stem is silent while calm")


func test_below_threshold_stays_calm_and_reports_no_flip() -> void:
	var flipped: bool = _mix.on_progress(_config.music_tense_progress_threshold - STEP)
	assert_false(flipped)
	assert_false(_mix.is_tense())


func test_zero_progress_while_calm_is_no_flip() -> void:
	assert_false(_mix.on_progress(0.0))
	assert_false(_mix.is_tense())


func test_reaching_threshold_flips_tense_and_returns_true() -> void:
	var flipped: bool = _mix.on_progress(_config.music_tense_progress_threshold)
	assert_true(flipped, "the rising edge is inclusive of the threshold")
	assert_true(_mix.is_tense())


func test_above_threshold_flips_tense() -> void:
	assert_true(_mix.on_progress(1.0))
	assert_true(_mix.is_tense())


func test_flip_is_reported_only_once() -> void:
	assert_true(_mix.on_progress(_config.music_tense_progress_threshold))
	assert_false(_mix.on_progress(_config.music_tense_progress_threshold + STEP))
	assert_false(_mix.on_progress(1.0))
	assert_true(_mix.is_tense())


func test_release_zone_does_not_raise_tense_from_calm() -> void:
	assert_false(_mix.on_progress(_release()))
	assert_false(_mix.on_progress(_config.music_tense_progress_threshold - STEP))
	assert_false(_mix.is_tense(), "only the plain threshold raises tense")


func test_tense_holds_at_exactly_the_release_point() -> void:
	_go_tense()
	assert_false(_mix.on_progress(_release()))
	assert_true(_mix.is_tense())


func test_tense_holds_between_release_point_and_threshold() -> void:
	_go_tense()
	assert_false(_mix.on_progress(_config.music_tense_progress_threshold - STEP))
	assert_true(_mix.is_tense())


func test_below_release_point_flips_back_and_returns_true() -> void:
	_go_tense()
	var flipped: bool = _mix.on_progress(_release() - STEP)
	assert_true(flipped)
	assert_false(_mix.is_tense())


func test_broken_capture_zero_progress_returns_to_calm() -> void:
	_go_tense()
	assert_true(_mix.on_progress(0.0))
	assert_false(_mix.is_tense())


func test_progress_hovering_at_threshold_does_not_flap() -> void:
	var flips: int = 0
	var threshold: float = _config.music_tense_progress_threshold
	for progress: float in [threshold, threshold - STEP, threshold, threshold - STEP, threshold + STEP, _release()]:
		if _mix.on_progress(progress):
			flips += 1
	assert_eq(flips, 1, "one rising flip, no flapping inside the margin")
	assert_true(_mix.is_tense())


func test_full_cycle_can_repeat() -> void:
	assert_true(_mix.on_progress(1.0))
	assert_true(_mix.on_progress(0.0))
	assert_true(_mix.on_progress(1.0))
	assert_true(_mix.is_tense())


func test_tense_state_swaps_stem_volumes() -> void:
	_go_tense()
	assert_eq(_mix.tense_db(), _config.music_volume_db)
	assert_lt(_mix.calm_db(), SILENT_CEILING_DB, "the calm stem is silent while tense")


func test_volumes_return_when_flipping_back_to_calm() -> void:
	_go_tense()
	_mix.on_progress(0.0)
	assert_eq(_mix.calm_db(), _config.music_volume_db)
	assert_lt(_mix.tense_db(), SILENT_CEILING_DB)


func test_volumes_do_not_move_inside_the_margin() -> void:
	_go_tense()
	_mix.on_progress(_release())
	assert_eq(_mix.tense_db(), _config.music_volume_db)
	assert_lt(_mix.calm_db(), SILENT_CEILING_DB)


func test_reset_from_tense_returns_to_calm() -> void:
	_go_tense()
	_mix.reset()
	assert_false(_mix.is_tense())
	assert_eq(_mix.calm_db(), _config.music_volume_db)
	assert_lt(_mix.tense_db(), SILENT_CEILING_DB)


func test_reset_is_idempotent_when_calm() -> void:
	_mix.reset()
	_mix.reset()
	assert_false(_mix.is_tense())
	assert_eq(_mix.calm_db(), _config.music_volume_db)


func test_after_reset_the_rising_edge_reports_again() -> void:
	_go_tense()
	_mix.reset()
	assert_true(_mix.on_progress(_config.music_tense_progress_threshold))
	assert_true(_mix.is_tense())


func test_after_reset_a_release_zone_value_does_not_stay_tense() -> void:
	_go_tense()
	_mix.reset()
	assert_false(_mix.on_progress(_release()), "reset forgets the tense state, so no hysteresis carries over")
	assert_false(_mix.is_tense())


func test_reads_threshold_and_margin_from_the_config() -> void:
	_config.music_tense_progress_threshold = WIDE_THRESHOLD
	_config.music_tense_release_margin = WIDE_MARGIN
	var mix: StemMix = StemMix.new(_config)
	assert_false(mix.on_progress(WIDE_THRESHOLD - STEP), "the old 0.6 threshold no longer applies")
	assert_true(mix.on_progress(WIDE_THRESHOLD))
	assert_false(mix.on_progress(WIDE_THRESHOLD - WIDE_MARGIN), "release point moved with the margin")
	assert_true(mix.on_progress(WIDE_THRESHOLD - WIDE_MARGIN - STEP))
	assert_false(mix.is_tense())


func test_zero_margin_is_a_single_threshold() -> void:
	_config.music_tense_release_margin = ZERO_MARGIN
	var mix: StemMix = StemMix.new(_config)
	var threshold: float = _config.music_tense_progress_threshold
	assert_true(mix.on_progress(threshold))
	assert_false(mix.on_progress(threshold))
	assert_true(mix.on_progress(threshold - STEP), "no hysteresis band with a zero margin")
	assert_false(mix.is_tense())


func test_reads_the_stem_volume_from_the_config() -> void:
	_config.music_volume_db = OTHER_VOLUME_DB
	var mix: StemMix = StemMix.new(_config)
	assert_eq(mix.calm_db(), OTHER_VOLUME_DB)
	mix.on_progress(1.0)
	assert_eq(mix.tense_db(), OTHER_VOLUME_DB)
