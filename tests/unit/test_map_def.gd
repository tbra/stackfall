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


# --- A2a/A2b: Oval/Ring/Twin/Cross MapDef resources (docs/M6_PLAN.md A2a/A2b) --

## for_variant_and_size() itself (config/MapDef.gd:200-205) never reads a
## config/maps/<variant>_<size>.tres file by name -- for any non-ROUND variant
## it duplicates for_size(size)'s cached ROUND resource and only overwrites
## map_shape, so field_radius/cell_size/territory_res/etc are inherited from
## the same-size Round resource by construction, not by a per-variant file.
## Kept here (generalized to every non-ROUND shape x every size, not just
## A0's single OVAL/MEDIUM spot check above) because the plan asks for exactly
## this coverage even though it would pass unchanged whether or not A2a/A2b's
## own .tres files below exist.
func test_for_variant_and_size_non_round_matches_the_same_size_round_resource() -> void:
	for size: MapDef.MapSize in [MapDef.MapSize.SMALL, MapDef.MapSize.MEDIUM, MapDef.MapSize.LARGE]:
		var round_map: MapDef = MapDef.for_size(size)
		for shape: MapDef.MapShape in [
			MapDef.MapShape.OVAL, MapDef.MapShape.RING, MapDef.MapShape.TWIN, MapDef.MapShape.CROSS,
		]:
			var routed: MapDef = MapDef.for_variant_and_size(shape, size)
			assert_eq(routed.map_shape, shape, "shape %d size %d must set map_shape" % [shape, size])
			assert_almost_eq(
				routed.field_radius, round_map.field_radius, 0.001,
				"shape %d size %d field_radius must match the same-size Round resource" % [shape, size]
			)
			assert_almost_eq(
				routed.cell_size, round_map.cell_size, 0.001,
				"shape %d size %d cell_size must match the same-size Round resource" % [shape, size]
			)


## The 12 shipped config/maps/<variant>_<size>.tres resources (A2a/A2b). These
## are not reached through for_variant_and_size() (see the DECISION above) --
## they are validated by loading each file directly: map_shape/field_radius/
## cell_size must match their same-size Round sibling, and every home/goal
## flag position for player counts 2..8 / goal counts 1..5 must be solid
## ground per that resource's own shape_contains(), using each map's real
## field_radius (30/45/60) rather than this file's synthetic FIELD_RADIUS.
const VARIANT_MAP_FILES: Dictionary = {
	MapDef.MapShape.OVAL: ["oval_small", "oval_medium", "oval_large"],
	MapDef.MapShape.RING: ["ring_small", "ring_medium", "ring_large"],
	MapDef.MapShape.TWIN: ["twin_small", "twin_medium", "twin_large"],
	MapDef.MapShape.CROSS: ["cross_small", "cross_medium", "cross_large"],
}
const ROUND_MAP_FILES: Array[String] = ["round_small", "round_medium", "round_large"]


func test_shipped_variant_resources_load_and_match_their_round_sibling() -> void:
	for shape: int in VARIANT_MAP_FILES.keys():
		var names: Array = VARIANT_MAP_FILES[shape]
		for i: int in range(names.size()):
			var variant_map: MapDef = load("res://config/maps/%s.tres" % names[i]) as MapDef
			assert_not_null(variant_map, "%s.tres must load as a MapDef" % names[i])
			var round_map: MapDef = load("res://config/maps/%s.tres" % ROUND_MAP_FILES[i]) as MapDef
			assert_eq(variant_map.map_shape, shape, "%s.tres must set map_shape" % names[i])
			assert_almost_eq(
				variant_map.field_radius, round_map.field_radius, 0.001,
				"%s.tres field_radius must match %s.tres" % [names[i], ROUND_MAP_FILES[i]]
			)
			assert_almost_eq(
				variant_map.cell_size, round_map.cell_size, 0.001,
				"%s.tres cell_size must match %s.tres" % [names[i], ROUND_MAP_FILES[i]]
			)


func test_shipped_variant_resources_place_every_flag_on_solid_ground() -> void:
	for shape: int in VARIANT_MAP_FILES.keys():
		var names: Array = VARIANT_MAP_FILES[shape]
		for map_name: String in names:
			var map_def: MapDef = load("res://config/maps/%s.tres" % map_name) as MapDef
			for slot_count: int in range(2, 9):
				for slot_id: int in range(slot_count):
					var home: Vector2 = map_def.home_flag_position(slot_id, slot_count)
					assert_true(
						map_def.shape_contains(home),
						"%s.tres home flag %d/%d at %s must be solid ground"
							% [map_name, slot_id, slot_count, home]
					)
			for goal_count: int in range(1, 6):
				var goals: PackedVector2Array = map_def.goal_flag_positions(goal_count)
				for goal: Vector2 in goals:
					assert_true(
						map_def.shape_contains(goal),
						"%s.tres goal flag %s (count %d) must be solid ground"
							% [map_name, goal, goal_count]
					)


# --- shipped per-variant resources are what for_variant_and_size() returns ----

## A2a/A2b ship config/maps/<shape>_<size>.tres; for_variant_and_size() must
## hand back that file (same resource_path) rather than the in-memory Round
## duplicate fallback, for every non-Round shape and size.
func test_for_variant_and_size_returns_the_shipped_variant_resource() -> void:
	for shape: int in [MapDef.MapShape.OVAL, MapDef.MapShape.RING, MapDef.MapShape.TWIN, MapDef.MapShape.CROSS]:
		for size: int in [MapDef.MapSize.SMALL, MapDef.MapSize.MEDIUM, MapDef.MapSize.LARGE]:
			var path: String = MapDef.variant_resource_path(shape, size as MapDef.MapSize)
			assert_true(ResourceLoader.exists(path), "%s should ship" % path)
			var routed: MapDef = MapDef.for_variant_and_size(shape, size as MapDef.MapSize)
			assert_eq(routed.resource_path, path)
			assert_eq(routed.map_shape, shape as MapDef.MapShape)
