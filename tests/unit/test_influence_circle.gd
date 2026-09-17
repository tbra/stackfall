extends GutTest
## Spec 2.2's influence rule: "r = influence_base + influence_k * h ... capped
## at influence_max = 0.6 * field_radius", and spec 3.3's "two circles are
## connected if they overlap".

const MAP_RADIUS: float = 45.0

var _tuning: TerritoryTuning = preload("res://config/territory_tuning.tres")


func test_a_block_flat_on_the_disk_gets_the_base_radius() -> void:
	assert_almost_eq(
		InfluenceCircle.radius_for_height(0.0, _tuning, MAP_RADIUS),
		_tuning.influence_base,
		0.0001
	)


func test_height_below_the_surface_still_gives_the_base_radius() -> void:
	assert_almost_eq(
		InfluenceCircle.radius_for_height(-3.0, _tuning, MAP_RADIUS),
		_tuning.influence_base,
		0.0001,
		"A negative height must not shrink the circle below influence_base."
	)


func test_radius_grows_linearly_with_height() -> void:
	for height: float in [1.0, 4.0, 10.0]:
		assert_almost_eq(
			InfluenceCircle.radius_for_height(height, _tuning, MAP_RADIUS),
			_tuning.influence_base + _tuning.influence_k * height,
			0.0001
		)


func test_radius_is_capped_at_the_map_fraction() -> void:
	var cap: float = _tuning.influence_max_fraction * MAP_RADIUS
	assert_almost_eq(
		InfluenceCircle.radius_for_height(1000.0, _tuning, MAP_RADIUS), cap, 0.0001
	)
	## The cap scales with the map, so a small disk caps sooner.
	var small_cap: float = _tuning.influence_max_fraction * 30.0
	assert_almost_eq(
		InfluenceCircle.radius_for_height(1000.0, _tuning, 30.0), small_cap, 0.0001
	)


func test_just_below_the_cap_is_not_clamped() -> void:
	var cap: float = _tuning.influence_max_fraction * MAP_RADIUS
	var height: float = (cap - _tuning.influence_base) / _tuning.influence_k - 1.0
	assert_lt(InfluenceCircle.radius_for_height(height, _tuning, MAP_RADIUS), cap)


func test_overlap_is_inclusive_at_exactly_the_summed_radii() -> void:
	var a: InfluenceCircle = InfluenceCircle.new(Vector2.ZERO, 2.0, 0, 0)
	var b: InfluenceCircle = InfluenceCircle.new(Vector2(5.0, 0.0), 3.0, 0, 1)
	assert_true(a.overlaps(b), "Exactly r1 + r2 apart counts as overlapping.")
	assert_true(b.overlaps(a), "Overlap is symmetric.")


func test_circles_just_past_the_summed_radii_do_not_overlap() -> void:
	var a: InfluenceCircle = InfluenceCircle.new(Vector2.ZERO, 2.0, 0, 0)
	var b: InfluenceCircle = InfluenceCircle.new(Vector2(5.01, 0.0), 3.0, 0, 1)
	assert_false(a.overlaps(b))


func test_contains_point_is_inclusive_on_the_rim() -> void:
	var c: InfluenceCircle = InfluenceCircle.new(Vector2(1.0, 2.0), 4.0, 0, 0)
	assert_true(c.contains_point(Vector2(1.0, 2.0)))
	assert_true(c.contains_point(Vector2(5.0, 2.0)), "A point exactly on the rim is inside.")
	assert_false(c.contains_point(Vector2(5.01, 2.0)))


func test_for_block_builds_a_non_home_circle_at_the_projected_center() -> void:
	var circle: InfluenceCircle = InfluenceCircle.for_block(
		Vector2(3.0, -7.0), 5.0, 1, 2, 99, _tuning, MAP_RADIUS
	)
	assert_eq(circle.center, Vector2(3.0, -7.0))
	assert_almost_eq(
		circle.radius, _tuning.influence_base + _tuning.influence_k * 5.0, 0.0001
	)
	assert_eq(circle.team_id, 1)
	assert_eq(circle.slot_id, 2)
	assert_eq(circle.body_id, 99)
	assert_false(circle.is_home)


func test_for_home_uses_home_radius_and_anchors() -> void:
	var circle: InfluenceCircle = InfluenceCircle.for_home(Vector2(0.0, 38.0), 3, 3, _tuning)
	assert_eq(circle.center, Vector2(0.0, 38.0))
	assert_almost_eq(circle.radius, _tuning.home_radius, 0.0001)
	assert_eq(circle.team_id, 3)
	assert_eq(circle.slot_id, 3)
	assert_true(circle.is_home)
	assert_eq(circle.body_id, -1, "A home circle has no body behind it.")


func test_height_credit_keeps_the_placing_slot_not_the_tower_owner() -> void:
	## Spec 2.2, "Height credit": one block on an enemy tower gives *you* a
	## circle at that height. The circle simply carries whatever slot/team it
	## was built with; nothing about the tower below it enters here.
	var mine: InfluenceCircle = InfluenceCircle.for_block(
		Vector2.ZERO, 12.0, 0, 0, 5, _tuning, MAP_RADIUS
	)
	var theirs: InfluenceCircle = InfluenceCircle.for_block(
		Vector2.ZERO, 11.0, 1, 1, 4, _tuning, MAP_RADIUS
	)
	assert_eq(mine.team_id, 0)
	assert_gt(mine.radius, theirs.radius, "The higher block projects farther.")
