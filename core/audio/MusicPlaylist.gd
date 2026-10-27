class_name MusicPlaylist
extends RefCounted
## Pure music-track scheduler: which track plays next, gaps and fades. Sfx owns the players and
## streams and acts on the Step that advance() returns.

enum Phase { STOPPED, WAITING, PLAYING, SWITCHING }
## What Sfx must do with its player after advance().
enum Step { NONE, START_TRACK, STOP_PLAYER }

const CONTEXTS: Array[StringName] = [&"menu", &"lobby", &"gameplay"]
const NO_TRACK: int = -1

var _config: AudioConfig
var _rng: RandomNumberGenerator
var _phase: Phase = Phase.STOPPED
var _context: StringName = &"menu"
var _wait_remaining: float = 0.0
var _age: float = 0.0
var _envelope: float = 0.0
var _switch_start_envelope: float = 0.0
var _switch_elapsed: float = 0.0
var _last_track_by_context: Dictionary[StringName, int] = {}
## The pick for the next start, kept so a prefetch and the start agree.
var _next_context: StringName = &""
var _next_index: int = NO_TRACK


func _init(config: AudioConfig, rng: RandomNumberGenerator) -> void:
	_config = config
	_rng = rng


## Leaves STOPPED for the initial delay; a running or waiting playlist is untouched.
func start() -> void:
	if _phase == Phase.STOPPED:
		_schedule(_config.music_initial_delay_seconds)


## menu, lobby or gameplay; others are ignored.
func set_context(context: StringName) -> void:
	if context not in CONTEXTS or context == _context:
		return
	_context = context
	if _phase == Phase.PLAYING:
		_phase = Phase.SWITCHING
		_switch_start_envelope = _envelope
		_switch_elapsed = 0.0
	elif _phase != Phase.SWITCHING:
		_schedule(_config.music_initial_delay_seconds)


func advance(delta: float, playback_position: float, track_length: float) -> Step:
	match _phase:
		Phase.WAITING:
			_wait_remaining -= delta
			if _wait_remaining <= 0.0:
				if next_track() == NO_TRACK:
					_phase = Phase.STOPPED
					return Step.NONE
				return Step.START_TRACK
		Phase.PLAYING:
			_age = playback_position if playback_position >= 0.0 else _age + delta
			var fade_in: float = 1.0 if _config.music_fade_in_seconds <= 0.0 else clampf(_age / _config.music_fade_in_seconds, 0.0, 1.0)
			var fade_out: float = 1.0 if _config.music_fade_out_seconds <= 0.0 else clampf((track_length - _age) / _config.music_fade_out_seconds, 0.0, 1.0)
			_envelope = minf(fade_in, fade_out)
		Phase.SWITCHING:
			_switch_elapsed += delta
			var fraction: float = 1.0 if _config.music_fade_out_seconds <= 0.0 else clampf(_switch_elapsed / _config.music_fade_out_seconds, 0.0, 1.0)
			_envelope = _switch_start_envelope * (1.0 - fraction)
			if fraction >= 1.0:
				_schedule(_config.music_initial_delay_seconds)
				return Step.STOP_PLAYER
	return Step.NONE


## Index chosen for the current context (-1: none); never an immediate repeat.
func next_track() -> int:
	if _next_context != _context or _next_index == NO_TRACK:
		_next_context = _context
		_next_index = _choose_index()
	return _next_index


## The track at `index` of the current context is playing (it may differ from next_track()
## when that one failed to load).
func track_started(index: int) -> void:
	_last_track_by_context[_context] = index
	_next_context = &""
	_next_index = NO_TRACK
	_age = 0.0
	_envelope = 0.0 if _config.music_fade_in_seconds > 0.0 else 1.0
	_phase = Phase.PLAYING


## Draws the gap before the next track.
func track_finished() -> void:
	_envelope = 0.0
	if _phase == Phase.SWITCHING:
		_schedule(_config.music_initial_delay_seconds)
	elif _phase == Phase.PLAYING:
		var minimum: float = maxf(_config.music_gap_min_seconds, 0.0)
		_schedule(_rng.randf_range(minimum, maxf(minimum, _config.music_gap_max_seconds)))


func envelope() -> float:
	return _envelope


func phase() -> Phase:
	return _phase


func context() -> StringName:
	return _context


func release() -> void:
	_phase = Phase.STOPPED
	_next_context = &""
	_next_index = NO_TRACK


func _schedule(delay: float) -> void:
	_wait_remaining = maxf(delay, 0.0)
	_phase = Phase.WAITING


func _choose_index() -> int:
	var count: int = _config.playlist_track_count(_context)
	var streams: Array[AudioStream] = _config.playlist_for_context(_context)
	var previous: int = _last_track_by_context.get(_context, NO_TRACK)
	var choices: Array[int] = []
	for index: int in range(count):
		if (streams.is_empty() or streams[index] != null) and (index != previous or count == 1):
			choices.append(index)
	if choices.is_empty():
		# Also tolerate a playlist with null entries and only one usable track.
		if previous >= 0 and previous < count and (streams.is_empty() or streams[previous] != null):
			return previous
		return NO_TRACK
	return choices[_rng.randi_range(0, choices.size() - 1)]
