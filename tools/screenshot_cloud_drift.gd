extends Node
## Bontago-mp0.92: cloud drift captures from the sandbox start framing: two calm frames 3 s apart
## and one storm frame. Run:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_cloud_drift.tscn -- --agent-probe --render-size=1280x720 out=<dir>
const SETTLE_SECONDS: float = 1.5
const PAIR_GAP_S: float = 3.0
const STORM_WAIT_S: float = 10.0
const DRAW_FRAMES: int = 6

var _out_dir: String = "user://"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=").trim_suffix("/") + "/"
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	await _frames()
	_save(viewport, "calm_a")
	await get_tree().create_timer(PAIR_GAP_S).timeout
	await _frames()
	_save(viewport, "calm_b")
	print("DRIFT calm offset=%s heading=%s" % [skybox.cloud_drift().offset, skybox.cloud_wind_dir()])
	skybox.set_cloud_storm_wind(Vector2.from_angle(deg_to_rad(120.0)))
	skybox.set_storm_sky(1.0, Skybox.load_theme("storm"))
	await get_tree().create_timer(STORM_WAIT_S).timeout
	await _frames()
	_save(viewport, "storm")
	print("DRIFT storm offset=%s heading=%s mult=%.2f" % [skybox.cloud_drift().offset, skybox.cloud_wind_dir(), skybox.cloud_drift().speed_mult])
	get_tree().quit()


func _frames() -> void:
	for i: int in range(DRAW_FRAMES):
		await get_tree().process_frame


func _save(viewport: SubViewport, label: String) -> void:
	var image: Image = viewport.get_texture().get_image()
	var path: String = _out_dir + "cloud_drift_" + label + ".png"
	print("DRIFT saved %s err=%d" % [path, image.save_png(path)])
