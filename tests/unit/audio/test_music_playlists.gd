extends GutTest


func test_shipped_playlists_load_playable_tracks() -> void:
	var shipped: AudioConfig = load("res://config/audio/audio_config.tres")
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
	_sfx.play_music() # Sfx no longer self-starts; Main starts it after the splash.


func after_each() -> void:
	Settings.set_config_path_for_test(Settings.REAL_CONFIG_PATH)
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
	assert_false(_sfx._tense_stem_available)
	Events.goal_capture_progress.emit(0, 1.0)
	assert_false(_sfx._tense_stem_is_active, "playlist mode ignores adaptive stems")


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


# --- Lazy music loading ----------------------------------

const MENU_TRACK: String = "res://assets/audio/music/menu-theme.mp3"
func _lazy_sfx() -> Node:
	var shipped: AudioConfig = load("res://config/audio/audio_config.tres").duplicate() as AudioConfig
	shipped.music_fade_out_seconds = 1.0
	var sfx: Node = SFX_SCRIPT.new()
	sfx.config = shipped
	add_child_autofree(sfx)
	sfx.set_process(false)
	sfx.play_music() # started by Main after the splash, not by _ready().
	return sfx


func test_failed_track_load_advances_to_next_entry() -> void:
	var sfx: Node = _lazy_sfx()
	sfx.config.menu_playlist_paths = PackedStringArray(["res://config/audio/audio_config.tres", MENU_TRACK, "res://config/audio/audio_config.tres"])
	sfx._next_track_context = &"menu"
	sfx._next_track_index = 0
	sfx._start_playlist_track()
	assert_eq(sfx._music_state, sfx.MusicState.PLAYING, "skipped the missing entry")
	assert_eq(int(sfx._last_track_by_context[&"menu"]), 1)

