extends Node
## Bontago-22y.6: snow capture. Boots the real Main.tscn sandbox, builds a few
## towers, starts a snow event with fast growth, and shoots light buildup and
## heavy buildup on towers and disc. Off-screen SubViewport capture only:
##   godot --path . --windowed --position 10000,10000 tools/screenshot_weather_snow.tscn
const OUTPUT_DIR: String = "user://"
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const FAST_SECONDS_PER_LEVEL: float = 1.5
const TOWERS: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(3.0, 0.0, 1.0), Vector3(-2.5, 0.0, 2.5), Vector3(1.5, 0.0, -3.0)]
const CLIP_LEVEL: float = 0.98
const CLIP_SAMPLE_STEP: int = 4
var _main: Node = null
var _view: Transform3D = Transform3D.IDENTITY


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main._start_sandbox_match_with_args(PackedStringArray(["sandbox", "players=2"]))
	await _wait(90)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres") as PhysicsTuning
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var parent: Node3D = Match.blocks_parent()
	var index: int = 0
	for base: Vector3 in TOWERS:
		for level: int in range(3 + index % 3):
			var shape: BlockShape = shapes[(index * 3 + level) % shapes.size()]
			var block: Block = BlockFactory.build(shape, tuning, index % 2, Color(0.9, 0.25, 0.2) if index % 2 == 0 else Color(0.2, 0.45, 0.95))
			parent.add_child(block)
			block.global_position = base + Vector3(0.0, 0.2 + float(level) * 2.2, 0.0)
			Events.block_placed.emit(block, shape.id)
			await _wait(45)
		index += 1
	await _wait(180)
	# Snow off, for a side-by-side with the snowy player views.
	var field_off: Field = Match.field()
	var home_off: Vector3 = field_off.world_from_disk_local(field_off.home_flag_position(0, 2), 0.0)
	await _shoot_player_view("snow_r5_off_2_player_view.png", home_off)
	_aim(Vector3.ZERO, 40.0, -40.0, 0.2)
	await _shoot("snow_r5_off_1_disc_wide.png")
	var snow: SnowTuning = load("res://config/weather/snow.tres") as SnowTuning
	snow.seconds_per_level = FAST_SECONDS_PER_LEVEL
	snow.ramp_in_s = 0.5
	print("SNOWSHOT start_event=%s blocks=%d" % [Match.weather().start_event(&"snow"), Match.registry().tracked_block_count()])
	await _wait(int(FAST_SECONDS_PER_LEVEL * 60.0 * 1.3))
	var field: Field = Match.field()
	var home: Vector2 = field.home_flag_position(0, 2)
	var home_world: Vector3 = field.world_from_disk_local(home, 0.0)
	await _shoot_set("light", home_world)
	await _wait(int(FAST_SECONDS_PER_LEVEL * 60.0 * 5.0))
	await _shoot_set("heavy", home_world)
	get_tree().quit()


## Disc wide, player view from home toward the towers (territory), towers.
func _shoot_set(tag: String, home_world: Vector3) -> void:
	_aim(Vector3.ZERO, 40.0, -40.0, 0.2)
	await _shoot("snow_r5_%s_1_disc_wide.png" % tag)
	await _shoot_player_view("snow_r5_%s_2_player_view.png" % tag, home_world)
	_aim(Vector3(0.3, 1.5, 0.0), 11.0, -30.0, 0.5)
	await _shoot("snow_r5_%s_3_towers.png" % tag)


func _shoot_player_view(file_name: String, home_world: Vector3) -> void:
	var toward: Vector3 = (Vector3.ZERO - home_world).normalized()
	var eye: Vector3 = home_world - toward * 4.0 + Vector3(0.0, 7.0, 0.0)
	_view = Transform3D(Basis.IDENTITY, eye).looking_at(home_world + toward * 14.0, Vector3.UP)
	await _shoot(file_name)


func _aim(target: Vector3, distance: float, pitch_deg: float, yaw: float) -> void:
	var elevation: float = deg_to_rad(-pitch_deg)
	var offset: Vector3 = Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * distance
	_view = Transform3D(Basis.IDENTITY, target + offset).looking_at(target, Vector3.UP)


func _shoot(file_name: String) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
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
	camera.global_transform = _view
	camera.current = true
	for _i: int in range(3):
		await RenderingServer.frame_post_draw
	var image: Image = sub.get_texture().get_image()
	sub.queue_free()
	var path: String = OUTPUT_DIR + file_name
	image.save_png(path)
	print("SCREENSHOT snow saved=%s clipped=%.4f %s" % [ProjectSettings.globalize_path(path), _clipped_fraction(image), _live_snow_uniforms()])


## The disc material's live snow uniforms (what the shader actually uses).
func _live_snow_uniforms() -> String:
	var field: Field = Match.field()
	var material: ShaderMaterial = field.overlay().material() if field != null and field.overlay() != null else null
	if material == null:
		return "disc_material=none"
	var out: PackedStringArray = PackedStringArray()
	for key: StringName in [&"snow_strength", &"snow_threshold", &"snow_seam_bias", &"snow_softness", &"snow_edge_soft", &"snow_light_gain"]:
		out.append("%s=%s" % [key, material.get_shader_parameter(key)])
	return " ".join(out)


## Share of pixels with every channel at or above CLIP_LEVEL (blown out).
func _clipped_fraction(image: Image) -> float:
	var clipped: int = 0
	var total: int = 0
	for y: int in range(0, image.get_height(), CLIP_SAMPLE_STEP):
		for x: int in range(0, image.get_width(), CLIP_SAMPLE_STEP):
			var c: Color = image.get_pixel(x, y)
			total += 1
			if c.r >= CLIP_LEVEL and c.g >= CLIP_LEVEL and c.b >= CLIP_LEVEL:
				clipped += 1
	return float(clipped) / float(maxi(total, 1))


func _wait(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().physics_frame
