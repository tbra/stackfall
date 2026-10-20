extends GutTest
## BlockBag (spec 1.4) from the outside: what weight_of() reports, exactly what
## one bag holds (copies per shape and the stabilizer top-up), and that peek()
## previews the same sequence next() deals without disturbing it.

const FALLBACK_WEIGHT: float = 0.0001


func _shape(id: StringName, weight: float = 1.0) -> BlockShape:
	var shape: BlockShape = BlockShape.new()
	shape.id = id
	shape.weight = weight
	return shape


## Shapes a, b, c, d with the given weights; multiplier 1.0 so a weight of n
## means n copies per bag.
func _config(
	shapes: Array[BlockShape], stabilizers: Array[StringName], min_stabilizers: int
) -> BlockFeedConfig:
	var config: BlockFeedConfig = BlockFeedConfig.new()
	config.shapes = shapes
	config.weight_overrides = PackedFloat32Array()
	config.stabilizer_ids = stabilizers
	config.min_stabilizers_per_bag = min_stabilizers
	config.bag_multiplier = 1.0
	return config


## Draws `count` shapes and tallies them by id.
func _tally(bag: BlockBag, count: int) -> Dictionary:
	var tally: Dictionary = {}
	for _i: int in range(count):
		var id: StringName = bag.next().id
		tally[id] = int(tally.get(id, 0)) + 1
	return tally


func _draw(bag: BlockBag, count: int) -> Array[BlockShape]:
	var drawn: Array[BlockShape] = []
	for _i: int in range(count):
		drawn.append(bag.next())
	return drawn


# --- weight_of ---------------------------------------------------------------


func test_weight_of_is_the_shape_weight_without_an_override() -> void:
	var a: BlockShape = _shape(&"a", 2.5)
	var bag: BlockBag = BlockBag.new(_config([a], [], 0), 1)
	assert_eq(bag.weight_of(a), 2.5)


func test_weight_of_a_null_shape_is_the_tiny_positive_fallback() -> void:
	var bag: BlockBag = BlockBag.new(_config([_shape(&"a", 2.5)], [], 0), 1)
	assert_eq(bag.weight_of(null), FALLBACK_WEIGHT)


func test_weight_of_a_non_positive_shape_weight_is_clamped_positive() -> void:
	var zero: BlockShape = _shape(&"zero", 0.0)
	var negative: BlockShape = _shape(&"negative", -3.0)
	var bag: BlockBag = BlockBag.new(_config([zero, negative], [], 0), 1)
	assert_eq(bag.weight_of(zero), FALLBACK_WEIGHT)
	assert_eq(bag.weight_of(negative), FALLBACK_WEIGHT)


func test_weight_override_replaces_the_shape_weight() -> void:
	var a: BlockShape = _shape(&"a", 1.0)
	var b: BlockShape = _shape(&"b", 1.0)
	var config: BlockFeedConfig = _config([a, b], [], 0)
	config.weight_overrides = PackedFloat32Array([4.0, 0.5])
	var bag: BlockBag = BlockBag.new(config, 1)
	assert_eq(bag.weight_of(a), 4.0)
	assert_eq(bag.weight_of(b), 0.5)


func test_zero_or_negative_override_falls_back_to_the_shape_weight() -> void:
	var a: BlockShape = _shape(&"a", 3.0)
	var b: BlockShape = _shape(&"b", 5.0)
	var config: BlockFeedConfig = _config([a, b], [], 0)
	config.weight_overrides = PackedFloat32Array([0.0, -2.0])
	var bag: BlockBag = BlockBag.new(config, 1)
	assert_eq(bag.weight_of(a), 3.0, "An override of 0 means no override.")
	assert_eq(bag.weight_of(b), 5.0, "A negative override means no override.")


func test_shapes_past_a_short_override_list_keep_their_own_weight() -> void:
	var a: BlockShape = _shape(&"a", 1.0)
	var b: BlockShape = _shape(&"b", 7.0)
	var config: BlockFeedConfig = _config([a, b], [], 0)
	config.weight_overrides = PackedFloat32Array([2.0])
	var bag: BlockBag = BlockBag.new(config, 1)
	assert_eq(bag.weight_of(a), 2.0)
	assert_eq(bag.weight_of(b), 7.0)


