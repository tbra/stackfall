extends GutTest
## autoload/Sfx.gd + config/audio/AudioConfig.gd: audio loaded at
## runtime from a folder on disk, never through Godot's import pipeline.
## Uses a fresh Sfx instance pointed at a temp folder (set_root_dir_for_test)
## rather than the real "Sfx" autoload singleton, so these tests don't depend
## on the shipped effect files.

const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")


var _sfx: Node
var _config: AudioConfig
var _tmp_dir: String
var _empty_dir: String
var _settings_cfg_path: String


func before_each() -> void:
	# Sfx.gd talks to the real "Settings" autoload singleton directly
	# (Settings.master_volume_db()), so isolating this
	# file's Settings state means redirecting that singleton itself to a
	# temp cfg (set_config_path_for_test), not creating a second instance --
	# restored to user://settings.cfg in after_each so nothing leaks into the
	# owner's real settings file or another test file.
	_settings_cfg_path = OS.get_user_data_dir().path_join("test_sfx_settings_tmp.cfg")
	_delete_if_exists(_settings_cfg_path)
	Settings.set_config_path_for_test(_settings_cfg_path)

	_config = load("res://config/audio/audio_config.tres").duplicate() as AudioConfig
	_config.contextual_music_enabled = false # Legacy disk/stem fixtures only.
	_config.bundled_theme = null # Existing fixtures test optional disk audio.
	_config.bundled_theme_path = ""
	_sfx = autofree(SFX_SCRIPT.new())
	_sfx.config = _config
	add_child_autofree(_sfx)

	_tmp_dir = OS.get_user_data_dir().path_join("test_sfx_tmp")
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_write_tiny_wav(_tmp_dir.path_join(_config.click_file))
	_write_tiny_wav(_tmp_dir.path_join(_config.gift_claimed_file))
	_write_tiny_wav(_tmp_dir.path_join(_config.gift_spawn_file))
	for filename: String in _config.thud_files:
		_write_tiny_wav(_tmp_dir.path_join(filename))

	_empty_dir = OS.get_user_data_dir().path_join("test_sfx_tmp_empty")
	DirAccess.make_dir_recursive_absolute(_empty_dir)
	for existing: String in DirAccess.get_files_at(_empty_dir):
		DirAccess.remove_absolute(_empty_dir.path_join(existing))


func after_each() -> void:
	for filename: String in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(filename))
	# The gift-claimed tests below host a real private loopback session; Net is a
	# singleton that outlives this one test file, so it must always come back OFFLINE.
	Net.leave()
	# Restore the real Settings singleton to its own persisted file so later
	# tests (and the user's real user://settings.cfg) never see this test
	# file's temp master_volume_db values.
	Settings.set_config_path_for_test(Settings.REAL_CONFIG_PATH)
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


func test_play_returns_false_for_unknown_event() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	assert_false(_sfx.play(&"not_a_real_event"))


## effects were inaudible next to the music. The bundled wavs
## are now normalised (a script removed in (see git history)); these guard the playback side.
const BUNDLED_CUE_EVENTS: Array[StringName] = [
	AudioConfig.EVENT_THUD, AudioConfig.EVENT_REJECTED, AudioConfig.EVENT_CLICK,
	AudioConfig.EVENT_START_GAME, AudioConfig.EVENT_HOVER, AudioConfig.EVENT_DROP,
	AudioConfig.EVENT_BOUNCE, AudioConfig.EVENT_CREAK, AudioConfig.EVENT_ROCKET,
	AudioConfig.EVENT_BOMB, AudioConfig.EVENT_VOLCANO, AudioConfig.EVENT_QUAKE,
	AudioConfig.EVENT_PROPELLER, AudioConfig.EVENT_BREAKAGE, AudioConfig.EVENT_GIFT_CLAIMED,
	AudioConfig.EVENT_GIFT_SPAWNED,
]
func test_every_bundled_cue_resolves_to_a_stream() -> void:
	_sfx.set_root_dir_for_test(ProjectSettings.globalize_path("res://assets/audio/sfx"))
	for event: StringName in BUNDLED_CUE_EVENTS:
		for filename: String in _config.files_for_event(event):
			var stream: AudioStream = _sfx._load_stream(filename)
			assert_not_null(stream, "cue %s file %s should load from assets/audio/sfx" % [event, filename])
			assert_gt(stream.get_length(), 0.0, "%s should have a non-zero length" % filename)


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


func test_gift_flight_start_plays_spawn_jingle() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_gift_flight_spawned(7, Vector3.UP * 18.0, Vector3.ZERO)
	assert_true(_any_player_playing(), "A new gift flight must cue the spawn chime")


const SPECIALS_DIR: String = "res://config/gifts/specials"


