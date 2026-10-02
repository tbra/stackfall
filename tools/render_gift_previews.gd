extends SceneTree
## Build-time only: godot --path . --windowed --position 10000,10000
## -s tools/render_gift_previews.gd. Bakes each gift's held_scene to
## assets/ui/gift_previews/<id>.png, same camera/lighting style and size as
## render_block_previews.gd but keeping the model colours.
const OUTPUT: String = "res://assets/ui/gift_previews/"
const RESOLUTION: int = 384
const FRAME_FRACTION: float = 0.80
const GIFT_IDS: Array[StringName] = [
	&"anvil", &"bomb", &"cat", &"earthquake", &"freeze", &"glue", &"jumping_bean",
	&"magnet", &"paintball", &"propeller", &"rocket", &"stackfall", &"volcano",
]
const LIGHT_ENERGY: float = 1.0
const AMBIENT_ENERGY: float = 0.6

func _initialize() -> void:
	call_deferred("_render_all")

func _render_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(RESOLUTION, RESOLUTION)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.TRANSPARENT
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = AMBIENT_ENERGY
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = LIGHT_ENERGY
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(8.0, 6.0, 8.0)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	for id: StringName in GIFT_IDS:
		var def: SpecialDef = SpecialDef.find_by_id(id)
		if def == null or def.held_scene == null:
			push_error("No held_scene for %s" % id)
			quit(1)
			return
		var visual: Node3D = def.held_scene.instantiate() as Node3D
		viewport.add_child(visual)
		var minimum: Vector2 = Vector2.INF
		var maximum: Vector2 = -Vector2.INF
		for node: Node in visual.find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			var bounds: AABB = mesh.global_transform * mesh.get_aabb()
			for index: int in range(8):
				var corner: Vector3 = bounds.get_endpoint(index)
				var projected: Vector2 = Vector2(camera.basis.x.dot(corner), camera.basis.y.dot(corner))
				minimum = minimum.min(projected)
				maximum = maximum.max(projected)
		var middle: Vector2 = (minimum + maximum) * 0.5
		camera.position = camera.basis.z * 20.0 + camera.basis.x * middle.x + camera.basis.y * middle.y
		camera.size = maxf(maximum.x - minimum.x, maximum.y - minimum.y) / FRAME_FRACTION
		for frame: int in range(3):
			await process_frame
			await RenderingServer.frame_post_draw
		var image: Image = viewport.get_texture().get_image()
		var error: Error = image.save_png(OUTPUT + String(id) + ".png")
		if error != OK:
			push_error("Preview save failed: %s (%s)" % [id, error])
			quit(1)
			return
		print("PREVIEW_RENDERED ", id)
		visual.queue_free()
		await process_frame
	quit()
