extends Node
## Bakes a static, script-free copy of a staged mid-match board into
## res://visual_demo/VisualDemo.tscn so the owner can open it in the editor
## and tweak visuals (Environment, light, sky, fog, block/disc/territory
## materials, beacons) live in the 3D viewport and inspector.
##
## Boots the real Main.tscn sandbox (same pattern as
## tools/screenshot_xtq41_beacons.gd), drops a few towers per player near each
## home beacon through Match.request_place(), lets physics settle and the
## territory grow, then clones every visible 3D node into a new scene with
## scripts removed and physics bodies replaced by plain Node3D. Meshes,
## materials and generated textures are embedded, so the editor shows exactly
## what the game rendered; shader-driven animation (TIME) keeps running.
##
## Run windowed, off-screen (a real render device is required so generated
## ArrayMeshes keep their surface data):
##   godot --path . --position 10000,10000 tools/bake_visual_demo.tscn
## Optional user args after `--`: --players=N (2-8, default 4), --map=<variant_size>
## (e.g. ring_large; default: config/match_defaults.tres), --theme=<name> (a
## config/sky_themes/<name>.tres; default sunset). Sunset bakes to VisualDemo.tscn,
## any other theme to VisualDemo_<Name>.tscn (e.g. VisualDemo_Night.tscn).
##
## The output folder is gitignored: when assets/original is installed the
## baked sky faces are the original game's copyrighted textures.
##
## Limitations (runtime-scripted, not reproducible in a static copy):
## - DiscMirror's planar reflection follows the live camera, so it is
##   disabled in the bake (mirror_enabled = false on the territory material);
##   SSR, the ReflectionProbe and sky reflection remain.
## - SunFlare is a screen-space CanvasLayer driven by script; it is kept with
##   its script, so it appears only when the scene is run (F6), not in the
##   editor viewport.
## - Script-driven motion (beacon pulse, block effects, tilt) is frozen.
## Tweaks made in the demo are local to it: port chosen values back to the
## config/*.tres resource (or scene) the game reads them from.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts).

const OUTPUT_DIR: String = "res://visual_demo"
const OUTPUT_SCENE: String = "res://visual_demo/VisualDemo.tscn"
const DEFAULT_THEME: String = "sunset"
const DEFAULT_PLAYERS: int = 4
const BOOT_WAIT_S: float = 1.5
const SETTLE_WAIT_S: float = 8.0

## Towers per player and blocks per tower. Each tower stands at a point
## between the player's home beacon and the disk center (TOWER_RADIAL_FRACTIONS
## of the beacon's own radius), offset sideways by TOWER_SIDE_OFFSET_M so
## towers do not land on the beacon itself.
const TOWER_RADIAL_FRACTIONS: Array[float] = [0.72, 0.45]
const TOWER_SIDE_OFFSETS_M: Array[float] = [1.6, -0.8]
const BLOCKS_PER_TOWER: int = 3
const DROP_BASE_HEIGHT_M: float = 1.0
const DROP_SPACING_M: float = 1.4
const DROP_INTERVAL_TICKS: int = 20

## Generated textures larger than this are written to their own .res files
## next to the scene instead of bloating the text .tscn.
const EXTERNALIZE_TEXTURE_MIN_PX: int = 256

## Classes never copied: collision/queries and 2D/UI (SunFlare is handled
## separately).
const SKIP_CLASSES: Array[StringName] = [
	&"CollisionShape3D", &"CollisionPolygon3D", &"RayCast3D", &"ShapeCast3D", &"Area3D",
	&"Control", &"CanvasLayer", &"Timer", &"AudioStreamPlayer",
	&"AudioStreamPlayer3D", &"SubViewport",
]
## Nodes skipped by name (the planar mirror; see class doc).
const SKIP_NAMES: Array[StringName] = [&"DiscMirror"]
const SKIP_PROPERTIES: Array[String] = ["script", "owner"]

## Self-check render of the saved scene, loaded fresh in its own World3D.
const CHECK_SHOT_PATH: String = "user://visual_demo_check.png"
## The same view of the live match just before baking, for a parity check.
const LIVE_SHOT_PATH: String = "user://visual_demo_live.png"
const CHECK_SHOT_SIZE: Vector2i = Vector2i(1280, 720)
const CHECK_SHOT_FRAMES: int = 6

