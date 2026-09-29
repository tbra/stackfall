extends Node
## Renders the baked visual demo (res://visual_demo/VisualDemo.tscn, made by
## tools/bake_visual_demo.gd) from a fixed set of camera views, so visual
## changes to shaders, materials and the environment can be compared quickly
## without re-running a match. Materials in the bake reference the project's
## shader files by path, so shader edits show up here without re-baking;
## changes to game scripts (new nodes, new material setup) need a re-bake.
##
## Run windowed, off-screen:
##   godot --path . --position 10000,10000 tools/shoot_visual_demo.tscn
## Optional user args after `--`:
##   --scene=res://visual_demo/VisualDemo.tscn  scene to shoot
##   --out=user://gfx_shots                     output folder
##   --tag=baseline                             file-name prefix
##   --wait=1.0                                 seconds to run before shooting
##                                              (lets TIME-driven shaders move)
##   --views=player,overview,sun,horizon,close  subset/order of views
## Writes <out>/<tag>_<view>.png per view and <tag>_sheet.png, a 3x2 contact
## sheet of all views.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts).

const DEFAULT_SCENE: String = "res://visual_demo/VisualDemo.tscn"
const DEFAULT_OUT: String = "user://gfx_shots"
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)
const SHEET_COLUMNS: int = 3
const SHEET_CELL: Vector2i = Vector2i(640, 360)
const SETTLE_FRAMES: int = 8
const ALL_VIEWS: PackedStringArray = ["player", "overview", "sun", "horizon", "close"]

## View framings as multiples of the disk radius (measured from DiskMesh).
const OVERVIEW_DISTANCE_R: float = 1.55
const OVERVIEW_HEIGHT_R: float = 0.95
const SUN_DISTANCE_R: float = 1.35
const SUN_HEIGHT_R: float = 0.35
const HORIZON_DISTANCE_R: float = 1.08
const HORIZON_HEIGHT_R: float = 0.06
const CLOSE_DISTANCE_M: float = 9.0
const CLOSE_HEIGHT_M: float = 4.0
const FALLBACK_RADIUS_M: float = 30.0
const VIEW_FOV_DEG: float = 50.0


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var scene_path: String = _string_arg(args, "scene", DEFAULT_SCENE)
	var out_dir: String = _string_arg(args, "out", DEFAULT_OUT)
	var tag: String = _string_arg(args, "tag", "shot")
	var wait_s: float = _string_arg(args, "wait", "1.0").to_float()
	var views: PackedStringArray = _string_arg(args, "views", ",".join(ALL_VIEWS)).split(",", false)
	if not ResourceLoader.exists(scene_path):
		push_error("GFX_SHOT missing %s (run tools/bake_visual_demo.tscn first)" % scene_path)
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var sub: SubViewport = SubViewport.new()
	sub.size = SHOT_SIZE
	sub.own_world_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var scene: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	sub.add_child(scene)
	var player_camera: Camera3D = _find_camera(scene)
	var camera: Camera3D = Camera3D.new()
	camera.fov = VIEW_FOV_DEG
	camera.far = player_camera.far if player_camera != null else 4000.0
	sub.add_child(camera)

	await get_tree().create_timer(maxf(wait_s, 0.0)).timeout
	var radius: float = _disk_radius(scene)
	var sheet: Image = Image.create_empty(SHEET_CELL.x * SHEET_COLUMNS, SHEET_CELL.y * 2, false, Image.FORMAT_RGB8)
	var index: int = 0
	for view: String in views:
		if not _frame(camera, player_camera, scene, view, radius):
			push_error("GFX_SHOT unknown view '%s'" % view)
			continue
		camera.current = true
		for _i: int in range(SETTLE_FRAMES):
			await RenderingServer.frame_post_draw
		var image: Image = sub.get_texture().get_image()
		var path: String = "%s/%s_%s.png" % [out_dir, tag, view]
		image.save_png(path)
		print("GFX_SHOT %s=%s" % [view, ProjectSettings.globalize_path(path)])
		if index < SHEET_COLUMNS * 2:
			var cell: Image = image.duplicate() as Image
			cell.convert(Image.FORMAT_RGB8)
			cell.resize(SHEET_CELL.x, SHEET_CELL.y, Image.INTERPOLATE_BILINEAR)
			var at: Vector2i = Vector2i((index % SHEET_COLUMNS) * SHEET_CELL.x, (index / SHEET_COLUMNS) * SHEET_CELL.y)
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, SHEET_CELL), at)
		index += 1
	var sheet_path: String = "%s/%s_sheet.png" % [out_dir, tag]
	sheet.save_png(sheet_path)
	print("GFX_SHOT sheet=%s" % ProjectSettings.globalize_path(sheet_path))
	get_tree().quit(0)