func test_weight_of_a_shape_outside_the_bag_ignores_overrides() -> void:
	var a: BlockShape = _shape(&"a", 1.0)
	var stranger: BlockShape = _shape(&"stranger", 9.0)
	var config: BlockFeedConfig = _config([a], [], 0)
	config.weight_overrides = PackedFloat32Array([4.0])
	var bag: BlockBag = BlockBag.new(config, 1)
	assert_eq(bag.weight_of(stranger), 9.0)


# --- bag composition ---------------------------------------------------------


func test_a_bag_holds_round_weight_times_multiplier_copies_of_each_shape() -> void:
	var a: BlockShape = _shape(&"a", 3.0)
	var b: BlockShape = _shape(&"b", 1.0)
	var c: BlockShape = _shape(&"c", 0.2)  # rounds to 0, but every shape gets one.
	var config: BlockFeedConfig = _config([a, b, c], [], 0)
	config.bag_multiplier = 1.5  # 4.5 -> 5 (round half away from zero), 1.5 -> 2, 0.3 -> 0 -> 1
	var bag: BlockBag = BlockBag.new(config, 5)
	for bag_index: int in range(3):
		var tally: Dictionary = _tally(bag, 8)
		assert_eq(tally.get(&"a", 0), 5, "bag %d: copies of a" % bag_index)
		assert_eq(tally.get(&"b", 0), 2, "bag %d: copies of b" % bag_index)
		assert_eq(tally.get(&"c", 0), 1, "bag %d: copies of c" % bag_index)


func test_weight_overrides_set_the_copies_in_a_bag() -> void:
	var a: BlockShape = _shape(&"a", 1.0)
	var b: BlockShape = _shape(&"b", 1.0)
	var config: BlockFeedConfig = _config([a, b], [], 0)
	config.weight_overrides = PackedFloat32Array([3.0, 0.0])
	var tally: Dictionary = _tally(BlockBag.new(config, 5), 4)
	assert_eq(tally.get(&"a", 0), 3)
	assert_eq(tally.get(&"b", 0), 1, "An override of 0 leaves the shape's own weight.")


func test_stabilizer_top_up_adds_exactly_the_missing_copies() -> void:
	var a: BlockShape = _shape(&"a")
	var b: BlockShape = _shape(&"b")
	var c: BlockShape = _shape(&"c")
	# a and b are stabilizers with 1 copy each; the minimum of 5 is 3 short.
	var bag: BlockBag = BlockBag.new(_config([a, b, c], [&"a", &"b"], 5), 2)
	for bag_index: int in range(3):
		var tally: Dictionary = _tally(bag, 6)
		assert_eq(
			int(tally.get(&"a", 0)) + int(tally.get(&"b", 0)), 5,
			"bag %d: exactly the minimum of stabilizers" % bag_index
		)
		assert_eq(tally.get(&"c", 0), 1, "bag %d: a non-stabilizer is never topped up" % bag_index)


func test_stabilizer_top_up_is_shared_round_robin_starting_with_the_first_shape() -> void:
	var a: BlockShape = _shape(&"a")
	var b: BlockShape = _shape(&"b")
	var c: BlockShape = _shape(&"c")
	var bag: BlockBag = BlockBag.new(_config([a, b, c], [&"a", &"b"], 5), 2)
	var tally: Dictionary = _tally(bag, 6)
	assert_eq(tally.get(&"a", 0), 3, "3 missing copies go a, b, a.")
	assert_eq(tally.get(&"b", 0), 2)


func test_a_single_stabilizer_shape_is_topped_up_to_the_minimum() -> void:
	var a: BlockShape = _shape(&"a")
	var b: BlockShape = _shape(&"b")
	var bag: BlockBag = BlockBag.new(_config([a, b], [&"a"], 4), 9)
	for bag_index: int in range(3):
		var tally: Dictionary = _tally(bag, 5)
		assert_eq(tally.get(&"a", 0), 4, "bag %d: copies of the only stabilizer" % bag_index)
		assert_eq(tally.get(&"b", 0), 1, "bag %d" % bag_index)


