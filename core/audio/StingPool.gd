class_name StingPool
extends RefCounted
## Pure round-robin player slots and no-repeat variant picks for sound cues.

var _sfx_count: int
var _ui_count: int
var _rng: RandomNumberGenerator
var _next_sfx: int = 0
var _next_ui: int = 0
## key -> last variant index picked for it.
var _last_variant: Dictionary[int, int] = {}


func _init(sfx_count: int, ui_count: int, rng: RandomNumberGenerator) -> void:
	_sfx_count = sfx_count
	_ui_count = ui_count
	_rng = rng


func next_sfx_slot() -> int:
	var slot: int = _next_sfx
	_next_sfx = (_next_sfx + 1) % _sfx_count
	return slot


func next_ui_slot() -> int:
	var slot: int = _next_ui
	_next_ui = (_next_ui + 1) % _ui_count
	return slot


## Never the previous pick for `key` when count > 1.
func pick_variant(key: int, count: int) -> int:
	if count <= 1:
		return 0
	var index: int = _rng.randi_range(0, count - 2)
	if index >= _last_variant.get(key, -1):
		index += 1
	_last_variant[key] = index
	return index
