extends Node
## Audio for the game's own sound effects and music (assets-audio package).
## Loads streams at runtime from res://assets/effects (in the editor) or
## <exe dir>/assets/effects (exported). HARD CONSTRAINT: third-party
## copyrighted assets (including the original Bontago's) never enter this
## repo. Absent folder: one info print, then every play() is a silent
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
## Settings.audio_settings_changed (docs/archive/M6_PLAN.md package C3). Bontago
## (options package): SFX playback additionally adds Settings.sfx_volume_db(),
## music playback additionally adds Settings.music_volume_db() -- master
## multiplies every channel, the music/SFX sliders only ever scale their own.

const LocalFeedback := preload("res://autoload/match/LocalFeedback.gd")

const AUDIO_SUBDIR: String = "assets/effects"

## Effectively-silent volume_db floor for whichever music stem is faded out
## of the adaptive crossfade (docs/M7_PLAN.md P6). Not a tunable -- it is an
## engineering constant matching AudioServer's own convention that -80 dB
## reads as inaudible on any reasonable output device -- so it stays a local
## const rather than another AudioConfig field (CLAUDE.md "no magic numbers"
## is about designer-facing tunables; this is neither designer-facing nor
## something anyone would want to retune).
const MUSIC_STEM_MUTE_DB: float = -80.0

## DECISION (Bontago-fca.49): engine constant, not designer-facing. AudioServer
## only frees a stopped playback after one mix cycle plus a main-thread cleanup,
## so anything stopped/replaced within this window of get_tree().quit() is
## still listed (and reported as leaked) at exit. Long enough for several
## mix cycles at any real output buffer size.
const QUIT_DRAIN_S: float = 0.25
const MSEC_PER_S: float = 1000.0

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
## Lazy music (Bontago-1pi.11.61): the track chosen for the next start, the
## path-playlist requests still outstanding (path -> true) and loaded-but-not-yet
## started streams (path -> AudioStream). Only the upcoming track is ever held.
var _next_track_context: StringName = &""
var _next_track_index: int = -1
var _music_requested: Dictionary = {}
var _last_gift_spawn_msec: int = -1
## Bontago-1pi.56: true while a late joiner's world replay is being applied
## (Events.world_replay_changed). The replay re-emits block_placed per body, the
## elimination of every dead slot and every falling crate's flight so the world
## rebuilds; those are state, not news, and must not sound. Not cleared by
## match_scope_reset: the client's world build fires that mid-replay.
var _world_replay_silent: bool = false
var _last_music_tick_usec: int = Time.get_ticks_usec()
## Bontago-mp0.116: last variant index played per "<surface>_<tier>" key.
var _last_impact_variant: Dictionary = {}
## Bontago-bth.3: resolved impact streams per surface x tier (int key from
## _impact_cache_key), so a hit does no string building or file-exists stat. Only
## filled when every variation resolved; dropped when config/root/variation set change.
const IMPACT_SURFACES: Array[StringName] = [AudioConfig.SURFACE_BLOCK, AudioConfig.SURFACE_DISC]
const IMPACT_TIERS: Array[StringName] = [AudioConfig.TIER_SOFT, AudioConfig.TIER_MEDIUM, AudioConfig.TIER_HARD]
var _impact_stream_cache: Dictionary = {}
var _impact_cache_config: AudioConfig = null
var _impact_cache_root: String = ""
var _impact_cache_files: Dictionary = {}
## Bontago-bth.3: reused surface-query objects (radius refreshed per call).
var _surface_shape: SphereShape3D = SphereShape3D.new()
var _surface_params: PhysicsShapeQueryParameters3D = _make_surface_params()
var _surface_ids: PackedInt64Array = PackedInt64Array()

## Beacon-claim tension layer (Bontago-1pi.114); see the section near the end.
var _claim_state: ClaimTensionState
var _claim_player: AudioStreamPlayer
var _claim_tween: Tween
var _claim_duck_tween: Tween
var _claim_duck_db: float = 0.0
var _claim_stream_missing: bool = false
var _claim_flush_queued: bool = false
var _claim_last_level: float = 0.0
## Test seams: null = use Net/Match.
var _claim_test_local_team: Variant = null
var _claim_test_live: Variant = null
var _claim_test_client: Variant = null
var _claim_test_hold_s: Variant = null
## Last applied (volume_db, pitch, duck) targets; an unchanged target makes no tweens.
var _claim_last_targets: Vector3 = Vector3(MUSIC_STEM_MUTE_DB, 1.0, 0.0)
## Client-side extrapolation of a hold between sparse replicated updates.
var _claim_ext: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()


