class_name BlockBag
extends RefCounted
## The weighted "bag" randomizer (spec 2.4), replacing M1's SimpleBlockFeed.
##
## Spec 2.4: "Weights are set per shape in BlockFeedConfig. Use a 'bag'
## randomizer so no player goes long without getting a stabilizing shape."
##
## **Algorithm.** A bag holds round(weight * bag_multiplier) copies of each
## shape, at least one each, shuffled with a seeded RandomNumberGenerator.
## next() draws from the front; when the bag empties, a fresh one is built and
## shuffled. Before shuffling, the bag is checked against
## min_stabilizers_per_bag: if it holds fewer copies of the shapes named in
## stabilizer_ids than that, extra stabilizer copies are added until it does.
## That is the "no player goes long without a stabilizing shape" guarantee,
## and it is a property a unit test can assert over many bags.
##
## The seed is per player slot and comes from MatchConfig.rng_seed, so a
## replayed match with the same seed deals the same blocks. Pure logic: no
## scene tree (CLAUDE.md).

var _config: BlockFeedConfig = null
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _shapes: Array[BlockShape] = []

var _bag: Array[BlockShape] = []
var _bag_pos: int = 0
var _draw_count: int = 0

## A bag built ahead of time by peek() when it needs to look past the current
## bag's end, using a cloned RandomNumberGenerator so the real _rng (and thus
## every future draw) is untouched until next() actually commits to it. That
## is what makes peek() both non-consuming and exactly deterministic with the
## sequence next() would have produced anyway.
var _pending_bag: Array[BlockShape] = []
var _pending_rng_state: int = 0


func _init(config: BlockFeedConfig, rng_seed: int = -1) -> void:
	_config = config
	if rng_seed >= 0:
		_rng.seed = rng_seed
	else:
		_rng.randomize()
	_shapes = config.shapes if config.shapes.size() > 0 else BlockShape.load_all_shapes()


func config() -> BlockFeedConfig:
	return _config


## The shapes this bag deals from: BlockFeedConfig.shapes, or every shape
## under res://config/blocks/ via BlockShape.load_all_shapes() when that is
## empty.
func shapes() -> Array[BlockShape]:
	return _shapes


## Effective weight of a shape: the BlockFeedConfig override if there is one,
## otherwise BlockShape.weight. Never returns a non-positive number.
func weight_of(shape: BlockShape) -> float:
	if shape == null:
		return 0.0001
	var index: int = _shapes.find(shape)
	if index >= 0 and index < _config.weight_overrides.size():
		var override: float = _config.weight_overrides[index]
		if override > 0.0:
			return override
	return maxf(shape.weight, 0.0001)


## Draws the next shape, refilling the bag when it runs dry. Never null once
## the feed has at least one shape.
func next() -> BlockShape:
	if _shapes.is_empty():
		return null
	if _bag_pos >= _bag.size():
		if _pending_bag.size() > 0:
			_bag = _pending_bag
			_pending_bag = []
			_rng.state = _pending_rng_state
		else:
			_bag = _build_bag(_rng)
		_bag_pos = 0
	var shape: BlockShape = _bag[_bag_pos]
	_bag_pos += 1
	_draw_count += 1
	return shape


## The next `count` shapes without consuming them, for the HUD's next-block
## preview (spec 2.4: the next block, optionally the next 3). Peeking across a
## bag boundary refills first, so the preview never goes short.
func peek(count: int = 1) -> Array[BlockShape]:
	var result: Array[BlockShape] = []
	if _shapes.is_empty() or count <= 0:
		return result
	if _bag.is_empty():
		# Nothing drawn yet: build the first bag for real, same as next()
		# would, so peek() before any next() call still sees the right shapes.
		_bag = _build_bag(_rng)
		_bag_pos = 0
	var index: int = _bag_pos
	var source: Array[BlockShape] = _bag
	var used_pending: bool = false
	for _i: int in range(count):
		if index >= source.size():
			if not used_pending:
				_ensure_pending()
				source = _pending_bag
				index = 0
				used_pending = true
			if index >= source.size():
				break
		result.append(source[index])
		index += 1
	return result


## How many draws are left before the bag refills. Tests use it to line
## themselves up on a bag boundary.
func remaining() -> int:
	return maxi(_bag.size() - _bag_pos, 0)


## Total draws made so far, across all bags.
func draw_count() -> int:
	return _draw_count


func _ensure_pending() -> void:
	if _pending_bag.size() > 0 or _shapes.is_empty():
		return
	var clone: RandomNumberGenerator = RandomNumberGenerator.new()
	clone.state = _rng.state
	_pending_bag = _build_bag(clone)
	_pending_rng_state = clone.state


## Builds one shuffled bag: round(weight * bag_multiplier) copies of each
## shape (at least one), topped up with extra stabilizer copies until
## min_stabilizers_per_bag is met, then Fisher-Yates shuffled with `rng`. Pure
## function of `rng`'s state so it can be replayed identically from a cloned
## generator (see _ensure_pending).
func _build_bag(rng: RandomNumberGenerator) -> Array[BlockShape]:
	var counts: Dictionary = {}
	for shape: BlockShape in _shapes:
		var copies: int = maxi(1, int(round(weight_of(shape) * _config.bag_multiplier)))
		counts[shape] = copies

	var stabilizer_shapes: Array[BlockShape] = []
	for shape: BlockShape in _shapes:
		if _config.stabilizer_ids.has(shape.id):
			stabilizer_shapes.append(shape)
	if stabilizer_shapes.size() > 0:
		var stabilizer_total: int = 0
		for shape: BlockShape in stabilizer_shapes:
			stabilizer_total += int(counts[shape])
		var deficit: int = _config.min_stabilizers_per_bag - stabilizer_total
		var next_stabilizer: int = 0
		while deficit > 0:
			var shape: BlockShape = stabilizer_shapes[next_stabilizer % stabilizer_shapes.size()]
			counts[shape] = int(counts[shape]) + 1
			deficit -= 1
			next_stabilizer += 1

	var bag: Array[BlockShape] = []
	for shape: BlockShape in _shapes:
		for _i: int in range(int(counts[shape])):
			bag.append(shape)

	for i: int in range(bag.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: BlockShape = bag[i]
		bag[i] = bag[j]
		bag[j] = tmp
	return bag
