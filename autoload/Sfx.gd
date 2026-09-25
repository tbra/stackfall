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
## exception -- UI button press/hover has no Events signal of its own and
## isn't gameplay, so those two files call Sfx.play() straight from their
## button handlers.
##
## No class_name: this is the Sfx autoload singleton (same reason Events,
## Settings, Net and Match have none -- see autoload/Net.gd's header).

const AUDIO_SUBDIR: String = "assets/original/audio"

@export var config: AudioConfig = preload("res://config/audio_config.tres")

var _root_dir: String = ""
var _available: bool = false
var _streams_by_filename: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _next_sfx_player_index: int = 0
var _music_player: AudioStreamPlayer
var _music_enabled: bool = true
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	Block.impact_speed_min = config.impact_speed_min
	Block.impacts_enabled = config.impacts_enabled
	_root_dir = _resolve_root_dir()
	_available = DirAccess.dir_exists_absolute(_root_dir)
	if not _available:
		print(
			"Sfx: no original assets at %s -- run tools/install_original_assets.ps1 (optional; the game runs silently without it)."
			% _root_dir
		)
	_build_player_pool()
	Events.block_impacted.connect(_on_block_impacted)
	Events.placement_rejected.connect(_on_placement_rejected)
	Events.block_placed.connect(_on_block_placed)
	Events.player_eliminated.connect(_on_player_eliminated)
	Events.gift_claimed.connect(_on_gift_claimed)
	play_music()


func _resolve_root_dir() -> String:
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + AUDIO_SUBDIR)
	return OS.get_executable_path().get_base_dir().path_join(AUDIO_SUBDIR)


func _build_player_pool() -> void:
	for _i: int in range(config.max_simultaneous):
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(player)
		_sfx_players.append(player)
	_music_player = AudioStreamPlayer.new()
	add_child(_music_player)


## Plays one of `event`'s configured files on a pooled AudioStreamPlayer (or
## the music player for AudioConfig.EVENT_MUSIC). Returns whether anything
## actually played -- false with no assets installed, an unknown event, or a
## missing file.
func play(event: StringName) -> bool:
	var stream: AudioStream = _pick_stream(event)
	if stream == null:
		return false
	if event == AudioConfig.EVENT_MUSIC:
		_play_music_stream(stream)
		return true
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db
	player.play()
	return true


## Positional variant of play(). DECISION (autoload/Sfx.gd): 3D/spatial audio
## isn't required yet (brief: "3D not required now -- 2D/global players are
## fine"), so this ignores `position` and behaves exactly like play(); the
## parameter stays so callers don't need to change when spatial audio lands.
func play_at(event: StringName, _position: Vector3) -> bool:
	return play(event)


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		_music_player.stop()
	elif not _music_player.playing:
		play_music()


func play_music() -> void:
	if not _music_enabled:
		return
	var stream: AudioStream = _pick_stream(AudioConfig.EVENT_MUSIC)
	if stream != null:
		_play_music_stream(stream)


func _play_music_stream(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_player.stream = stream
	_music_player.volume_db = config.music_volume_db
	_music_player.play()


func _pick_stream(event: StringName) -> AudioStream:
	if not _available:
		return null
	var files: Array[String] = config.files_for_event(event)
	if files.is_empty():
		return null
	var filename: String = files[0] if files.size() == 1 else files[_rng.randi_range(0, files.size() - 1)]
	return _load_stream(filename)


func _load_stream(filename: String) -> AudioStream:
	var key: String = filename.to_lower()
	if _streams_by_filename.has(key):
		return _streams_by_filename[key]
	var full_path: String = _root_dir.path_join(key)
	if not FileAccess.file_exists(full_path):
		print("Sfx: expected file missing: %s" % full_path)
		return null
	var stream: AudioStream = null
	if key.ends_with(".wav"):
		stream = AudioStreamWAV.load_from_file(full_path)
	elif key.ends_with(".mp3"):
		stream = AudioStreamMP3.load_from_file(full_path)
	if stream != null:
		_streams_by_filename[key] = stream
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


# --- Events hooks -------------------------------------------------------------

func _on_block_impacted(speed: float) -> void:
	if speed < config.impact_speed_min:
		return
	var stream: AudioStream = _pick_stream(AudioConfig.EVENT_THUD)
	if stream == null:
		return
	var player: AudioStreamPlayer = _next_sfx_player()
	player.stream = stream
	player.volume_db = config.sfx_volume_db + config.impact_volume_db(speed)
	player.play()


func _on_placement_rejected(_slot_id: int, _reason: StringName) -> void:
	play(AudioConfig.EVENT_REJECTED)


func _on_block_placed(_block: RigidBody3D, _shape_id: StringName) -> void:
	play(AudioConfig.EVENT_DROP)


func _on_player_eliminated(_slot_id: int, _team_id: int) -> void:
	play(AudioConfig.EVENT_BREAKAGE)


## DECISION (autoload/Sfx.gd, Bontago-6y2): unlike the hooks above (a block
## drop/thud/rejection/breakage is a physical event any nearby player would
## actually hear happen, so every hook above plays for every slot, no
## gating), a gift claim queues a special for exactly one slot -- it is
## personal feedback, not a world event. Gating on Net.is_local_slot()
## mirrors game/GiftCrate.gd's own "_local_watch_slot()" comment and
## ui/HUD.gd's gift toast (Bontago-1en.16), both already local-only; a
## global "someone somewhere claimed a gift" chime would be noise in an
## 8-player match with crates spawning continuously. Net.is_local_slot() is
## also correct in hot-seat/offline play with no extra branching: it always
## returns true there (one human drives every slot), so every claim plays,
## same as it would if the local human just made it.
##
## Simplest reasonable option per the brief: no quieter variant for other
## slots' claims -- nothing else about a gift claim has non-local feedback
## either, so this just stays silent for them rather than inventing a new
## tunable with no other precedent to match.
func _on_gift_claimed(_gift_id: int, slot_id: int, _special_id: StringName) -> void:
	if not Net.is_local_slot(slot_id):
		return
	play(AudioConfig.EVENT_GIFT_CLAIMED)
