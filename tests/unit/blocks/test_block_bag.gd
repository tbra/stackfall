extends GutTest
## The weighted bag randomizer (spec 1.4): core/blocks/BlockBag.gd.


func _config() -> BlockFeedConfig:
	var config: BlockFeedConfig = BlockFeedConfig.new()
	config.shapes = []  # empty -> every shape under res://config/blocks/
	config.weight_overrides = PackedFloat32Array()
	config.stabilizer_ids = [&"square4", &"slab6", &"cube"]
	config.min_stabilizers_per_bag = 2
	config.bag_multiplier = 2.0
	return config


func test_deals_every_shape_under_config_blocks() -> void:
	var bag: BlockBag = BlockBag.new(_config(), 1)
	var seen: Dictionary = {}
	for _i: int in range(500):
		seen[bag.next().id] = true
	for shape: BlockShape in BlockShape.load_bag_shapes():
		assert_true(seen.has(shape.id), "%s should show up in 500 draws." % shape.id)


## Bag copies per shape: round(weight * multiplier), at least 1 (spec 1.4).
## The bag quantises weights, so rare shapes (e.g. cube8 0.25 -> 1 copy) land
## above their nominal share; compare against the quantised share.
func _copies(bag: BlockBag, shape: BlockShape, config: BlockFeedConfig) -> float:
	return float(maxi(1, int(round(bag.weight_of(shape) * config.bag_multiplier))))


func test_weights_hold_over_2000_draws() -> void:
	var config: BlockFeedConfig = _config()
	var bag: BlockBag = BlockBag.new(config, 7)
	var counts: Dictionary = {}
	var total_draws: int = 2000
	for _i: int in range(total_draws):
		var shape: BlockShape = bag.next()
		counts[shape.id] = counts.get(shape.id, 0) + 1

	var total_weight: float = 0.0
	for shape: BlockShape in bag.shapes():
		total_weight += _copies(bag, shape, config)

	for shape: BlockShape in bag.shapes():
		var expected_fraction: float = _copies(bag, shape, config) / total_weight
		var actual_fraction: float = float(counts.get(shape.id, 0)) / float(total_draws)
		assert_almost_eq(
			actual_fraction, expected_fraction, expected_fraction * 0.15 + 0.01,
			"%s drawn %.3f of the time, expected %.3f (+/-15%%)." % [shape.id, actual_fraction, expected_fraction]
		)


## Cards in one bag: the quantised copies of every shape, plus the stabilizer
## top-up that reaches min_stabilizers_per_bag.
func _bag_size(bag: BlockBag, config: BlockFeedConfig) -> int:
	var total: int = 0
	var stabilizers: int = 0
	for shape: BlockShape in bag.shapes():
		var copies: int = int(_copies(bag, shape, config))
		total += copies
		if config.stabilizer_ids.has(shape.id):
			stabilizers += copies
	return total + maxi(config.min_stabilizers_per_bag - stabilizers, 0)


func test_every_bag_carries_the_minimum_stabilizers() -> void:
	var config: BlockFeedConfig = _config()
	var bag: BlockBag = BlockBag.new(config, 3)
	var bag_size: int = _bag_size(bag, config)
	var bags_checked: int = 0
	for _bag_index: int in range(8):
		var stabilizers_in_bag: int = 0
		for _i: int in range(bag_size):
			if config.stabilizer_ids.has(bag.next().id):
				stabilizers_in_bag += 1
		# spec 1.4: a finished bag had at least min_stabilizers_per_bag.
		assert_gte(
			stabilizers_in_bag, config.min_stabilizers_per_bag,
			"A bag had only %d stabilizer(s)." % stabilizers_in_bag
		)
		bags_checked += 1
	assert_eq(bags_checked, 8, "Should have crossed several bag boundaries.")


func test_peek_never_goes_short_across_a_bag_boundary_and_does_not_consume() -> void:
	var config: BlockFeedConfig = _config()
	var bag: BlockBag = BlockBag.new(config, 11)
	# Drain the first bag down to its last shape.
	for _i: int in range(_bag_size(bag, config) - 1):
		bag.next()

	var preview: Array[BlockShape] = bag.peek(3)
	assert_eq(preview.size(), 3, "peek(3) should return 3 shapes even across a bag boundary.")
	assert_eq(bag.peek(3), preview, "peek() must not consume draws.")

	# The real draws that follow must match exactly what was previewed.
	for expected: BlockShape in preview:
		assert_eq(bag.next(), expected)


func test_same_seed_deals_the_same_sequence() -> void:
	var bag_a: BlockBag = BlockBag.new(_config(), 1234)
	var bag_b: BlockBag = BlockBag.new(_config(), 1234)
	for _i: int in range(300):
		assert_eq(bag_a.next(), bag_b.next())


