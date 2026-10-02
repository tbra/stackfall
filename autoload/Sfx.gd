extends Node
## Placeholder audio from the original Bontago install (assets-audio
## package). Loads streams at runtime from res://assets/original/audio (in
## the editor) or <exe dir>/assets/original/audio (exported) -- never through
## Godot's import pipeline, since that folder is gitignored (HARD CONSTRAINT:
## third-party copyrighted assets never enter the public repo, see
## tools/install_original_assets.ps1) and a fresh checkout has no .import
## files for it. Absent folder: one info print, then every play() is a silent
## no-op -- the game runs fine with no sound, the same "supported absence"
## pattern tools/check_steam_setup.ps1 documents for addons/godotsteam/.
##
## Listens on Events; nothing in gameplay code calls Sfx directly (CLAUDE.md's
## global-signal-bus convention). ui/MainMenu.gd and ui/Lobby.gd are the sole
## UI exceptions -- button press/hover has no Events signal of its own, so
## those screens call Sfx.play() from their button handlers. Main.gd also
## supplies the current menu/lobby/gameplay music context.
##
## No class_name: this is the Sfx autoload singleton (same reason Events,
## Settings, Net and Match have none -- see autoload/Net.gd's header).
##
## Music uses bundled context playlists; custom folder preferences are
## temporarily ignored by owner direction. SFX stay on the folder above.
## Every play()/play_music()/impact-thud
## volume_db also adds Settings.master_volume_db() on top of this file's own
## AudioConfig.sfx_volume_db/music_volume_db baseline, live-updated via
## Settings.audio_settings_changed (docs/M6_PLAN.md package C3). Bontago
## (options package): SFX playback additionally adds Settings.sfx_volume_db(),
## music playback additionally adds Settings.music_volume_db() -- master
## multiplies every channel, the music/SFX sliders only ever scale their own.

const AUDIO_SUBDIR: String = "assets/effects"
const ORIGINAL_AUDIO_SUBDIR: String = "assets/original/audio"

## Effectively-silent volume_db floor for whichever music stem is faded out
## of the adaptive crossfade (docs/M7_PLAN.md P6). Not a tunable -- it is an
## engineering constant matching AudioServer's own convention that -80 dB
## reads as inaudible on any reasonable output device -- so it stays a local
## const rather than another AudioConfig field (CLAUDE.md "no magic numbers"
## is about designer-facing tunables; this is neither designer-facing nor
## something anyone would want to retune).
const MUSIC_STEM_MUTE_DB: float = -80.0

@export var config: AudioConfig = preload("res://config/audio_config.tres")

var _root_dir: String = ""
var _available: bool = false
var _streams_by_filename: Dictionary = {}
## Legacy disk-music fallback cache; independent of bundled playlist streams.
var _music_root_dir: String = ""
var _music_available: bool = false
var _music_streams_by_filename: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player_index: int = 0
var _music_player: AudioStreamPlayer
var _music_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Adaptive music (docs/M7_PLAN.md P6): a second AudioStreamPlayer for the
## tense stem, on the same bus as _music_player, started in sync with it
## whenever both config.music_stem_calm_file and config.music_stem_tense_file
## resolve to real files under _music_root_dir. Missing tense file: this
## player is simply never given a stream and _tense_stem_available stays
## false -- single-stream playback through _music_player is untouched, no
## error/warning (Skybox.gd's fallback_active pattern).
var _tense_music_player: AudioStreamPlayer
var _tense_stem_available: bool = false
## Which side of the crossfade Events.goal_capture_progress last asked for.
## Drives calm_stem_target_volume_db()/tense_stem_target_volume_db() even
## when _tense_stem_available is false, so a test (or a later real asset
## drop) can read the intended target without needing a live Tween to finish.
var _tense_stem_is_active: bool = false
var _music_crossfade_tween: Tween

