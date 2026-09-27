extends Node
## Bontago-mp0.3.4: a small, dedicated visual probe for vfx/SunFlare.gd --
## tools/capture_mockup08.gd's own framings (overview/player) do not
## reliably point the camera anywhere near config/sun_flare.tres'
## sun_direction (their camera orientation follows the map's own red/blue
## home axis, which has no relationship to where the sun sits), so this is a
## second, narrower capture that aims the camera directly at the sun to
## confirm the flare actually renders. Not part of the running game
## (CLAUDE.md: build-time scripts live in tools/ -- kept in vfx/ instead
## since it is this package's own throwaway verification tool, not a
## reusable general-purpose capture utility like tools/capture_mockup08.gd).
##
##   godot --path . --windowed --position 10000,10000 --resolution 1280x720 res://tools/capture_sun_flare_probe.tscn -- --out=feedback/overhaul/<tag>

const FRAME_SIZE: Vector2i = Vector2i(1280, 720)
const SETTLE_S: float = 1.5

var _out_dir: String = "res://feedback/overhaul/latest"


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var text: String = arg.lstrip("-")
		if text.begins_with("out="):
			_out_dir = text.substr(4)
	if not _out_dir.begins_with("res://") and not _out_dir.contains(":"):
		_out_dir = "res://" + _out_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	call_deferred("_capture")


func _capture() -> void:
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = FRAME_SIZE
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_S).timeout

	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_S).timeout

	var flare: SunFlare = main.get_node("SunFlare") as SunFlare
	var rig: Node = main.get_node("CameraRig")
	rig.set_process(false)
	var camera: Camera3D = rig.get_node("Camera3D") as Camera3D
	var direction: Vector3 = flare.config.sun_direction.normalized()
	# Stand back from the field center and look straight down `direction`
	# toward the sun -- the field's own geometry stays in shot near the
	# bottom of frame so the flare is seen in a recognizable gameplay
	# context, not an empty sky.
	camera.global_position = -direction * 45.0 + Vector3.UP * 6.0
	camera.look_at(camera.global_position + direction, Vector3.UP)

	# vfx/SunFlare.gd's own class doc: a freshly moved camera's rendering
	# transform lags one physics tick behind a script write until a physics
	# step syncs it (physics interpolation) -- wait a couple of ticks before
	# reading back the projected flare.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout

	get_window().mode = Window.MODE_WINDOWED
	get_window().size = FRAME_SIZE
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var tag: String = _out_dir.get_file()
	var path: String = "%s/%s-sunflare.png" % [_out_dir, tag]
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE saved=%s" % ProjectSettings.globalize_path(path))
	print("CAPTURE sun_flare_visibility=%f" % flare.current_visibility())
	get_tree().quit()
