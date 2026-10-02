extends Node
## In-match HUD review at the probe render size.

const SETTLE_FRAMES: int = 45
const OUTPUT_DIR: String = "res://captures"
var _shot_viewport: SubViewport = null


func _ready() -> void:
	_shot_viewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_shot_viewport.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.start_sandbox_from_menu()
	for _i: int in int(3.5 * Engine.physics_ticks_per_second) + SETTLE_FRAMES:
		await get_tree().physics_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	await _capture_at(Vector2i(1280, 720))
	await _capture_at(AgentProbe.parse_render_size(OS.get_cmdline_user_args()))
	get_tree().quit()


func _capture_at(render_size: Vector2i) -> void:
	if render_size == Vector2i.ZERO:
		return
	_shot_viewport.size = render_size
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path: String = OUTPUT_DIR.path_join("cx_hud_%dx%d.png" % [render_size.x, render_size.y])
	var image: Image = _shot_viewport.get_texture().get_image()
	var err: Error = ContactSheet.save_capture(image, path)
	print("HUD_CAPTURE %s error=%s" % [ProjectSettings.globalize_path(path), err])
