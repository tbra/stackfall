extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/jumping_bean_v1/jumping_bean_v1.glb")
	if packed == null:
		push_error("Jumping bean GLB import failed")
		quit(1)
		return
	var instance := packed.instantiate()
	var player := _find_player(instance)
	if player == null or not player.has_animation("idle_hop_1p5s"):
		push_error("idle_hop_1p5s clip missing")
		instance.free()
		quit(1)
		return
	var animation := player.get_animation("idle_hop_1p5s")
	var hop := false
	var roll := false
	var squash := false
	for track: int in animation.get_track_count():
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				hop = animation.position_track_interpolate(track, 0.0).distance_to(animation.position_track_interpolate(track, 0.375)) > 0.1
			Animation.TYPE_ROTATION_3D:
				roll = animation.rotation_track_interpolate(track, 0.0).angle_to(animation.rotation_track_interpolate(track, 0.375)) > 0.1
			Animation.TYPE_SCALE_3D:
				squash = animation.scale_track_interpolate(track, 0.0).distance_to(animation.scale_track_interpolate(track, 0.375)) > 0.1
	print("Imported hop: %.2fs, %d tracks; hop=%s roll=%s squash=%s" % [animation.length, animation.get_track_count(), hop, roll, squash])
	if animation.length < 1.4 or animation.length > 1.6 or not (hop and roll and squash):
		push_error("Hop motion did not survive import")
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