var _externalized: int = 0
var _output_scene: String = OUTPUT_SCENE
var _name_counts: Dictionary[String, int] = {}


func _ready() -> void:
	Settings.set_graphics_preset(&"high")
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var players: int = clampi(_int_arg(args, "players", DEFAULT_PLAYERS), 2, 8)
	var sandbox_args: PackedStringArray = PackedStringArray(["sandbox", "players=%d" % players])

	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	var map_id: String = _string_arg(args, "map", "")
	if map_id != "":
		var parts: PackedStringArray = map_id.to_upper().split("_")
		if parts.size() != 2 or not MatchConfig.MapVariant.has(parts[0]) or not MapDef.MapSize.has(parts[1]):
			push_error("VISUAL_DEMO unknown map '%s' (expected e.g. ring_large)" % map_id)
			get_tree().quit(1)
			return
		var match_config: MatchConfig = (main.get("match_config") as MatchConfig).duplicate(true) as MatchConfig
		match_config.map_variant = MatchConfig.MapVariant[parts[0]] as MatchConfig.MapVariant
		match_config.map_size = MapDef.MapSize[parts[1]] as MapDef.MapSize
		main.set("match_config", match_config)

	var theme_id: String = _string_arg(args, "theme", DEFAULT_THEME)
	if theme_id != DEFAULT_THEME:
		var sky_theme: SkyThemeDef = Skybox.load_theme(theme_id)
		if sky_theme == null:
			push_error("VISUAL_DEMO unknown theme '%s'" % theme_id)
			get_tree().quit(1)
			return
		(main.get_node("Skybox") as Skybox).theme = sky_theme
		_output_scene = "%s/VisualDemo_%s.tscn" % [OUTPUT_DIR, theme_id.capitalize()]

	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main._start_sandbox_match_with_args(sandbox_args)
	await _wait_ticks(int(BOOT_WAIT_S * Engine.physics_ticks_per_second))

	var field: Field = main.get_node("Field") as Field
	# The pre-match countdown must finish before placements are accepted.
	while Match.state() != Match.State.PLAYING:
		await get_tree().physics_frame
	await _drop_towers(field, players)
	await _wait_ticks(int(SETTLE_WAIT_S * Engine.physics_ticks_per_second))
	await RenderingServer.frame_post_draw

	await _render_shot(get_viewport().world_3d, null, LIVE_SHOT_PATH)
	var error: Error = _bake(main)
	if error == OK:
		main.queue_free()
		await _render_shot(null, (load(_output_scene) as PackedScene).instantiate(), CHECK_SHOT_PATH)
	get_tree().quit(0 if error == OK else 1)


func _drop_towers(field: Field, players: int) -> void:
	var placed: int = 0
	for level: int in range(BLOCKS_PER_TOWER):
		for slot_id: int in range(players):
			var home: Vector2 = field.home_flag_position(slot_id, players)
			var side: Vector2 = home.orthogonal().normalized()
			for tower: int in range(TOWER_RADIAL_FRACTIONS.size()):
				var local: Vector2 = home * TOWER_RADIAL_FRACTIONS[tower] + side * TOWER_SIDE_OFFSETS_M[tower]
				var height: float = field.surface_y() + DROP_BASE_HEIGHT_M + DROP_SPACING_M * float(level)
				var origin: Vector3 = field.world_from_disk_local(local, height)
				Match.debug_unlock_slot(slot_id)
				var result: StringName = Match.request_place(slot_id, origin, 0, Quaternion.IDENTITY, false)
				if result == PlacementRules.REASON_OK:
					placed += 1
				else:
					print("VISUAL_DEMO drop slot=%d tower=%d level=%d result=%s" % [slot_id, tower, level, result])
		await _wait_ticks(DROP_INTERVAL_TICKS)
	print("VISUAL_DEMO placed=%d" % placed)


