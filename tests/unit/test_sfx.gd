extends GutTest
## autoload/Sfx.gd + config/AudioConfig.gd: placeholder audio loaded at
## runtime from a gitignored assets/original/audio folder, never through
## Godot's import pipeline. Uses a fresh Sfx instance pointed at a temp
## folder (set_root_dir_for_test) rather than the real "Sfx" autoload
## singleton, so these tests don't depend on tools/install_original_assets.ps1
## ever having been run on this machine.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")

var _sfx: Node
var _config: AudioConfig
var _tmp_dir: String
var _empty_dir: String
var _settings_cfg_path: String


func before_each() -> void:
	# Sfx.gd talks to the real "Settings" autoload singleton directly
	# (Settings.custom_music_dir()/master_volume_db()), so isolating this
	# file's Settings state means redirecting that singleton itself to a
	# temp cfg (set_config_path_for_test), not creating a second instance --
	# restored to user://settings.cfg in after_each so nothing leaks into the
	# owner's real settings file or another test file.
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_sfx_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)

	_config = load("res://config/audio_config.tres").duplicate() as AudioConfig
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _config
	add_child_autofree(_sfx)

	_tmp_dir = OS.get_user_data_dir().path_join("test_sfx_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_write_tiny_wav(_tmp_dir.path_join(_config.click_file))
	_write_tiny_wav(_tmp_dir.path_join(_config.gift_claimed_file))
	for filename: String in _config.thud_files:
		_write_tiny_wav(_tmp_dir.path_join(filename))

	_empty_dir = OS.get_user_data_dir().path_join("test_sfx_tmp_empty")
	DirAccess.make_dir_recursive_absolute(_empty_dir)
	for existing: String in DirAccess.get_files_at(_empty_dir):
		DirAccess.remove_absolute(_empty_dir.path_join(existing))


func after_each() -> void:
	for filename: String in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(filename))
	# The gift-claimed tests below poke Net's own private mode/local-slot
	# state directly (the same underscore direct-access convention
	# tests/unit/test_gift_claim.gd documents for Match._gifts) to exercise
	# the "not the local slot" branch without a real ENet connection. Net is
	# a singleton that outlives this one test file, so it must always come
	# back to its real default afterward.
	Net._mode = Net.Mode.OFFLINE
	Net._local_slot = 0
	# Restore the real Settings singleton to its own persisted file so later
	# tests (and the owner's real user://settings.cfg) never see this test
	# file's temp custom_music_dir/master_volume_db values.
	Settings.set_config_path_for_test("user://settings.cfg")
	_delete_if_exists(_settings_cfg_path)


