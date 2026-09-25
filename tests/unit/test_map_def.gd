extends GutTest
## The map-shape mechanism (spec 2.1, docs/M6_PLAN.md package A0):
## MapDef.shape_contains()/shape_test() and for_variant_and_size() -- the
## interface stub A2a/A2b's real Oval/Ring/Twin/Cross data packages build on.
## This package ships the mechanism and reasonable default tunables; the
## data (which numbers a shipped .tres carries) is A2a/A2b's own scope.

const FIELD_RADIUS: float = 20.0

const ALL_SHAPES: Array[MapDef.MapShape] = [
	MapDef.MapShape.ROUND, MapDef.MapShape.OVAL, MapDef.MapShape.RING,
	MapDef.MapShape.TWIN, MapDef.MapShape.CROSS,
]


func _map(shape: MapDef.MapShape) -> MapDef:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = FIELD_RADIUS
	map_def.map_shape = shape
	return map_def


# --- shape_contains(): the bounding circle is a hard outer limit for every shape ---

func test_every_shape_rejects_a_point_outside_the_bounding_circle() -> void:
	var outside: Vector2 = Vector2(FIELD_RADIUS * 1.5, 0.0)
	for shape: MapDef.MapShape in ALL_SHAPES:
		var map_def: MapDef = _map(shape)
		assert_false(
			map_def.shape_contains(outside),
			"shape %d must reject a point outside field_radius's bounding circle" % shape
		)


# --- shape_contains(): the disk center -----------------------------------------

func test_round_oval_twin_and_cross_accept_the_center() -> void:
	for shape: MapDef.MapShape in [
		MapDef.MapShape.ROUND, MapDef.MapShape.OVAL, MapDef.MapShape.TWIN, MapDef.MapShape.CROSS,
	]:
		var map_def: MapDef = _map(shape)
		assert_true(
			map_def.shape_contains(Vector2.ZERO),
			"shape %d must accept the disk center" % shape
		)


func test_ring_rejects_its_own_hole() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.RING)
	assert_false(
		map_def.shape_contains(Vector2.ZERO),
		"the ring's own hole must not read as solid ground"
	)
	# Just past the hole's rim the annulus is solid again.
	var hole_radius: float = FIELD_RADIUS * map_def.ring_hole_radius_fraction
	assert_true(map_def.shape_contains(Vector2(hole_radius + 1.0, 0.0)))


func test_cross_rejects_a_corner_between_arms() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.CROSS)
	# A diagonal point well inside the bounding circle but off both arms.
	var corner: Vector2 = Vector2(1.0, 1.0).normalized() * (FIELD_RADIUS * 0.7)
	assert_true(
		corner.length() <= FIELD_RADIUS,
		"fixture: the corner must still be inside the bounding circle"
	)
	var half_width: float = FIELD_RADIUS * map_def.cross_arm_half_width_fraction
	assert_true(absf(corner.x) > half_width and absf(corner.y) > half_width,
		"fixture: the corner must be outside both arms")
	assert_false(map_def.shape_contains(corner), "a corner between arms must not be solid ground")


func test_round_shape_contains_is_a_plain_circle() -> void:
	var map_def: MapDef = _map(MapDef.MapShape.ROUND)
	assert_true(map_def.shape_contains(Vector2(FIELD_RADIUS * 0.99, 0.0)))
	assert_false(map_def.shape_contains(Vector2(FIELD_RADIUS * 1.01, 0.0)))


# --- shape_test(): only non-ROUND shapes hand CellGrid a Callable --------------

func test_round_shape_test_is_empty() -> void:
	assert_false(_map(MapDef.MapShape.ROUND).shape_test().is_valid())


func test_non_round_shape_test_is_bound_and_matches_shape_contains() -> void:
	for shape: MapDef.MapShape in [
		MapDef.MapShape.OVAL, MapDef.MapShape.RING, MapDef.MapShape.TWIN, MapDef.MapShape.CROSS,
	]:
		var map_def: MapDef = _map(shape)
		var test: Callable = map_def.shape_test()
		assert_true(test.is_valid(), "shape %d must hand CellGrid a bound Callable" % shape)
		assert_eq(
			bool(test.call(Vector2.ZERO)), map_def.shape_contains(Vector2.ZERO),
			"shape_test() must agree with shape_contains() at the same point"
		)


# --- for_variant_and_size(): ROUND is byte-identical to for_size() -------------

func test_for_variant_and_size_round_matches_for_size_for_every_size() -> void:
	for size: MapDef.MapSize in [MapDef.MapSize.SMALL, MapDef.MapSize.MEDIUM, MapDef.MapSize.LARGE]:
		var direct: MapDef = MapDef.for_size(size)
		var routed: MapDef = MapDef.for_variant_and_size(MapDef.MapShape.ROUND, size)
		assert_eq(routed, direct, "ROUND must route to the exact same for_size() result")
		assert_eq(routed.field_radius, direct.field_radius)
		assert_eq(routed.cell_size, direct.cell_size)
		assert_eq(routed.map_shape, direct.map_shape)


func test_for_variant_and_size_non_round_sets_the_shape_without_mutating_the_cached_resource() -> void:
	var direct: MapDef = MapDef.for_size(MapDef.MapSize.MEDIUM)
	var routed: MapDef = MapDef.for_variant_and_size(MapDef.MapShape.OVAL, MapDef.MapSize.MEDIUM)
	assert_eq(routed.map_shape, MapDef.MapShape.OVAL)
	assert_eq(
		direct.map_shape, MapDef.MapShape.ROUND,
		"for_size()'s cached ROUND resource must not be mutated by a later variant request"
	)
	assert_almost_eq(routed.field_radius, direct.field_radius, 0.001)


# --- every shape's flags land on their own solid ground (review fix, Bontago-keo.2) --

## Every home_flag_position(slot, count) for every slot count 2..8 (spec 2.8's
## 2-8 players) and every goal_flag_positions(count) for every goal count 1..5
## (spec 2.2's "Setup allows 1-5") must be solid ground for its own map_shape
## -- field_radius is the universal outer bound every shape sizes its own
## interior geometry to fit inside (config/MapDef.gd's DECISION above
## shape_contains()), so nothing this file hands to Field/PlayerSlot can ever
## place a flag in a hole, a gap between TWIN's sub-disks, or outside the
## bounding circle.
func test_every_shape_places_every_flag_on_solid_ground() -> void:
	for shape: MapDef.MapShape in ALL_SHAPES:
		var map_def: MapDef = _map(shape)
		for slot_count: int in range(2, 9):
			for slot_id: int in range(slot_count):
				var home: Vector2 = map_def.home_flag_position(slot_id, slot_count)
				assert_true(
					map_def.shape_contains(home),
					"shape %d home flag %d/%d at %s must be solid ground"
						% [shape, slot_id, slot_count, home]
				)
		for goal_count: int in range(1, 6):
			var goals: PackedVector2Array = map_def.goal_flag_positions(goal_count)
			for goal: Vector2 in goals:
				assert_true(
					map_def.shape_contains(goal),
					"shape %d goal flag %s (count %d) must be solid ground" % [shape, goal, goal_count]
				)
