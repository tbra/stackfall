extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/cat_v1/cat_v1.glb")
	if packed == null:
		push_error("Cat GLB import failed")
		quit(1)
		return
	var instance := packed.instantiate()
	var player := _find_player(instance)
	if player == null or not player.has_animation("tail_sway_2s"):
		push_error("tail_sway_2s clip missing")
		instance.free()
		quit(1)
		return
	var animation := player.get_animation("tail_sway_2s")
	var moving := false
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			moving = animation.rotation_track_interpolate(track, 0.0).angle_to(animation.rotation_track_interpolate(track, 0.5)) > 0.1
	print("Imported tail loop: %.2fs, %d tracks, moving=%s" % [animation.length, animation.get_track_count(), moving])
	if animation.length < 1.9 or animation.length > 2.1 or not moving:
		push_error("Tail sway did not survive import")
		instance.free()
		quit(1)
		return
	instance.free()
	quit()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child: Node in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