func _delete_if_exists(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _write_tiny_wav(path: String) -> void:
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 22050
	wav.stereo = false
	var data: PackedByteArray = PackedByteArray()
	data.resize(2205 * 2)  # ~0.1 s of 16-bit silence
	wav.data = data
	var err: Error = wav.save_to_wav(path)
	assert_eq(err, OK, "fixture wav should save cleanly: %s" % path)


func test_play_returns_true_when_file_is_installed() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	assert_true(_sfx.play(AudioConfig.EVENT_CLICK))


func test_play_returns_false_with_empty_root() -> void:
	_sfx.set_root_dir_for_test(_empty_dir)
	assert_false(_sfx.play(AudioConfig.EVENT_CLICK))


func test_play_returns_false_for_unknown_event() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	assert_false(_sfx.play(&"not_a_real_event"))


func test_event_map_covers_every_audio_config_key() -> void:
	for event: StringName in AudioConfig.ALL_EVENTS:
		var files: Array[String] = _config.files_for_event(event)
		assert_false(files.is_empty(), "AudioConfig.files_for_event(%s) should not be empty" % event)


func test_impact_below_speed_min_does_not_play() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_block_impacted(_config.impact_speed_min * 0.5)
	assert_false(_any_player_playing())


func test_impact_at_or_above_speed_min_plays() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_block_impacted(_config.impact_speed_loud)
	assert_true(_any_player_playing())


func _any_player_playing() -> bool:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		if player.playing:
			return true
	return false


func test_volume_scaling_clamps_to_configured_range() -> void:
	var below_min_db: float = _config.impact_volume_db(_config.impact_speed_min - 100.0)
	var at_min_db: float = _config.impact_volume_db(_config.impact_speed_min)
	var at_loud_db: float = _config.impact_volume_db(_config.impact_speed_loud)
	var far_above_loud_db: float = _config.impact_volume_db(_config.impact_speed_loud + 1000.0)

	assert_almost_eq(below_min_db, _config.impact_quiet_db_offset, 0.0001)
	assert_almost_eq(at_min_db, _config.impact_quiet_db_offset, 0.0001)
	assert_almost_eq(at_loud_db, _config.impact_loud_db_offset, 0.0001)
	assert_almost_eq(far_above_loud_db, _config.impact_loud_db_offset, 0.0001)


# --- Events.gift_claimed (Bontago-6y2) ----------------------------------------

func test_gift_claimed_for_the_local_slot_plays_the_claim_sound() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	# Net defaults to OFFLINE, where is_local_slot() is true for every slot
	# (hot-seat/offline: one human drives all of them) -- no setup needed.
	assert_eq(Net._mode, Net.Mode.OFFLINE, "fixture: Net starts OFFLINE")

	_sfx._on_gift_claimed(1, 0, &"anvil")

	assert_true(_any_player_playing(), "the claiming slot's own claim must play a sound")


func test_gift_claimed_for_a_non_local_slot_plays_nothing() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	Net._mode = Net.Mode.CLIENT
	Net._local_slot = 0

	_sfx._on_gift_claimed(1, 1, &"anvil")

	assert_false(_any_player_playing(), "another slot's claim must not play a sound here")


func test_gift_claimed_for_the_local_slot_plays_even_as_a_connected_client() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	Net._mode = Net.Mode.CLIENT
	Net._local_slot = 2

	_sfx._on_gift_claimed(1, 2, &"anvil")

	assert_true(_any_player_playing(), "the local slot's own claim must still play once connected as a client")


# --- Custom music folder + master volume (docs/M6_PLAN.md package C3) --------

func test_play_music_uses_custom_music_dir_when_set() -> void:
	var music_dir: String = OS.get_user_data_dir().path_join("test_sfx_custom_music")
	DirAccess.make_dir_recursive_absolute(music_dir)
	_config.music_file = "custom_track.wav"
	_write_tiny_wav(music_dir.path_join(_config.music_file))

	# The bundled root ( _tmp_dir, via set_root_dir_for_test) never has
	# "custom_track.wav" -- only the custom music folder does, so a
	# successfully playing track proves play_music() read the custom folder,
	# not the bundled one.
	_sfx.set_root_dir_for_test(_tmp_dir)
	Settings.set_custom_music_dir(music_dir)
	_sfx._music_player.stop()  # discard whatever _ready()'s own auto-play call already picked

	_sfx.play_music()

	assert_true(_sfx._music_player.playing, "play_music() should load the track from the custom music folder")

	for filename: String in DirAccess.get_files_at(music_dir):
		DirAccess.remove_absolute(music_dir.path_join(filename))
	DirAccess.remove_absolute(music_dir)


func test_play_music_falls_back_silently_when_custom_music_dir_is_missing() -> void:
	# Settings.custom_music_dir() points at a path that was never created --
	# the same "set but missing" case as an unplugged drive. This must fall
	# back to the bundled root (here _empty_dir, which has no music file
	# either) with no error, matching Sfx.gd's own "supported absence"
	# pattern for the bundled folder itself.
	Settings.set_custom_music_dir(OS.get_user_data_dir().path_join("test_sfx_custom_music_missing"))
	_sfx.set_root_dir_for_test(_empty_dir)
	_sfx._music_player.stop()  # discard whatever _ready()'s own auto-play call already picked

	_sfx.play_music()

	assert_false(_sfx._music_player.playing, "a missing custom music dir should fall back silently, not error")


func test_master_volume_db_offsets_play_volume_db() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)

	assert_true(_sfx.play(AudioConfig.EVENT_CLICK))
	var baseline_db: float = _first_playing_sfx_player().volume_db
	_stop_all_sfx_players()

	Settings.set_master_volume_db(-6.0)
	assert_true(_sfx.play(AudioConfig.EVENT_CLICK))
	var offset_db: float = _first_playing_sfx_player().volume_db

	assert_almost_eq(offset_db - baseline_db, -6.0, 0.0001)


func _first_playing_sfx_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		if player.playing:
			return player
	return null


func _stop_all_sfx_players() -> void:
	for player: AudioStreamPlayer in _sfx._sfx_players:
		player.stop()


# --- Adaptive music crossfade (docs/M7_PLAN.md P6, Bontago-xtq.31) ------------

func _install_both_stem_files() -> void:
	_config.music_stem_calm_file = "calm_stem.wav"
	_config.music_stem_tense_file = "tense_stem.wav"
	_write_tiny_wav(_tmp_dir.path_join(_config.music_stem_calm_file))
	_write_tiny_wav(_tmp_dir.path_join(_config.music_stem_tense_file))
	_sfx.set_root_dir_for_test(_tmp_dir)


func test_tense_stem_unavailable_without_a_tense_file() -> void:
	# The default fixture (before_each) never writes a file matching either
	# AudioConfig's default music_stem_calm_file/music_stem_tense_file --
	# this must resolve to "no pairing" with no error/warning, the same
	# "supported absence" every other missing-asset case in this file gets.
	_sfx.set_root_dir_for_test(_tmp_dir)

	assert_false(_sfx.tense_stem_available(), "no tense (or calm) stem file installed -- pairing unavailable")

	# Must not error when a capture starts even with nothing to crossfade to.
	Events.goal_capture_progress.emit(0, 0.9)

	assert_false(_sfx.tense_stem_available(), "still unavailable -- single-stream playback stays untouched")


