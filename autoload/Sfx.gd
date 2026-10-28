extends Node
## Audio for the game's own sound effects and music.
## Loads streams at runtime from res://assets/audio/sfx (in the editor) or
## <exe dir>/assets/audio/sfx (exported). HARD CONSTRAINT: third-party
## copyrighted assets (including the original Bontago's) never enter this
## repo. Absent folder: one info print, then every play() is a silent
## no-op -- the game runs fine with no sound, the same "supported absence"
## pattern tools/check_steam_setup.ps1 documents for addons/godotsteam/.
##
## Listens on Events; nothing in gameplay code calls Sfx directly (CLAUDE.md's
## global-signal-bus convention). ui/menus/MainMenu.gd and ui/lobby/Lobby.gd are the sole
## UI exceptions -- button press/hover has no Events signal of its own, so
## those screens call Sfx.play() from their button handlers. Main.gd also
## supplies the current menu/lobby/gameplay music context.
##
## No class_name: this is the Sfx autoload singleton (same reason Events,
## Settings, Net and Match have none -- see autoload/Net.gd's header).
##
## Music uses the bundled context playlists. Every play()/play_music()/impact-thud
## volume_db also adds Settings.master_volume_db() on top of this file's own
## AudioConfig.sfx_volume_db/music_volume_db baseline, live-updated via
## Settings.audio_settings_changed. SFX playback additionally adds
## Settings.sfx_volume_db(), music playback Settings.music_volume_db() -- master
## multiplies every channel, the music/SFX sliders only ever scale their own.

const LocalFeedback := preload("res://autoload/match/LocalFeedback.gd")

const AUDIO_SUBDIR: String = "assets/audio/sfx"

## Effectively-silent volume_db floor for whichever music stem is faded out
## of the adaptive crossfade.
## Engineering constant matching AudioServer's convention that -80 dB reads as
## inaudible on any reasonable output device; not designer-facing, so it stays
## a local const rather than an AudioConfig field.
const MUSIC_STEM_MUTE_DB: float = StemMix.MUTE_DB

## DECISION: engine constant, not designer-facing. AudioServer
## only frees a stopped playback after one mix cycle plus a main-thread cleanup,
## so anything stopped/replaced within this window of get_tree().quit() is
## still listed (and reported as leaked) at exit. Long enough for several
## mix cycles at any real output buffer size.
const QUIT_DRAIN_S: float = 0.25
const MSEC_PER_S: float = 1000.0

@export var config: AudioConfig = preload("res://config/audio/audio_config.tres")

## The effects/music folder and its decoded-stream cache (one root serves both).
var _library: StreamLibrary = StreamLibrary.new(_resolve_root_dir())
var _sfx_players: Array[AudioStreamPlayer] = []
## pause-proof pool for menu cues (see _build_player_pool).
const UI_PLAYER_COUNT: int = 4
var _ui_players: Array[AudioStreamPlayer] = []
## Focus-move hover cue: one central hook for every menu. Menu navigation
## actions that press this frame arm it; a gui_focus_changed in the same frame plays one hover.
## Mouse focus (click/hover grab) and programmatic focus (a screen opening) arm nothing, so
## they stay silent here and mouse hover keeps its own mouse_entered cue.
const FOCUS_NAV_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev",
]
var _focus_nav_frame: int = -1
var _focus_hover_frame: int = -1
## Round-robin player slots and no-repeat variant picks; built with the player pool.
var _sting_pool: StingPool
## The contextual music scheduler; this node owns the players and streams it asks for.
var _playlist: MusicPlaylist
var _music_player: AudioStreamPlayer
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## Adaptive music: the tense stem, on the same bus as _music_player, started in sync with it
## whenever both config.music_stem_calm_file and config.music_stem_tense_file
## resolve to real files in the library. Missing tense file: this
## player is simply never given a stream and _tense_stem_available stays
## false -- single-stream playback through _music_player is untouched, no
## error/warning (Skybox.gd's fallback_active pattern).
var _tense_music_player: AudioStreamPlayer
var _tense_stem_available: bool = false
## The calm/tense rules Events.goal_capture_progress drives; it answers even while
## _tense_stem_available is false, so the intended target is readable without a live Tween.
var _stem_mix: StemMix
var _music_crossfade_tween: Tween

## Lazy music: the path-playlist requests still outstanding (path -> true).
## Only the upcoming track is ever held.
var _music_requested: Dictionary = {}
## The requested path the next start will take; reaping spares it.
var _pending_music_path: String = ""
var _last_gift_spawn_msec: int = -1
## last special cue time per SpecialDef id (special_cue_min_interval_s).
var _last_special_cue_msec: Dictionary[StringName, int] = {}
## live timed-special loops, oldest first: {player, def_id}.
var _special_loops: Array[Dictionary] = []
var _last_glue_hit_msec: int = -1
var _last_bean_hop_msec: int = -1
## true while a late joiner's world replay is being applied
## (Events.world_replay_changed). The replay re-emits block_placed per body, the
## elimination of every dead slot and every falling crate's flight so the world
## rebuilds; those are state, not news, and must not sound. Not cleared by
## match_scope_reset: the client's world build fires that mid-replay.
var _world_replay_silent: bool = false
var _last_music_tick_usec: int = Time.get_ticks_usec()
## resolved impact streams per surface x tier (int key from
## _impact_cache_key), so a hit does no string building or file-exists stat. Only
## filled when every variation resolved; dropped when config/root/variation set change.
const IMPACT_SURFACES: Array[StringName] = [AudioConfig.SURFACE_BLOCK, AudioConfig.SURFACE_DISC]
const IMPACT_TIERS: Array[StringName] = [AudioConfig.TIER_SOFT, AudioConfig.TIER_MEDIUM, AudioConfig.TIER_HARD]
var _impact_stream_cache: Dictionary = {}
var _impact_cache_config: AudioConfig = null
var _impact_cache_root: String = ""
var _impact_cache_files: Dictionary = {}
## reused surface-query objects (radius refreshed per call).
var _surface_shape: SphereShape3D = SphereShape3D.new()
var _surface_params: PhysicsShapeQueryParameters3D = _make_surface_params()
var _surface_ids: PackedInt64Array = PackedInt64Array()

