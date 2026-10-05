extends Node
## Bontago-mp0.136/mp0.137 probe: a timed frame sequence at a low-cloud view, and a phase strip.
## User args: out=<dir> phase=<0..1> frames=<n> step=<s> shadows=on|off pose=low|high
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_cloud_blink.tscn -- --agent-probe --render-size=1280x720 out=<dir>
const SETTLE_SECONDS: float = 1.5
const DRAW_FRAMES: int = 4
const FOV_DEG: float = 85.0
const POSES: Dictionary = {
	"low": [Vector3(0.0, 35.0, 60.0), -28.0],
	"high": [Vector3(0.0, 20.0, 0.0), 25.0],
}

var _out_dir: String = "user://"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var phases: PackedStringArray = PackedStringArray(["0.44"])
	var frames: int = 1
	var step_s: float = 0.5
	var shadows_on: bool = true
	var pose: String = "low"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=").trim_suffix("/") + "/"
		elif arg.begins_with("phase="):
			phases = arg.trim_prefix("phase=").split(",", false)
		elif arg.begins_with("frames="):
			frames = int(arg.trim_prefix("frames="))
		elif arg.begins_with("step="):
			step_s = float(arg.trim_prefix("step="))
		elif arg == "shadows=off":
			shadows_on = false
		elif arg.begins_with("pose="):
			pose = arg.trim_prefix("pose=")
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	var shadows: CloudShadows = main.get_node("CloudShadows") as CloudShadows
	if not shadows_on:
		var preset: GraphicsPreset = Settings.current_graphics_preset().duplicate() as GraphicsPreset
		preset.cloud_shadows_enabled = false
		shadows._on_graphics_preset_changed(preset)
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	rig.set_physics_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	camera.fov = FOV_DEG
	var spec: Array = POSES[pose]
	for phase: String in phases:
		skybox.set_cycle_phase(float(phase))
		var sun: Vector3 = skybox.sun_direction()
		var flat: Vector3 = Vector3(sun.x, 0.0, sun.z).normalized()
		var position: Vector3 = spec[0] as Vector3
		camera.global_position = position
		camera.look_at(position + flat * 100.0, Vector3.UP)
		camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(float(spec[1])))
		for index: int in range(frames):
			await get_tree().create_timer(step_s).timeout
			for _i: int in range(DRAW_FRAMES):
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path: String = "%sblink_%s_p%s_%02d.png" % [_out_dir, "on" if shadows_on else "off", phase, index]
			viewport.get_texture().get_image().save_png(path)
			print("BLINK saved=%s" % ProjectSettings.globalize_path(path))
	get_tree().quit()