func _bake(main: Node) -> Error:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	var root: Node3D = Node3D.new()
	root.name = "VisualDemo"
	for child: Node in main.get_children():
		_clone_into(child, root, root)

	var sun_flare: Node = main.get_node_or_null("SunFlare")
	if sun_flare != null:
		var flare: CanvasLayer = CanvasLayer.new()
		flare.name = "SunFlare"
		flare.set_script(sun_flare.get_script())
		root.add_child(flare)
		flare.owner = root
		var camera: Camera3D = _find_current_camera(root)
		if camera != null:
			flare.set("camera_path", flare.get_path_to(camera))

	_disable_planar_mirror(root)
	# The held-block ghost sits right in front of the camera; it is kept for
	# tweaking but starts hidden (toggle its eye icon in the scene tree).
	var ghost: Node3D = root.get_node_or_null("GhostPreview") as Node3D
	if ghost != null:
		ghost.visible = false

	var packed: PackedScene = PackedScene.new()
	var pack_error: Error = packed.pack(root)
	if pack_error != OK:
		push_error("VISUAL_DEMO pack failed: %s" % error_string(pack_error))
		return pack_error
	var save_error: Error = ResourceSaver.save(packed, _output_scene)
	var size: int = FileAccess.get_file_as_bytes(_output_scene).size()
	print("VISUAL_DEMO saved=%s bytes=%d externalized_textures=%d error=%s" % [
		ProjectSettings.globalize_path(_output_scene), size, _externalized, error_string(save_error),
	])
	root.free()
	return save_error


## Copies `src` (and its subtree) under `dst_parent`. Non-3D plain nodes are
## flattened (their 3D children attach to `dst_parent` directly); physics
## bodies become Node3D so nothing falls when the demo is run.
func _clone_into(src: Node, dst_parent: Node, root: Node) -> void:
	if src.name in SKIP_NAMES or _is_skipped_class(src):
		return
	if src is Node3D and not (src as Node3D).visible:
		return

	var dst: Node = null
	if src is CollisionObject3D:
		dst = Node3D.new()
		(dst as Node3D).transform = (src as Node3D).transform
	elif src is Node3D or src is WorldEnvironment:
		dst = ClassDB.instantiate(src.get_class()) as Node
		_copy_properties(src, dst)

	if dst == null:
		for child: Node in src.get_children():
			_clone_into(child, dst_parent, root)
		return

	dst.name = _readable_name(src)
	# A flattened non-3D parent means the live node sat directly in world
	# space, so its global transform is the right local one under root.
	if dst is Node3D and dst_parent == root:
		(dst as Node3D).transform = (src as Node3D).global_transform
	dst_parent.add_child(dst)
	dst.owner = root
	for child: Node in src.get_children():
		_clone_into(child, dst, root)


## Runtime-built nodes get auto names like "_RigidBody3D_7933"; give the
## ones the owner will pick in the scene tree a readable, unique name.
func _readable_name(src: Node) -> String:
	var base: String = String(src.name)
	if src is Block:
		var block: Block = src as Block
		base = "Block_P%d_%s" % [block.owner_slot + 1, block.shape_id]
	elif src is HomeFlag:
		base = "HomeBeacon"
	elif src is GoalFlag:
		base = "GoalBeacon"
	elif base.begins_with("_") or base.begins_with("@"):
		base = src.get_class()
	else:
		return base
	var count: int = _name_counts.get(base, 0) + 1
	_name_counts[base] = count
	return "%s_%d" % [base, count]


## Renders CHECK_SHOT_SIZE through a SubViewport: either sharing `world`
## (the live match, viewed by its current camera) or, with `scene`, a fresh
## World3D holding that scene and its own current camera.
func _render_shot(world: World3D, scene: Node, path: String) -> void:
	var sub: SubViewport = SubViewport.new()
	sub.size = CHECK_SHOT_SIZE
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if scene != null:
		sub.own_world_3d = true
		sub.add_child(scene)
	else:
		var source: Camera3D = get_viewport().get_camera_3d()
		var camera: Camera3D = Camera3D.new()
		camera.fov = source.fov
		camera.near = source.near
		camera.far = source.far
		camera.environment = source.environment
		sub.world_3d = world
		sub.add_child(camera)
		camera.transform = source.global_transform
		camera.current = true
	add_child(sub)
	for _i: int in range(CHECK_SHOT_FRAMES):
		await RenderingServer.frame_post_draw
	sub.get_texture().get_image().save_png(path)
	print("VISUAL_DEMO shot=%s" % ProjectSettings.globalize_path(path))
	sub.queue_free()