func _frame(camera: Camera3D, player_camera: Camera3D, scene: Node3D, view: String, radius: float) -> bool:
	var sun_dir: Vector3 = _toward_sun(scene)
	var sun_flat: Vector3 = Vector3(sun_dir.x, 0.0, sun_dir.z).normalized()
	match view:
		"player":
			if player_camera == null:
				return false
			camera.fov = player_camera.fov
			camera.global_transform = player_camera.global_transform
			return true
		"overview":
			# Three-quarter view across the disk, sun off to one side (mockup 08).
			var side: Vector3 = sun_flat.rotated(Vector3.UP, deg_to_rad(-120.0))
			_place(camera, side * radius * OVERVIEW_DISTANCE_R + Vector3.UP * radius * OVERVIEW_HEIGHT_R, Vector3.ZERO)
		"sun":
			# Looking across the disk into the sun.
			_place(camera, -sun_flat * radius * SUN_DISTANCE_R + Vector3.UP * radius * SUN_HEIGHT_R, sun_flat * radius)
		"horizon":
			# From just past the rim, looking out and slightly down at the cloud sea.
			var out: Vector3 = sun_flat.rotated(Vector3.UP, deg_to_rad(90.0))
			var eye: Vector3 = out * radius * HORIZON_DISTANCE_R + Vector3.UP * radius * HORIZON_HEIGHT_R
			_place(camera, eye, eye + out * radius - Vector3.UP * radius * 0.25)
		"close":
			var target: Vector3 = _first_block_position(scene)
			var from_center: Vector3 = Vector3(target.x, 0.0, target.z).normalized()
			if from_center == Vector3.ZERO:
				from_center = Vector3.BACK
			_place(camera, target + from_center * CLOSE_DISTANCE_M + Vector3.UP * CLOSE_HEIGHT_M, target + Vector3.UP)
		_:
			return false
	camera.fov = VIEW_FOV_DEG
	return true


func _place(camera: Camera3D, eye: Vector3, target: Vector3) -> void:
	camera.global_position = eye
	camera.look_at(target, Vector3.UP)


func _toward_sun(scene: Node3D) -> Vector3:
	var light: DirectionalLight3D = _find_first(scene, "DirectionalLight3D") as DirectionalLight3D
	if light == null:
		return Vector3(1.0, 0.3, 0.0).normalized()
	return light.global_transform.basis.z.normalized()


func _disk_radius(scene: Node3D) -> float:
	var disk: MeshInstance3D = scene.find_child("DiskMesh", true, false) as MeshInstance3D
	if disk == null or disk.mesh == null:
		return FALLBACK_RADIUS_M
	var box: AABB = disk.global_transform * disk.get_aabb()
	return maxf(box.size.x, box.size.z) * 0.5


func _first_block_position(scene: Node3D) -> Vector3:
	var container: Node = scene.find_child("BlocksContainer", true, false)
	if container != null:
		for child: Node in container.get_children():
			if child is Node3D:
				return (child as Node3D).global_position
	return Vector3.ZERO


func _find_camera(root: Node) -> Camera3D:
	return _find_first(root, "Camera3D") as Camera3D


func _find_first(root: Node, class_type: String) -> Node:
	if root.is_class(class_type):
		return root
	for child: Node in root.get_children():
		var found: Node = _find_first(child, class_type)
		if found != null:
			return found
	return null


func _string_arg(args: PackedStringArray, key: String, fallback: String) -> String:
	var prefix: String = "--%s=" % key
	for arg: String in args:
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return fallback


## Tool runs must never take over the owner's desktop: no focus stealing, and
## the sandbox's PlayerController mouse capture is undone every frame.
func _enter_tree() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
