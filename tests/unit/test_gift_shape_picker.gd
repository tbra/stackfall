extends GutTest
## Bontago-1pi.85.31: weighted, deterministic shape pick shared by Stackfall and Volcano.

const PICKS: int = 4000


func _weights(ids: PackedStringArray, values: PackedFloat32Array) -> GiftShapeWeights:
	var w: GiftShapeWeights = GiftShapeWeights.new()
	w.shape_ids = ids
	w.weights = values
	return w


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _counts(weights: Resource, seed_value: int) -> Dictionary:
	var rng: RandomNumberGenerator = _rng(seed_value)
	var counts: Dictionary = {}
	for _i: int in range(PICKS):
		var id: StringName = GiftShapePicker.pick(rng, weights).id
		counts[id] = int(counts.get(id, 0)) + 1
	return counts


func test_weights_are_respected() -> void:
	var counts: Dictionary = _counts(_weights(PackedStringArray(["cube", "bar3"]), PackedFloat32Array([9.0, 1.0])), 1)
	assert_gt(int(counts[&"cube"]), int(counts[&"bar3"]) * 4)


func test_zero_weight_shapes_are_never_picked() -> void:
	var counts: Dictionary = _counts(_weights(PackedStringArray(["cube", "L3"]), PackedFloat32Array([0.0, 0.0])), 2)
	assert_false(counts.has(&"cube"))
	assert_false(counts.has(&"L3"))
	assert_gt(counts.size(), 3, "other shapes keep their own weight")


func test_deterministic_per_seed() -> void:
	var weights: Resource = load("res://config/gifts/gift_shape_weights.tres")
	var a: RandomNumberGenerator = _rng(77)
	var b: RandomNumberGenerator = _rng(77)
	var different: bool = false
	var c: RandomNumberGenerator = _rng(78)
	for _i: int in range(40):
		var pa: StringName = GiftShapePicker.pick(a, weights).id
		assert_eq(pa, GiftShapePicker.pick(b, weights).id)
		if pa != GiftShapePicker.pick(c, weights).id:
			different = true
	assert_true(different)


func test_invalid_weights_fall_back_safely() -> void:
	var bad_size: GiftShapeWeights = _weights(PackedStringArray(["cube"]), PackedFloat32Array())
	var negative: GiftShapeWeights = _weights(PackedStringArray(["cube"]), PackedFloat32Array([-3.0]))
	var nan: GiftShapeWeights = _weights(PackedStringArray(["cube"]), PackedFloat32Array([NAN]))
	for w: Resource in [null, bad_size, negative, nan, Resource.new()]:
		var shape: BlockShape = GiftShapePicker.pick(_rng(3), w)
		assert_not_null(shape)
		assert_gt(shape.weight, 0.0)
	assert_true(_counts(negative, 4).size() > 3)


func test_footprint_radius_is_zero_for_cube_and_grows_for_bars() -> void:
	assert_eq(GiftShapePicker.footprint_radius(load("res://config/blocks/cube.tres") as BlockShape, 1.0), 0.0)
	assert_gt(GiftShapePicker.footprint_radius(load("res://config/blocks/bar4.tres") as BlockShape, 1.0), 1.0)