enum MusicState { STOPPED, WAITING, PLAYING, SWITCHING }
var _music_state: MusicState = MusicState.STOPPED
var _music_context: StringName = &"menu"
var _music_wait_remaining: float = 0.0
var _music_age: float = 0.0
var _music_envelope: float = 0.0
var _switch_start_envelope: float = 0.0
var _switch_elapsed: float = 0.0
var _last_track_by_context: Dictionary = {}
var _last_gift_spawn_msec: int = -1
var _last_music_tick_usec: int = Time.get_ticks_usec()


func _ready() -> void:
	Block.impact_speed_min = config.impact_speed_min
	Block.impacts_enabled = config.impacts_enabled
	_root_dir = _resolve_root_dir()
	_available = DirAccess.dir_exists_absolute(_root_dir) or DirAccess.dir_exists_absolute(_resolve_original_audio_root_dir())
	if not _available:
		print(
			"Sfx: no effects at %s or original audio at %s -- game runs silently."
			% [_root_dir, _resolve_original_audio_root_dir()]
		)
	_refresh_music_root_dir()
	_build_player_pool()
	_refresh_tense_stem()
	Events.block_impacted.connect(_on_block_impacted)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.block_placed.connect(_on_block_placed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_flight_spawned.connect(_on_gift_flight_spawned)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Settings.audio_settings_changed.connect(_on_audio_settings_changed)
	play_music()


func _resolve_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + AUDIO_SUBDIR)
	return OS.get_executable_path().get_base_dir().path_join(AUDIO_SUBDIR)


func _resolve_original_audio_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + ORIGINAL_AUDIO_SUBDIR)
	return OS.get_executable_path().get_base_dir().path_join(ORIGINAL_AUDIO_SUBDIR)


## Legacy fallback stays on the original bundled root. Custom folders are
## ignored even when a saved preference points at an existing directory.
func _refresh_music_root_dir() -> void:
	# Owner request: ignore persisted custom-folder overrides for now, even
	# on the legacy fallback path. Keep the preference for future restoration.
	_music_root_dir = _root_dir
	_music_available = DirAccess.dir_exists_absolute(_music_root_dir)
	_music_streams_by_filename.clear()


## Settings.audio_settings_changed fires for both a master-volume change and a
## custom-music-dir change (autoload/Settings.gd), so this re-resolves the
## music folder and, per docs/M6_PLAN.md package C3, re-applies the volume to
## whatever is already playing -- no restart needed to hear a slider move.
func _on_audio_settings_changed() -> void:
	if config.contextual_music_enabled:
		_apply_playlist_volume()
		return
	_refresh_music_root_dir()
	_refresh_tense_stem()
	if _music_player.playing:
		_music_player.volume_db = calm_stem_target_volume_db()
	if _tense_stem_available and _tense_music_player.playing:
		_tense_music_player.volume_db = tense_stem_target_volume_db()


func _build_player_pool() -> void:
	for _i: int in range(config.max_simultaneous):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	_tense_music_player = AudioStreamPlayer.new()
	_tense_music_player.bus = _music_player.bus
	add_child(_tense_music_player)


## Plays one of `event`'s configured files on a pooled AudioStreamPlayer (or
## the music player for AudioConfig.EVENT_MUSIC). Returns whether anything
## actually played -- false with no assets installed, an unknown event, or a
## missing file.
func play(event: StringName) -> bool:
	if event == AudioConfig.EVENT_MUSIC and config.contextual_music_enabled:
		play_music()
		return _music_enabled and not config.playlist_for_context(_music_context).is_empty()
	var stream: AudioStream = _pick_stream(event)
	if stream == null:
		return false
	if event == AudioConfig.EVENT_MUSIC:
		_play_music_stream(stream)
		return true
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db + Settings.master_volume_db() + Settings.sfx_volume_db()
	player.play()
	return true


## Positional variant of play(). DECISION (autoload/Sfx.gd): 3D/spatial audio
## isn't required yet (brief: "3D not required now -- 2D/global players are
## fine"), so this ignores `position` and behaves exactly like play(); the
## parameter stays so callers don't need to change when spatial audio lands.
func play_at(event: StringName, _position: Vector3) -> bool:
	return play(event)


