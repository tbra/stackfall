extends Node
## Bontago-mp0.126 capture: real gameplay camera during a storm with the horizon cells,
## plus draw-call / primitive counts with the cells shown vs hidden.
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_horizon_storm.tscn -- --agent-probe --render-size=1280x720
const CAPTURE_SIZE: Vector2i = Vector2i(1280, 720)
const WAIT_STATE_TIMEOUT_S: float = 40.0
const PLAYING_EXTRA_PHYSICS_FRAMES: int = 30
const STORM_SECONDS: float = 14.0
const HARD_DEADLINE_S: float = 200.0
const RNG_SEED: int = 777
const LOOK_PITCH_DEG: float = -4.0
const PITCH_FRAMES: int = 20

var _main: Node = null
var _viewport: SubViewport = null


func _ready() -> void:
	get_tree().create_timer(HARD_DEADLINE_S).timeout.connect(func() -> void: get_tree().quit(1))
	call_deferred("_run")


func _run() -> void:
	_viewport = AgentProbe.make_render_viewport(self, CAPTURE_SIZE)
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_viewport.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = 2
	config.hot_seat = false
	config.rng_seed = RNG_SEED
	config.weather_mode = MatchConfig.WeatherMode.OFF
	Net.host_game(AgentProbe.free_udp_port(), "Probe")
	await get_tree().process_frame
	_main.call("_on_lobby_start_requested", config)
	var waited: float = 0.0
	while Match.state() != Match.State.PLAYING and waited < WAIT_STATE_TIMEOUT_S:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(PLAYING_EXTRA_PHYSICS_FRAMES):
		await get_tree().physics_frame
	print("PROBE storm start=%s" % Match.weather().start_event(&"storm"))
	await get_tree().create_timer(STORM_SECONDS).timeout
	var cells: HorizonStormCells = get_tree().root.find_child("HorizonStormCells", true, false) as HorizonStormCells
	print("PROBE cells=%d opacity=%.2f intensity=%.2f layout=%s" % [cells.cells().size(), cells.opacity, cells.intensity, str(HorizonStormCells.layout(Match.weather().seed_value(), cells.config))])
	for cell: Node3D in cells.cells():
		print("PROBE cell pos=%s style=%s" % [cell.global_position, cell.get("silhouette_style")])
	var camera: Camera3D = _viewport.get_camera_3d()
	print("PROBE camera pos=%s far=%s fov=%s" % [camera.global_position, camera.far, camera.fov])
	await _frames()
	var on_stats: Dictionary = _stats()
	await _grab("horizon_storm_on")
	# Players pitch up to look at the horizon; the default -35 deg framing ends at the horizon line.
	var rig: CameraRig = get_tree().root.find_child("CameraRig", true, false) as CameraRig
	for _i: int in range(PITCH_FRAMES):
		rig.set("_pitch", deg_to_rad(LOOK_PITCH_DEG))
		await get_tree().process_frame
	await _frames()
	for cell: Node3D in cells.cells():
		var cam: Camera3D = _viewport.get_camera_3d()
		print("PROBE cell screen=%s behind=%s" % [cam.unproject_position(cell.global_position), cam.is_position_behind(cell.global_position)])
	await _grab("horizon_storm_pitched")
	cells.visible = false
	cells.set_process(false)
	await _frames()
	var off_stats: Dictionary = _stats()
	print("PROBE perf cells_on=%s cells_off=%s" % [str(on_stats), str(off_stats)])
	get_tree().quit()


func _frames() -> void:
	for _i: int in range(6):
		await RenderingServer.frame_post_draw


func _stats() -> Dictionary:
	var rid: RID = _viewport.get_viewport_rid()
	return {
		"draw_calls": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
	}


func _grab(label: String) -> void:
	var image: Image = _viewport.get_texture().get_image()
	var path: String = "user://%s.png" % label
	image.save_png(path)
	print("PROBE shot=%s" % ProjectSettings.globalize_path(path))
