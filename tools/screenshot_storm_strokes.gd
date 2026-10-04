extends Node
## Bontago-mp0.131: stroke draw-on / draw-off probe. A bare StormPresentation under a
## dark sky, captured a few times 0.3 s apart so strokes show mid-draw-on and mid-draw-off:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_storm_strokes.tscn -- --agent-probe
## Saves PNGs under res://scratch/ (not committed).
const OUTPUT_DIR: String = "res://scratch/"
const RENDER_SIZE: Vector2i = Vector2i(1280, 720)
const FRAMES: int = 4
const STEP_S: float = 0.3
const WARMUP_S: float = 2.0
const CAMERA_POS: Vector3 = Vector3(0.0, 14.0, 70.0)
const CAMERA_TARGET: Vector3 = Vector3(0.0, 14.0, 0.0)
const SKY_COLOR: Color = Color(0.12, 0.16, 0.24)
const STORM_SEED: int = 11


func _ready() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = RENDER_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_COLOR
	var world_env: WorldEnvironment = WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var camera: Camera3D = Camera3D.new()
	viewport.add_child(camera)
	camera.position = CAMERA_POS
	camera.look_at(CAMERA_TARGET)
	var storm: StormPresentation = StormPresentation.new()
	viewport.add_child(storm)
	storm.configure(STORM_SEED)
	storm.set_intensity(1.0)
	await get_tree().create_timer(WARMUP_S).timeout
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	for i: int in range(FRAMES):
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var path: String = ProjectSettings.globalize_path(OUTPUT_DIR + "storm_strokes_%d.png" % i)
		print("STORM_STROKES saved ", path, " err=", image.save_png(path))
		await get_tree().create_timer(STEP_S).timeout
	get_tree().quit()
