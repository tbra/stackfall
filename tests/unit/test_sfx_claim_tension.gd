extends GutTest
## autoload/Sfx.gd beacon-claim tension layer (Bontago-1pi.114): volume, duck,
## sting and reset, in both contextual_music modes. A fresh Sfx instance is
## used so nothing depends on the shipped assets; state is driven through the
## real Events signals.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")
const MINE: int = 1
const RIVAL: int = 2
const NOT_LOCAL: int = -2

var _sfx: Node
var _config: AudioConfig
var _dir: String
var _settings_path: String


func before_each() -> void:
	_settings_path = OS.get_user_data_dir().path_join("test_sfx_claim_settings_tmp.cfg")
	Settings.set_config_path_for_test(_settings_path)
	_config = (load("res://config/audio_config.tres") as AudioConfig).duplicate() as AudioConfig
	_config.claim_interrupt_min_interval_s = 0.0
	_dir = OS.get_user_data_dir().path_join("test_sfx_claim_tmp")
	DirAccess.make_dir_recursive_absolute(_dir)
	for filename: String in [_config.claim_tension_file, _config.claim_interrupt_file, _config.claim_rival_broken_file]:
		_write_wav(_dir.path_join(filename))
	_build_sfx()


func after_each() -> void:
	for filename: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(filename))
	Settings.set_config_path_for_test(Settings.default_config_path())
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)


func _build_sfx() -> void:
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _config
	add_child_autofree(_sfx)
	_sfx.set_root_dir_for_test(_dir)
	_sfx._claim_test_local_team = MINE
	_sfx._claim_test_live = true


func _write_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)
	wav.data = data
	assert_eq(wav.save_to_wav(path), OK)


func _stings(before: int) -> int:
	return (_sfx._next_sfx_player_index - before + _sfx._sfx_players.size()) % _sfx._sfx_players.size()


func _volume_at(progress: float) -> float:
	Events.goal_capture_progress.emit(MINE, progress)
	return _sfx.claim_tension_target_volume_db()


func test_volume_and_duck_follow_progress() -> void:
	for contextual: bool in [false, true]:
		_config.contextual_music_enabled = contextual
		_sfx.reset_claim_tension()
		var silent: float = _volume_at(0.0)
		var half: float = _volume_at(0.5)
		var full: float = _volume_at(1.0)
		assert_eq(silent, SFX_SCRIPT.MUSIC_STEM_MUTE_DB, "contextual=%s" % contextual)
		assert_gt(half, silent)
		assert_gt(full, half)
		assert_almost_eq(full, _config.claim_tension_max_db, 0.001)
		assert_almost_eq(_sfx.claim_duck_target_db(), _config.claim_music_duck_db, 0.001)
		Events.goal_capture_progress.emit(MINE, 0.5)
		assert_between(_sfx.claim_duck_target_db(), _config.claim_music_duck_db, 0.0)
		assert_gt(_sfx.claim_tension_pitch_scale(), 1.0)


func test_duck_reaches_playlist_volume() -> void:
	_config.contextual_music_enabled = true
	_sfx._music_envelope = 1.0
	_sfx._apply_playlist_volume()
	var base: float = _sfx._music_player.volume_db
	_sfx._set_claim_duck(-6.0)
	_sfx._apply_playlist_volume()
	assert_almost_eq(_sfx._music_player.volume_db, base - 6.0, 0.001)


func test_rival_is_quieter_darker() -> void:
	Events.goal_capture_progress.emit(MINE, 0.8)
	var mine_db: float = _sfx.claim_tension_target_volume_db()
	var mine_pitch: float = _sfx.claim_tension_pitch_scale()
	_sfx._claim_test_local_team = NOT_LOCAL
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.goal_capture_progress.emit(RIVAL, 0.8)
	assert_lt(_sfx.claim_tension_target_volume_db(), mine_db)
	assert_lt(_sfx.claim_tension_pitch_scale(), mine_pitch)


func test_sting_once_per_break_and_not_on_win() -> void:
	var before: int = _sfx._next_sfx_player_index
	Events.goal_capture_progress.emit(MINE, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_stings(before), 1, "one sting for one break")
	# Win: the zero reading is followed by match_won in the same call stack.
	before = _sfx._next_sfx_player_index
	Events.goal_capture_progress.emit(MINE, 1.0)
	Events.goal_capture_progress.emit(-1, 0.0)
	Events.match_won.emit(MINE)
	await get_tree().process_frame
	assert_eq(_stings(before), 0, "a win never stings")
	assert_eq(_sfx.claim_tension_level(), 0.0)