func set_music_enabled(enabled: bool) -> void:
	if enabled == _music_enabled:
		return
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()
		_tense_music_player.stop()
		_music_state = MusicState.STOPPED
		_music_envelope = 0.0
	elif not _music_player.playing:
		play_music()


func play_music() -> void:
	if not _music_enabled:
		return
	if config.contextual_music_enabled:
		if _music_state == MusicState.STOPPED:
			_schedule_music(config.music_initial_delay_seconds)
		return
	var stream: AudioStream = _pick_stream(AudioConfig.EVENT_MUSIC)
	if stream != null:
		_play_music_stream(stream)


func _play_music_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.volume_db = calm_stem_target_volume_db()
	_music_player.play()
	_sync_tense_player_with_calm()


func _pick_stream(event: StringName) -> AudioStream:
	var is_music: bool = event == AudioConfig.EVENT_MUSIC
	if is_music:
		# The legacy bundled theme is independent of optional original assets.
		if config.bundled_theme != null:
			return config.bundled_theme
		if not _music_available:
			return null
		# DECISION (autoload/Sfx.gd, Bontago-xtq.31 review, MEDIUM): only steer
		# music_file's own EVENT_MUSIC selection toward music_stem_calm_file
		# once a real tense partner exists (_tense_stem_available) -- with no
		# tense asset installed there is nothing to be "calm" relative to, so
		# the existing music_file selection (which defaults to the same
		# filename anyway) stays the simplest single source of truth. Once
		# both stems are installed, the calm player must actually play the
		# calm-labelled file rather than whatever music_file/shuffle would
		# otherwise pick, or the two could silently mismatch.
		if _tense_stem_available:
			return _load_stream_from_root(
				config.music_stem_calm_file, _music_root_dir, _music_streams_by_filename
			)
	elif not _available:
		return null
	var files: Array[String] = config.files_for_event(event)
	if files.is_empty():
		return null
	var filename: String = files[0] if files.size() == 1 else files[_rng.randi_range(0, files.size() - 1)]
	if is_music:
		return _load_stream_from_root(filename, _music_root_dir, _music_streams_by_filename)
	return _load_stream(filename)


func _load_stream(filename: String) -> AudioStream:
	# The replacement effects folder intentionally contains only newly chosen
	# sounds. Keep original sounds (bomb, boing, rocket, etc.) working without
	# copying the licensed originals into tracked assets/effects. Test-injected
	# roots still stay isolated and never consult the developer's asset folder.
	if _root_dir == _resolve_root_dir() and not FileAccess.file_exists(_root_dir.path_join(filename.to_lower())):
		var original_root: String = _resolve_original_audio_root_dir()
		if FileAccess.file_exists(original_root.path_join(filename.to_lower())):
			return _load_stream_from_root(filename, original_root, _streams_by_filename)
	return _load_stream_from_root(filename, _root_dir, _streams_by_filename)


## Shared by _load_stream() (bundled SFX root) and _pick_stream()'s music path
## (bundled or custom root, per _refresh_music_root_dir()). `cache` is a
## Dictionary reference (GDScript Dictionaries are reference types), so a hit
## the caller adds here is visible to the caller's own dict too.
func _load_stream_from_root(filename: String, root_dir: String, cache: Dictionary) -> AudioStream:
	var key: String = filename.to_lower()
	if cache.has(key):
		return cache[key]
	var full_path: String = root_dir.path_join(key)
	if not FileAccess.file_exists(full_path):
		print("Sfx: expected file missing: %s" % full_path)
		return null
	var stream: AudioStream = null
	if key.ends_with(".wav"):
		stream = AudioStreamWAV.load_from_file(full_path)
	elif key.ends_with(".mp3"):
		stream = AudioStreamMP3.load_from_file(full_path)
	if stream != null:
		cache[key] = stream
	return stream


func _next_sfx_player() -> AudioStreamPlayer:
	var player: AudioStreamPlayer = _sfx_players[_next_sfx_player_index]
	_next_sfx_player_index = (_next_sfx_player_index + 1) % _sfx_players.size()
	return player


# --- Test seam ---------------------------------------------------------------