## Beacon-claim tension layer; see the section near the end.
var _claim_state: ClaimTensionState
var _claim_player: AudioStreamPlayer
var _claim_tween: Tween
var _claim_duck_tween: Tween
var _claim_duck_db: float = 0.0
var _claim_stream_missing: bool = false
var _claim_flush_queued: bool = false
var _claim_last_level: float = 0.0
## Last applied (volume_db, pitch, duck) targets; an unchanged target makes no tweens.
var _claim_last_targets: Vector3 = Vector3(MUSIC_STEM_MUTE_DB, 1.0, 0.0)
## Client-side extrapolation of a hold between sparse replicated updates.
var _claim_ext: ClaimProgressExtrapolator = ClaimProgressExtrapolator.new()


func _ready() -> void:
	BlockBody.impact_speed_min = config.impact_speed_min
	BlockBody.impacts_enabled = config.impacts_enabled
	if not _library.available():
		print("Sfx: no effects at %s -- game runs silently." % _library.root_dir())
	_build_player_pool()
	_playlist = MusicPlaylist.new(config, _rng)
	_stem_mix = StemMix.new(config)
	_refresh_tense_stem()
	_build_claim_layer()
	var listener: FocusNavListener = FocusNavListener.new()
	listener.on_event = _note_focus_nav
	add_child(listener)
	get_viewport().gui_focus_changed.connect(_on_gui_focus_changed)
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
	Events.special_triggered.connect(_on_special_triggered)
	Events.special_consumed.connect(_on_special_consumed)
	Events.bean_hopped.connect(_on_bean_hopped)
	Events.match_scope_reset.connect(stop_special_loops)
	Events.world_replay_changed.connect(_on_world_replay_changed)
	Events.goal_capture_progress.connect(_on_goal_capture_progress)
	Events.goal_capture_progress.connect(_on_claim_progress)
	Events.match_won.connect(_on_claim_match_won)
	# A new match must not inherit the previous match's tense stem.
	Events.match_scope_reset.connect(reset_match_audio)
	Events.match_scope_reset.connect(reset_claim_tension)
	Settings.audio_settings_changed.connect(_on_audio_settings_changed)
	# Music is NOT started here; Main._show_main_menu() calls play_music() once
	# the splash intro is over (or at once when there is none).


func _resolve_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + AUDIO_SUBDIR)
	return OS.get_executable_path().get_base_dir().path_join(AUDIO_SUBDIR)


## Settings.audio_settings_changed re-applies the volume of whatever is already
## playing -- no restart needed to hear a slider move.
func _on_audio_settings_changed() -> void:
	if config.contextual_music_enabled:
		_apply_playlist_volume()
		return
	_library.release()
	_refresh_tense_stem()
	if _music_player.playing:
		_music_player.volume_db = calm_stem_target_volume_db()
	if _tense_stem_available and _tense_music_player.playing:
		_tense_music_player.volume_db = tense_stem_target_volume_db()


## Inner node that stays live under the offline pause menu (Sfx itself pauses with the tree).
class FocusNavListener extends Node:
	var on_event: Callable

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _input(event: InputEvent) -> void:
		on_event.call(event)


## Arms the focus-move hover cue for this frame. Code that moves focus from _process (a held
## stick or d-pad repeat, with no input event that frame) calls this just before grab_focus().
func note_focus_nav() -> void:
	_focus_nav_frame = Engine.get_process_frames()


func _note_focus_nav(event: InputEvent) -> void:
	if event is InputEventMouse or not event.is_pressed():
		return
	for action: StringName in FOCUS_NAV_ACTIONS:
		if event.is_action_pressed(action, true):
			note_focus_nav()
			return


func _on_gui_focus_changed(_control: Control) -> void:
	var frame: int = Engine.get_process_frames()
	if _focus_nav_frame != frame or _focus_hover_frame == frame:
		return
	_focus_hover_frame = frame
	play(AudioConfig.EVENT_HOVER)