func _is_skipped_class(node: Node) -> bool:
	for class_name_value: StringName in SKIP_CLASSES:
		if node.is_class(class_name_value):
			return true
	return false


func _copy_properties(src: Object, dst: Object) -> void:
	for property: Dictionary in src.get_property_list():
		var usage: int = property["usage"]
		var name: String = property["name"]
		if (usage & PROPERTY_USAGE_STORAGE) == 0 or name in SKIP_PROPERTIES:
			continue
		var value: Variant = src.get(name)
		if value is Resource:
			value = _prepare_resource(value as Resource)
		dst.set(name, value)


## Walks resource properties so large generated textures anywhere below
## (e.g. inside a ShaderMaterial's parameters) are saved as their own files.
func _prepare_resource(resource: Resource) -> Resource:
	if resource is ImageTexture and resource.resource_path == "":
		var texture: ImageTexture = resource as ImageTexture
		if maxi(texture.get_width(), texture.get_height()) >= EXTERNALIZE_TEXTURE_MIN_PX:
			_externalized += 1
			var path: String = "%s/texture_%02d.res" % [OUTPUT_DIR, _externalized]
			ResourceSaver.save(texture, path, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
		return texture
	if resource is ShaderMaterial:
		var material: ShaderMaterial = resource as ShaderMaterial
		for uniform: Dictionary in material.shader.get_shader_uniform_list() if material.shader != null else []:
			var value: Variant = material.get_shader_parameter(uniform["name"])
			if value is Resource:
				_prepare_resource(value as Resource)
			elif value is Array or value is PackedColorArray:
				# A vec4[] uniform set from Color values does not survive text
				# serialization (saves as zeros); store it as vec4s instead.
				material.set_shader_parameter(uniform["name"], _to_vector4_array(value))
	elif resource is Environment:
		var environment: Environment = resource as Environment
		if environment.sky != null and environment.sky.sky_material != null:
			_prepare_resource(environment.sky.sky_material)
	elif resource is Mesh:
		var mesh: Mesh = resource as Mesh
		for surface: int in range(mesh.get_surface_count()):
			var surface_material: Material = mesh.surface_get_material(surface)
			if surface_material != null:
				_prepare_resource(surface_material)
	elif resource is BaseMaterial3D:
		var base: BaseMaterial3D = resource as BaseMaterial3D
		if base.albedo_texture != null:
			_prepare_resource(base.albedo_texture)
	if resource is Material and (resource as Material).next_pass != null:
		_prepare_resource((resource as Material).next_pass)
	return resource


func _to_vector4_array(values: Variant) -> PackedVector4Array:
	var result: PackedVector4Array = PackedVector4Array()
	for value: Variant in values:
		if value is Color:
			var color: Color = value as Color
			result.append(Vector4(color.r, color.g, color.b, color.a))
		elif value is Vector4:
			result.append(value as Vector4)
	return result


func _disable_planar_mirror(root: Node) -> void:
	for node: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		var material: ShaderMaterial = geometry.material_override as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path.ends_with("territory.gdshader"):
			material.set_shader_parameter(&"mirror_enabled", false)
			material.set_shader_parameter(&"mirror_tex", null)


func _find_current_camera(root: Node) -> Camera3D:
	for node: Node in root.find_children("*", "Camera3D", true, false):
		if (node as Camera3D).current:
			return node as Camera3D
	return null


func _int_arg(args: PackedStringArray, key: String, fallback: int) -> int:
	var value: String = _string_arg(args, key, "")
	return value.to_int() if value.is_valid_int() else fallback


func _string_arg(args: PackedStringArray, key: String, fallback: String) -> String:
	for arg: String in args:
		var trimmed: String = arg.trim_prefix("--")
		if trimmed.begins_with(key + "="):
			return trimmed.substr(key.length() + 1)
	return fallback


func _wait_ticks(ticks: int) -> void:
	for _i: int in range(ticks):
		await get_tree().physics_frame