func test_every_shipped_special_has_a_cue_that_loads() -> void:
	_sfx.set_root_dir_for_test(ProjectSettings.globalize_path("res://assets/audio/sfx"))
	var checked: int = 0
	for file: String in DirAccess.get_files_at(SPECIALS_DIR):
		if not file.ends_with(".tres"):
			continue
		var def: SpecialDef = load(SPECIALS_DIR.path_join(file)) as SpecialDef
		if def == null:
			continue
		# A one-shot on its trigger, a loop for a timed window, or (the bean) a hop sound.
		var filename: String = _config.special_cue_files.get(def.id, "")
		if filename.is_empty():
			filename = _config.special_loop_files.get(def.id, "")
		if filename.is_empty() and def.id == &"jumping_bean":
			filename = _config.bean_hop_file
		assert_false(filename.is_empty(), "special %s needs a sound" % def.id)
		var stream: AudioStream = _sfx._load_stream(filename)
		assert_not_null(stream, "special %s cue %s should load from assets/audio/sfx" % [def.id, filename])
		checked += 1
	assert_gt(checked, 0, "fixture: at least one SpecialDef found")
	for file: String in [_config.glue_hit_file, _config.drop_file]:
		assert_not_null(_sfx._load_stream(file), "%s should load from assets/audio/sfx" % file)


func test_special_consumed_loops_for_the_window_and_trigger_fades_it() -> void:
	_write_tiny_wav(_tmp_dir.path_join(_config.special_loop_files[&"earthquake"]))
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_special_consumed(0, &"earthquake")
	assert_eq(_sfx._special_loops.size(), 1, "the rumble starts when the gift is used")
	var player: AudioStreamPlayer = _sfx._special_loops[0]["player"] as AudioStreamPlayer
	assert_true(player.playing)
	assert_eq((player.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_FORWARD, "it loops")
	_sfx._on_special_triggered(-1, &"earthquake", Vector3.ZERO, 0)
	assert_eq(_sfx._special_loops.size(), 0, "the window's end fades it out")


func test_special_triggered_plays_its_cue() -> void:
	_write_tiny_wav(_tmp_dir.path_join(_config.special_cue_files[&"bomb"]))
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_special_triggered(5, &"bomb", Vector3.ZERO, 0)
	assert_true(_any_player_playing(), "a triggered special must sound")


func test_special_triggered_with_an_unknown_id_is_silent() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_special_triggered(5, &"not_a_special", Vector3.ZERO, 0)
	assert_false(_any_player_playing())


func test_special_triggered_is_silent_during_a_world_replay() -> void:
	_write_tiny_wav(_tmp_dir.path_join(_config.special_cue_files[&"bomb"]))
	_sfx.set_root_dir_for_test(_tmp_dir)
	_sfx._on_world_replay_changed(true)
	_sfx._on_special_triggered(5, &"bomb", Vector3.ZERO, 0)
	assert_false(_any_player_playing(), "a late joiner's replay is state, not news")


func test_gift_claimed_for_the_local_slot_plays_the_claim_sound() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	# Net defaults to OFFLINE, where is_local_slot() is true for every slot
	# (offline: one human drives all of them) -- no setup needed.
	assert_true(Net.is_offline(), "fixture: Net starts OFFLINE")

	_sfx._on_gift_claimed(1, 0, &"anvil")

	assert_true(_any_player_playing(), "the claiming slot's own claim must play a sound")


func test_gift_claimed_for_a_non_local_slot_plays_nothing() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)
	# A hosting Net drives slot 0 only, so slot 1 is somebody else's seat.
	assert_eq(Net.host_game(AgentProbe.free_udp_port(), "", false), OK)
	assert_false(Net.is_local_slot(1), "fixture: slot 1 is not this instance's seat")

	_sfx._on_gift_claimed(1, 1, &"anvil")

	assert_false(_any_player_playing(), "another slot's claim must not play a sound here")


func test_master_volume_db_offsets_play_volume_db() -> void:
	_sfx.set_root_dir_for_test(_tmp_dir)

	assert_true(_sfx.play(AudioConfig.EVENT_CLICK))
	var baseline_db: float = _first_playing_sfx_player().volume_db
	_stop_all_sfx_players()

	Settings.set_master_volume_percent(0.5)
	assert_true(_sfx.play(AudioConfig.EVENT_CLICK))
	var offset_db: float = _first_playing_sfx_player().volume_db

	assert_almost_eq(offset_db - baseline_db, linear_to_db(0.5), 0.0001)


func _first_playing_sfx_player() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _sfx._sfx_players + _sfx._ui_players:
		if player.playing:
			return player
	return null


func _stop_all_sfx_players() -> void:
	for player: AudioStreamPlayer in _sfx._sfx_players + _sfx._ui_players:
		player.stop()


# --- Adaptive music crossfade ------------

func _install_both_stem_files() -> void:
	_config.music_stem_calm_file = "calm_stem.wav"
	_config.music_stem_tense_file = "tense_stem.wav"
	_write_tiny_wav(_tmp_dir.path_join(_config.music_stem_calm_file))
	_write_tiny_wav(_tmp_dir.path_join(_config.music_stem_tense_file))
	_sfx.set_root_dir_for_test(_tmp_dir)


func test_goal_capture_progress_crossfades_toward_tense_when_stems_available() -> void:
	_install_both_stem_files()
	assert_true(_sfx._tense_stem_available, "both stem files installed -- pairing should be available")

	Events.goal_capture_progress.emit(0, 0.9)

	assert_gt(
		_sfx.tense_stem_target_volume_db(),
		_sfx.calm_stem_target_volume_db(),
		"progress above the tense threshold should target the tense stem louder than the calm one",
	)