func _build_player_pool() -> void:
	for _i: int in range(config.max_simultaneous):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)
	# DECISION: menu cues (click, hover, start, lobby UI cues) use their own
	# small pool that keeps playing while the offline pause menu has paused the tree; match SFX,
	# ambience and music stay on the pausable pool above and freeze with the world.
	for _i: int in range(UI_PLAYER_COUNT):
		var ui_player: AudioStreamPlayer = AudioStreamPlayer.new()
		ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(ui_player)
		_ui_players.append(ui_player)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	_tense_music_player = AudioStreamPlayer.new()
	_tense_music_player.bus = _music_player.bus
	add_child(_tense_music_player)
	_sting_pool = StingPool.new(_sfx_players.size(), _ui_players.size(), _rng)


## Plays one of `event`'s configured files on a pooled AudioStreamPlayer (or
## the music player for AudioConfig.EVENT_MUSIC). Returns whether anything
## actually played -- false with no assets installed, an unknown event, or a
## missing file.
func play(event: StringName) -> bool:
	if event == AudioConfig.EVENT_MUSIC and config.contextual_music_enabled:
		play_music()
		return config.playlist_track_count(_playlist.context()) > 0
	var stream: AudioStream = _pick_stream(event)
	if stream == null:
		return false
	if event == AudioConfig.EVENT_MUSIC:
		_play_music_stream(stream)
		return true
	var player: AudioStreamPlayer = _next_ui_player() if _is_menu_event(event) else _next_sfx_player()
	player.stream = stream
	player.volume_db = _volume_db(config.sfx_volume_db, Settings.sfx_volume_db())
	player.play()
	return true


func play_music() -> void:
	if config.contextual_music_enabled:
		_last_music_tick_usec = Time.get_ticks_usec()
		_playlist.start()
		_prepare_next_track()
		return
	var stream: AudioStream = _pick_stream(AudioConfig.EVENT_MUSIC)
	if stream != null:
		_play_music_stream(stream)


## Single theme: the explicit stream (tests/custom builds) else the
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
		# The bundled theme comes first.
		var bundled: AudioStream = _bundled_theme()
		if bundled != null:
			return bundled
		if not _library.available():
			return null
		# DECISION (autoload/Sfx.gd): only steer music_file's own EVENT_MUSIC
		# selection toward music_stem_calm_file once a real tense partner exists
		# (_tense_stem_available) -- with no tense asset installed there is
		# nothing to be "calm" relative to, so the existing music_file selection
		# stays the single source of truth. Once both stems are installed, the
		# calm player must play the calm-labelled file rather than whatever
		# music_file/shuffle would otherwise pick, or the two could silently
		# mismatch.
		if _tense_stem_available:
			return _library.stream(config.music_stem_calm_file)
	elif not _library.available():
		return null
	var files: Array[String] = config.files_for_event(event)
	if files.is_empty():
		return null
	var filename: String = files[0] if files.size() == 1 else files[_rng.randi_range(0, files.size() - 1)]
	return _library.stream(filename)


func _is_menu_event(event: StringName) -> bool:
	return event == AudioConfig.EVENT_CLICK or event == AudioConfig.EVENT_HOVER or event == AudioConfig.EVENT_START_GAME


func _next_ui_player() -> AudioStreamPlayer:
	if _ui_players.is_empty():
		return _next_sfx_player()
	return _ui_players[_sting_pool.next_ui_slot()]


func _next_sfx_player() -> AudioStreamPlayer:
	return _sfx_players[_sting_pool.next_sfx_slot()]


# --- Adaptive music -------------------------------------------------------------

## Re-derives _tense_stem_available against the current library.
## Requires BOTH config.music_stem_calm_file and config.music_stem_tense_file
## to resolve to real files there -- a "calm" stem with no matching "tense"
## partner has nothing to crossfade to, so it is treated the same as a
## missing tense file (no error either way, just _tense_stem_available
## staying false). Called whenever the library can change (_ready(),
## _on_audio_settings_changed()).
func _refresh_tense_stem() -> void:
	var was_available: bool = _tense_stem_available
	_tense_stem_available = false
	if _tense_music_player == null:
		return  # called from _ready() before _build_player_pool() creates it
	_tense_music_player.stop()
	# The owner theme is a complete mix, not a stem of the original score.
	if config.contextual_music_enabled or _bundled_theme() != null:
		_stem_mix.reset()
		return
	if not _library.available():
		if was_available:
			_stem_mix.reset()  # the tense stem just disappeared -- fall back to calm
		return
	if not _library.has_file(config.music_stem_calm_file) or not _library.has_file(config.music_stem_tense_file):
		if was_available:
			_stem_mix.reset()  # the tense (or its calm partner) just disappeared -- fall back to calm
		return
	var stream: AudioStream = _library.stream(config.music_stem_tense_file)
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


## Target volume_db for the calm stem given the last _on_goal_capture_progress
## call: full baseline while calm is the active side, MUSIC_STEM_MUTE_DB while
## tense is. Exposed (with tense_stem_target_volume_db() below) so a test can
## assert the intended crossfade direction without waiting for a live Tween
## or touching audio hardware.
##
## DECISION (autoload/Sfx.gd): never mute unless the tense stem is actually
## available -- the StemMix flag alone isn't enough to gate this, because
## it can flip true from a plain Events.goal_capture_progress reading (no asset
## needed) even in the shipped single-stream config. Without this guard, the
## next play_music()/_on_audio_settings_changed() call would apply
## MUSIC_STEM_MUTE_DB to the only music stream that exists and mute it
## permanently.
func calm_stem_target_volume_db() -> float:
	if not _tense_stem_available:
		return _volume_db(config.music_volume_db, Settings.music_volume_db())
	return _stem_target_db(_stem_mix.calm_db())


