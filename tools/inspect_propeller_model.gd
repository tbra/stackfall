extends SceneTree


func _initialize() -> void:
	var packed: PackedScene = load("res://assets/models/propeller_v1/propeller_v1.glb")
	if packed == null:
		push_error("Propeller GLB import failed")
		quit(1)
		return
	var instance := packed.instantiate()
	var player := _find_player(instance)
	if player == null or not player.has_animation("spin_1s"):
		push_error("spin_1s clip missing")
		instance.free()
		quit(1)
		return
	var animation := player.get_animation("spin_1s")
	print("Imported propeller loop: %.2fs, %d tracks" % [animation.length, animation.get_track_count()])
	var rotated := false
	for track in animation.get_track_count():
		if animation.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			var start := animation.rotation_track_interpolate(track, 0.0)
			var quarter := animation.rotation_track_interpolate(track, 0.25)
			var half := animation.rotation_track_interpolate(track, 0.5)
			rotated = start.angle_to(quarter) > 0.5 and start.angle_to(half) > 1.0
	if animation.length < 0.9 or animation.length > 1.1 or not rotated:
		push_error("Rotor motion did not survive import")
		instance.free()
		quit(1)
		return
	print("Rotor rotates across quarter and half loop")
	instance.free()
	quit()


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