func test_rival_break_plays_a_cue_and_signals() -> void:
	_sfx._claim_test_local_team = NOT_LOCAL
	watch_signals(Events)
	var before: int = _sfx._next_sfx_player_index
	Events.goal_capture_progress.emit(RIVAL, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_stings(before), 1)
	assert_signal_emitted_with_parameters(Events, "claim_interrupted", [false, 0.7])


func test_not_live_break_is_silent() -> void:
	_sfx._claim_test_live = false
	var before: int = _sfx._next_sfx_player_index
	Events.goal_capture_progress.emit(MINE, 0.7)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_stings(before), 0)


func test_scope_reset_clears_layer() -> void:
	Events.goal_capture_progress.emit(MINE, 0.9)
	assert_true(_sfx._claim_player.playing)
	Events.match_scope_reset.emit()
	assert_eq(_sfx.claim_tension_level(), 0.0)
	assert_eq(_sfx.claim_duck_applied_db(), 0.0)
	assert_false(_sfx._claim_player.playing)
	assert_eq(_sfx._claim_player.volume_db, SFX_SCRIPT.MUSIC_STEM_MUTE_DB)


func test_missing_files_are_a_silent_noop() -> void:
	for filename: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(filename))
	_sfx.set_root_dir_for_test(_dir)
	var before: int = _sfx._next_sfx_player_index
	Events.goal_capture_progress.emit(MINE, 0.7)
	assert_false(_sfx._claim_player.playing)
	Events.goal_capture_progress.emit(-1, 0.0)
	await get_tree().process_frame
	assert_eq(_stings(before), 0)


func test_disabled_music_silences_bed() -> void:
	_sfx.set_music_enabled(false)
	Events.goal_capture_progress.emit(MINE, 0.9)
	assert_eq(_sfx.claim_tension_target_volume_db(), SFX_SCRIPT.MUSIC_STEM_MUTE_DB)


func test_client_extrapolates_between_sparse_updates_and_stops_on_break() -> void:
	_sfx._claim_test_client = true
	_sfx._claim_test_hold_s = 20.0
	Events.goal_capture_progress.emit(MINE, 0.1)
	var at_first: float = _sfx.claim_tension_level()
	_sfx._claim_extrapolate(5.0)  # 0.35
	var mid: float = _sfx.claim_tension_level()
	assert_gt(mid, at_first, "keeps rising with no new packet")
	_sfx._claim_extrapolate(5.0)  # 0.6
	assert_gt(_sfx.claim_tension_level(), mid)
	Events.goal_capture_progress.emit(MINE, 0.6)  # snaps to the received value
	assert_almost_eq(_sfx._claim_ext.progress(), 0.6, 0.0001)
	_sfx._claim_extrapolate(100.0)
	assert_almost_eq(_sfx._claim_ext.progress(), 1.0, 0.0001, "capped at a full hold")
	Events.goal_capture_progress.emit(-1, 0.0)
	var level_after_break: float = _sfx.claim_tension_level()
	_sfx._claim_extrapolate(5.0)
	assert_eq(level_after_break, 0.0)
	assert_eq(_sfx.claim_tension_level(), 0.0, "no extrapolation after a break")


func test_host_does_not_extrapolate() -> void:
	_sfx._claim_test_client = false
	_sfx._claim_test_hold_s = 20.0
	Events.goal_capture_progress.emit(MINE, 0.3)
	var before: float = _sfx.claim_tension_level()
	_sfx._claim_extrapolate(5.0)
	assert_eq(_sfx.claim_tension_level(), before)


func test_holding_update_ignored_when_match_not_live() -> void:
	Events.goal_capture_progress.emit(MINE, 0.9)
	Events.match_won.emit(MINE)
	_sfx._claim_test_live = false
	Events.goal_capture_progress.emit(MINE, 1.0)  # END zero-time redraw
	assert_eq(_sfx.claim_tension_level(), 0.0)
	assert_false(_sfx._claim_player.playing and _sfx._claim_player.volume_db > SFX_SCRIPT.MUSIC_STEM_MUTE_DB)


func test_unchanged_target_makes_no_new_tweens() -> void:
	Events.goal_capture_progress.emit(-1, 0.0)
	assert_null(_sfx._claim_tween, "silent and already silent: no tween")
	Events.goal_capture_progress.emit(MINE, 0.5)
	var tween: Tween = _sfx._claim_tween
	assert_not_null(tween)
	Events.goal_capture_progress.emit(MINE, 0.5)
	assert_same(_sfx._claim_tween, tween, "same target keeps the running tween")