## Mirror of calm_stem_target_volume_db() for the tense stem. Symmetric guard:
## with no tense stem installed there is nothing to raise the volume of, so
## this stays muted (moot in practice -- the tense player is never started
## while unavailable).
func tense_stem_target_volume_db() -> float:
	if not _tense_stem_available:
		return MUSIC_STEM_MUTE_DB
	return _stem_target_db(_stem_mix.tense_db())


## A stem gain from StemMix with the master and music-channel offsets added; a muted stem stays muted.
func _stem_target_db(stem_db: float) -> float:
	return stem_db if stem_db <= MUSIC_STEM_MUTE_DB else _volume_db(stem_db, Settings.music_volume_db())


## Events.goal_capture_progress (spec 1.10's adaptive music crossfade): the
## crossfade only cares how close ANY team is to capturing, not which one, so
## team_id is unused. Events.gd: "team_id is -1 with progress 0 when a capture
## breaks" -- 0.0 is always below the threshold, so StemMix needs no special case.
func _on_goal_capture_progress(_team_id: int, progress: float) -> void:
	if config.contextual_music_enabled:
		return
	if not _stem_mix.on_progress(progress):
		return
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


## Events.match_scope_reset. A match left while the tense stem
## was up (contextual music off: only a later goal_capture_progress clears it) must
## not start the next match tense. Returns the stems to calm exactly as _ready() leaves
## them: tense flag off, an in-flight crossfade killed, each stem at its calm target.
## Idempotent. Playlist position and context are NOT touched (they continue
## across matches); with contextual music on the tense stem never activates and the
## playlist envelope owns the volume, so only the flag and tween are cleared.
func reset_match_audio() -> void:
	if _music_crossfade_tween != null and _music_crossfade_tween.is_valid():
		_music_crossfade_tween.kill()
	_music_crossfade_tween = null
	_stem_mix.reset()
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
	if context == _playlist.context() or context not in MusicPlaylist.CONTEXTS:
		return
	_playlist.set_context(context)
	if not config.contextual_music_enabled:
		return
	_last_music_tick_usec = Time.get_ticks_usec()
	# Prefetch the next context's track now so it is decoded-ready by the time
	# the fade-out of the current one ends.
	_prepare_next_track()


func _process(delta: float) -> void:
	_claim_extrapolate(delta)
	# Sandbox slow-motion changes Engine.time_scale, not the audio clock.
	# Silence and transitions use wall time; song fades follow the decoder.
	var now_usec: int = Time.get_ticks_usec()
	var real_delta: float = maxf(float(now_usec - _last_music_tick_usec) / 1000000.0, 0.0)
	_last_music_tick_usec = now_usec
	var playback_position: float = -1.0
	if _playlist.phase() == MusicPlaylist.Phase.PLAYING and _music_player.playing:
		playback_position = maxf(0.0, _music_player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency())
	_advance_music(real_delta, playback_position)
	if not _music_requested.is_empty():
		_reap_music_requests()


## Quit-time release: stop every player and drop stream refs
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


## The one quit helper: marks the quit, drains audio, then quits the tree.
## Every real quit path (Main close, Boot close, AgentProbe --quit-on-menu) goes through it so
## none skips drain_for_quit. Safe to call without awaiting.
func quit_tree(exit_code: int = 0) -> void:
	if _quit_started:  # a second request during the drain is a no-op; first exit code wins
		return
	_quit_started = true
	QuitFlag.mark()
	await drain_for_quit()
	get_tree().quit(exit_code)


func release_audio() -> void:
	if _music_crossfade_tween != null and _music_crossfade_tween.is_valid():
		_music_crossfade_tween.kill()
	_music_crossfade_tween = null
	_playlist.release()
	stop_special_loops()
	var players: Array[AudioStreamPlayer] = _sfx_players.duplicate()
	players.append_array(_ui_players)
	players.append(_music_player)
	players.append(_tense_music_player)
	players.append(_claim_player)
	for player: AudioStreamPlayer in players:
		if player != null and is_instance_valid(player):
			player.stop()
			player.stream = null
	_kill_claim_tweens()
	_library.release()
	_drop_music_requests()


func _notification(what: int) -> void:
	if what == NOTIFICATION_UNPAUSED:
		_last_music_tick_usec = Time.get_ticks_usec()


func _advance_music(delta: float, playback_position: float = -1.0) -> void:
	if not config.contextual_music_enabled:
		return
	var length: float = _music_player.stream.get_length() if _music_player.stream != null else 0.0
	match _playlist.advance(delta, playback_position, length):
		MusicPlaylist.Step.START_TRACK:
			_start_playlist_track()
		MusicPlaylist.Step.STOP_PLAYER:
			_music_player.stop()
			_music_player.stream = null # release the faded-out track
			_last_music_tick_usec = Time.get_ticks_usec()
			_prepare_next_track()
	var phase: MusicPlaylist.Phase = _playlist.phase()
	if phase == MusicPlaylist.Phase.PLAYING or phase == MusicPlaylist.Phase.SWITCHING:
		_apply_playlist_volume()


