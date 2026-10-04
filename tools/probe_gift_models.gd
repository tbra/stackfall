extends Node
## Bontago-mp0.119 probe: crate, opened reveal, held-gift models and a 1x1
## block for scale in one off-screen capture.
const SPECIALS: Array[StringName] = [&"anvil", &"bomb", &"cat", &"rocket", &"magnet", &"volcano"]
const SPACING: float = 1.5

func _ready() -> void:
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1600, 400))
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	viewport.add_child(light)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.27, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.85, 0.9)
	viewport.add_child(env)
	var table: GiftModelTable = GiftModelTable.shared()
	var items: Array[Node3D] = []
	var block: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3.ONE
	block.mesh = box
	items.append(block)
	var crate: Node3D = table.build_crate_visual()
	crate.position.y = 0.3
	items.append(crate)
	var reveal: Node3D = table.build_reveal_visual()
	reveal.position.y = 0.3
	items.append(reveal)
	for id: StringName in SPECIALS:
		items.append(table.build_gift_visual(id, id == &"cat"))
	var count: int = items.size()
	for i: int in range(count):
		items[i].position.x += (float(i) - float(count - 1) * 0.5) * SPACING
		viewport.add_child(items[i])
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(count) * SPACING * 0.25 + 0.2
	camera.position = Vector3(2.0, 2.0, 6.0)
	viewport.add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0))
	var player: AnimationPlayer = GiftModelTable._player_of(reveal)
	if player != null:
		player.seek(1.0, true)
	for _f: int in range(4):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var out_dir: String = OS.get_environment("TEMP").path_join("captures").path_join("gift_models")
	DirAccess.make_dir_recursive_absolute(out_dir)
	ContactSheet.save_capture(viewport.get_texture().get_image(), out_dir.path_join("mp0_119_sheet.png"))
	get_tree().quit()
