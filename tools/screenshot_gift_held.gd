extends Node
## Individual 320 px model tiles plus baked HUD icons in one probe contact sheet.
const IDS: Array[StringName] = [&"anvil", &"bomb", &"cat", &"earthquake", &"freeze", &"glue", &"jumping_bean", &"magnet", &"paintball", &"propeller", &"rocket", &"stackfall", &"volcano"]
const TILE_SIZE: int = 320
const CAPTURE_SIDE: int = 720

func _ready() -> void:
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	viewport.add_child(light)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.2, 0.27, 0.34)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	viewport.add_child(environment)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.24
	camera.position = Vector3(1.6, 1.25, 3.5)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var canvas: CanvasLayer = CanvasLayer.new()
	viewport.add_child(canvas)
	var icon: TextureRect = TextureRect.new()
	icon.position = Vector2(805.0, 500.0)
	icon.size = Vector2(150.0, 150.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	canvas.add_child(icon)
	var label: Label = Label.new()
	label.position = Vector2(325.0, 610.0)
	label.add_theme_font_size_override("font_size", 42)
	canvas.add_child(label)
	var output_dir: String = OS.get_environment("TEMP").path_join("captures").path_join("gift_models")
	DirAccess.make_dir_recursive_absolute(output_dir)
	for id: StringName in IDS:
		var def: SpecialDef = SpecialDef.find_by_id(id)
		var model: Node3D = def.held_scene.instantiate() as Node3D
		viewport.add_child(model)
		icon.texture = load("res://assets/ui/gift_previews/%s.png" % id) as Texture2D
		label.text = String(id).replace("_", " ")
		for frame: int in range(3):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var center_x: int = (image.get_width() - CAPTURE_SIDE) / 2
		var tile: Image = image.get_region(Rect2i(center_x, 0, CAPTURE_SIDE, CAPTURE_SIDE))
		tile.resize(TILE_SIZE, TILE_SIZE, Image.INTERPOLATE_LANCZOS)
		var error: Error = ContactSheet.save_capture(tile, output_dir.path_join("%s.png" % id))
		if error != OK:
			push_error("Gift capture failed: %s" % error)
			get_tree().quit(1)
			return
		model.queue_free()
		await get_tree().process_frame
	print("GIFT_CONTACT ", output_dir.path_join("screenshot_gift_held_sheet.png"))
	get_tree().quit()