## Starts the threaded load of the upcoming track (path playlists only); idempotent.
func _prepare_next_track() -> void:
	var phase: MusicPlaylist.Phase = _playlist.phase()
	if phase != MusicPlaylist.Phase.WAITING and phase != MusicPlaylist.Phase.SWITCHING:
		return
	var index: int = _playlist.next_track()
	var paths: PackedStringArray = config.playlist_paths_for_context(_playlist.context())
	_pending_music_path = paths[index] if index >= 0 and index < paths.size() else ""
	if not _pending_music_path.is_empty():
		_request_music_path(_pending_music_path)


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
	for path: String in _music_requested.keys():
		if path == _pending_music_path:
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
	_pending_music_path = ""


func _load_track(context: StringName, index: int) -> AudioStream:
	var override: Array[AudioStream] = config.playlist_for_context(context)
	if not override.is_empty():
		return override[index]
	return _take_music_stream(config.playlist_paths_for_context(context)[index])


func _start_playlist_track() -> void:
	var context: StringName = _playlist.context()
	var selected: int = _playlist.next_track()
	_pending_music_path = ""
	var source: AudioStream = _load_track(context, selected)
	# A failed load advances to the next entry; each entry is tried once.
	var count: int = config.playlist_track_count(context)
	var tried: int = 1
	while source == null and tried < count:
		selected = (selected + 1) % count
		tried += 1
		source = _load_track(context, selected)
	if source == null:
		_playlist.release()
		return
	# Duplicate before changing loop flags: imported shared resources must
	# not inherit this playback's settings.
	var stream: AudioStream = source.duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = false
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_music_player.stream = stream
	_playlist.track_started(selected)
	_apply_playlist_volume()
	_music_player.play()


func _apply_playlist_volume() -> void:
	if _music_player == null:
		return
	var envelope: float = _playlist.envelope()
	var baseline: float = _volume_db(config.music_volume_db, Settings.music_volume_db())
	_music_player.volume_db = MUSIC_STEM_MUTE_DB if envelope <= 0.0 else maxf(MUSIC_STEM_MUTE_DB, baseline + _claim_duck_db + linear_to_db(envelope))


func _on_music_finished() -> void:
	if not config.contextual_music_enabled:
		return
	_music_player.stream = null # finished track: release it during the silent gap
	_last_music_tick_usec = Time.get_ticks_usec()
	_playlist.track_finished()
	_prepare_next_track()


# --- Events hooks -------------------------------------------------------------

## Host and client both reach this: Block.gd emits it on the host's own detection
## and MatchNet re-emits it from the replicated impact batch.
func _on_block_impacted_at(speed: float, position: Vector3) -> void:
	# with no sample root nothing can play (the picks below return
	# null), so skip the physics surface query too.
	if speed < config.impact_speed_min or not _library.available():
		return
	_play_impact(speed, _classify_surface(position))
	if _impact_touches_glue():
		_play_glue_hit()


## Block-on-block when the impact point overlaps at least
## config.impact_block_surface_min_blocks distinct Blocks (the faller plus what
## it hit); otherwise the disc. DECISION: the impact event
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
	# every block in the query is kept (no early return at
	# min_blocks), so _impact_touches_glue() can look at all of them.
	for result: Dictionary in world.direct_space_state.intersect_shape(_surface_params, 8):
		if result.get("collider") is BlockBody:
			var id: int = int(result["collider_id"])
			if not _surface_ids.has(id):
				_surface_ids.append(id)
	if _surface_ids.size() >= min_blocks:
		return AudioConfig.SURFACE_BLOCK
	return AudioConfig.SURFACE_DISC


## Picks the variation sample for `surface` x the speed's strength tier (random
## variant, never the same twice in a row); falls back to the plain thud set
## when the variation files are missing.
func _play_impact(speed: float, surface: StringName) -> void:
	var stream: AudioStream = _pick_impact_stream(speed, surface)
	if stream == null:
		stream = _pick_stream(AudioConfig.EVENT_THUD)
	if stream == null:
		return
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = _volume_db(config.sfx_volume_db + config.impact_volume_db(speed), Settings.sfx_volume_db())
	player.play()


func _pick_impact_stream(speed: float, surface: StringName) -> AudioStream:
	if not _library.available():
		return null
	var tier: StringName = config.impact_tier(speed)
	var key: int = _impact_cache_key(surface, tier)
	var streams: Array[AudioStream] = _impact_streams(surface, tier, key)
	if streams.is_empty():
		return null
	return streams[_sting_pool.pick_variant(key, streams.size())]


## Small int key for the two surfaces x three tiers, -1 for anything else (which
## then bypasses the cache and its variant memory, as an unknown set has no files).
func _impact_cache_key(surface: StringName, tier: StringName) -> int:
	var s: int = IMPACT_SURFACES.find(surface)
	var t: int = IMPACT_TIERS.find(tier)
	if s < 0 or t < 0:
		return -1
	return s * IMPACT_TIERS.size() + t


