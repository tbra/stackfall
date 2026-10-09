extends GutTest
## MapDef's round-only geometry (Bontago-fca.75 removed oval/ring/twin/cross):
## shape_contains()/shape_test(), for_variant_and_size() and the flag layouts.

const FIELD_RADIUS: float = 20.0
const REMOVED_VARIANTS: Array[int] = [1, 2, 3, 4, 99, -1]
const MAP_FILES: Array[String] = ["round_small", "round_medium", "round_large"]


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = FIELD_RADIUS
	return map_def


func test_shape_contains_is_a_plain_circle() -> void:
	var map_def: MapDef = _map()
	assert_true(map_def.shape_contains(Vector2.ZERO))
	assert_true(map_def.shape_contains(Vector2(FIELD_RADIUS * 0.99, 0.0)))
	assert_false(map_def.shape_contains(Vector2(FIELD_RADIUS * 1.01, 0.0)))
	assert_false(map_def.shape_contains(Vector2(FIELD_RADIUS, FIELD_RADIUS)))


func test_shape_test_is_empty() -> void:
	assert_false(_map().shape_test().is_valid())


func test_only_round_remains() -> void:
	assert_eq(MapDef.MapShape.keys(), ["ROUND"])
	assert_eq(MapDef.MapShape.ROUND, 0)


func test_for_variant_and_size_round_matches_for_size_for_every_size() -> void:
	for size: MapDef.MapSize in [MapDef.MapSize.SMALL, MapDef.MapSize.MEDIUM, MapDef.MapSize.LARGE]:
		assert_eq(MapDef.for_variant_and_size(MapDef.MapShape.ROUND, size), MapDef.for_size(size))


func test_a_removed_variant_draws_the_round_map() -> void:
	for variant: int in REMOVED_VARIANTS:
		for size: MapDef.MapSize in [MapDef.MapSize.SMALL, MapDef.MapSize.MEDIUM, MapDef.MapSize.LARGE]:
			assert_eq(MapDef.for_variant_and_size(variant, size), MapDef.for_size(size), "variant %d" % variant)


func test_the_removed_map_resources_are_gone() -> void:
	for shape_name: String in ["oval", "ring", "twin", "cross"]:
		assert_false(ResourceLoader.exists("res://config/maps/%s_medium.tres" % shape_name), shape_name)


func test_every_flag_lands_on_solid_ground() -> void:
	var maps: Array[MapDef] = [_map()]
	for map_name: String in MAP_FILES:
		maps.append(load("res://config/maps/%s.tres" % map_name) as MapDef)
	for map_def: MapDef in maps:
		for slot_count: int in range(2, 9):
			for slot_id: int in range(slot_count):
				var home: Vector2 = map_def.home_flag_position(slot_id, slot_count)
				assert_true(map_def.shape_contains(home), "home %d/%d at %s" % [slot_id, slot_count, home])
		for goal_count: int in range(1, 6):
			for goal: Vector2 in map_def.goal_flag_positions(goal_count):
				assert_true(map_def.shape_contains(goal), "goal %s (count %d)" % [goal, goal_count])


func test_a_single_goal_is_the_centre_and_more_sit_on_the_goal_ring() -> void:
	var map_def: MapDef = _map()
	assert_eq(map_def.goal_flag_positions(1)[0], Vector2.ZERO)
	for goal: Vector2 in map_def.goal_flag_positions(3):
		assert_almost_eq(goal.length(), FIELD_RADIUS * map_def.goal_flag_radius_fraction, 0.001)


func test_scaled_copy_scales_the_radius_and_territory_resolution() -> void:
	var map_def: MapDef = MapDef.for_size(MapDef.MapSize.MEDIUM)
	var half: MapDef = map_def.scaled(0.5)
	assert_almost_eq(half.field_radius, map_def.field_radius * 0.5, 0.001)
	assert_eq(half.territory_res, map_def.territory_res / 2)
	assert_eq(map_def.scaled(1.0), map_def)
