extends GutTest
## TerritoryCull.drop_contained: a same-team block circle fully inside a larger
## kept circle is dropped; homes are never dropped and never contain.


func _block(x: float, y: float, r: float, team: int = 0) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, y), r, team, team, false, 1)


func _home(x: float, y: float, r: float, team: int = 0) -> InfluenceCircle:
	return InfluenceCircle.new(Vector2(x, y), r, team, team, true, -1)


func _cull(circles: Array[InfluenceCircle]) -> Array[InfluenceCircle]:
	return TerritoryCull.drop_contained(circles)


func test_empty_input_returns_empty() -> void:
	var result: Array[InfluenceCircle] = _cull([] as Array[InfluenceCircle])
	assert_eq(result.size(), 0)


func test_single_circle_is_kept() -> void:
	var a: InfluenceCircle = _block(1.0, 1.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([a] as Array[InfluenceCircle])
	assert_eq(result.size(), 1)
	assert_same(result[0], a)


func test_contained_same_team_circle_is_dropped() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var small: InfluenceCircle = _block(1.0, 0.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([big, small] as Array[InfluenceCircle])
	assert_eq(result.size(), 1)
	assert_same(result[0], big)


func test_overlapping_but_not_contained_is_kept() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var edge: InfluenceCircle = _block(4.0, 0.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([big, edge] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)
	assert_same(result[0], big)
	assert_same(result[1], edge)


func test_contained_other_team_circle_is_kept() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0, 0)
	var other: InfluenceCircle = _block(1.0, 0.0, 2.0, 1)
	var result: Array[InfluenceCircle] = _cull([big, other] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)


func test_order_independent_larger_listed_last() -> void:
	var small: InfluenceCircle = _block(1.0, 0.0, 2.0)
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var result: Array[InfluenceCircle] = _cull([small, big] as Array[InfluenceCircle])
	assert_eq(result.size(), 1)
	assert_same(result[0], big)


func test_equal_circles_are_never_culled() -> void:
	var a: InfluenceCircle = _block(0.0, 0.0, 3.0)
	var b: InfluenceCircle = _block(0.0, 0.0, 3.0)
	var result: Array[InfluenceCircle] = _cull([a, b] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)
	assert_same(result[0], a)
	assert_same(result[1], b)


func test_equal_radius_different_centers_are_kept() -> void:
	var a: InfluenceCircle = _block(0.0, 0.0, 3.0)
	var b: InfluenceCircle = _block(0.5, 0.0, 3.0)
	var result: Array[InfluenceCircle] = _cull([a, b] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)


func test_tangent_inside_circle_is_dropped() -> void:
	# distance 3 == radius gap 5 - 2: touching from inside is contained.
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var small: InfluenceCircle = _block(3.0, 0.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([big, small] as Array[InfluenceCircle])
	assert_eq(result.size(), 1)
	assert_same(result[0], big)


func test_just_poking_out_circle_is_kept() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var small: InfluenceCircle = _block(3.25, 0.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([big, small] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)


func test_chain_leaves_only_the_largest() -> void:
	var a: InfluenceCircle = _block(0.0, 0.0, 8.0)
	var b: InfluenceCircle = _block(1.0, 0.0, 4.0)
	var c: InfluenceCircle = _block(1.5, 0.0, 1.0)
	var result: Array[InfluenceCircle] = _cull([c, b, a] as Array[InfluenceCircle])
	assert_eq(result.size(), 1)
	assert_same(result[0], a)


func test_home_is_never_dropped_by_a_larger_block() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 10.0)
	var home: InfluenceCircle = _home(1.0, 0.0, 6.0)
	var result: Array[InfluenceCircle] = _cull([big, home] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)
	assert_true(result.has(home))


func test_home_is_never_a_container() -> void:
	var home: InfluenceCircle = _home(0.0, 0.0, 6.0)
	var inside: InfluenceCircle = _block(0.5, 0.0, 2.0)
	var result: Array[InfluenceCircle] = _cull([home, inside] as Array[InfluenceCircle])
	assert_eq(result.size(), 2)


func test_survivors_keep_input_order() -> void:
	var a: InfluenceCircle = _block(20.0, 0.0, 2.0)
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var gone: InfluenceCircle = _block(1.0, 0.0, 1.0)
	var home: InfluenceCircle = _home(-20.0, 0.0, 6.0)
	var other: InfluenceCircle = _block(0.0, 0.0, 1.0, 1)
	var result: Array[InfluenceCircle] = _cull(
		[a, big, gone, home, other] as Array[InfluenceCircle]
	)
	assert_eq(result.size(), 4)
	assert_same(result[0], a)
	assert_same(result[1], big)
	assert_same(result[2], home)
	assert_same(result[3], other)


func test_input_is_not_mutated() -> void:
	var big: InfluenceCircle = _block(0.0, 0.0, 5.0)
	var small: InfluenceCircle = _block(1.0, 0.0, 2.0)
	var input: Array[InfluenceCircle] = [small, big]
	_cull(input)
	assert_eq(input.size(), 2)
	assert_same(input[0], small)
	assert_same(input[1], big)


func test_survivors_are_unchanged_circles() -> void:
	var big: InfluenceCircle = _block(1.5, -2.5, 5.0)
	var result: Array[InfluenceCircle] = _cull(
		[big, _block(2.0, -2.5, 1.0)] as Array[InfluenceCircle]
	)
	assert_eq(result.size(), 1)
	assert_eq(result[0].center, Vector2(1.5, -2.5))
	assert_eq(result[0].radius, 5.0)
	assert_eq(result[0].team_id, 0)
