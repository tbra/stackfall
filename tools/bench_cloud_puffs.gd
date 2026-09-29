extends Node
## Bontago-adt.1: rough GPU cost of the 3D cloud puffs (vfx/CloudSea.gd).
## Loads the baked visual demo into a fixed-size SubViewport (never the main
## window, which agent runs shrink via override.cfg), frames two views (the three-quarter overview
## and a low view across the cloud sea, the worst case for puff overdraw) and
## measures that SubViewport's GPU render time with the Puffs node shown and
## hidden, alternating blocks of frames so drift/thermal effects cancel out.
##
## Run windowed, off-screen, on an otherwise idle machine:
##   godot --path . --position 10000,10000 tools/bench_cloud_puffs.tscn -- --scene=res://visual_demo/VisualDemo.tscn
## Prints one CLOUD_BENCH line per view: mean GPU ms with/without puffs.
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts).

const DEFAULT_SCENE: String = "res://visual_demo/VisualDemo.tscn"
const WARMUP_FRAMES: int = 30
const BLOCK_FRAMES: int = 60
const BLOCKS: int = 4
const FALLBACK_RADIUS_M: float = 30.0
const OVERVIEW_DISTANCE_R: float = 1.55
const OVERVIEW_HEIGHT_R: float = 0.95
const LOW_DISTANCE_R: float = 1.08
const LOW_HEIGHT_R: float = 0.06
const LOW_LOOK_DOWN_R: float = 0.25
const VIEW_FOV_DEG: float = 50.0
const VIEW_SIZE: Vector2i = Vector2i(1280, 720)


func _ready() -> void:
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	var scene_path: String = DEFAULT_SCENE
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.substr("--scene=".length())
	var sub: SubViewport = SubViewport.new()
	sub.size = VIEW_SIZE
	sub.own_world_3d = true
	sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sub)
	var scene: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	sub.add_child(scene)
	var puffs: Node3D = scene.find_child("Puffs", true, false) as Node3D
	if puffs == null:
		push_error("CLOUD_BENCH no Puffs node in %s" % scene_path)
		get_tree().quit(1)
		return
	var camera: Camera3D = Camera3D.new()
	camera.fov = VIEW_FOV_DEG
	camera.far = 4000.0
	sub.add_child(camera)
	camera.current = true
	var radius: float = _disk_radius(scene)
	var rid: RID = sub.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var views: Dictionary[String, Array] = {
		"overview": [Vector3(radius * OVERVIEW_DISTANCE_R, radius * OVERVIEW_HEIGHT_R, 0.0), Vector3.ZERO],
		"low": [Vector3(radius * LOW_DISTANCE_R, radius * LOW_HEIGHT_R, 0.0),
			Vector3(radius * (LOW_DISTANCE_R + 1.0), radius * (LOW_HEIGHT_R - LOW_LOOK_DOWN_R), 0.0)],
	}
	for view: String in views:
		var framing: Array = views[view]
		camera.global_position = framing[0]
		camera.look_at(framing[1], Vector3.UP)
		var with_ms: float = 0.0
		var without_ms: float = 0.0
		for block: int in range(BLOCKS * 2):
			var shown: bool = block % 2 == 0
			puffs.visible = shown
			for _i: int in range(WARMUP_FRAMES):
				await RenderingServer.frame_post_draw
			var total: float = 0.0
			for _i: int in range(BLOCK_FRAMES):
				await RenderingServer.frame_post_draw
				total += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			if shown:
				with_ms += total / float(BLOCK_FRAMES * BLOCKS)
			else:
				without_ms += total / float(BLOCK_FRAMES * BLOCKS)
		print("CLOUD_BENCH view=%s size=%s gpu_ms_with=%.3f gpu_ms_without=%.3f puffs_ms=%.3f instances=%d" % [
			view, VIEW_SIZE, with_ms, without_ms, with_ms - without_ms,
			(puffs as MultiMeshInstance3D).multimesh.instance_count if puffs is MultiMeshInstance3D else -1,
		])
	get_tree().quit(0)


func _disk_radius(scene: Node3D) -> float:
	var disk: MeshInstance3D = scene.find_child("DiskMesh", true, false) as MeshInstance3D
	if disk == null or disk.mesh == null:
		return FALLBACK_RADIUS_M
	var box: AABB = disk.global_transform * disk.get_aabb()
	return maxf(box.size.x, box.size.z) * 0.5


func _process(_delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
