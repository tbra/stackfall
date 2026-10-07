extends GutTest


func test_shipped_playlists_load_playable_tracks() -> void:
	var shipped: AudioConfig = load("res://config/audio_config.tres")
	for context: StringName in [&"menu", &"lobby", &"gameplay"]:
		var paths: PackedStringArray = shipped.playlist_paths_for_context(context)
		assert_false(paths.is_empty(), "%s has at least one track" % context)
		assert_eq(shipped.playlist_track_count(context), paths.size())
		assert_true(shipped.playlist_for_context(context).is_empty(), "shipped config holds paths, not resident streams")
		for path: String in paths:
			var stream: AudioStream = load(path) as AudioStream
			assert_not_null(stream)
			assert_gt(stream.get_length(), 0.0, "tracks decode, not empty placeholders")


const SFX_SCRIPT: GDScript = preload("res://autoload/Sfx.gd")
var _sfx: Node
var _config: AudioConfig
var _settings_path: String

## The fixture pins its own silent-gap range so the gap assertions do not
## depend on AudioConfig's shipped defaults (retuned in 7416172).
const GAP_MIN_S: float = 30.0
const GAP_MAX_S: float = 75.0


func before_each() -> void:
	_settings_path = OS.get_user_data_dir().path_join("test_playlist_settings.cfg")
	DirAccess.remove_absolute(_settings_path)
	Settings.set_config_path_for_test(_settings_path)
	_config = AudioConfig.new()
	_config.menu_playlist = [_track(20.0)]
	_config.lobby_playlist = [_track(25.0)]
	_config.gameplay_playlist = [_track(30.0), _track(35.0), _track(40.0)]
	_config.music_gap_min_seconds = GAP_MIN_S
	_config.music_gap_max_seconds = GAP_MAX_S
	_sfx = SFX_SCRIPT.new()
	_sfx.config = _config
	add_child_autofree(_sfx)
	_sfx.set_process(false) # Drive scheduling deterministically, no real waits.


func after_each() -> void:
	_sfx.set_music_enabled(false)
	Settings.set_config_path_for_test(Settings.default_config_path())
	DirAccess.remove_absolute(_settings_path)


func _track(seconds: float) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.mix_rate = 1000
	stream.format = AudioStreamWAV.FORMAT_8_BITS
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(int(seconds * stream.mix_rate))
	bytes.fill(128)
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream


func _start() -> void:
	_sfx._advance_music(_config.music_initial_delay_seconds)


func test_context_track_fades_in_and_out_without_looping() -> void:
	assert_false(_sfx._music_player.playing, "initial delay is silent")
	_start()
	assert_true(_sfx._music_player.playing)
	assert_eq(_sfx._music_player.stream.get_length(), 20.0)
	assert_eq((_sfx._music_player.stream as AudioStreamWAV).loop_mode, AudioStreamWAV.LOOP_DISABLED)
	assert_eq(_config.menu_playlist[0].loop_mode, AudioStreamWAV.LOOP_FORWARD, "source resource is untouched")
	assert_eq(_sfx._music_envelope, 0.0)
	_sfx._advance_music(2.0)
	assert_almost_eq(_sfx._music_envelope, 0.5, 0.001)
	_sfx._advance_music(16.0)
	assert_almost_eq(_sfx._music_envelope, 0.4, 0.001, "last two seconds fade out")


func test_finished_track_waits_before_next_and_does_not_repeat() -> void:
	_sfx.set_music_context(&"gameplay")
	_start()
	var first: int = _sfx._last_track_by_context[&"gameplay"]
	_sfx._music_player.stop() # Simulate audio backend end then its finished signal.
	_sfx._on_music_finished()
	assert_between(_sfx._music_wait_remaining, GAP_MIN_S, GAP_MAX_S)
	_sfx._advance_music(1.0)
	assert_false(_sfx._music_player.playing, "silent gap remains")
	_sfx._advance_music(GAP_MAX_S)
	assert_true(_sfx._music_player.playing)
	assert_ne(_sfx._last_track_by_context[&"gameplay"], first)


