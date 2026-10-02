extends Node
## Bontago-59o.6: gust swoosh probe. Renders one gust on a flat blue backdrop in an
## off-screen SubViewport and saves frames at a few times into user://:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_gust_swoosh.tscn -- --agent-probe --render-size=1280x720
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const SHOT_TIMES_S: Array[float] = [0.9, 1.5, 2.4]
const BACKDROP: Color = Color(0.33, 0.66, 0.96)


func _ready() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = CAPTURE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKDROP
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0.0, 0.0, 9.0)
	var presenter: BreezePresenter = BreezePresenter.new()
	viewport.add_child(presenter)
	var gust: Dictionary = {"id": 3, "x": 0.0, "y": 0.0, "z": 0.0, "a": 0.0, "r": 3.2, "d": 8.0}
	Events.breeze_gust_started.emit(gust)
	var elapsed: float = 0.0
	for shot: int in range(SHOT_TIMES_S.size()):
		while elapsed < SHOT_TIMES_S[shot]:
			await get_tree().process_frame
			elapsed += get_process_delta_time()
		await RenderingServer.frame_post_draw
		var path: String = "user://gust_swoosh_%d.png" % shot
		viewport.get_texture().get_image().save_png(path)
		print("SHOT ", ProjectSettings.globalize_path(path), " t=", elapsed)
	get_tree().quit()
