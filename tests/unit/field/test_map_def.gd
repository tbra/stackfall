extends GutTest
## MapDef's round-only geometry:
## shape_contains()/shape_test(), base() and the flag layouts.

const FIELD_RADIUS: float = 20.0


func _map() -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = FIELD_RADIUS
	return map_def


func test_every_flag_lands_on_solid_ground() -> void:
	var maps: Array[MapDef] = [_map(), MapDef.base(), MapDef.base().scaled(0.5), MapDef.base().scaled(1.75)]
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
	var map_def: MapDef = MapDef.base()
	var half: MapDef = map_def.scaled(0.5)
	assert_almost_eq(half.field_radius, map_def.field_radius * 0.5, 0.001)
	assert_eq(half.territory_res, map_def.territory_res / 2)
	assert_eq(map_def.scaled(1.0), map_def)


func test_home_radius_is_disc_radius_minus_the_fixed_inset_for_every_scale() -> void:
	for factor: float in [0.5, 1.0, 1.75]:
		var map_def: MapDef = MapDef.base().scaled(factor)
		assert_gt(map_def.home_flag_edge_inset, 0.0, "inset is a positive tunable")
		for count: int in [2, 5, 8]:
			for slot_id: int in range(count):
				var home: Vector2 = map_def.home_flag_position(slot_id, count)
				assert_almost_eq(home.length(), map_def.field_radius - map_def.home_flag_edge_inset, 0.001)
				assert_true(map_def.shape_contains(home))


