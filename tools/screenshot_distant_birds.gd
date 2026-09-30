extends Node3D
## Bontago-59o.7 probe: one DistantBirds flock over a plain sky, shot at a
## gameplay-like distance. Saves user://distant_birds_<arg>.png (arg after --).
##   godot --path . --windowed --position 10000,10000 tools/screenshot_distant_birds.tscn -- before
const SUNSET: SkyThemeDef = preload("res://config/sky_themes/sunset.tres")
const SIZE: Vector2i = Vector2i(1280, 720)
const CAMERA_HEIGHT_M: float = 20.0
const CAMERA_FOV_DEG: float = 25.0
const SETTLE_S: float = 8.0
const STEP_S: float = 0.25
const FLAP_FRAMES: int = 3


func _ready() -> void:
	var tag: String = "shot"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		tag = args[0]
	var viewport: SubViewport = SubViewport.new()
	viewport.size = SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.95, 0.72, 0.6)
	env_node.environment = environment
	viewport.add_child(env_node)
	var birds: DistantBirds = DistantBirds.new()
	viewport.add_child(birds)
	var theme: SkyThemeDef = SUNSET.duplicate() as SkyThemeDef
	theme.bird_single_chance = 0.0
	theme.bird_flock_size_min = 5
	theme.bird_flock_size_max = 5
	birds.configure(theme, true)
	birds.launch_now(0)
	var flight: FlockPlanner.Flight = birds.flight_of(0)
	var t: float = flight.duration_s * 0.5
	birds.advance(t)
	var focus: Vector3 = flight.start + flight.velocity * t
	var camera: Camera3D = Camera3D.new()
	camera.far = 4000.0
	viewport.add_child(camera)
	camera.fov = CAMERA_FOV_DEG
	camera.look_at_from_position(Vector3(0.0, CAMERA_HEIGHT_M, 0.0), focus)
	camera.current = true
	for _i: int in range(FLAP_FRAMES):
		birds.advance(STEP_S)
		await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png("user://distant_birds_%s.png" % tag)
	print("SAVED ", ProjectSettings.globalize_path("user://distant_birds_%s.png" % tag), " dist=", focus.length())
	get_tree().quit()