## tests/unit/test_sfx.gd points a fresh Sfx instance at a temp folder instead
## of assets/original/audio, which is gitignored and absent on a clean
## checkout -- the same Variant/seam pattern ui/MainMenu.gd's net_provider
## uses for a value GUT can't otherwise inject.
func set_root_dir_for_test(path: String) -> void:
	_root_dir = path
	_available = DirAccess.dir_exists_absolute(path)
	_streams_by_filename.clear()
	_refresh_music_root_dir()  # re-derive the bundled-fallback case against the new _root_dir
	_refresh_tense_stem()


# --- Adaptive music (docs/M7_PLAN.md P6) -------------------------------------

## Re-derives _tense_stem_available against the current _music_root_dir.
## Requires BOTH config.music_stem_calm_file and config.music_stem_tense_file
## to resolve to real files there -- a "calm" stem with no matching "tense"
## partner has nothing to crossfade to, so it is treated the same as a
## missing tense file (no error either way, just tense_stem_available()
## staying false). Called whenever _music_root_dir can change (_ready(),
## _on_audio_settings_changed(), set_root_dir_for_test()) since a custom
## music folder swap can gain or lose either file.
func _refresh_tense_stem() -> void:
	var was_available: bool = _tense_stem_available
	_tense_stem_available = false
	if _tense_music_player == null:
		return  # called from _ready() before _build_player_pool() creates it
	_tense_music_player.stop()
	# The owner theme is a complete mix, not a stem of the original score.
	if config.contextual_music_enabled or config.bundled_theme != null:
		_tense_stem_is_active = false
		return
	if not _music_available:
		if was_available:
			_tense_stem_is_active = false  # the tense stem just disappeared -- fall back to calm
		return
	var calm_path: String = _music_root_dir.path_join(config.music_stem_calm_file.to_lower())
	var tense_path: String = _music_root_dir.path_join(config.music_stem_tense_file.to_lower())
	if not FileAccess.file_exists(calm_path) or not FileAccess.file_exists(tense_path):
		if was_available:
			_tense_stem_is_active = false  # the tense (or its calm partner) just disappeared -- fall back to calm
		return
	var stream: AudioStream = _load_stream_from_root(
		config.music_stem_tense_file, _music_root_dir, _music_streams_by_filename
	)
	if stream == null:
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_tense_music_player.stream = stream
	_tense_music_player.volume_db = tense_stem_target_volume_db()
	_tense_stem_available = true
	_sync_tense_player_with_calm()


## Starts (or stops) the tense player alongside whatever _music_player is
## currently doing, so the two stems never drift apart -- called any time
## _music_player's playback state or position could have just changed.
func _sync_tense_player_with_calm() -> void:
	if not _tense_stem_available:
		return
	if _music_player.playing:
		_tense_music_player.play(_music_player.get_playback_position())
	else:
		_tense_music_player.stop()


## True only when both stem files resolved (see _refresh_tense_stem()) --
## false with no tense asset installed, no calm partner, or the bundled/
## custom music folder itself missing. Read by tests and a manual tester
## checking for the absence of any error/warning in that case.
func tense_stem_available() -> bool:
	return _tense_stem_available


## Target volume_db for the calm stem given the last _on_goal_capture_progress
## call: full baseline while calm is the active side, MUSIC_STEM_MUTE_DB while
## tense is. Exposed (with tense_stem_target_volume_db() below) so a test can
## assert the intended crossfade direction without waiting for a live Tween
## or touching audio hardware.
##
## DECISION (autoload/Sfx.gd, Bontago-xtq.31 review, HIGH): never mute unless
## the tense stem is actually available -- _tense_stem_is_active alone isn't
## enough to gate this, because it can flip true from a plain
## Events.goal_capture_progress reading (no asset needed) even in the shipped
## single-stream config with no tense file installed. Without this guard, the
## next play_music()/_on_audio_settings_changed() call would apply
## MUSIC_STEM_MUTE_DB to the only music stream that exists and mute it
## permanently. _tense_stem_available true is required before this stem can
## ever be the muted side.
func calm_stem_target_volume_db() -> float:
	var baseline_db: float = config.music_volume_db + Settings.master_volume_db() + Settings.music_volume_db()
	if not _tense_stem_available:
		return baseline_db
	return MUSIC_STEM_MUTE_DB if _tense_stem_is_active else baseline_db


