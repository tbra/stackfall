extends GutTest
## BotModeGoal.next_goal_index: the unheld goal nearest the bot's home-connected component.


func test_next_goal_index_picks_the_unheld_goal_nearest_the_component() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0), Vector2(-10.0, 0.0)])
	var component: PackedVector2Array = PackedVector2Array([Vector2(-6.0, 0.0)])
	var held: Array[bool] = [false, false]
	assert_eq(BotModeGoal.next_goal_index(goals, held, component, Vector2.ZERO), 1)
	var near_held: Array[bool] = [false, true]
	assert_eq(BotModeGoal.next_goal_index(goals, near_held, component, Vector2.ZERO), 0, "a held goal is skipped")
	var all_held: Array[bool] = [true, true]
	assert_eq(BotModeGoal.next_goal_index(goals, all_held, component, Vector2.ZERO), -1)


func test_next_goal_index_falls_back_to_the_anchor_without_component_points() -> void:
	var goals: PackedVector2Array = PackedVector2Array([Vector2(10.0, 0.0), Vector2(-10.0, 0.0)])
	var held: Array[bool] = [false, false]
	assert_eq(BotModeGoal.next_goal_index(goals, held, PackedVector2Array(), Vector2(8.0, 0.0)), 0)
