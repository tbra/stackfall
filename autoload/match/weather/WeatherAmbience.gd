class_name WeatherAmbience
extends Node
## Weather ambience and gust whoosh (Bontago-mp0.118). Client-side cosmetic on
## every peer, driven only by Events (the replicated weather state and the
## replicated Breeze gust signal); it owns no physics and no authority.
##
## Each active weather's looping bed (WeatherTuning.ambience_loop) has its own
## player. The bed's target gain is the ramped weather intensity; the live gain
## slews toward it over WeatherAudioTuning.crossfade_s, so a weather change
## crosses over, a new match fades in, and match end / return to menu fades out.
## A bed whose gain reaches silence stops. Volume adds the Master and SFX
## sliders exactly as autoload/Sfx.gd does (the project has no AudioServer
## bus layout, only plain AudioStreamPlayers).
##
## DECISION (WeatherAmbience): no new bus; the ambience counts as SFX for the
## slider. While the pause menu is open it is ducked, not stopped.
## DECISION (Bontago-1pi.77): superseded -- weather has its own Settings
## channel (Weather slider, Master still applies, SFX no longer does). The
## project has no AudioServer bus layout, so "bus" here is the Settings channel.
## DECISION (WeatherAmbience): WAV loops are not looping on import, so the
## runtime duplicates each stream and sets forward looping over its full length.

var tuning: WeatherAudioTuning = preload("res://config/weather_audio.tres")

var _defs: Dictionary = {}
var _beds: Dictionary = {}
var _gust_streams: Array[AudioStreamWAV] = []
var _gust_players: Array[AudioStreamPlayer] = []
var _gust_next: int = 0
var _paused_duck: bool = false
var gusts_played: int = 0
var last_gust_stream: AudioStreamWAV = null


func _ready() -> void:
	for def: WeatherTuning in WeatherTuning.load_all():
		_defs[def.id] = def
	_load_gusts()
	Events.weather_started.connect(_on_started)
	Events.weather_stopped.connect(_on_stopped)
	Events.weather_intensity_changed.connect(_on_intensity_changed)
	Events.match_scope_reset.connect(fade_all_out)
	Events.breeze_gust_started.connect(_on_gust)
	Events.pause_menu_opened.connect(_on_pause_changed.bind(true))
	Events.pause_menu_closed.connect(_on_pause_changed.bind(false))
	Settings.audio_settings_changed.connect(_refresh_volumes)


## Quit-time release (Bontago-fca.49): stop beds and gust voices, drop streams.
func _exit_tree() -> void:
	release_audio()


func release_audio() -> void:
	for weather_id: StringName in _beds.keys():
		var player: AudioStreamPlayer = (_beds[weather_id] as Dictionary)["player"] as AudioStreamPlayer
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	for player: AudioStreamPlayer in _gust_players:
		if is_instance_valid(player):
			player.stop()
			player.stream = null
	_gust_streams.clear()
	last_gust_stream = null


func _process(delta: float) -> void:
	advance(delta)


## Test seam: replace the registry.
func set_defs(defs: Array[WeatherTuning]) -> void:
	_defs.clear()
	for def: WeatherTuning in defs:
		_defs[def.id] = def


## Moves every bed's gain toward its target and stops silent ones.
func advance(delta: float) -> void:
	var step: float = delta / maxf(tuning.crossfade_s, 0.001)
	for weather_id: StringName in _beds.keys():
		var bed: Dictionary = _beds[weather_id]
		var gain: float = move_toward(float(bed["gain"]), float(bed["target"]), step)
		bed["gain"] = gain
		var player: AudioStreamPlayer = bed["player"] as AudioStreamPlayer
		if gain <= tuning.silent_gain and float(bed["target"]) <= 0.0:
			bed["gain"] = 0.0
			if player.playing:
				player.stop()
			continue
		player.volume_db = _bed_volume_db(weather_id, gain)


func bed_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for weather_id: StringName in _beds.keys():
		ids.append(weather_id)
	return ids


func is_bed_playing(weather_id: StringName) -> bool:
	return _beds.has(weather_id) and (_beds[weather_id]["player"] as AudioStreamPlayer).playing


func bed_gain(weather_id: StringName) -> float:
	return float(_beds[weather_id]["gain"]) if _beds.has(weather_id) else 0.0


func bed_target(weather_id: StringName) -> float:
	return float(_beds[weather_id]["target"]) if _beds.has(weather_id) else 0.0


func bed_player(weather_id: StringName) -> AudioStreamPlayer:
	return (_beds[weather_id]["player"] as AudioStreamPlayer) if _beds.has(weather_id) else null


func gust_stream_count() -> int:
	return _gust_streams.size()


## Linear amplitude 0..1 the bed should reach at `intensity`.
static func target_gain(intensity: float) -> float:
	return clampf(intensity, 0.0, 1.0)