## Streams for one set, resolved through _library.stream once and then reused.
func _impact_streams(surface: StringName, tier: StringName, key: int) -> Array[AudioStream]:
	if key >= 0:
		if not (is_same(_impact_cache_config, config) and _impact_cache_root == _library.root_dir() 				and is_same(_impact_cache_files, config.impact_variation_files)):
			_impact_stream_cache.clear()
			_impact_cache_config = config
			_impact_cache_root = _library.root_dir()
			_impact_cache_files = config.impact_variation_files
		var cached: Variant = _impact_stream_cache.get(key)
		if cached != null:
			return cached as Array[AudioStream]
	var resolved: Array[AudioStream] = []
	var complete: bool = true
	for file: String in config.impact_variation_for(surface, tier):
		var stream: AudioStream = _library.stream(file)
		complete = complete and stream != null
		resolved.append(stream)
	# A missing file keeps a null entry (retried and reported
	# on each pick), so only a fully resolved set is cached.
	if key >= 0 and complete:
		_impact_stream_cache[key] = resolved
	return resolved


## Plays a lobby/loading UI cue (AudioConfig.ui_cue_files). False when unknown or
## the file is missing.
func play_ui_cue(cue: StringName) -> bool:
	var filename: String = config.ui_cue_file(cue)
	if filename.is_empty() or not _library.available():
		return false
	var stream: AudioStream = _library.stream(filename)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _next_ui_player()
	player.stream = stream
	player.volume_db = _volume_db(config.sfx_volume_db + config.ui_cue_volume_db, Settings.sfx_volume_db())
	player.play()
	return true


## net_peer_joined fires for a remote peer on the host and for the local peer on
## a client once accepted. DECISION: both chime; a late-joiner world replay
## stays silent.
func _on_net_peer_joined(_peer_id: int, _slot_id: int, _player_name: String) -> void:
	if _world_replay_silent:
		return
	play_ui_cue(&"player_joined")


## DECISION: the local peer's own departure (host shutdown or leaving) does not play player_left; kick/error have no dedicated cue.
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


## The refusal sound is the refused player's own feedback. The
## host sees every slot's refusals on its bus, so a remote client's (or a bot's)
## must stay silent here -- see autoload/match/LocalFeedback.gd.
func _on_placement_rejected(slot_id: int, _reason: StringName) -> void:
	if not LocalFeedback.is_own_human_slot(slot_id):
		return
	play(AudioConfig.EVENT_REJECTED)


func _on_world_replay_changed(active: bool) -> void:
	_world_replay_silent = active


## The release cue is the dropping player's own feedback. The
## host sees every slot's placements (bots, remote clients) and a client sees
## every replicated spawn, so only a block owned by this machine's human seat
## sounds it; impact sounds are separate and unaffected.
func _on_block_placed(block: RigidBody3D, _shape_id: StringName) -> void:
	if _world_replay_silent:
		return
	if not _plays_drop_cue_for(block):
		return
	play(AudioConfig.EVENT_DROP)


func _plays_drop_cue_for(block: RigidBody3D) -> bool:
	var body: BlockBody = block as BlockBody
	if body == null:
		return false
	return LocalFeedback.is_own_human_slot(body.owner_slot)


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
	if _within_interval(_last_gift_spawn_msec, config.gift_spawn_min_interval_s, now_msec):
		return
	if play(AudioConfig.EVENT_GIFT_SPAWNED):
		_last_gift_spawn_msec = now_msec


## Spec 1.10 "Specials have distinct warning sounds": a special
## going off is a world event like an impact, so every instance hears every
## special -- the host on its own trigger, a client on the replicated one.
## Chained triggers of the same special inside special_cue_min_interval_s sound once.
func _on_special_triggered(_net_id: int, def_id: StringName, _position: Vector3, _chain_depth: int) -> void:
	# A timed special's trigger ends its window: its loop (if any) fades out.
	_fade_out_special_loop(def_id)
	if _world_replay_silent or not _library.available():
		return
	var filename: String = config.special_cue_files.get(def_id, "")
	if filename.is_empty():
		return
	var now_msec: int = Time.get_ticks_msec()
	var last_msec: int = _last_special_cue_msec.get(def_id, -1)
	if _within_interval(last_msec, config.special_cue_min_interval_s, now_msec):
		return
	var stream: AudioStream = _library.stream(filename)
	if stream == null:
		return
	_last_special_cue_msec[def_id] = now_msec
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = _volume_db(config.sfx_volume_db + config.special_cue_volume_db, Settings.sfx_volume_db())
	player.play()


# --- Timed-special loops, Glue hits, Jumping Bean hops ----------

## A timed special (Earthquake, Magnet) was used: loop its bed for the effect's
## whole window. special_consumed is the one start signal every peer gets (an
## in-place Earthquake has no carrier on a client).
## DECISION: the window length is the effect's own effect_lifetime_s(), read dynamically so this autoload gains no compile edge
## to SpecialEffect (tools/lint_layers.py L3). Magnet's pull_start_delay_s (0 by
## default) is inside that lifetime, so a delayed pull would hum early.
func _on_special_consumed(_slot_id: int, special_id: StringName) -> void:
	if _world_replay_silent or not _library.available():
		return
	var filename: String = config.special_loop_files.get(special_id, "")
	if filename.is_empty():
		return
	var seconds: float = _special_active_seconds(special_id)
	var source: AudioStream = _library.stream(filename)
	if source == null or seconds <= 0.0:
		return
	while _special_loops.size() >= maxi(config.special_loop_max, 1):
		_stop_special_loop(0)
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	add_child(player)
	player.stream = _looped_copy(source)
	var target_db: float = (
		_volume_db(config.sfx_volume_db + config.special_loop_volume_db, Settings.sfx_volume_db())
	)
	player.volume_db = MUSIC_STEM_MUTE_DB
	player.play()
	var fade_in: float = minf(config.special_loop_fade_in_s, seconds)
	var fade_out: float = minf(config.special_loop_fade_out_s, maxf(seconds - fade_in, 0.0))
	var tween: Tween = player.create_tween()
	tween.tween_property(player, "volume_db", target_db, fade_in)
	tween.tween_interval(maxf(seconds - fade_in - fade_out, 0.0))
	tween.tween_property(player, "volume_db", MUSIC_STEM_MUTE_DB, fade_out)
	tween.tween_callback(_on_special_loop_done.bind(player))
	_special_loops.append({"player": player, "def_id": special_id})