## Mirror of calm_stem_target_volume_db() for the tense stem. Symmetric guard:
## with no tense stem installed there is nothing to raise the volume of, so
## this stays muted regardless of _tense_stem_is_active (moot in practice --
## _tense_music_player is never given a stream or started while unavailable,
## see _refresh_tense_stem()/_sync_tense_player_with_calm()).
func tense_stem_target_volume_db() -> float:
	var baseline_db: float = config.music_volume_db + Settings.master_volume_db() + Settings.music_volume_db()
	if not _tense_stem_available:
		return MUSIC_STEM_MUTE_DB
	return baseline_db if _tense_stem_is_active else MUSIC_STEM_MUTE_DB


## Events.goal_capture_progress (spec 2.10's adaptive music, docs/M7_PLAN.md
## P6): the crossfade only cares how close ANY team is to capturing, not
## which one, so team_id is unused here -- underscore-prefixed to match this
## file's own convention for an unused handler parameter (e.g.
## _on_player_eliminated()), even though ui/HUD.gd's own sibling handler of
## this same signal does use it for a different purpose (which team's colour
## to draw). Events.gd's own doc comment: "team_id is -1 with progress 0 when
## a capture breaks" -- that case falls out of the plain
## `progress >= threshold` check below with no special-casing, since 0.0 is
## always below music_tense_progress_threshold.
func _on_goal_capture_progress(_team_id: int, progress: float) -> void:
	if config.contextual_music_enabled:
		return
	# Hysteresis (docs/M7_PLAN.md P6 review, MINOR, Bontago-xtq.31): the rising
	# edge (calm -> tense) always uses the plain threshold; the falling edge
	# (tense -> calm) only fires music_tense_release_margin below it, so
	# progress hovering right at the threshold doesn't flap the crossfade
	# every frame. config.music_tense_release_margin defaults to a small
	# positive value; 0.0 reproduces the old single-threshold behaviour.
	var release_threshold: float = config.music_tense_progress_threshold - config.music_tense_release_margin
	var want_tense: bool = (
		progress >= config.music_tense_progress_threshold
		if not _tense_stem_is_active
		else progress >= release_threshold
	)
	if want_tense == _tense_stem_is_active:
		return
	_tense_stem_is_active = want_tense
	if not _tense_stem_available:
		return  # single-stream playback: nothing installed to crossfade to
	if _music_crossfade_tween != null and _music_crossfade_tween.is_valid():
		_music_crossfade_tween.kill()
	_music_crossfade_tween = create_tween()
	_music_crossfade_tween.set_parallel(true)
	_music_crossfade_tween.tween_property(
		_music_player, "volume_db", calm_stem_target_volume_db(), config.music_crossfade_seconds
	)
	_music_crossfade_tween.tween_property(
		_tense_music_player, "volume_db", tense_stem_target_volume_db(), config.music_crossfade_seconds
	)


# --- Contextual intermittent music -------------------------------------------

## One state machine owns transitions; no delayed callbacks/tweens can start
## stale music after rapid menu/lobby/gameplay changes.
func set_music_context(context: StringName) -> void:
	if context not in [&"menu", &"lobby", &"gameplay"] or context == _music_context:
		return
	_music_context = context
	if not config.contextual_music_enabled or not _music_enabled:
		return
	if _music_state == MusicState.PLAYING:
		_music_state = MusicState.SWITCHING
		_switch_start_envelope = _music_envelope
		_switch_elapsed = 0.0
	elif _music_state != MusicState.SWITCHING:
		_schedule_music(config.music_initial_delay_seconds)