## Looping copy of a WAV: forward loop over its whole length. Null when the
## path is not a WAV.
static func make_loop(path: String) -> AudioStreamWAV:
	var source: AudioStreamWAV = load(path) as AudioStreamWAV
	if source == null:
		return null
	var looped: AudioStreamWAV = source.duplicate() as AudioStreamWAV
	# Frame count from the length, not the byte size: the import compresses to QOA.
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	looped.loop_begin = 0
	looped.loop_end = int(round(looped.get_length() * float(looped.mix_rate)))
	return looped


func fade_all_out() -> void:
	for weather_id: StringName in _beds.keys():
		_beds[weather_id]["target"] = 0.0


## Immediately silence everything (session teardown).
func stop_all_now() -> void:
	for weather_id: StringName in _beds.keys():
		var bed: Dictionary = _beds[weather_id]
		bed["target"] = 0.0
		bed["gain"] = 0.0
		(bed["player"] as AudioStreamPlayer).stop()


func _on_started(weather_id: StringName) -> void:
	var bed: Dictionary = _bed_for(weather_id)
	if bed.is_empty():
		return
	bed["target"] = 0.0
	var player: AudioStreamPlayer = bed["player"] as AudioStreamPlayer
	if not player.playing:
		bed["gain"] = 0.0
		player.volume_db = _bed_volume_db(weather_id, 0.0)
		player.play()


func _on_stopped(weather_id: StringName) -> void:
	if _beds.has(weather_id):
		_beds[weather_id]["target"] = 0.0


func _on_intensity_changed(weather_id: StringName, intensity: float) -> void:
	var bed: Dictionary = _bed_for(weather_id)
	if bed.is_empty():
		return
	bed["target"] = target_gain(intensity)
	var player: AudioStreamPlayer = bed["player"] as AudioStreamPlayer
	if float(bed["target"]) > 0.0 and not player.playing:
		player.volume_db = _bed_volume_db(weather_id, float(bed["gain"]))
		player.play()


## The bed record for `weather_id`, created on first use; empty when that
## weather has no loop (fog, ceiling) or the stream will not load.
func _bed_for(weather_id: StringName) -> Dictionary:
	if _beds.has(weather_id):
		return _beds[weather_id]
	var def: WeatherTuning = _defs.get(weather_id) as WeatherTuning
	if def == null or def.ambience_loop == "":
		return {}
	var stream: AudioStreamWAV = make_loop(def.ambience_loop)
	if stream == null:
		return {}
	var player: AudioStreamPlayer = AudioStreamPlayer.new()
	player.name = "Bed_" + String(weather_id)
	player.stream = stream
	add_child(player)
	var bed: Dictionary = {"player": player, "gain": 0.0, "target": 0.0}
	_beds[weather_id] = bed
	return bed


func _bed_volume_db(weather_id: StringName, gain: float) -> float:
	var def: WeatherTuning = _defs.get(weather_id) as WeatherTuning
	var base_db: float = def.ambience_volume_db if def != null else 0.0
	return base_db + _mix_db() + linear_to_db(maxf(gain, tuning.silent_gain))


func _mix_db() -> float:
	var db: float = Settings.master_volume_db() + Settings.weather_volume_db()
	return db + (tuning.pause_duck_db if _paused_duck else 0.0)


func _refresh_volumes() -> void:
	for weather_id: StringName in _beds.keys():
		var bed: Dictionary = _beds[weather_id]
		(bed["player"] as AudioStreamPlayer).volume_db = _bed_volume_db(weather_id, float(bed["gain"]))


func _on_pause_changed(paused: bool) -> void:
	_paused_duck = paused
	_refresh_volumes()


func _load_gusts() -> void:
	_gust_streams.clear()
	for path: String in tuning.gust_streams:
		var stream: AudioStreamWAV = load(path) as AudioStreamWAV
		if stream != null:
			_gust_streams.append(stream)
	_gust_streams.sort_custom(func(a: AudioStreamWAV, b: AudioStreamWAV) -> bool: return a.get_length() < b.get_length())
	for i: int in tuning.gust_voices:
		var player: AudioStreamPlayer = AudioStreamPlayer.new()
		player.name = "Gust%d" % i
		add_child(player)
		_gust_players.append(player)


## Picks the whoosh whose length is closest to the gust's duration "d".
func gust_stream_for(duration_s: float) -> AudioStreamWAV:
	var best: AudioStreamWAV = null
	var best_gap: float = INF
	for stream: AudioStreamWAV in _gust_streams:
		var gap: float = absf(stream.get_length() - duration_s)
		if gap < best_gap:
			best_gap = gap
			best = stream
	return best


func _on_gust(gust: Dictionary) -> void:
	if _gust_players.is_empty():
		return
	var stream: AudioStreamWAV = gust_stream_for(float(gust.get("d", 0.0)))
	if stream == null:
		return
	var player: AudioStreamPlayer = _gust_players[_gust_next]
	_gust_next = (_gust_next + 1) % _gust_players.size()
	player.stream = stream
	player.volume_db = tuning.gust_volume_db + _mix_db()
	player.play()
	gusts_played += 1
	last_gust_stream = stream