## Seconds `special_id`'s effect stays active (0 when unknown).
func _special_active_seconds(special_id: StringName) -> float:
	var def: SpecialDef = SpecialDef.find_by_id(special_id)
	if def == null or def.effect == null or not def.effect.has_method(&"effect_lifetime_s"):
		return 0.0
	return float(def.effect.call(&"effect_lifetime_s"))


## Fades out and frees the oldest live loop for `def_id` (no-op without one).
func _fade_out_special_loop(def_id: StringName) -> void:
	for i: int in range(_special_loops.size()):
		if _special_loops[i]["def_id"] != def_id:
			continue
		var player: AudioStreamPlayer = _special_loops[i]["player"] as AudioStreamPlayer
		_special_loops.remove_at(i)
		if is_instance_valid(player):
			var tween: Tween = player.create_tween()
			tween.tween_property(player, "volume_db", MUSIC_STEM_MUTE_DB, config.special_loop_fade_out_s)
			tween.tween_callback(player.queue_free)
		return


func _on_special_loop_done(player: AudioStreamPlayer) -> void:
	for i: int in range(_special_loops.size()):
		if _special_loops[i]["player"] == player:
			_special_loops.remove_at(i)
			break
	if is_instance_valid(player):
		player.queue_free()


func _stop_special_loop(index: int) -> void:
	var player: AudioStreamPlayer = _special_loops[index]["player"] as AudioStreamPlayer
	_special_loops.remove_at(index)
	if is_instance_valid(player):
		player.queue_free()


## Stops every timed-special loop at once (match reset, release_audio).
func stop_special_loops() -> void:
	while not _special_loops.is_empty():
		_stop_special_loop(0)


## True when a block in the last impact query wears the glue coat
## (HoneyCoat, reached through LateScripts like net/MatchNet.gd does).
func _impact_touches_glue() -> bool:
	if config.glue_hit_file.is_empty():
		return false
	var coat: Script = LateScripts.script(LateScripts.HONEY_COAT)
	for id: int in _surface_ids:
		var body: Object = instance_from_id(id)
		if body != null and bool(coat.call(&"is_coated", body)):
			return true
	return false


func _play_glue_hit() -> void:
	var now_msec: int = Time.get_ticks_msec()
	if _within_interval(_last_glue_hit_msec, config.glue_hit_min_interval_s, now_msec):
		return
	if _play_cue_file(config.glue_hit_file):
		_last_glue_hit_msec = now_msec


func _on_bean_hopped(_position: Vector3) -> void:
	if _world_replay_silent:
		return
	var now_msec: int = Time.get_ticks_msec()
	if _within_interval(_last_bean_hop_msec, config.bean_hop_min_interval_s, now_msec):
		return
	if _play_cue_file(config.bean_hop_file):
		_last_bean_hop_msec = now_msec


## True while `now_msec` is still inside `interval_s` of `last_msec` (-1 = never played).
func _within_interval(last_msec: int, interval_s: float, now_msec: int) -> bool:
	return last_msec >= 0 and float(now_msec - last_msec) < interval_s * MSEC_PER_S


## One-shot of an effects-folder file on the SFX pool; false when missing.
func _play_cue_file(filename: String) -> bool:
	if filename.is_empty() or not _library.available():
		return false
	var stream: AudioStream = _library.stream(filename)
	if stream == null:
		return false
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = _volume_db(config.sfx_volume_db, Settings.sfx_volume_db())
	player.play()
	return true


## The F4 SFX tab's file list: the loadable (.wav/.mp3, what the library reads)
## files directly inside the effects folder, lowercase, alphabetical. Empty with no assets.
func effect_files() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	if not _library.available():
		return found
	for filename: String in DirAccess.get_files_at(_library.root_dir()):
		var lower: String = filename.to_lower()
		if lower.ends_with(".wav") or lower.ends_with(".mp3"):
			found.append(lower)
	found.sort()
	return found


## Plays one effects-folder file once on the same pool and volume a real event
## uses (the F4 SFX tab's Play button). False when the file is missing or not loadable.
func preview_file(filename: String) -> bool:
	return _play_cue_file(filename)