func test_goal_capture_progress_crossfades_toward_tense_when_stems_available() -> void:
	_install_both_stem_files()
	assert_true(_sfx.tense_stem_available(), "both stem files installed -- pairing should be available")

	Events.goal_capture_progress.emit(0, 0.9)

	assert_gt(
		_sfx.tense_stem_target_volume_db(),
		_sfx.calm_stem_target_volume_db(),
		"progress above the tense threshold should target the tense stem louder than the calm one",
	)


func test_goal_capture_progress_returns_to_calm_when_a_capture_breaks() -> void:
	_install_both_stem_files()

	Events.goal_capture_progress.emit(0, 0.9)
	# Events.gd: "team_id is -1 with progress 0 when a capture breaks".
	Events.goal_capture_progress.emit(-1, 0.0)

	assert_gt(
		_sfx.calm_stem_target_volume_db(),
		_sfx.tense_stem_target_volume_db(),
		"a broken/reset capture should target the calm stem louder than the tense one",
	)


## Regression (Bontago-xtq.31 review, HIGH): in the shipped single-stream
## config (no tense asset installed), crossing the tense threshold must never
## leave the calm stem's own volume math muted -- it is the only music stream
## that exists. Before the fix, _on_goal_capture_progress flipped
## _tense_stem_is_active before checking _tense_stem_available, so the next
## play_music()/audio_settings_changed volume re-apply silenced the single
## stream permanently.
func test_single_stream_progress_past_threshold_then_settings_change_stays_at_baseline() -> void:
	# A real music file must exist for play_music() to have anything to set
	# _music_player.volume_db to below -- .wav (not the default .mp3) so
	# _write_tiny_wav's own fixture bytes load through the right codec.
	_config.music_file = "single_stream_music.wav"
	_write_tiny_wav(_tmp_dir.path_join(_config.music_file))
	_sfx.set_root_dir_for_test(_tmp_dir)
	assert_false(_sfx.tense_stem_available(), "fixture: no tense (or calm) stem file installed")

	Events.goal_capture_progress.emit(0, 1.0)
	_sfx.play_music()  # exercises _play_music_stream()'s own volume_db assignment

	var expected_baseline_db: float = _config.music_volume_db + Settings.master_volume_db()
	assert_almost_eq(
		_sfx._music_player.volume_db,
		expected_baseline_db,
		0.0001,
		"play_music() must not mute the only music stream after crossing the tense threshold",
	)

	# Settings.set_master_volume_db() emits audio_settings_changed, which
	# re-applies calm_stem_target_volume_db() to the live _music_player --
	# the second path the review flagged (besides play_music()) that could
	# mute the single stream permanently.
	Settings.set_master_volume_db(-3.0)
	expected_baseline_db = _config.music_volume_db + Settings.master_volume_db()
	assert_almost_eq(
		_sfx._music_player.volume_db,
		expected_baseline_db,
		0.0001,
		"audio_settings_changed must not mute the only music stream after crossing the tense threshold",
	)
	assert_almost_eq(
		_sfx.calm_stem_target_volume_db(),
		expected_baseline_db,
		0.0001,
		"calm_stem_target_volume_db() must never mute without an available tense stem",
	)


## MEDIUM (Bontago-xtq.31 review): once a real tense partner exists, the calm
## player must actually play music_stem_calm_file, not whatever music_file's
## own (possibly different) selection would otherwise pick.
func test_calm_player_uses_the_calm_stem_file_once_both_stems_are_installed() -> void:
	_install_both_stem_files()

	_sfx.play_music()

	var calm_stream: AudioStream = _sfx._music_streams_by_filename[_config.music_stem_calm_file.to_lower()]
	assert_not_null(calm_stream, "fixture: the calm stem file should have loaded into the music stream cache")
	assert_eq(
		_sfx._music_player.stream,
		calm_stream,
		"the calm player should play music_stem_calm_file once a tense partner exists",
	)


## MINOR (Bontago-xtq.31 review): hysteresis around music_tense_progress_threshold
## keeps progress hovering near the boundary from flapping the crossfade.
func test_hysteresis_keeps_the_tense_stem_active_within_the_release_margin() -> void:
	_install_both_stem_files()
	_config.music_tense_progress_threshold = 0.6
	_config.music_tense_release_margin = 0.1

	Events.goal_capture_progress.emit(0, 0.65)  # cross the rising threshold
	assert_true(_sfx._tense_stem_is_active, "fixture: crossing the threshold should activate the tense stem")

	Events.goal_capture_progress.emit(0, 0.55)  # below the threshold, still above (threshold - margin) == 0.5
	assert_true(
		_sfx._tense_stem_is_active,
		"progress within the release margin below the threshold should not flap back to calm",
	)

	Events.goal_capture_progress.emit(0, 0.45)  # below the release point
	assert_false(_sfx._tense_stem_is_active, "progress below the release point should return to calm")
