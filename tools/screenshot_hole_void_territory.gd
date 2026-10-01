extends Node
## Bontago-1pi.11.44 evidence probe: two overlapping team territories with an
## active void on the overlap, seen from a match-like camera. Standalone (no
## match): the hole raster is derived from the circle overlap and pushed
## straight into the overlay. Probe args:
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/screenshot_hole_void_territory.tscn -- --agent-probe --render-size=1280x720

const OUTPUT_DIR: String = "res://feedback/"
const SIDE_M: float = 40.0
const CIRCLE_CENTRES: Array[Vector2] = [Vector2(-3.4, 0.0), Vector2(3.4, 0.5)]
const CIRCLE_RADIUS: float = 6.5
const TEAM_COLORS: Array[Color] = [Color(0.9, 0.3, 0.25), Color(0.25, 0.5, 0.95)]
const CAMERA_OFFSET: Vector3 = Vector3(0.0, 11.0, 12.0)

var _overlay: TerritoryOverlay = null


func _ready() -> void:
	var map_def: MapDef = MapDef.new()
	map_def.field_radius = SIDE_M * 0.5
	map_def.cell_size = 1.0
	map_def.territory_res = 400
	_overlay = TerritoryOverlay.new()
	_overlay.configure(map_def, load("res://config/territory_visuals.tres"), load("res://config/territory_tuning.tres"))
	var vp: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	vp.add_child(_overlay)
	var side: int = _overlay.cells_per_side()
	var half: float = float(side) * 0.5
	var state: PackedByteArray = PackedByteArray()
	state.resize(side * side)
	var holes: int = 0
	for cy: int in range(side):
		for cx: int in range(side):
			var p: Vector2 = Vector2(float(cx) + 0.5 - half, float(cy) + 0.5 - half)
			var inside: int = 0
			for c: Vector2 in CIRCLE_CENTRES:
				if p.distance_to(c) <= CIRCLE_RADIUS:
					inside += 1
			if inside == 2:
				state[cy * side + cx] = TerritoryRaster.STATE_CONTESTED | TerritoryRaster.STATE_HOLE
				holes += 1
	_overlay.set_slot_colors(PackedColorArray(TEAM_COLORS))
	_overlay.push_cells(PackedByteArray(), state, side)
	_overlay.set_circles(
		PackedFloat32Array([CIRCLE_CENTRES[0].x, CIRCLE_CENTRES[1].x]),
		PackedFloat32Array([CIRCLE_CENTRES[0].y, CIRCLE_CENTRES[1].y]),
		PackedFloat32Array([CIRCLE_RADIUS, CIRCLE_RADIUS]),
		PackedInt32Array([0, 1]),
		PackedVector2Array(), PackedFloat32Array(), false
	)
	print("hole cells=%d" % holes)
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
	var cam: Camera3D = Camera3D.new()
	vp.add_child(cam)
	cam.look_at_from_position(CAMERA_OFFSET, Vector3(0.0, 0.0, 0.5))
	for _i: int in range(30):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = vp.get_texture().get_image()
	ContactSheet.save_capture(image, OUTPUT_DIR + "hole_void_territory_a3.png")
	print("SCREENSHOT hole_void_territory saved size=%s" % image.get_size())
	get_tree().quit()
