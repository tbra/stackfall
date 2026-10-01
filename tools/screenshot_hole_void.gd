extends Node
## Bontago-1pi.11.42 evidence probe: a hole patch on the disc plus blocks at
## 0 / 40 / 75 % dissolve. Standalone (no match): a TerritoryOverlay fed a
## raster with forced holes, frozen blocks, one sun. Probe args:
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/screenshot_hole_void.tscn -- --agent-probe --render-size=1280x720

const OUTPUT_DIR: String = "res://feedback/"
const CUBE: BlockShape = preload("res://config/blocks/cube.tres")
const PHYSICS: PhysicsTuning = preload("res://config/physics_tuning.tres")
const SIDE_M: float = 24.0
const HOLE_CELLS: Array[Vector2i] = [
	Vector2i(10, 12), Vector2i(11, 12), Vector2i(12, 12), Vector2i(11, 13), Vector2i(12, 13), Vector2i(11, 11),
]
const AMOUNTS: Array[float] = [0.0, 0.4, 0.75]

var _overlay: TerritoryOverlay = null
var _cam: Camera3D = null


func _ready() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = SIDE_M * 0.5
	map_def.cell_size = 1.0
	map_def.territory_res = 240
	var tuning: TerritoryTuning = load("res://config/territory_tuning.tres")
	_overlay = TerritoryOverlay.new()
	_overlay.configure(map_def, load("res://config/territory_visuals.tres"), tuning)
	var vp: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	vp.add_child(_overlay)
	var grid: CellGrid = CellGrid.new(map_def.field_radius, map_def.cell_size)
	var raster: TerritoryRaster = TerritoryRaster.new(grid, tuning)
	for cell: Vector2i in HOLE_CELLS:
		raster.force_hole_cell(cell.x, cell.y, 1.0, true)
	_overlay.set_source(raster, PackedColorArray())
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	vp.add_child(sun)
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.5, 0.6, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.8)
	vp.add_child(env)
	_cam = Camera3D.new()
	vp.add_child(_cam)
	# Cell (cx, cy) centre in disk-local coordinates.
	var centre: Vector3 = Vector3(11.0 + 0.5 - 12.0 + 0.5, 0.0, 12.0 + 0.5 - 12.0 - 0.5)
	var top: float = map_def.disk_height * 0.5
	_cam.look_at_from_position(centre + Vector3(0.0, 3.2, 3.6), centre + Vector3(0.0, 0.0, -0.3))
	for index: int in range(AMOUNTS.size()):
		var block: Block = BlockFactory.build(CUBE, PHYSICS, -1, Color(0.9, 0.35, 0.3))
		block.freeze = true
		vp.add_child(block)
		block.global_position = centre + Vector3(-2.6 + 1.6 * float(index), top + 0.5 * PHYSICS.cube_size, 1.6)
		for child: Node in block.get_children():
			if child is MeshInstance3D:
				(child as MeshInstance3D).set_instance_shader_parameter(&"dissolve_amount", AMOUNTS[index])
	for _i: int in range(20):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = vp.get_texture().get_image()
	ContactSheet.save_capture(image, OUTPUT_DIR + "hole_void_a.png")
	print("SCREENSHOT hole_void saved size=%s" % image.get_size())
	get_tree().quit()
