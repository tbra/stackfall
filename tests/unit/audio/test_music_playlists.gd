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
const MENU_TRACK: String = "res://assets/audio/music/menu-theme.mp3"
const NOT_A_TRACK: String = "res://config/audio/audio_config.tres"
const WAIT_LIMIT_MSEC: int = 4000
const SLOW_MOTION_SCALE: float = 0.01
const SHORT_DELAY_S: float = 0.2

var _saved_time_scale: float = 1.0


func before_each() -> void:
	_saved_time_scale = Engine.time_scale


func after_each() -> void:
	Engine.time_scale = _saved_time_scale


## A throwaway Sfx on the shipped config with a short initial delay, started like Main does.
func _sfx_with_menu_paths(paths: PackedStringArray) -> Node:
	var config: AudioConfig = load("res://config/audio/audio_config.tres").duplicate() as AudioConfig
	config.menu_playlist_paths = paths
	config.music_initial_delay_seconds = SHORT_DELAY_S
	var sfx: Node = SFX_SCRIPT.new()
	sfx.config = config
	add_child_autofree(sfx)
	sfx.play_music()
	return sfx


## The sounding player of a fresh Sfx is its music player (no cue has been requested).
func _await_music(sfx: Node) -> AudioStreamPlayer:
	var deadline: int = Time.get_ticks_msec() + WAIT_LIMIT_MSEC
	while Time.get_ticks_msec() < deadline:
		for child: Node in sfx.get_children():
			var player: AudioStreamPlayer = child as AudioStreamPlayer
			if player != null and player.playing:
				return player
		await get_tree().process_frame
	return null


func test_failed_track_load_advances_to_next_entry() -> void:
	var sfx: Node = _sfx_with_menu_paths(PackedStringArray([NOT_A_TRACK, MENU_TRACK]))
	var player: AudioStreamPlayer = await _await_music(sfx)
	assert_not_null(player, "the playable entry starts after the unloadable one is skipped")
	if player != null:
		assert_true(player.stream is AudioStreamMP3)


func test_silence_and_start_follow_wall_time_not_game_time() -> void:
	Engine.time_scale = SLOW_MOTION_SCALE
	var sfx: Node = _sfx_with_menu_paths(PackedStringArray([MENU_TRACK]))
	var player: AudioStreamPlayer = await _await_music(sfx)
	assert_not_null(player, "slow motion does not stretch the silent delay")
