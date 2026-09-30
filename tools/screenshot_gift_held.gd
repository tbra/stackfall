extends Node
## Bontago-59o.14.1 contact sheet: every gift's held model in a row with the
## block ghost tint off-screen capture. Usage: --windowed --position 10000,10000
## -- (see CLAUDE.md); quits right after saving.

const OUTPUT_PATH: String = "user://gift_held_sheet.png"
const SPACING: float = 1.6
const CAMERA_HEIGHT: float = 3.0
const CAMERA_DISTANCE: float = 9.0
const CAMERA_FOV: float = 55.0
const ROW_COUNT: int = 2
const WINDOW_SIZE: Vector2i = Vector2i(1400, 600)


func _ready() -> void:
	get_window().size = WINDOW_SIZE
	var ids: Array[StringName] = [
		&"anvil", &"bomb", &"cat", &"earthquake", &"glue", &"jumping_bean",
		&"magnet", &"paintball", &"propeller", &"rocket", &"stackfall", &"volcano",
	]
	var per_row: int = ids.size() / ROW_COUNT
	for index: int in ids.size():
		var def: SpecialDef = SpecialDef.find_by_id(ids[index])
		var model: Node3D = def.held_scene.instantiate() as Node3D
		var column: int = index % per_row
		var row: int = index / per_row
		model.position = Vector3((column - (per_row - 1) * 0.5) * SPACING, -row * SPACING, 0.0)
		add_child(model)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	add_child(light)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.65, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var camera: Camera3D = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.position = Vector3(0.0, -SPACING * 0.5, CAMERA_DISTANCE)
	add_child(camera)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(OUTPUT_PATH)
	print("saved ", ProjectSettings.globalize_path(OUTPUT_PATH))
	get_tree().quit()
