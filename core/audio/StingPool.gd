class_name StingPool
extends RefCounted
## STUB (P7 plan section 2.2): null-object bodies, nothing wired; the filler package P7-Imusic implements it.
## Pure round-robin player slots and no-repeat variant picks for sound cues.


func _init(_sfx_count: int, _ui_count: int, _rng: RandomNumberGenerator) -> void:
	pass


func next_sfx_slot() -> int:
	return 0


func next_ui_slot() -> int:
	return 0


## Never the previous pick for `key` when count > 1.
func pick_variant(_key: int, _count: int) -> int:
	return 0