func _process(_delta: float) -> void:
	# Sandbox slow-motion changes Engine.time_scale, not the audio clock.
	# Silence and transitions use wall time; song fades follow the decoder.
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = maxf(float(now_usec - _last_music_tick_usec) / 1000000.0, 0.0)
	_last_music_tick_usec = now_usec
	var playback_position: float = -1.0
	if _music_state == MusicState.PLAYING and _music_player.playing:
		playback_position = maxf(0.0, _music_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	_advance_music(real_delta, playback_position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_music_tick_usec = Time.get_ticks_usec()


func _advance_music(delta: float, playback_position: float = -1.0) -> void:
	if not config.contextual_music_enabled or not _music_enabled:
		return
	match _music_state:
		MusicState.WAITING:
			_music_wait_remaining -= delta
			if _music_wait_remaining <= 0.0:
				_start_playlist_track()
		MusicState.PLAYING:
			_music_age = playback_position if playback_position >= 0.0 else _music_age + delta
			var fade_in: float = 1.0 if config.music_fade_in_seconds <= 0.0 else clampf(_music_age / config.music_fade_in_seconds, 0.0, 1.0)
			var remaining: float = _music_player.stream.get_length() - _music_age
			var fade_out: float = 1.0 if config.music_fade_out_seconds <= 0.0 else clampf(remaining / config.music_fade_out_seconds, 0.0, 1.0)
			_music_envelope = minf(fade_in, fade_out)
			_apply_playlist_volume()
		MusicState.SWITCHING:
			_switch_elapsed += delta
			var fraction: float = 1.0 if config.music_fade_out_seconds <= 0.0 else clampf(_switch_elapsed / config.music_fade_out_seconds, 0.0, 1.0)
			_music_envelope = _switch_start_envelope * (1.0 - fraction)
			_apply_playlist_volume()
			if fraction >= 1.0:
				_music_player.stop()
				_schedule_music(config.music_initial_delay_seconds)


func _schedule_music(delay: float) -> void:
	_last_music_tick_usec = Time.get_ticks_usec()
	_music_wait_remaining = maxf(delay, 0.0)
	_music_state = MusicState.WAITING


func _start_playlist_track() -> void:
	var playlist: Array[AudioStream] = config.playlist_for_context(_music_context)
	var choices: Array[int] = []
	var previous: int = int(_last_track_by_context.get(_music_context, -1))
	for index: int in range(playlist.size()):
		if playlist[index] != null and (index != previous or playlist.size() == 1):
			choices.append(index)
	if choices.is_empty():
		# Also tolerate a playlist with null entries and only one usable track.
		if previous >= 0 and previous < playlist.size() and playlist[previous] != null:
			choices.append(previous)
		else:
			_music_state = MusicState.STOPPED
			return
	var selected: int = choices[_rng.randi_range(0, choices.size() - 1)]
	_last_track_by_context[_music_context] = selected
	# Duplicate before changing loop flags: imported shared resources and
	# legacy consumers must not inherit one another's playback settings.
	var stream: AudioStream = playlist[selected].duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_music_player.stream = stream
	_music_age = 0.0
	_music_envelope = 0.0 if config.music_fade_in_seconds > 0.0 else 1.0
	_music_state = MusicState.PLAYING
	_apply_playlist_volume()
	_music_player.play()


func _apply_playlist_volume() -> void:
	if _music_player == null:
		return
	var baseline: float = config.music_volume_db + Settings.master_volume_db() + Settings.music_volume_db()
	_music_player.volume_db = MUSIC_STEM_MUTE_DB if _music_envelope <= 0.0 else maxf(MUSIC_STEM_MUTE_DB, baseline + linear_to_db(_music_envelope))


func _on_music_finished() -> void:
	if not config.contextual_music_enabled or not _music_enabled:
		return
	if _music_state == MusicState.SWITCHING:
		_schedule_music(config.music_initial_delay_seconds)
	elif _music_state == MusicState.PLAYING:
		var minimum: float = maxf(config.music_gap_min_seconds, 0.0)
		_schedule_music(_rng.randf_range(minimum, maxf(minimum, config.music_gap_max_seconds)))
	_music_envelope = 0.0


# --- Events hooks -------------------------------------------------------------

func _on_block_impacted(speed: float) -> void:
	if speed < config.impact_speed_min:
		return
	var stream: AudioStream = _pick_stream(AudioConfig.EVENT_THUD)
	if stream == null:
		return
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db + config.impact_volume_db(speed) + Settings.master_volume_db() + Settings.sfx_volume_db()
	player.play()


func _on_placement_rejected(_slot_id: int, _reason: StringName) -> void:
	play(AudioConfig.EVENT_REJECTED)


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	play(AudioConfig.EVENT_DROP)


func _on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	play(AudioConfig.EVENT_BREAKAGE)


## The flight event is emitted locally on the host and on each client when
## the reliable spawn arrives. Late claim or landing events do not retrigger
## it, and gift_spawn_min_interval_s rate-limits the jingle.
func _on_gift_flight_spawned(_gift_id: int, _origin: Vector3, _landing: Vector3) -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _last_gift_spawn_msec >= 0 and float(now_msec - _last_gift_spawn_msec) < config.gift_spawn_min_interval_s * 1000.0:
		return
	if play(AudioConfig.EVENT_GIFT_SPAWNED):
		_last_gift_spawn_msec = now_msec


## DECISION (autoload/Sfx.gd, Bontago-6y2): unlike the hooks above (a block
## drop/thud/rejection/breakage is a physical event any nearby player would
## actually hear happen, so every hook above plays for every slot, no
## gating), a gift claim queues a special for the whole claiming team -- it is
## personal feedback, not a world event. Gating on "any locally-driven slot on
## the claiming team" mirrors game/GiftCrate.gd's own "_local_watch_slot()"
## comment and ui/HUD.gd's gift toast (Bontago-1en.16), both already
## local-only; a global "someone somewhere claimed a gift" chime would be
## noise in an 8-player match with crates spawning continuously. The
## Net.is_local_slot() check inside the loop is also correct in hot-seat/
## offline play with no extra branching: it always returns true there (one
## human drives every slot), so every claim plays, same as it would if the
## local human just made it.
##
## Simplest reasonable option per the brief: no quieter variant for other
## teams' claims -- nothing else about a gift claim has non-local feedback
## either, so this just stays silent for them rather than inventing a new
## tunable with no other precedent to match.
##
## Bontago-keo.17 (owner decision "b"): `recipient_slot` is the RESOLVED
## RECIPIENT -- the one teammate nearest the crate, not every teammate -- but
## this sound is still a team-wide notification (a teammate should hear
## "your team claimed a special" even on the claim that doesn't land in their
## own queue). A single Net.is_local_slot(recipient_slot) check would only
## ever fire for the recipient's own local slot, silently dropping the sound
## for a teammate at a different slot index once real teams exist. Loops
## every slot instead and plays once as soon as any locally-driven slot is
## found on the recipient's team, so a claim landing on slot 0 plays for a
## local player at slot 0 or its teammate slot 2 alike under TEAMS_2.
##
## The loop bound is `maxi(Match.slot_count(), recipient_slot + 1)`, not just
## Match.slot_count(): tests/unit/test_sfx.gd's own gift_claimed tests call
## this directly with no match ever started (Match.slot_count() == 0 then),
## the same way they always have -- team_of_slot() falls back to identity
## with no config (see _team_of_slot() below), so this bound keeps checking
## at least slot recipient_slot itself in that case, reproducing the exact
## single-slot check this handler used before real teams existed.
func _on_gift_claimed(_gift_id: int, recipient_slot: int, _special_id: StringName) -> void:
	for slot_id: int in range(maxi(Match.slot_count(), recipient_slot + 1)):
		if not Net.is_local_slot(slot_id):
			continue
		if _team_of_slot(slot_id) != _team_of_slot(recipient_slot):
			continue
		play(AudioConfig.EVENT_GIFT_CLAIMED)
		return


## Null-safe mirror of config/MatchConfig.gd's team_of_slot() -- Match.config
## is null before a match starts (TeamMode.OFF's own "every slot is its own
## team" fallback), matching ui/HUD.gd's own _team_of_slot() helper.
func _team_of_slot(slot_id: int) -> int:
	if Match.config == null:
		return slot_id
	return Match.config.team_of_slot(slot_id)
