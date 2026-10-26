class_name MusicPlaylist
extends RefCounted
## STUB (P7 plan section 2.2): null-object bodies, nothing wired; the filler package P7-Imusic implements it.
## Pure music-track scheduler: which track plays next, gaps and fades.

enum Phase { STOPPED, WAITING, PLAYING, SWITCHING }
## What Sfx must do with its player after advance().
enum Step { NONE, START_TRACK, STOP_PLAYER }


func _init(_config: AudioConfig, _rng: RandomNumberGenerator) -> void:
	pass


## menu, lobby or gameplay; others are ignored.
func set_context(_context: StringName) -> void:
	pass


func advance(_delta: float, _playback_position: float, _track_length: float) -> Step:
	return Step.NONE


## Index chosen for the current context (-1: none); never an immediate repeat.
func next_track() -> int:
	return -1


func track_started(_index: int) -> void:
	pass


## Draws the gap before the next track.
func track_finished() -> void:
	pass


func envelope() -> float:
	return 0.0


func phase() -> Phase:
	return Phase.STOPPED


func context() -> StringName:
	return &""


func release() -> void:
	pass
