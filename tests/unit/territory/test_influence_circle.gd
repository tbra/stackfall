extends GutTest
## Spec 2.2's influence rule: "r = influence_base + h * tan(40 deg) ... capped
## at influence_max = 0.6 * field_radius", and spec 3.3's "two circles are
## connected if they overlap".

const MAP_RADIUS: float = 45.0

var _tuning: TerritoryTuning = preload("res://config/territory/territory_tuning.tres")


func test_a_block_flat_on_the_disk_gets_the_base_radius() -> void:
	assert_almost_eq(
		InfluenceCircle.radius_for_height(0.0, _tuning, MAP_RADIUS),
		_tuning.influence_base,
		0.0001
	)


func test_radius_grows_linearly_with_height() -> void:
	for height: float in [1.0, 4.0, 10.0]:
		assert_almost_eq(
			InfluenceCircle.radius_for_height(height, _tuning, MAP_RADIUS),
			_tuning.influence_base + InfluenceCircle.cone_slope() * height,
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


func test_overlap_is_inclusive_at_exactly_the_summed_radii() -> void:
	var a: InfluenceCircle = InfluenceCircle.new(Vector2.ZERO, 2.0, 0, 0)
	var b: InfluenceCircle = InfluenceCircle.new(Vector2(5.0, 0.0), 3.0, 0, 1)
	assert_true(a.overlaps(b), "Exactly r1 + r2 apart counts as overlapping.")
	assert_true(b.overlaps(a), "Overlap is symmetric.")


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
