extends Node
## Native art capture only. Build each actual selectable map from match config.
const OUT: String = "res://assets/ui/loading_arena_v2/"
const SHAPES: Array[String] = ["round", "oval", "ring", "twin", "cross"]
const THEMES: Array[String] = ["sunset", "night", "dawn"]

func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var evidence: Array[Dictionary] = []
	for variant: int in range(SHAPES.size()):
		var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1920,1080))
		var main: Node3D = (load("res://game/Main.tscn") as PackedScene).instantiate() as Node3D
		var config: MatchConfig = (main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
		config.map_variant = variant as MatchConfig.MapVariant
		config.map_size = MapDef.MapSize.MEDIUM
		main.set("match_config", config)
		viewport.add_child(main)
		await get_tree().process_frame
		main.call("_start_sandbox_match_with_args", PackedStringArray(["sandbox", "players=4"]))
		for i: int in range(45):
			await get_tree().physics_frame
		var field: Field = main.get_node("Field") as Field
		assert(field.map_def.map_shape == variant, "actual field does not match requested shape")
		for control: Node in main.find_children("*", "Control", true, false):
			(control as Control).visible = false
		for layer: Node in main.find_children("*", "CanvasLayer", true, false):
			(layer as CanvasLayer).visible = false
		for ghost: Node in main.find_children("*", "GhostPreview", true, false):
			(ghost as Node3D).visible = false
		var rig: CameraRig = main.get_node("CameraRig") as CameraRig
		rig.set_process(false)
		rig.set_physics_process(false)
		var camera: Camera3D = rig.get_camera()
		camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		camera.fov = 50.0
		camera.global_position = Vector3(85,65,90)
		camera.look_at(Vector3(-10,27,8))
		camera.current = true
		_spawn_stacks(main, field)
		_capture_shape_geometry(field)
		var sky: Skybox = main.get_node("Skybox") as Skybox
		for theme: String in THEMES:
			assert(sky.set_theme_by_id(theme), "theme missing")
			for i: int in range(20):
				await get_tree().physics_frame
			await RenderingServer.frame_post_draw
			var image: Image = viewport.get_texture().get_image()
			var filename: String = "%s_%s.png" % [SHAPES[variant],theme]
			assert(image.save_png(OUT+filename) == OK, "PNG save failed")
			evidence.append({"shape":SHAPES[variant], "map_variant":variant,
				"theme":theme, "filename":filename, "native_size":[1920,1080],
				"map_resource":field.map_def.resource_path, "field_radius":field.map_def.field_radius,
				"capture_geometry": "analytic_shape" if variant >= 2 else "game_default"})
			print("LOADING SHAPE CAPTURE ", filename, " actual shape=", field.map_def.map_shape)
		Match.abort_match()
		viewport.queue_free()
		for i: int in range(5):
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
	var file: FileAccess = FileAccess.open(OUT+"manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"plates":evidence, "camera_position":[85,65,90],
		"camera_target":[-10,27,8], "fov":50, "size_class":"medium",
		"crop":"centered_keep_aspect_covered"},"\t")+"\n")
	file.close()
	print("LOADING SHAPES COMPLETE: ", evidence.size(), " plates")
	get_tree().quit()

func _spawn_stacks(main: Node3D, field: Field) -> void:
	var shapes: Array[BlockShape] = [load("res://config/blocks/cube.tres") as BlockShape,
		load("res://config/blocks/domino.tres") as BlockShape]
	var tuning: PhysicsTuning = Match.get("_physics_tuning") as PhysicsTuning
	var container: Node3D = main.get_node("BlocksContainer") as Node3D
	var flags: Array[HomeFlag] = field.home_flags()
	for slot: int in range(flags.size()):
		var center: Vector3 = flags[slot].global_position * 0.82
		assert(field.map_def.shape_contains(Vector2(center.x,center.z)), "stack not on solid ground")
		for level: int in range(7):
			var block: Block = BlockFactory.build(shapes[level%2],tuning,slot,Match.slot(slot).color)
			container.add_child(block)
			block.freeze = true
			block.global_position = center+Vector3(float(level%2)*tuning.cube_size*0.2,
				tuning.cube_size*(0.5+level),0)
			block.rotation.y = float(level%2)*PI/2.0

