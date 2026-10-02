extends Node
## Bontago-8or.26: one capture of the black hole vortex. User arg `preset=high|low`.
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_black_hole.tscn -- --agent-probe --render-size=1280x720
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const CAPTURE_AGE_S: float = 1.5
const LIFETIME_S: float = 5.0
const CORE_RADIUS_M: float = 0.7
const CAMERA_POSITION: Vector3 = Vector3(0.0, 7.0, 9.0)
const GROUND_SIZE: float = 30.0
const GROUND_COLOR: Color = Color(0.45, 0.62, 0.4)
const BLOCK_SIZE: float = 0.8


func _ready() -> void:
	var preset: StringName = &"high"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("preset="):
			preset = StringName(arg.trim_prefix("preset="))
	Settings.set_graphics_preset(preset)
	var sub: SubViewport = SubViewport.new()
	sub.size = CAPTURE_SIZE
	sub.own_world_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.6, 0.78, 0.95)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	sub.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sub.add_child(light)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	ground.mesh = plane
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = GROUND_COLOR
	ground.material_override = ground_material
	sub.add_child(ground)
	for offset: Vector3 in [Vector3(3.5, 0.4, 1.0), Vector3(-4.0, 0.4, -2.0), Vector3(1.0, 0.4, 4.0)]:
		var cube: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3.ONE * BLOCK_SIZE
		cube.mesh = box
		cube.position = offset
		sub.add_child(cube)
	var camera: Camera3D = Camera3D.new()
	sub.add_child(camera)
	camera.position = CAMERA_POSITION
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var visual: BlackHoleVisual = BlackHoleVisual.new()
	sub.add_child(visual)
	visual.setup(CORE_RADIUS_M, LIFETIME_S)
	var elapsed: float = 0.0
	while elapsed < CAPTURE_AGE_S:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	var path: String = "user://black_hole_%s.png" % preset
	image.save_png(path)
	print("BH saved=%s size=%s" % [ProjectSettings.globalize_path(path), image.get_size()])
	get_tree().quit()
