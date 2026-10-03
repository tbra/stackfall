extends Node
## Asset capture only. Real arena renderer; no changes to live loading UI.
const OUT: String = "res://assets/ui/loading_arena_v1/"

func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1920, 1080))
	var main: Node3D = (load("res://game/Main.tscn") as PackedScene).instantiate() as Node3D
	viewport.add_child(main)
	await get_tree().process_frame
	main.call("_start_sandbox_match_with_args", PackedStringArray(["sandbox", "players=4"]))
	for i: int in range(60):
		await get_tree().physics_frame
	for control: Node in main.find_children("*", "Control", true, false):
		(control as Control).visible = false
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		if layer.name != "SunFlare":
			(layer as CanvasLayer).visible = false
	for ghost: Node in main.find_children("*", "GhostPreview", true, false):
		(ghost as Node3D).visible = false
	var rig: CameraRig = main.get_node("CameraRig") as CameraRig
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_camera()
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera.fov = 50.0
	camera.global_position = Vector3(85, 65, 90)
	camera.look_at(Vector3(-10, 27, 8))
	camera.current = true
	_spawn_stacks(main)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var sky: Skybox = main.get_node("Skybox") as Skybox
	for theme: String in ["sunset", "night", "dawn"]:
		sky.set_theme_by_id(theme)
		for i: int in range(30):
			await get_tree().physics_frame
		await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var error: Error = image.save_png(OUT + "arena_%s.png" % theme)
		if error != OK:
			push_error("Loading arena PNG save failed: %s" % error)
			get_tree().quit(1)
			return
		print("LOADING ARENA CAPTURE ", theme, " ", image.get_size())
	await _capture_loading_composition(viewport)
	Match.abort_match()
	for i: int in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	viewport.queue_free()
	for i: int in range(10):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	get_tree().quit()

func _capture_loading_composition(viewport: SubViewport) -> void:
	viewport.size = Vector2i(1280, 720)
	var screen: LoadingScreen = (load("res://ui/LoadingScreen.tscn") as PackedScene).instantiate() as LoadingScreen
	viewport.add_child(screen)
	var content: Control = screen.get_node("Layer/Content") as Control
	var background: TextureRect = TextureRect.new()
	background.texture = ImageTexture.create_from_image(Image.load_from_file(OUT + "arena_sunset.png"))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(background)
	content.move_child(background, 0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	(screen.get_node("Layer/Content/Background") as ColorRect).color = Color(0.06, 0.07, 0.09, 0.58)
	var slots: Array[PlayerSlot] = []
	for i: int in range(Match.slot_count()):
		slots.append(Match.slot(i))
	screen.show_for_match(Match.config, slots)
	screen.set_stage("Preparing arena", 0.65)
	for i: int in range(5):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://docs/art_mockups/loading_arena_v1/loading_composition.png"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	viewport.get_texture().get_image().save_png(path)
	print("LOADING COMPOSITION CAPTURE ", viewport.size)
	screen.cancel()
	screen.queue_free()
	for i: int in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw

func _spawn_stacks(main: Node3D) -> void:
	var shapes: Array[BlockShape] = [
		load("res://config/blocks/cube.tres") as BlockShape,
		load("res://config/blocks/domino.tres") as BlockShape,
	]
	var tuning: PhysicsTuning = Match.get("_physics_tuning") as PhysicsTuning
	var colors: Array[Color] = [Color("eb6b5c"), Color("75cbd1"), Color("e8b85d"), Color("a596d5")]
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	for slot: int in range(4):
		var angle: float = TAU * float(slot) / 4.0 + 0.4
		var center: Vector3 = Vector3(cos(angle) * 24, 0, sin(angle) * 24)
		for level: int in range(7):
			var block: Block = BlockFactory.build(shapes[level % 2], tuning, slot, colors[slot])
			container.add_child(block)
			block.freeze = true
			block.global_position = center + Vector3(float(level % 2) * tuning.cube_size * 0.2, tuning.cube_size * (0.5 + level), 0)
			block.rotation.y = float(level % 2) * PI / 2.0