## Capture-only mesh correction: gameplay currently renders these three shapes
## as round bodies. Reuse its live territory/rim materials on analytic contours.
## No game script or collision geometry is changed by this art tool.
func _capture_shape_geometry(field: Field) -> void:
	var map: MapDef = field.map_def
	if map.map_shape < MapDef.MapShape.RING:
		return
	var outer: PackedVector2Array = PackedVector2Array()
	var inner: PackedVector2Array = PackedVector2Array()
	const SEGMENTS: int = 512
	for i: int in range(SEGMENTS):
		var angle: float = TAU * float(i) / SEGMENTS
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		var radius: float = map.field_radius
		if map.map_shape == MapDef.MapShape.TWIN:
			var offset: float = map.field_radius * map.twin_center_offset_fraction
			var disk_radius: float = map.field_radius * map.twin_disk_radius_fraction
			radius = absf(offset * direction.x) + sqrt(maxf(0.0,
				disk_radius * disk_radius - offset * offset * direction.y * direction.y))
		elif map.map_shape == MapDef.MapShape.CROSS:
			var width: float = map.field_radius * map.cross_arm_half_width_fraction
			radius = minf(radius, width / maxf(0.0001, minf(absf(direction.x), absf(direction.y))))
		outer.append(direction * radius)
		if map.map_shape == MapDef.MapShape.RING:
			inner.append(direction * map.field_radius * map.ring_hole_radius_fraction)
	var top: SurfaceTool = SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(SEGMENTS):
		var j: int = (i + 1) % SEGMENTS
		var a: Vector2 = inner[i] if not inner.is_empty() else Vector2.ZERO
		var b: Vector2 = inner[j] if not inner.is_empty() else Vector2.ZERO
		_top_triangle(top, a, outer[i], outer[j], map)
		if not inner.is_empty():
			_top_triangle(top, a, outer[j], b, map)
	# Bontago-mp0.150.1: the arena is one ArrayMesh (surface 0 = top, then rim
	# surfaces). Borrow the live rim materials from a round-shaped ArenaMesh build.
	var overlay: TerritoryOverlay = field.overlay()
	var body_visuals: DiscBodyVisuals = field.disc_body_visuals
	var round_map: MapDef = map.duplicate() as MapDef
	round_map.map_shape = MapDef.MapShape.ROUND
	var donor: ArenaMesh = ArenaMesh.new()
	var donor_mesh: ArrayMesh = ArrayMesh.new()
	donor.append_side_surfaces(donor_mesh, round_map, body_visuals, body_visuals.segments, 0.0)
	var band_material: Material = donor.material_for_surface(donor.surface_index(ArenaMesh.Kind.BAND))
	var rim_material: Material = donor.material_for_surface(donor.surface_index(ArenaMesh.Kind.CHAMFER))
	var arena: ArrayMesh = ArrayMesh.new()
	arena.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, (top.commit() as ArrayMesh).surface_get_arrays(0))
	overlay.mesh = arena
	overlay.set_surface_override_material(0, overlay.material())
	var shift: float = map.disk_height * 0.5
	var height: float = 2.0 * map.field_radius * body_visuals.band_height_fraction
	var chamfer_y: float = -height * body_visuals.chamfer_height_fraction
	var contours: Array[PackedVector2Array] = [outer]
	if not inner.is_empty():
		inner.reverse()
		contours.append(inner)
	for index: int in range(contours.size()):
		var points: PackedVector2Array = contours[index]
		var scaled: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in points:
			scaled.append(point * (body_visuals.band_radius_scale if index == 0 else 2.0 - body_visuals.band_radius_scale))
		var band: Array = donor.call("_ring_arrays", scaled, scaled, chamfer_y + shift, -map.disk_height - height + shift, false)
		var rim: Array = donor.call("_ring_arrays", points, scaled, shift, chamfer_y + shift, false, true)
		arena.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, band)
		overlay.set_surface_override_material(arena.get_surface_count() - 1, band_material)
		arena.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, rim)
		overlay.set_surface_override_material(arena.get_surface_count() - 1, rim_material)

func _top_triangle(tool: SurfaceTool, a: Vector2, b: Vector2, c: Vector2, map: MapDef) -> void:
	for point: Vector2 in [a,b,c]:
		tool.set_normal(Vector3.UP)
		tool.set_uv(point / (2.0 * map.field_radius) + Vector2.ONE * 0.5)
		tool.add_vertex(Vector3(point.x, map.disk_height * 0.5, point.y))
