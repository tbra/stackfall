extends Node3D
## Windowed smoke-shot for Bontago-xtq.5 (owner screenshot,
## docs/solid-blocks-issue.png: placed blocks render inside-out, looking
## hollow -- the translucent ghost material happened to mask it because its
## material has culling off). Unlike tools/screenshot_xtq3_solid_blocks.gd
## (which drives a full sandbox match through physics), this probes
## core/blocks/BlockMeshBuilder.gd directly with one opaque, default
## (cull_back) StandardMaterial3D MeshInstance3D per shipped BlockShape, no
## RigidBody3D/collision/Match involved -- if a face is wound backwards,
## backface culling on an opaque material removes it and the shape reads as
## hollow/missing faces exactly like the owner's report, independent of any
## other system's behaviour.
##
## Run windowed (a real render is required for the screenshot):
##   godot --path . --scene res://tools/screenshot_solid_blocks_xtq5.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game).

const OUTPUT_PATH: String = "res://docs/solid-blocks-fixed.png"
const SETTLE_FRAMES: int = 2
const ROW_GAP: float = 1.0

var _tuning: PhysicsTuning = preload("res://config/physics_tuning.tres")


func _ready() -> void:
	_add_light_and_environment()
	var camera: Camera3D = _add_camera()

	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var cursor_x: float = 0.0
	var min_x: float = 0.0
	var max_x: float = 0.0
	for shape: BlockShape in shapes:
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = Color(0.75, 0.65, 0.25)
		# Default cull_mode (CULL_BACK): the exact condition that hides a
		# backwards-wound face -- the owner's ghost material has culling off,
		# which is why the ghost never showed this bug.
		var mesh: ArrayMesh = BlockMeshBuilder.build_mesh(shape, _tuning.cube_size, _tuning.cube_margin)
		var mesh_instance: MeshInstance3D = MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.material_override = material

		var extent: Vector3 = _cell_extent(shape)
		var half_width: float = extent.x * _tuning.cube_size * 0.5
		var x: float = cursor_x + half_width
		mesh_instance.position = Vector3(x, 0.0, 0.0)
		add_child(mesh_instance)

		cursor_x = x + half_width + ROW_GAP
		min_x = minf(min_x, x - half_width)
		max_x = maxf(max_x, x + half_width)

	await get_tree().process_frame
	await get_tree().process_frame

	var center_x: float = (min_x + max_x) * 0.5
	# Low, to-the-side angle so both a near vertical face and a top face are
	# visible on every shape -- a face-on or top-down shot could still look
	# right even with every side face missing.
	camera.global_position = Vector3(center_x - 3.0, 1.5, 6.0)
	camera.look_at(Vector3(center_x, 0.5, 0.0), Vector3.UP)

	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame

	await _shoot()
	get_tree().quit()


func _cell_extent(shape: BlockShape) -> Vector3:
	if shape.cells.is_empty():
		return Vector3.ONE
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF
	for cell: Vector3i in shape.cells:
		min_x = minf(min_x, float(cell.x))
		max_x = maxf(max_x, float(cell.x))
		min_z = minf(min_z, float(cell.z))
		max_z = maxf(max_z, float(cell.z))
	return Vector3(max_x - min_x + 1.0, 1.0, max_z - min_z + 1.0)


func _add_light_and_environment() -> void:
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.15, 0.15, 0.18)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.35, 0.35, 0.35)
	world_environment.environment = environment
	add_child(world_environment)

	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.2
	add_child(light)


func _add_camera() -> Camera3D:
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.current = true
	return camera


func _shoot() -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	var path: String = OUTPUT_PATH
	image.save_png(path)
	print("SCREENSHOT solid_blocks_xtq5 saved=%s" % ProjectSettings.globalize_path(path))
