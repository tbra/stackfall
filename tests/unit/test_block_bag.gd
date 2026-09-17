extends GutTest
## The weighted bag randomizer (spec 2.4): core/feed/BlockBag.gd.


func _config() -> BlockFeedConfig:
	var config: BlockFeedConfig = BlockFeedConfig.new()
	config.shapes = []  # empty -> every shape under res://config/blocks/
	config.weight_overrides = PackedFloat32Array()
	config.stabilizer_ids = [&"square4", &"slab6", &"cube"]
	config.min_stabilizers_per_bag = 2
	config.bag_multiplier = 2.0
	config.preview_count = 1
	return config


func test_deals_every_shape_under_config_blocks() -> void:
	var bag: BlockBag = BlockBag.new(_config(), 1)
	var seen: Dictionary = {}
	for _i: int in range(500):
		seen[bag.next().id] = true
	for shape: BlockShape in BlockShape.load_all_shapes():
		assert_true(seen.has(shape.id), "%s should show up in 500 draws." % shape.id)


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
		total_weight += bag.weight_of(shape)

	for shape: BlockShape in bag.shapes():
		var expected_fraction: float = bag.weight_of(shape) / total_weight
		var actual_fraction: float = float(counts.get(shape.id, 0)) / float(total_draws)
		assert_almost_eq(
			actual_fraction, expected_fraction, expected_fraction * 0.15 + 0.01,
			"%s drawn %.3f of the time, expected %.3f (+/-15%%)." % [shape.id, actual_fraction, expected_fraction]
		)


func test_every_bag_carries_the_minimum_stabilizers() -> void:
	var config: BlockFeedConfig = _config()
	var stabilizer_ids: Array[StringName] = config.stabilizer_ids
	var bag: BlockBag = BlockBag.new(config, 3)

	# Walk bag boundaries via remaining(): it counts down each draw and jumps
	# back up the moment a fresh bag is built, which is the boundary to check
	# the stabilizer count against. The very first draw always looks like a
	# "refill" (remaining() goes from 0, before any bag exists, up to a full
	# bag), so that one is skipped rather than checked as a completed bag.
	var stabilizers_in_bag: int = 0
	var bags_checked: int = 0
	var seen_first_bag: bool = false
	for _i: int in range(400):
		var before: int = bag.remaining()
		var shape: BlockShape = bag.next()
		if stabilizer_ids.has(shape.id):
			stabilizers_in_bag += 1
		if bag.remaining() > before:
			if seen_first_bag:
				# Refilled after this draw: the bag that just finished had at
				# least min_stabilizers_per_bag (spec 2.4).
				assert_gte(
					stabilizers_in_bag, config.min_stabilizers_per_bag,
					"A bag had only %d stabilizer(s)." % stabilizers_in_bag
				)
				bags_checked += 1
			seen_first_bag = true
			stabilizers_in_bag = 0
	assert_gt(bags_checked, 3, "Should have crossed several bag boundaries in 400 draws.")


func test_peek_never_goes_short_across_a_bag_boundary_and_does_not_consume() -> void:
	var bag: BlockBag = BlockBag.new(_config(), 11)
	# Force the first bag into existence, then drain it down to its last
	# shape. (remaining() reads 0 before any bag has ever been built, so the
	# drain condition alone would never run without this first draw.)
	bag.next()
	while bag.remaining() > 1:
		bag.next()

	var draw_count_before: int = bag.draw_count()
	var preview: Array[BlockShape] = bag.peek(3)
	assert_eq(preview.size(), 3, "peek(3) should return 3 shapes even across a bag boundary.")
	assert_eq(bag.draw_count(), draw_count_before, "peek() must not consume draws.")
	assert_eq(bag.remaining(), 1, "peek() must not touch the current bag's position.")

	# The real draws that follow must match exactly what was previewed.
	for expected: BlockShape in preview:
		assert_eq(bag.next(), expected)


func test_same_seed_deals_the_same_sequence() -> void:
	var bag_a: BlockBag = BlockBag.new(_config(), 1234)
	var bag_b: BlockBag = BlockBag.new(_config(), 1234)
	for _i: int in range(300):
		assert_eq(bag_a.next(), bag_b.next())


func test_same_seed_deals_the_same_sequence_even_with_interleaved_peeks() -> void:
	var bag_a: BlockBag = BlockBag.new(_config(), 99)
	var bag_b: BlockBag = BlockBag.new(_config(), 99)
	for i: int in range(200):
		if i % 5 == 0:
			bag_b.peek(3)  # should not perturb bag_b's real draw sequence
		assert_eq(bag_a.next(), bag_b.next())


func test_weight_of_uses_config_override_when_present() -> void:
	var config: BlockFeedConfig = _config()
	config.shapes = BlockShape.load_all_shapes()
	config.weight_overrides = PackedFloat32Array([5.0])
	var bag: BlockBag = BlockBag.new(config, 1)
	assert_almost_eq(bag.weight_of(config.shapes[0]), 5.0, 0.001)
	assert_almost_eq(bag.weight_of(config.shapes[1]), config.shapes[1].weight, 0.001)
