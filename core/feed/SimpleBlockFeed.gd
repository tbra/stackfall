class_name SimpleBlockFeed
extends RefCounted
## M1's placeholder feed: a plain random pick over the available BlockShape
## resources. Spec 2.4's weighted "bag" randomizer (so no player goes long
## without a stabilizing shape) is M2 scope; this just needs to hand out
## something for every placement. Pure logic, no scene tree, per CLAUDE.md.

var _shapes: Array[BlockShape] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(shapes: Array[BlockShape], rng_seed: int = -1) -> void:
	assert(shapes.size() > 0, "SimpleBlockFeed needs at least one BlockShape.")
	_shapes = shapes
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()


func next() -> BlockShape:
	return _shapes[_rng.randi_range(0, _shapes.size() - 1)]


func shape_count() -> int:
	return _shapes.size()
