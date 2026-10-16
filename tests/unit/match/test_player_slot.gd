extends GutTest
## PlayerSlot.home_position_for / goal_positions_for (spec 1.5): where the
## home and goal flags sit, disk-local.

const EPS: float = 0.001


func _map_def() -> MapDef:
	return load("res://config/match/maps/round.tres")


func test_two_players_sit_pi_apart_at_home_radius() -> void:
	var map_def: MapDef = _map_def()
	var a: Vector2 = PlayerSlot.home_position_for(0, 2, map_def)
	var b: Vector2 = PlayerSlot.home_position_for(1, 2, map_def)
	var expected_radius: float = map_def.field_radius - map_def.home_flag_edge_inset
	assert_almost_eq(a.length(), expected_radius, EPS)
	assert_almost_eq(b.length(), expected_radius, EPS)
	var angle: float = a.angle_to(b)
	assert_almost_eq(absf(angle), PI, EPS)


func test_goal_positions_for_three_is_symmetric_at_goal_radius() -> void:
	var map_def: MapDef = _map_def()
	var positions: PackedVector2Array = PlayerSlot.goal_positions_for(3, map_def)
	assert_eq(positions.size(), 3)
	var expected_radius: float = map_def.goal_flag_radius_fraction * map_def.field_radius
	for pos: Vector2 in positions:
		assert_almost_eq(pos.length(), expected_radius, EPS)
	for i: int in range(3):
		var a: Vector2 = positions[i]
		var b: Vector2 = positions[(i + 1) % 3]
		assert_almost_eq(absf(a.angle_to(b)), TAU / 3.0, EPS)


# --- Rules and props agree on where the flags stand -------------------------
# PlayerSlot is what the rules (Match, WinChecker) use; MapDef is what Field
# uses to place the flag props. If the two ever drift, a goal flag would be
# drawn somewhere the win check is not watching. They are the same function
# now; this pins that.
