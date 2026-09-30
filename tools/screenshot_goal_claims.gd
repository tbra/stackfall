extends Node
## Bontago-470.7 visual probe: four goal beacons staged neutral / claimed by
## team 0 (with a capture ring) / claimed by team 1 / contested, shot from an
## overview camera and a player-distance camera.
## Run off-screen: godot --path . --position 10000,10000 tools/screenshot_goal_claims.tscn --quit-after 400

const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const OVERVIEW_HEIGHT_M: float = 45.0
const OVERVIEW_BACK_M: float = 30.0
const PLAYER_DISTANCE_M: float = 9.0
const PLAYER_PITCH_DEG: float = -35.0
const SETTLE_FRAMES: int = 60
const CAPTURE_PROGRESS: float = 0.6


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)

	var field: Field = main.get_node("Field") as Field
	if Events.territory_updated.is_connected(field._on_territory_updated_for_goals):
		Events.territory_updated.disconnect(field._on_territory_updated_for_goals)
	var colors: PackedColorArray = MatchConfig.default_player_colors()
	field.place_flags(2, colors, 4)
	var flags: Array[GoalFlag] = field.goal_flags()
	flags[1].set_control(0, colors[0], PackedColorArray())
	flags[2].set_control(1, colors[1], PackedColorArray())
	flags[3].set_control(GoalControl.CONTESTED, Color.WHITE, PackedColorArray([colors[0], colors[1]]))
	flags[1].set_capture(0, CAPTURE_PROGRESS, colors[0])
	await _wait(SETTLE_FRAMES)

	await _shoot("goalclaim_overview_flash.png", _overview(), field)
	await _wait(120)
	await _shoot("goalclaim_overview.png", _overview(), field)
	for i: int in range(4):
		await _shoot("goalclaim_player_%d.png" % i, _player_view(flags[i].global_position), field)
	get_tree().quit()


func _overview() -> Transform3D:
	var pos: Vector3 = Vector3(0.0, OVERVIEW_HEIGHT_M, OVERVIEW_BACK_M)
	return Transform3D(Basis(), pos).looking_at(Vector3.ZERO, Vector3.UP)


func _player_view(target: Vector3) -> Transform3D:
	var pitch: float = deg_to_rad(PLAYER_PITCH_DEG)
	var offset: Vector3 = Vector3(0.0, -sin(pitch), cos(pitch)) * PLAYER_DISTANCE_M
	var focus: Vector3 = target + Vector3.UP * 1.5
	return Transform3D(Basis(), focus + offset).looking_at(focus, Vector3.UP)


func _shoot(file_name: String, xform: Transform3D, field: Field) -> void:
	var source: Camera3D = get_viewport().get_camera_3d()
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.world_3d = get_viewport().world_3d
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var camera: Camera3D = Camera3D.new()
	camera.fov = source.fov
	camera.near = source.near
	camera.far = source.far
	camera.environment = source.environment
	sub.add_child(camera)
	add_child(sub)
	camera.global_transform = xform
	camera.current = true
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	var path: String = "user://" + file_name
	image.save_png(path)
	print("SCREENSHOT goalclaim saved=%s" % ProjectSettings.globalize_path(path))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