## A looping duplicate of `source` (load_from_file ignores the .import loop flags;
## a stream that already loops is left alone).
func _looped_copy(source: AudioStream) -> AudioStream:
	var stream: AudioStream = source.duplicate() as AudioStream
	if stream is AudioStreamWAV and (stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var wav: AudioStreamWAV = stream as AudioStreamWAV
		var bytes_per_frame: int = (2 if wav.format == AudioStreamWAV.FORMAT_16_BITS else 1) * (2 if wav.stereo else 1)
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = wav.data.size() / bytes_per_frame
	return stream


## DECISION (autoload/Sfx.gd): unlike the world hooks above (a block
## drop/thud/breakage is a physical event any nearby player would hear, so
## those play for every slot), a gift claim queues a special for the whole
## claiming team and is personal feedback, not a world event. Gating on "any
## locally-driven slot on the claiming team" mirrors game/gifts/GiftCrate.gd's
## "_local_watch_slot()" and ui/hud/HUD.gd's gift toast; a global "someone
## claimed a gift" chime would be noise in an 8-player match with crates
## spawning continuously. The loop gates on LocalFeedback.is_own_human_slot():
## a human seat driven on this machine, so offline humans still hear their
## claims while offline bots (including bot teammates) never chime. No quieter
## variant for other teams' claims: they stay silent.
##
## `recipient_slot` is the RESOLVED RECIPIENT -- the one teammate nearest the
## crate, not every teammate -- but this sound is still a team-wide
## notification (a teammate should hear "your team claimed a special" even on
## a claim that doesn't land in their own queue). A single
## Net.is_local_slot(recipient_slot) check would silently drop the sound for a
## teammate at a different slot index. So this loops every slot and plays once
## as soon as any locally-driven slot is on the recipient's team (a claim
## landing on slot 0 plays for a local player at slot 0 or its teammate slot 2
## under TEAMS_2).
##
## The loop bound is `maxi(Match.slot_count(), recipient_slot + 1)`, not just
## Match.slot_count(): tests/unit/audio/test_sfx.gd calls this directly with no
## match started (slot_count() == 0), where team_of_slot() falls back to
## identity (see LocalFeedback.team_of_slot()), so this keeps checking at least slot
## recipient_slot itself.
func _on_gift_claimed(_gift_id: int, recipient_slot: int, _special_id: StringName) -> void:
	for slot_id: int in range(maxi(MatchContext.current().slot_count(), recipient_slot + 1)):
		# A human seat on this machine only -- offline every slot
		# is local, so a bot claiming on its own team (or a bot teammate) would
		# otherwise chime for a player who has nothing to do with it.
		if not LocalFeedback.is_own_human_slot(slot_id):
			continue
		if LocalFeedback.team_of_slot(slot_id) != LocalFeedback.team_of_slot(recipient_slot):
			continue
		play(AudioConfig.EVENT_GIFT_CLAIMED)
		return


## Final volume_db: `base_db` plus the master slider and the given channel slider (sfx or music).
func _volume_db(base_db: float, channel_db: float) -> float:
	return base_db + Settings.master_volume_db() + channel_db


# --- Beacon-claim tension layer ------------------------------
#
# Derived locally from Events.goal_capture_progress, which every machine already
# receives (MatchTerritory emits it on host and clients alike; Classic keeps its
# state in that signal, see ModeObjective.replicates_state()), so nothing new is
# replicated and the host stays authoritative. A looped bed is layered above
# whichever music runs (contextual playlist or disk stem), its volume/pitch
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
	if level <= 0.0 or not config.claim_tension_enabled:
		return MUSIC_STEM_MUTE_DB
	var baseline: float = _volume_db(config.claim_tension_max_db, Settings.music_volume_db())
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


func claim_tension_level() -> float:
	return _claim_state.level() if _claim_state != null else 0.0


func _local_claim_team(team_id: int) -> int:
	# Any human seat driven here that plays for the holding team makes it mine;
	# otherwise (rival, spectator, bots only) it is the quieter rival flavour.
	for slot_id: int in range(MatchContext.current().slot_count()):
		if LocalFeedback.is_own_human_slot(slot_id) and LocalFeedback.team_of_slot(slot_id) == team_id:
			return team_id
	return ClaimTensionState.NO_LOCAL_TEAM


func _claim_match_live() -> bool:
	return MatchPhase.is_live(MatchContext.current().state())


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


func _on_claim_match_won(_team_id: int) -> void:
	if _claim_state == null:
		return
	_claim_state.mark_won()
	_claim_ext.clear()
	_refresh_claim_target(false)


func _claim_is_client() -> bool:
	return MatchContext.current().net_is_client()


func _claim_hold_seconds() -> float:
	return MatchContext.current().capture_hold_seconds()


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
	if level > 0.0 and not _claim_player.playing and not _claim_stream_missing:
		_start_claim_bed()
	_kill_claim_tweens()
	var rising: bool = level > _claim_last_level
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
## it); the single disk stream needs the duck pushed explicitly.
func _apply_claim_duck() -> void:
	if _music_player == null or not _music_player.playing:
		return
	if config.contextual_music_enabled:
		_apply_playlist_volume()
	else:
		_music_player.volume_db = calm_stem_target_volume_db() + _claim_duck_db


func _start_claim_bed() -> void:
	if not _library.available():
		return
	var source: AudioStream = _library.stream(config.claim_tension_file)
	if source == null:
		_claim_stream_missing = true  # silent no-op: do not retry (and log) every step
		return
	_claim_player.stream = _looped_copy(source)
	_claim_player.play()
