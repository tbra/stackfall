class_name StemMix
extends RefCounted
## The adaptive two-stem rules (spec 1.10): which stem is up given the claim progress, and each
## stem's gain before Sfx adds the master/music settings offsets. Calm/tense hysteresis: the
## rising edge uses the plain threshold, the falling edge only fires music_tense_release_margin
## below it, so progress hovering at the threshold does not flap the crossfade. Sfx owns the
## players and tweens.

## Effectively-silent volume_db for the faded-out stem (AudioServer's -80 dB inaudible convention).
const MUTE_DB: float = -80.0

var _config: AudioConfig
var _tense: bool = false


func _init(config: AudioConfig) -> void:
	_config = config


## Feeds the claim progress; returns true when it flipped the calm/tense side.
func on_progress(progress: float) -> bool:
	var threshold: float = _config.music_tense_progress_threshold
	var want_tense: bool = progress >= (threshold - _config.music_tense_release_margin if _tense else threshold)
	if want_tense == _tense:
		return false
	_tense = want_tense
	return true


func calm_db() -> float:
	return MUTE_DB if _tense else _config.music_volume_db


func tense_db() -> float:
	return _config.music_volume_db if _tense else MUTE_DB


func reset() -> void:
	_tense = false