func _ready() -> void:
	BlockBody.impact_speed_min = config.impact_speed_min
	BlockBody.impacts_enabled = config.impacts_enabled
	_root_dir = _resolve_root_dir()
	_available = DirAccess.dir_exists_absolute(_root_dir)
	if not _available:
		print("Sfx: no effects at %s -- game runs silently." % _root_dir)
	_refresh_music_root_dir()
	_build_player_pool()
	_refresh_tense_stem()
	_build_claim_layer()
	Events.block_impacted_at.connect(_on_block_impacted_at)
	Events.lobby_ui_cue.connect(play_ui_cue)
	Events.net_peer_joined.connect(_on_net_peer_joined)
	Events.net_peer_left.connect(_on_net_peer_left)
	Events.loading_gate_opened.connect(_on_loading_gate_opened)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.block_placed.connect(_on_block_placed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_flight_spawned.connect(_on_gift_flight_spawned)
	Events.gift_claimed.connect(_on_gift_claimed)
	Events.world_replay_changed.connect(_on_world_replay_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.goal_capture_progress.connect(_on_claim_progress)
	Events.match_won.connect(_on_claim_match_won)
	# Bontago-1pi.46 (G6): a new match must not inherit the previous match's tense stem.
	Events.match_scope_reset.connect(reset_match_audio)
	Events.match_scope_reset.connect(reset_claim_tension)
	Settings.audio_settings_changed.connect(_on_audio_settings_changed)
	# Bontago-1pi.156: music is NOT started here; Main._show_main_menu() calls
	# play_music() once the splash intro is over (or at once when there is none).


func _resolve_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + AUDIO_SUBDIR)
	return OS.get_executable_path().get_base_dir().path_join(AUDIO_SUBDIR)


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
## music folder and, per docs/archive/M6_PLAN.md package C3, re-applies the volume to
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
		return _music_enabled and config.playlist_track_count(_music_context) > 0
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


func set_music_enabled(enabled: bool) -> void:
	if enabled == _music_enabled:
		return
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()
		_tense_music_player.stop()
		_music_state = MusicState.STOPPED
		_music_envelope = 0.0
		_refresh_claim_target(true)
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


## Legacy single theme: the explicit stream (tests/custom builds) else the
## configured path, loaded on use rather than resident from boot.
func _bundled_theme() -> AudioStream:
	if config.bundled_theme != null:
		return config.bundled_theme
	if config.bundled_theme_path.is_empty():
		return null
	return load(config.bundled_theme_path) as AudioStream


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
		# The legacy bundled theme comes first.
		var bundled: AudioStream = _bundled_theme()
		if bundled != null:
			return bundled
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
## of assets/effects, so the tests never depend on shipped files -- the same Variant/seam pattern ui/MainMenu.gd's net_provider
## uses for a value GUT can't otherwise inject.
func set_root_dir_for_test(path: String) -> void:
	_root_dir = path
	_available = DirAccess.dir_exists_absolute(path)
	_streams_by_filename.clear()
	_claim_stream_missing = false
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
	if config.contextual_music_enabled or _bundled_theme() != null:
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


## Bontago-1pi.46 (G6): Events.match_scope_reset. A match left while the tense stem
## was up (contextual music off: only a later goal_capture_progress clears it) must
## not start the next match tense. Returns the stems to calm exactly as _ready() leaves
## them: tense flag off, an in-flight crossfade killed, each stem at its calm target.
## Idempotent. Playlist position and context are NOT touched (audit D2: they continue
## across matches); with contextual music on the tense stem never activates and the
## playlist envelope owns the volume, so only the flag and tween are cleared.
func reset_match_audio() -> void:
	if _music_crossfade_tween != null and _music_crossfade_tween.is_valid():
		_music_crossfade_tween.kill()
	_music_crossfade_tween = null
	_tense_stem_is_active = false
	if config.contextual_music_enabled:
		return
	if _music_player != null:
		_music_player.volume_db = calm_stem_target_volume_db()
	if _tense_stem_available and _tense_music_player != null:
		_tense_music_player.volume_db = tense_stem_target_volume_db()


# --- Contextual intermittent music -------------------------------------------

## One state machine owns transitions; no delayed callbacks/tweens can start
## stale music after rapid menu/lobby/gameplay changes.
func set_music_context(context: StringName) -> void:
	if context not in [&"menu", &"lobby", &"gameplay"] or context == _music_context:
		return
	_music_context = context
	if not config.contextual_music_enabled or not _music_enabled:
		return
	# Prefetch the next context's track now so it is decoded-ready by the time
	# the fade-out of the current one ends.
	_prepare_next_track()
	if _music_state == MusicState.PLAYING:
		_music_state = MusicState.SWITCHING
		_switch_start_envelope = _music_envelope
		_switch_elapsed = 0.0
	elif _music_state != MusicState.SWITCHING:
		_schedule_music(config.music_initial_delay_seconds)


func _process(delta: float) -> void:
	_claim_extrapolate(delta)
	# Sandbox slow-motion changes Engine.time_scale, not the audio clock.
	# Silence and transitions use wall time; song fades follow the decoder.
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = maxf(float(now_usec - _last_music_tick_usec) / 1000000.0, 0.0)
	_last_music_tick_usec = now_usec
	var playback_position: float = -1.0
	if _music_state == MusicState.PLAYING and _music_player.playing:
		playback_position = maxf(0.0, _music_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	_advance_music(real_delta, playback_position)
	if not _music_requested.is_empty():
		_reap_music_requests()


## Quit-time release (Bontago-fca.49): stop every player and drop stream refs
## (and the filename caches) so AudioServer playbacks and the loaded MP3/WAV
## resources are not still referenced when the engine reports leaks at exit.
func _exit_tree() -> void:
	release_audio()


## Call (and await) right before get_tree().quit(): silences everything, then
## lets the AudioServer finish deleting the stopped playbacks (see QUIT_DRAIN_S).
func drain_for_quit() -> void:
	release_audio()
	await get_tree().create_timer(QUIT_DRAIN_S, true, false, true).timeout


## Set once quit_tree() has begun; later requests return at once.
var _quit_started: bool = false
## Test seam: replaces get_tree().quit(exit_code) so a test never ends the runner.
var quit_override: Callable = Callable()


## The one quit helper (Bontago-xtq.47): marks the quit, drains audio, then quits the tree.
## Every real quit path (Main close, Boot close, AgentProbe --quit-on-menu) goes through it so
## none skips drain_for_quit. Safe to call without awaiting.
func quit_tree(exit_code: int = 0) -> void:
	if _quit_started:  # a second request during the drain is a no-op (Bontago-6a4); first exit code wins
		return
	_quit_started = true
	QuitFlag.mark()
	await drain_for_quit()
	if quit_override.is_valid():
		quit_override.call(exit_code)
	else:
		get_tree().quit(exit_code)


func release_audio() -> void:
	if _music_crossfade_tween != null and _music_crossfade_tween.is_valid():
		_music_crossfade_tween.kill()
	_music_crossfade_tween = null
	_music_state = MusicState.STOPPED
	var players: Array[AudioStreamPlayer] = _sfx_players.duplicate()
	players.append(_music_player)
	players.append(_tense_music_player)
	players.append(_claim_player)
	for player: AudioStreamPlayer in players:
		if player != null and is_instance_valid(player):
			player.stop()
			player.stream = null
	_kill_claim_tweens()
	_streams_by_filename.clear()
	_music_streams_by_filename.clear()
	_drop_music_requests()


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
				_music_player.stream = null # release the faded-out track
				_schedule_music(config.music_initial_delay_seconds)


func _schedule_music(delay: float) -> void:
	_last_music_tick_usec = Time.get_ticks_usec()
	_music_wait_remaining = maxf(delay, 0.0)
	_music_state = MusicState.WAITING
	_prepare_next_track()


## Picks the next track for the current context and starts its threaded load
## (path playlists only). Idempotent while the pick is still valid.
func _prepare_next_track() -> void:
	if _next_track_context == _music_context and _next_track_index >= 0:
		return
	var index: int = _choose_track_index(_music_context)
	_next_track_context = _music_context
	_next_track_index = index
	if index < 0:
		return
	var paths: PackedStringArray = config.playlist_paths_for_context(_music_context)
	if index < paths.size():
		_request_music_path(paths[index])


func _choose_track_index(context: StringName) -> int:
	var count: int = config.playlist_track_count(context)
	var streams: Array[AudioStream] = config.playlist_for_context(context)
	var choices: Array[int] = []
	var previous: int = int(_last_track_by_context.get(context, -1))
	for index: int in range(count):
		if (streams.is_empty() or streams[index] != null) and (index != previous or count == 1):
			choices.append(index)
	if choices.is_empty():
		# Also tolerate a playlist with null entries and only one usable track.
		if previous >= 0 and previous < count and (streams.is_empty() or streams[previous] != null):
			return previous
		return -1
	return choices[_rng.randi_range(0, choices.size() - 1)]


func _request_music_path(path: String) -> void:
	if _music_requested.has(path):
		return
	if ResourceLoader.load_threaded_request(path) == OK:
		_music_requested[path] = true


## Loaded stream for `path`: collects the threaded request, or loads
## synchronously when none was made (fallback, may hitch once).
func _take_music_stream(path: String) -> AudioStream:
	var stream: AudioStream = null
	if _music_requested.has(path):
		stream = ResourceLoader.load_threaded_get(path) as AudioStream
	_music_requested.erase(path)
	if stream == null:
		stream = load(path) as AudioStream
	return stream


## Collects finished requests that are no longer the pending pick (a context
## changed again before they were used) and discards them.
func _reap_music_requests() -> void:
	var keep: String = ""
	var paths: PackedStringArray = config.playlist_paths_for_context(_next_track_context)
	if _next_track_index >= 0 and _next_track_index < paths.size():
		keep = paths[_next_track_index]
	for path: String in _music_requested.keys():
		if path == keep:
			continue
		if ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			ResourceLoader.load_threaded_get(path)
			_music_requested.erase(path)


## Quit/release: every threaded request must be collected or the loaded
## resources outlive the engine's leak report.
func _drop_music_requests() -> void:
	for path: String in _music_requested.keys():
		ResourceLoader.load_threaded_get(path)
	_music_requested.clear()
	_next_track_context = &""
	_next_track_index = -1


func _load_track(context: StringName, index: int) -> AudioStream:
	var override: Array[AudioStream] = config.playlist_for_context(context)
	if not override.is_empty():
		return override[index]
	return _take_music_stream(config.playlist_paths_for_context(context)[index])


func _start_playlist_track() -> void:
	if (
		_next_track_context != _music_context
		or _next_track_index < 0
		or _next_track_index >= config.playlist_track_count(_music_context)
	):
		_next_track_index = -1
		_next_track_context = &""
		_prepare_next_track()
	var selected: int = _next_track_index
	_next_track_context = &""
	_next_track_index = -1
	if selected < 0:
		_music_state = MusicState.STOPPED
		return
	var source: AudioStream = _load_track(_music_context, selected)
	# A failed load advances to the next entry; each entry is tried once.
	var count: int = config.playlist_track_count(_music_context)
	var tried: int = 1
	while source == null and tried < count:
		selected = (selected + 1) % count
		tried += 1
		source = _load_track(_music_context, selected)
	if source == null:
		_music_state = MusicState.STOPPED
		return
	_last_track_by_context[_music_context] = selected
	# Duplicate before changing loop flags: imported shared resources and
	# legacy consumers must not inherit one another's playback settings.
	var stream: AudioStream = source.duplicate() as AudioStream
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
	_music_player.volume_db = MUSIC_STEM_MUTE_DB if _music_envelope <= 0.0 else maxf(MUSIC_STEM_MUTE_DB, baseline + _claim_duck_db + linear_to_db(_music_envelope))


func _on_music_finished() -> void:
	if not config.contextual_music_enabled or not _music_enabled:
		return
	_music_player.stream = null # finished track: release it during the silent gap
	if _music_state == MusicState.SWITCHING:
		_schedule_music(config.music_initial_delay_seconds)
	elif _music_state == MusicState.PLAYING:
		var minimum: float = maxf(config.music_gap_min_seconds, 0.0)
		_schedule_music(_rng.randf_range(minimum, maxf(minimum, config.music_gap_max_seconds)))
	_music_envelope = 0.0


# --- Events hooks -------------------------------------------------------------

## Host and client both reach this: Block.gd emits it on the host's own detection
## and MatchNet re-emits it from the replicated impact batch (Bontago-1pi.55).
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	# Bontago-bth.3: with no sample root nothing can play (the picks below return
	# null), so skip the physics surface query too.
	if speed < config.impact_speed_min or not _available:
		return
	_play_impact(speed, _classify_surface(position))


## Speed-only entry kept for callers/tests without a position; treated as the disc.
func _on_block_impacted(speed: float) -> void:
	if speed < config.impact_speed_min:
		return
	_play_impact(speed, AudioConfig.SURFACE_DISC)


## Block-on-block when the impact point overlaps at least
## config.impact_block_surface_min_blocks distinct Blocks (the faller plus what
## it hit); otherwise the disc. DECISION (Bontago-mp0.116): the impact event
## carries no surface, so it is derived from a physics query (the same approach
## as BlockEffectsManager._find_block_at) -- works on clients too, whose frozen
## replicas still collide, and needs no wire change.
func _make_surface_params() -> PhysicsShapeQueryParameters3D:
	var params: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	params.shape = _surface_shape
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return params


func _classify_surface(position: Vector3) -> StringName:
	var world: World3D = get_tree().root.world_3d if is_inside_tree() else null
	if world == null:
		return AudioConfig.SURFACE_DISC
	_surface_shape.radius = config.impact_surface_query_radius_m
	_surface_params.transform = Transform3D(Basis(), position)
	var min_blocks: int = config.impact_block_surface_min_blocks
	_surface_ids.clear()
	for result: Dictionary in world.direct_space_state.intersect_shape(_surface_params, 8):
		if result.get("collider") is BlockBody:
			var id: int = int(result["collider_id"])
			if not _surface_ids.has(id):
				_surface_ids.append(id)
				if _surface_ids.size() >= min_blocks:
					return AudioConfig.SURFACE_BLOCK
	if _surface_ids.size() >= min_blocks:
		return AudioConfig.SURFACE_BLOCK
	return AudioConfig.SURFACE_DISC


## Picks the variation sample for `surface` x the speed's strength tier (random
## variant, never the same twice in a row); falls back to the legacy thud set
## when the variation files are missing.
func _play_impact(speed: float, surface: StringName) -> void:
	var stream: AudioStream = _pick_impact_stream(speed, surface)
	if stream == null:
		stream = _pick_stream(AudioConfig.EVENT_THUD)
	if stream == null:
		return
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db + config.impact_volume_db(speed) + Settings.master_volume_db() + Settings.sfx_volume_db()
	player.play()


func _pick_impact_stream(speed: float, surface: StringName) -> AudioStream:
	if not _available:
		return null
	var tier: StringName = config.impact_tier(speed)
	var key: int = _impact_cache_key(surface, tier)
	var streams: Array[AudioStream] = _impact_streams(surface, tier, key)
	if streams.is_empty():
		return null
	var index: int = 0
	if streams.size() > 1:
		var last: int = int(_last_impact_variant.get(key, -1))
		index = _rng.randi_range(0, streams.size() - 2)
		if last >= 0 and index >= last:
			index += 1
		_last_impact_variant[key] = index
	return streams[index]


## Small int key for the two surfaces x three tiers, -1 for anything else (which
## then bypasses the cache and its variant memory, as an unknown set has no files).
func _impact_cache_key(surface: StringName, tier: StringName) -> int:
	var s: int = IMPACT_SURFACES.find(surface)
	var t: int = IMPACT_TIERS.find(tier)
	if s < 0 or t < 0:
		return -1
	return s * IMPACT_TIERS.size() + t


## Streams for one set, resolved through _load_stream once and then reused.
func _impact_streams(surface: StringName, tier: StringName, key: int) -> Array[AudioStream]:
	if key >= 0:
		if not (is_same(_impact_cache_config, config) and _impact_cache_root == _root_dir 				and is_same(_impact_cache_files, config.impact_variation_files)):
			_impact_stream_cache.clear()
			_impact_cache_config = config
			_impact_cache_root = _root_dir
			_impact_cache_files = config.impact_variation_files
		var cached: Variant = _impact_stream_cache.get(key)
		if cached != null:
			return cached as Array[AudioStream]
	var resolved: Array[AudioStream] = []
	var complete: bool = true
	for file: String in config.impact_variation_for(surface, tier):
		var stream: AudioStream = _load_stream(file)
		complete = complete and stream != null
		resolved.append(stream)
	# A missing file keeps the old behaviour (null entry, retried and reported
	# on each pick), so only a fully resolved set is cached.
	if key >= 0 and complete:
		_impact_stream_cache[key] = resolved
	return resolved


## Plays a lobby/loading UI cue (AudioConfig.ui_cue_files). False when unknown or
## the file is missing.
func play_ui_cue(cue: StringName) -> bool:
	var filename: String = config.ui_cue_file(cue)
	if filename.is_empty() or not _available:
		return false
	var stream: AudioStream = _load_stream(filename)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db + config.ui_cue_volume_db + Settings.master_volume_db() + Settings.sfx_volume_db()
	player.play()
	return true


## net_peer_joined fires for a remote peer on the host and for the local peer on
## a client once accepted. DECISION (Bontago-mp0.117): both chime; a late-joiner
## world replay stays silent.
func _on_net_peer_joined(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	if _world_replay_silent:
		return
	play_ui_cue(&"player_joined")


## DECISION (Bontago-mp0.117): the local peer's own departure (host shutdown or
## leaving) does not play player_left; kick/error have no dedicated cue.
func _on_net_peer_left(peer_id: int, _slot_id: int, _reason: int) -> void:
	if _world_replay_silent or peer_id == Net.local_peer_id():
		return
	play_ui_cue(&"player_left")


## The loading ready gate actually opened (everyone ready / min display elapsed).
func _on_loading_gate_opened() -> void:
	# A late joiner's world replay re-emits the open gate; stay silent then.
	if _world_replay_silent:
		return
	play_ui_cue(&"all_players_ready")


## Bontago-1pi.52: the refusal sound is the refused player's own feedback. The
## host sees every slot's refusals on its bus, so a remote client's (or a bot's)
## must stay silent here -- see autoload/match/LocalFeedback.gd.
func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if not LocalFeedback.is_own_human_slot(slot_id):
		return
	play(AudioConfig.EVENT_REJECTED)


func _on_world_replay_changed(active: bool) -> void:
	_world_replay_silent = active


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	if _world_replay_silent:
		return
	play(AudioConfig.EVENT_DROP)


func _on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	if _world_replay_silent:
		return
	play(AudioConfig.EVENT_BREAKAGE)


## The flight event is emitted locally on the host and on each client when
## the reliable spawn arrives. Late claim or landing events do not retrigger
## it, and gift_spawn_min_interval_s rate-limits the jingle.
func _on_gift_flight_spawned(_gift_id: int, _origin: Vector3, _landing: Vector3) -> void:
	if _world_replay_silent:
		return
	var now_msec: int = Time.get_ticks_msec()
	if _last_gift_spawn_msec >= 0 and float(now_msec - _last_gift_spawn_msec) < config.gift_spawn_min_interval_s * 1000.0:
		return
	if play(AudioConfig.EVENT_GIFT_SPAWNED):
		_last_gift_spawn_msec = now_msec


## DECISION (autoload/Sfx.gd, Bontago-6y2): unlike the world hooks above (a
## block drop/thud/breakage is a physical event any nearby player would
## actually hear happen, so those play for every slot; the rejection sound is
## personal and gated to the refused local human since Bontago-1pi.52), a gift claim queues a special for the whole claiming team -- it is
## personal feedback, not a world event. Gating on "any locally-driven slot on
## the claiming team" mirrors game/GiftCrate.gd's own "_local_watch_slot()"
## comment and ui/HUD.gd's gift toast (Bontago-1en.16), both already
## local-only; a global "someone somewhere claimed a gift" chime would be
## noise in an 8-player match with crates spawning continuously. The loop gates
## on LocalFeedback.is_own_human_slot() (Bontago-1pi.52): a human seat driven
## on this machine, so hot-seat humans still hear their claims while offline
## bots (including bot teammates) never chime.
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
		# Bontago-1pi.52: a human seat on this machine only -- offline every slot
		# is local, so a bot claiming on its own team (or a bot teammate) would
		# otherwise chime for a player who has nothing to do with it.
		if not LocalFeedback.is_own_human_slot(slot_id):
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


# --- Beacon-claim tension layer (Bontago-1pi.114) ------------------------------
#
# Derived locally from Events.goal_capture_progress, which every machine already
# receives (MatchTerritory emits it on host and clients alike; Classic keeps its
# state in that signal, see ModeObjective.replicates_state()), so nothing new is
# replicated and the host stays authoritative. A looped bed is layered above
# whichever music runs (contextual playlist or legacy stem), its volume/pitch
# follow ClaimTensionState.level(), and the music is ducked while it is up.

func _build_claim_layer() -> void:
	_claim_state = ClaimTensionState.new(config)
	_claim_player = AudioStreamPlayer.new()
	_claim_player.volume_db = MUSIC_STEM_MUTE_DB
	add_child(_claim_player)


## Target volume_db of the tension bed at the current level (MUSIC_STEM_MUTE_DB
## when silent), including the master and music sliders.
func claim_tension_target_volume_db() -> float:
	var level: float = _claim_state.level() if _claim_state != null else 0.0
	if level <= 0.0 or not _music_enabled or not config.claim_tension_enabled:
		return MUSIC_STEM_MUTE_DB
	var baseline: float = config.claim_tension_max_db + Settings.master_volume_db() + Settings.music_volume_db()
	return clampf(baseline + linear_to_db(level), MUSIC_STEM_MUTE_DB, baseline)


## Pitch scale of the bed: rises toward claim_tension_pitch_max with level, lower
## (claim_rival_pitch_scale) while a rival holds.
func claim_tension_pitch_scale() -> float:
	if _claim_state == null:
		return 1.0
	var rise: float = lerpf(1.0, config.claim_tension_pitch_max, _claim_state.level())
	return rise if _claim_state.is_mine() else rise * config.claim_rival_pitch_scale


## Music duck (dB offset, <= 0) the current level asks for.
func claim_duck_target_db() -> float:
	if _claim_state == null or not config.claim_tension_enabled:
		return 0.0
	return config.claim_music_duck_db * _claim_state.level()


## The duck currently applied to the music (tweened toward claim_duck_target_db()).
func claim_duck_applied_db() -> float:
	return _claim_duck_db


func claim_tension_level() -> float:
	return _claim_state.level() if _claim_state != null else 0.0


func _local_claim_team(team_id: int) -> int:
	if _claim_test_local_team != null:
		return int(_claim_test_local_team)
	# Any human seat driven here that plays for the holding team makes it mine;
	# otherwise (rival, spectator, bots only) it is the quieter rival flavour.
	for slot_id: int in range(Match.slot_count()):
		if LocalFeedback.is_own_human_slot(slot_id) and _team_of_slot(slot_id) == team_id:
			return team_id
	return ClaimTensionState.NO_LOCAL_TEAM


func _claim_match_live() -> bool:
	if _claim_test_live != null:
		return bool(_claim_test_live)
	return Match.is_live(Match.state())


func _on_claim_progress(team_id: int, progress: float) -> void:
	if not config.claim_tension_enabled or _world_replay_silent or _claim_state == null:
		return
	var live: bool = _claim_match_live()
	var holding: bool = team_id != ClaimTensionState.NO_TEAM and progress > 0.0
	if holding and not live:
		return  # e.g. the END zero-time redraw must not revive the bed after a win
	_claim_ext.snap(team_id, progress)
	var now_s: float = float(Time.get_ticks_msec()) / MSEC_PER_S
	_claim_state.update(team_id, progress, _local_claim_team(team_id), live, now_s)
	_refresh_claim_target(false)
	# A win emits goal_capture_progress first and match_won after, in the same
	# call stack: judge the break one frame later so a win never stings.
	if not _claim_flush_queued and not _claim_state.peek_interrupt().is_empty():
		_claim_flush_queued = true
		_flush_claim_interrupt.call_deferred()


func _flush_claim_interrupt() -> void:
	_claim_flush_queued = false
	if _claim_state == null:
		return
	var info: Dictionary = _claim_state.take_interrupt()
	if info.is_empty():
		return
	var was_mine: bool = bool(info.get("was_mine", false))
	play(AudioConfig.EVENT_CLAIM_INTERRUPTED if was_mine else AudioConfig.EVENT_CLAIM_RIVAL_BROKEN)
	Events.claim_interrupted.emit(was_mine, float(info.get("peak", 0.0)))


func _on_claim_match_won(_team_id: int) -> void:
	if _claim_state == null:
		return
	_claim_state.mark_won()
	_claim_ext.clear()
	_refresh_claim_target(false)


func _claim_is_client() -> bool:
	if _claim_test_client != null:
		return bool(_claim_test_client)
	return Net.is_client()


func _claim_hold_seconds() -> float:
	if _claim_test_hold_s != null:
		return float(_claim_test_hold_s)
	return Match._territory_tuning.capture_hold


## A client only hears the capture progress when the territory raster changes
## (MatchNet skips unchanged boards), so between updates the hold is advanced
## here at the known hold rate while the holding team is unchanged; each real
## update snaps it back. Host path untouched. No new replication.
func _claim_extrapolate(delta: float) -> void:
	if _claim_state == null or not _claim_ext.is_holding() or not config.claim_tension_enabled:
		return
	if not _claim_is_client() or not _claim_match_live():
		return
	if not _claim_ext.advance(delta, _claim_hold_seconds()):
		return
	_claim_state.update(_claim_ext.team(), _claim_ext.progress(), _local_claim_team(_claim_ext.team()), true)
	_refresh_claim_target(true)


## New match scope: silence at once, forget any hold.
func reset_claim_tension() -> void:
	if _claim_state == null:
		return
	_claim_state.reset()
	_claim_flush_queued = false
	_claim_ext.clear()
	_refresh_claim_target(true)


func _kill_claim_tweens() -> void:
	for tween: Tween in [_claim_tween, _claim_duck_tween]:
		if tween != null and tween.is_valid():
			tween.kill()
	_claim_tween = null
	_claim_duck_tween = null


## Moves the bed volume/pitch and the music duck toward the current target;
## `immediate` jumps (scope reset).
func _refresh_claim_target(immediate: bool) -> void:
	if _claim_state == null or _claim_player == null:
		return
	var level: float = claim_tension_level() if config.claim_tension_enabled else 0.0
	var target_db: float = claim_tension_target_volume_db()
	var pitch: float = claim_tension_pitch_scale()
	var duck: float = claim_duck_target_db()
	var targets: Vector3 = Vector3(target_db, pitch, duck)
	if not immediate and targets == _claim_last_targets:
		return
	_claim_last_targets = targets
	if level > 0.0 and not _claim_player.playing and not _claim_stream_missing and _music_enabled:
		_start_claim_bed()
	_kill_claim_tweens()
	var rising: bool = level > _claim_last_level
	if not is_equal_approx(level, _claim_last_level):
		Events.claim_tension_changed.emit(level, _claim_state.is_mine())
	_claim_last_level = level
	if not immediate and level <= 0.0 and not _claim_player.playing and _claim_duck_db == duck:
		return
	if immediate or not is_inside_tree():
		_claim_player.volume_db = target_db
		_claim_player.pitch_scale = pitch
		_set_claim_duck(duck)
		if level <= 0.0:
			_claim_player.stop()
		return
	var fade: float = config.claim_fade_in_seconds if rising else config.claim_fade_out_seconds
	_claim_tween = create_tween().set_parallel(true)
	_claim_tween.tween_property(_claim_player, "volume_db", target_db, fade)
	_claim_tween.tween_property(_claim_player, "pitch_scale", pitch, fade)
	if level <= 0.0:
		_claim_tween.chain().tween_callback(_stop_claim_bed_if_silent)
	_claim_duck_tween = create_tween()
	_claim_duck_tween.tween_method(_set_claim_duck, _claim_duck_db, duck, config.claim_duck_seconds)


func _stop_claim_bed_if_silent() -> void:
	if claim_tension_level() <= 0.0 and _claim_player != null:
		_claim_player.stop()


func _set_claim_duck(duck_db: float) -> void:
	_claim_duck_db = duck_db
	_apply_claim_duck()


## The playlist re-applies its own volume every frame (with _claim_duck_db in
## it); the legacy single stream needs the duck pushed explicitly.
func _apply_claim_duck() -> void:
	if _music_player == null or not _music_player.playing:
		return
	if config.contextual_music_enabled:
		_apply_playlist_volume()
	else:
		_music_player.volume_db = calm_stem_target_volume_db() + _claim_duck_db


func _start_claim_bed() -> void:
	if not _available:
		return
	var source: AudioStream = _load_stream(config.claim_tension_file)
	if source == null:
		_claim_stream_missing = true  # silent no-op: do not retry (and log) every step
		return
	var stream: AudioStream = source.duplicate() as AudioStream
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# load_from_file ignores the .import loop flags; a stream that already loops is left alone.
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		var bytes_per_frame: int = (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / bytes_per_frame
	_claim_player.stream = stream
	_claim_player.play()