func test_no_top_up_when_the_stabilizers_already_meet_the_minimum() -> void:
	var a: BlockShape = _shape(&"a", 2.0)
	var b: BlockShape = _shape(&"b", 2.0)
	var c: BlockShape = _shape(&"c")
	# Natural stabilizer copies are 4 = the minimum exactly, so nothing is added.
	var bag: BlockBag = BlockBag.new(_config([a, b, c], [&"a", &"b"], 4), 4)
	for bag_index: int in range(3):
		var tally: Dictionary = _tally(bag, 5)
		assert_eq(tally.get(&"a", 0), 2, "bag %d" % bag_index)
		assert_eq(tally.get(&"b", 0), 2, "bag %d" % bag_index)
		assert_eq(tally.get(&"c", 0), 1, "bag %d" % bag_index)


func test_stabilizer_ids_naming_no_shape_in_the_feed_add_nothing() -> void:
	var a: BlockShape = _shape(&"a")
	var b: BlockShape = _shape(&"b")
	var tally: Dictionary = _tally(BlockBag.new(_config([a, b], [&"missing"], 6), 3), 2)
	assert_eq(tally.get(&"a", 0), 1)
	assert_eq(tally.get(&"b", 0), 1)


# --- peek --------------------------------------------------------------------


func test_peek_defaults_to_the_single_next_shape() -> void:
	var bag: BlockBag = BlockBag.new(_config([_shape(&"a"), _shape(&"b"), _shape(&"c")], [], 0), 8)
	var preview: Array[BlockShape] = bag.peek()
	assert_eq(preview.size(), 1)
	assert_eq(preview[0], bag.next())


func test_peek_with_nothing_requested_is_empty() -> void:
	var bag: BlockBag = BlockBag.new(_config([_shape(&"a")], [], 0), 8)
	assert_eq(bag.peek(0).size(), 0)
	assert_eq(bag.peek(-2).size(), 0)


func test_peek_before_any_draw_previews_the_first_shapes_dealt() -> void:
	var shapes: Array[BlockShape] = [_shape(&"a"), _shape(&"b"), _shape(&"c"), _shape(&"d")]
	var peeked: BlockBag = BlockBag.new(_config(shapes, [], 0), 21)
	var plain: BlockBag = BlockBag.new(_config(shapes, [], 0), 21)
	var preview: Array[BlockShape] = peeked.peek(3)
	assert_eq(preview, _draw(plain, 3), "peek() before any next() shows what next() deals first.")
	assert_eq(_draw(peeked, 12), _draw(BlockBag.new(_config(shapes, [], 0), 21), 12), "peeking first does not skip or reorder draws.")


func test_peeking_at_every_position_never_changes_the_dealt_sequence() -> void:
	var shapes: Array[BlockShape] = [_shape(&"a"), _shape(&"b", 2.0), _shape(&"c"), _shape(&"d")]
	var peeked: BlockBag = BlockBag.new(_config(shapes, [&"a"], 3), 77)
	var plain: BlockBag = BlockBag.new(_config(shapes, [&"a"], 3), 77)
	var total: int = 30  # several bags of 6 to 7 shapes
	for position: int in range(total):
		var preview: Array[BlockShape] = peeked.peek(4)
		assert_eq(preview.size(), 4, "peek(4) at draw %d should not go short" % position)
		assert_eq(peeked.peek(4), preview, "Repeated peeks agree at draw %d" % position)
		var expected: BlockShape = plain.next()
		assert_eq(preview[0], expected, "Preview head is the next draw at %d" % position)
		assert_eq(peeked.next(), expected, "Draw %d matches an un-peeked bag" % position)


func test_peek_reaches_into_the_following_bag_with_the_shapes_that_will_be_dealt() -> void:
	var shapes: Array[BlockShape] = [_shape(&"a"), _shape(&"b"), _shape(&"c")]
	var bag: BlockBag = BlockBag.new(_config(shapes, [], 0), 13)
	_draw(bag, 2)  # one shape left in the current bag of 3
	var preview: Array[BlockShape] = bag.peek(4)
	assert_eq(preview.size(), 4, "A preview across the bag boundary never goes short.")
	assert_eq(_draw(bag, 4), preview)
