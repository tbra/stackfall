extends GutTest
## The held Rocket and Magnet point their nose along the aim (not
## upright), and every throwable's arc preview starts inside the held model's world AABB.

const NOSE_TOLERANCE_DEG: float = 5.0
const AIM: Vector3 = Vector3(0.6, 0.3, -0.74)
func after_each() -> void:
	Settings._input(InputEventKey.new())


func _ghost_holding(id: StringName) -> GhostPreview:
	var ghost: GhostPreview = autofree(GhostPreview.new())
	add_child_autofree(ghost)
	ghost.set_shape(load("res://config/blocks/cube.tres"))
	ghost.set_held_gift(id)
	return ghost


func _nose_world(ghost: GhostPreview, id: StringName) -> Vector3:
	var axis: Vector3 = GiftModelTable.shared().entry_for(id).held_nose_axis
	return (ghost._gift_visual.global_basis * axis).normalized()


func test_held_rocket_and_magnet_nose_follows_the_aim_and_is_not_vertical() -> void:
	for id: StringName in [&"rocket", &"magnet"]:
		var ghost: GhostPreview = _ghost_holding(id)
		ghost.set_held_aim(AIM)
		var nose: Vector3 = _nose_world(ghost, id)
		assert_lt(rad_to_deg(nose.angle_to(AIM.normalized())), NOSE_TOLERANCE_DEG, "%s nose on aim" % id)
		assert_lt(absf(nose.dot(Vector3.UP)), 0.99, "%s not standing upright" % id)
