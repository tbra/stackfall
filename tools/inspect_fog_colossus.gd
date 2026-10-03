extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/fog_colossus_v1/fog_colossus_v1.glb")
	if packed == null:
		push_error("Fog colossus GLB did not import")
		quit(1)
		return
	var instance := packed.instantiate()
	var player := _find_player(instance)
	if player == null or not player.has_animation("drift_and_sway_12s"):
		push_error("Coordinated loop missing")
		instance.free()
		quit(1)
		return
	var animation := player.get_animation("drift_and_sway_12s")
	print("Imported loop: %.2fs, %d tracks" % [animation.length, animation.get_track_count()])
	if animation.length < 11.9 or animation.length > 12.1 or animation.get_track_count() < 10:
		push_error("Loop duration or track count unexpected")
		instance.free()
		quit(1)
		return
	var moving_positions := 0
	var moving_rotations := 0
	for track: int in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_POSITION_3D:
			var start := animation.position_track_interpolate(track, 0.0)
			var midpoint := animation.position_track_interpolate(track, 6.0)
			if start.distance_to(midpoint) > 0.1:
				moving_positions += 1
		elif animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var start := animation.rotation_track_interpolate(track, 0.0)
			var midpoint := animation.rotation_track_interpolate(track, 6.0)
			if start.angle_to(midpoint) > 0.01:
				moving_rotations += 1
	print("Motion check: %d moving position tracks, %d moving rotation tracks" % [moving_positions, moving_rotations])
	if moving_positions < 1 or moving_rotations < 6:
		push_error("Loop lacks coordinated root and limb motion")
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
