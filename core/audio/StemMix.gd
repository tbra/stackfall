class_name StemMix
extends RefCounted
## STUB (plan P7 section 2.2, package P7-Sstem): signatures only, null-object bodies.
## Nothing calls this yet. P7-Istem fills in the pure adaptive two-stem rules moved
## out of Sfx.gd (calm/tense hysteresis on the claim progress, stem gain targets);
## Sfx keeps the players and tweens. Adaptive stems are kept (not deleted).

@warning_ignore("unused_parameter")
func _init(config: AudioConfig) -> void:
	pass


@warning_ignore("unused_parameter")
func on_progress(progress: float) -> bool:
	return false


func is_tense() -> bool:
	return false


func calm_db() -> float:
	return 0.0


func tense_db() -> float:
	return 0.0


func reset() -> void:
	pass