func test_rapid_context_switch_uses_latest_playlist_and_fades_current() -> void:
	_start()
	_sfx._advance_music(4.0)
	_sfx.set_music_context(&"lobby")
	_sfx._advance_music(2.5)
	assert_almost_eq(_sfx._music_envelope, 0.5, 0.001)
	_sfx.set_music_context(&"gameplay")
	_sfx.set_music_context(&"lobby")
	_sfx._advance_music(2.5)
	assert_false(_sfx._music_player.playing)
	_start()
	assert_eq(_sfx._music_player.stream.get_length(), 25.0, "latest context wins")
	assert_false(_sfx.tense_stem_available())
	Events.goal_capture_progress.emit(0, 1.0)
	assert_false(_sfx._tense_stem_is_active, "playlist mode ignores adaptive stems")


func test_volume_change_preserves_fade_and_does_not_restart() -> void:
	_start()
	_sfx._advance_music(2.0)
	var stream: AudioStream = _sfx._music_player.stream
	var baseline: float = _sfx._music_player.volume_db
	Settings.set_master_volume_percent(0.5)
	assert_same(_sfx._music_player.stream, stream)
	assert_almost_eq(_sfx._music_envelope, 0.5, 0.001)
	assert_almost_eq(_sfx._music_player.volume_db, baseline + linear_to_db(0.5), 0.001)


func test_disable_cancels_wait_and_reenable_starts_current_context() -> void:
	_start()
	_sfx.set_music_enabled(false)
	_sfx.set_music_context(&"gameplay")
	_sfx._advance_music(1000.0)
	assert_false(_sfx._music_player.playing)
	_sfx.set_music_enabled(true)
	assert_false(_sfx._music_player.playing, "reenabling starts with initial delay")
	_start()
	assert_between(_sfx._music_player.stream.get_length(), 30.0, 40.0)


func test_custom_override_is_ignored_even_if_folder_exists() -> void:
	Settings.set_custom_music_dir(OS.get_user_data_dir())
	assert_eq(_sfx._music_root_dir, _sfx._root_dir)
	_start()
	assert_eq(_sfx._music_player.stream.get_length(), 20.0)


func test_empty_playlist_stops_cleanly_and_new_context_can_start() -> void:
	_config.menu_playlist.clear()
	_start()
	assert_false(_sfx._music_player.playing)
	_sfx.set_music_context(&"lobby")
	_start()
	assert_true(_sfx._music_player.playing)


func test_natural_fade_uses_audio_position_not_scaled_elapsed_time() -> void:
	_start()
	_sfx._advance_music(0.25, 4.0)
	assert_almost_eq(_sfx._music_envelope, 1.0, 0.001, "audio reached full fade-in despite slow game time")
	_sfx._advance_music(0.25, 19.0)
	assert_almost_eq(_sfx._music_envelope, 0.2, 0.001, "last audio second fades before decoder finishes")


func test_process_wait_and_switch_use_real_ticks_not_game_delta() -> void:
	_sfx._last_music_tick_usec = Time.get_ticks_usec() - 1000000
	_sfx._process(0.25)
	assert_almost_eq(_sfx._music_wait_remaining, 1.0, 0.05, "one real second advances wait, not a quarter second")
	_start()
	_sfx._advance_music(4.0)
	_sfx.set_music_context(&"lobby")
	_sfx._last_music_tick_usec = Time.get_ticks_usec() - 1000000
	_sfx._process(0.25)
	assert_almost_eq(_sfx._music_envelope, 0.8, 0.01, "context fade uses real seconds")


# --- Lazy music loading (Bontago-1pi.11.61) ----------------------------------

const MENU_TRACK: String = "res://assets/music/menu-theme.mp3"
const LOBBY_TRACK: String = "res://assets/music/lobby-theme.mp3"
const GAME_TRACKS: Array[String] = [
	"res://assets/music/stacking-blocks.mp3",
	"res://assets/music/stacking-blocks-2.mp3",
	"res://assets/music/stacking-blocks-3.mp3",
]


func _lazy_sfx() -> Node:
	var shipped: AudioConfig = load("res://config/audio_config.tres").duplicate() as AudioConfig
	shipped.music_fade_out_seconds = 1.0
	var sfx: Node = SFX_SCRIPT.new()
	sfx.config = shipped
	add_child_autofree(sfx)
	sfx.set_process(false)
	return sfx


func _preheld_tracks() -> Dictionary:
	var held: Dictionary = {}
	var all_paths: Array[String] = [MENU_TRACK, LOBBY_TRACK]
	all_paths.append_array(GAME_TRACKS)
	for path: String in all_paths:
		if ResourceLoader.has_cached(path) or Sfx._music_requested.has(path):
			held[path] = true
	return held


