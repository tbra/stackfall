extends SceneTree
## Build-time only: godot --path . --windowed --position 10000,10000
## -s tools/render_block_previews.gd. Regenerate after shape/mesh changes.
const OUTPUT: String = "res://assets/ui/block_previews/"
const RESOLUTION: int = 384
const FRAME_FRACTION: float = 0.80

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
	environment.environment.ambient_light_energy = 0.08
	viewport.add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	light.light_energy = 0.22
	viewport.add_child(light)
	var camera: Camera3D = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.position = Vector3(8.0, 6.0, 8.0)
	viewport.add_child(camera)
	camera.look_at(Vector3.ZERO)
	var tuning: PhysicsTuning = load("res://config/physics_tuning.tres")
	var visual_tuning: BlockVisualTuning = load("res://config/block_visual_tuning.tres")
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load("res://shaders/block_cell_grid.gdshader")
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var parameter: StringName = uniform["name"]
		var value: Variant = visual_tuning.get(parameter)
		if value != null:
			material.set_shader_parameter(parameter, value)
	material.set_shader_parameter(&"albedo_color", Color.WHITE)
	var outline_material: ShaderMaterial = ShaderMaterial.new()
	outline_material.shader = load("res://shaders/block_outline.gdshader")
	outline_material.set_shader_parameter(&"tint_color", Color.WHITE)
	for uniform: Dictionary in outline_material.shader.get_shader_uniform_list():
		var parameter: StringName = uniform["name"]
		var value: Variant = visual_tuning.get(parameter)
		if value != null:
			outline_material.set_shader_parameter(parameter, value)
	for shape: BlockShape in BlockShape.load_all_shapes():
		var visual: Node3D = Node3D.new()
		var generated_mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, tuning.cube_size, tuning.cube_margin)
		var body_mesh: MeshInstance3D = MeshInstance3D.new()
		body_mesh.name = "BlockMesh"
		body_mesh.mesh = generated_mesh
		body_mesh.material_override = material
		visual.add_child(body_mesh)
		var outline: MeshInstance3D = MeshInstance3D.new()
		outline.mesh = generated_mesh
		outline.material_override = outline_material
		visual.add_child(outline)
		viewport.add_child(visual)
		var mesh: MeshInstance3D = visual.get_node("BlockMesh")
		var bounds: AABB = mesh.get_aabb()
		var minimum: Vector2 = Vector2.INF
		var maximum: Vector2 = -Vector2.INF
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
		# DECISION: neutral baked lighting + runtime tint supports every player
		# colour without separate assets or a runtime 3D viewport.
		for y: int in range(image.get_height()):
			for x: int in range(image.get_width()):
				var pixel: Color = image.get_pixel(x, y)
				var value: float = pixel.get_luminance()
				image.set_pixel(x, y, Color(value, value, value, pixel.a))
		var error: Error = image.save_png(OUTPUT + String(shape.id) + ".png")
		if error != OK:
			push_error("Preview save failed: %s (%s)" % [shape.id, error])
			quit(1)
			return
		print("PREVIEW_RENDERED ", shape.id)
		visual.queue_free()
		await process_frame
	quit()
