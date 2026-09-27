extends Node
## Bontago-1pi.1 evidence probe (owner playtest: "there are 2 suns, one built
## in to the skybox and another with the lens flares"): points the camera
## straight at config/sun_flare.tres's own sun_direction (the same value
## shaders/sunset_clouds.gdshader's own sun_direction uniform defaults to --
## see that shader's DECISION comment) and captures a single off-screen frame
## so the fix (zeroing that shader's sun_core_intensity/sun_halo_intensity
## defaults, per Bontago-1pi.1) can be checked by eye: exactly one bright
## disc (the painted panorama sun, reinforced by vfx/SunFlare.gd's
## screen-space sparkle), not two.
##
## Same camera-placement idiom as tools/capture_sun_flare_probe.gd (stand
## back from the field center, look straight down `direction`), and the same
## off-screen-safe SubViewport-less direct capture that tool already uses
## (this probe does need the real window's own CanvasLayer -- vfx/SunFlare.gd
## draws onto the window's own Viewport, not a fresh SubViewport -- so it
## cannot use tools/screenshot_xtq28_sunset_fog.gd's own large-shot SubViewport
## trick, which only mirrors the 3D world, not 2D CanvasLayers).
##
## Run off-screen (owner rule, 2026-09-23):
##   godot --path . --windowed --position 10000,10000 \
##       res://tools/screenshot_pt1_single_sun.tscn
##
## Lives in tools/ (CLAUDE.md: build-time/manual-QA scripts, not part of the
## running game) -- this package's own evidence tool, not owned by another
## package.

const OUTPUT_PATH: String = "res://feedback/pt1-single-sun.png"
const SETTLE_S: float = 1.5


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))

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
	camera.global_position = -direction * 45.0 + Vector3.UP * 6.0
	camera.look_at(camera.global_position + direction, Vector3.UP)

	# vfx/SunFlare.gd's own class doc: a freshly moved camera's rendering
	# transform lags one physics tick behind a script write until a physics
	# step syncs it (physics interpolation) -- wait a couple of ticks before
	# reading back the projected flare.
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().create_timer(0.3).timeout

	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT pt1-single-sun saved=%s size=%s sun_flare_visibility=%f" % [
		ProjectSettings.globalize_path(OUTPUT_PATH), image.get_size(), flare.current_visibility(),
	])
	get_tree().quit()