func test_shipped_config_resource_does_not_reference_music_streams() -> void:
	var deps: PackedStringArray = ResourceLoader.get_dependencies("res://config/audio_config.tres")
	for dep: String in deps:
		assert_false(dep.contains("assets/music"), "audio_config.tres must not pull music: %s" % dep)


func test_boot_holds_at_most_the_first_contexts_track() -> void:
	var sfx: Node = _lazy_sfx()
	assert_true(sfx._next_track_context == &"menu")
	var requested: Array = sfx._music_requested.keys()
	assert_lte(requested.size(), 1)
	for path: String in requested:
		assert_true(path in [MENU_TRACK, LOBBY_TRACK], "only a menu-playlist track is requested at boot")
	for path: String in GAME_TRACKS:
		assert_false(sfx._music_requested.has(path), "gameplay tracks are not loaded at boot")


func test_context_switch_loads_next_and_frees_previous() -> void:
	# Residency left by the shared process (the real Sfx autoload's own prefetch,
	# or an earlier script in the same shard that loaded a track) is not ours to
	# assert on: snapshot it before this fixture touches anything (Bontago-fca.60).
	var preheld: Dictionary = _preheld_tracks()
	var sfx: Node = _lazy_sfx()
	sfx._advance_music(sfx.config.music_initial_delay_seconds)
	assert_true(sfx._music_player.playing)
	for path: String in [MENU_TRACK, LOBBY_TRACK]:
		if not preheld.has(path):
			assert_false(ResourceLoader.has_cached(path), "the started track's source is not kept (the player owns a copy)")
	sfx.set_music_context(&"gameplay")
	assert_eq(sfx._music_state, sfx.MusicState.SWITCHING)
	assert_eq(sfx._next_track_context, &"gameplay", "next context is prefetched during the fade-out")
	assert_eq(sfx._music_requested.size(), 1, "one gameplay track is prefetched, not all three")
	sfx._advance_music(sfx.config.music_fade_out_seconds + 0.1)
	assert_null(sfx._music_player.stream, "faded-out stream is released")
	sfx._advance_music(sfx.config.music_initial_delay_seconds)
	assert_true(sfx._music_player.playing)
	assert_true(sfx._music_player.stream is AudioStreamMP3)
	assert_true(sfx._music_requested.is_empty(), "request consumed")
	for path: String in [MENU_TRACK, LOBBY_TRACK]:
		if not preheld.has(path):
			assert_false(ResourceLoader.has_cached(path), "previous context's track is not resident: %s" % path)
	var cached_game: int = 0
	for path: String in GAME_TRACKS:
		if ResourceLoader.has_cached(path) and not preheld.has(path):
			cached_game += 1
	assert_eq(cached_game, 0, "started gameplay track is held only by the player's copy")


func test_release_audio_drains_pending_requests() -> void:
	var sfx: Node = _lazy_sfx()
	sfx.set_music_context(&"gameplay")
	sfx.release_audio()
	assert_true(sfx._music_requested.is_empty())
	assert_null(sfx._music_player.stream)


func test_legacy_theme_path_plays_when_contextual_music_is_off() -> void:
	var sfx: Node = _lazy_sfx()
	sfx.config.contextual_music_enabled = false
	sfx._music_player.stop()
	sfx.play_music()
	assert_true(sfx._music_player.playing, "bundled_theme_path still reaches the single-stream player")
	assert_true(sfx._music_player.stream is AudioStreamMP3)
	assert_false(sfx._tense_stem_available)


func test_failed_track_load_advances_to_next_entry() -> void:
	var sfx: Node = _lazy_sfx()
	sfx.config.menu_playlist_paths = PackedStringArray(["res://config/audio_config.tres", MENU_TRACK, "res://config/audio_config.tres"])
	sfx._next_track_context = &"menu"
	sfx._next_track_index = 0
	sfx._start_playlist_track()
	assert_eq(sfx._music_state, sfx.MusicState.PLAYING, "skipped the missing entry")
	assert_eq(int(sfx._last_track_by_context[&"menu"]), 1)


func test_all_tracks_failing_stops_after_trying_each_once() -> void:
	var sfx: Node = _lazy_sfx()
	sfx.config.menu_playlist_paths = PackedStringArray(["res://config/audio_config.tres", "res://config/audio_config.tres"])
	sfx._next_track_context = &"menu"
	sfx._next_track_index = 0
	sfx._start_playlist_track()
	assert_eq(sfx._music_state, sfx.MusicState.STOPPED)
