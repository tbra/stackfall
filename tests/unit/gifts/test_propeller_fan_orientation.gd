extends GutTest
## the Propeller model is an upward-facing fan, so the airflow reads as
## the lift the effect applies (SPEC 1.6). Blades lie flat and the spin is about vertical Y.

const SPIN_CLIP: StringName = &"spin_1s"
const QUARTER_TURN_T: float = 0.25
const FLAT_RATIO: float = 0.35
const AXIS_DOT_MIN: float = 0.99


func _visual() -> Node3D:
	var visual: Node3D = GiftModelTable.shared().build_gift_visual(&"propeller")
	add_child_autofree(visual)
	return visual


func _rotor_blades(visual: Node3D) -> MeshInstance3D:
	for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
		if String(node.name).to_lower().contains("blades"):
			return node as MeshInstance3D
	return null


func test_blades_lie_flat_in_the_horizontal_plane() -> void:
	var blades: MeshInstance3D = _rotor_blades(_visual())
	assert_not_null(blades, "rotor blade mesh found")
	if blades == null:
		return
	var box: AABB = blades.mesh.get_aabb()
	assert_lt(box.size.y, box.size.x * FLAT_RATIO, "blade disc is thin along vertical Y")
	assert_lt(box.size.y, box.size.z * FLAT_RATIO, "blade disc is thin along vertical Y (Z)")


func test_spin_clip_rotates_about_vertical_axis() -> void:
	var visual: Node3D = _visual()
	var player: AnimationPlayer = GiftModelTable._player_of(visual)
	assert_not_null(player, "spin player")
	if player == null:
		return
	var anim: Animation = player.get_animation(SPIN_CLIP)
	var found: bool = false
	for i: int in range(anim.get_track_count()):
		if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
			continue
		var q: Quaternion = anim.rotation_track_interpolate(i, anim.length * QUARTER_TURN_T)
		found = true
		assert_gt(absf(q.get_axis().dot(Vector3.UP)), AXIS_DOT_MIN, "spin axis is vertical")
	assert_true(found, "clip has a rotation track")
