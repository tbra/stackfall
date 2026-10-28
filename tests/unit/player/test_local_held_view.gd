extends GutTest
## LocalHeldView (game/world/LocalHeldView.gd): the held-pose store the controller writes and the
## HUD, birds and gift presenters read through MatchContext.local_held().

const CUBE_PATH: String = "res://config/blocks/cube.tres"


func _publish_sample(view: LocalHeldView, shape: BlockShape) -> void:
	view.publish(3, shape, Vector3(1.0, 2.0, 3.0), 5, Quaternion(0.0, 0.7071068, 0.0, 0.7071068),
			true, 4.5)


func test_a_new_view_holds_nothing() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	assert_null(view.shape)
	assert_eq(view.slot_id, -1)
	assert_false(view.visible)
	assert_eq(view.origin, Vector3.ZERO)
	assert_eq(view.orientation_index, 0)
	assert_eq(view.free_quat, Quaternion.IDENTITY)
	assert_eq(view.height_above_surface, 0.0)


func test_publish_round_trips_every_field() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	var shape: BlockShape = load(CUBE_PATH)
	_publish_sample(view, shape)
	assert_eq(view.slot_id, 3)
	assert_same(view.shape, shape)
	assert_eq(view.origin, Vector3(1.0, 2.0, 3.0))
	assert_eq(view.orientation_index, 5)
	assert_eq(view.free_quat, Quaternion(0.0, 0.7071068, 0.0, 0.7071068))
	assert_true(view.visible)
	assert_eq(view.height_above_surface, 4.5)


func test_publish_carries_a_hidden_flag_too() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	view.publish(0, load(CUBE_PATH), Vector3.ZERO, 0, Quaternion.IDENTITY, false, 0.0)
	assert_false(view.visible)
	assert_not_null(view.shape, "hidden is not the same as nothing held")


func test_a_second_publish_replaces_the_first() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	_publish_sample(view, load(CUBE_PATH))
	var other: BlockShape = load("res://config/blocks/bar3.tres")
	view.publish(1, other, Vector3(-1.0, 0.0, 0.5), 2, Quaternion.IDENTITY, false, 0.25)
	assert_eq(view.slot_id, 1)
	assert_same(view.shape, other)
	assert_eq(view.origin, Vector3(-1.0, 0.0, 0.5))
	assert_eq(view.orientation_index, 2)
	assert_eq(view.free_quat, Quaternion.IDENTITY)
	assert_false(view.visible)
	assert_eq(view.height_above_surface, 0.25)


func test_clear_drops_the_shape_slot_and_visibility() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	_publish_sample(view, load(CUBE_PATH))
	view.clear()
	assert_null(view.shape)
	assert_eq(view.slot_id, -1)
	assert_false(view.visible)


func test_clear_on_an_empty_view_is_harmless() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	view.clear()
	assert_null(view.shape)
	assert_eq(view.slot_id, -1)


func test_publish_after_clear_holds_again() -> void:
	var view: LocalHeldView = LocalHeldView.new()
	_publish_sample(view, load(CUBE_PATH))
	view.clear()
	_publish_sample(view, load(CUBE_PATH))
	assert_not_null(view.shape)
	assert_eq(view.slot_id, 3)
	assert_true(view.visible)
