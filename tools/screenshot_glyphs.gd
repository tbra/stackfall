extends Node
## Off-screen review of glyphs at the requested UI render size.

const SETTLE_FRAMES: int = 30
var _viewport: SubViewport


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://glyph_captures"))
	var render_size: Vector2i = Vector2i(1280, 720)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--render-size="):
			var parts: PackedStringArray = arg.trim_prefix("--render-size=").split("x")
			if parts.size() == 2:
				render_size = Vector2i(int(parts[0]), int(parts[1]))
	_viewport = SubViewport.new()
	_viewport.size = render_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	await _capture("res://ui/MainMenu.tscn", "menu")
	await _capture("res://ui/OptionsMenu.tscn", "options")
	var pause: PauseMenu = (load("res://ui/PauseMenu.tscn") as PackedScene).instantiate() as PauseMenu
	_viewport.add_child(pause)
	pause._open()
	await _wait_frames()
	await _save("pause")
	get_tree().quit()


func _capture(path: String, name: String) -> void:
	var scene: Control = (load(path) as PackedScene).instantiate() as Control
	_viewport.add_child(scene)
	await _wait_frames()
	await _save(name)
	_viewport.remove_child(scene)
	scene.queue_free()


func _wait_frames() -> void:
	for index: int in range(SETTLE_FRAMES):
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "res://glyph_captures/glyphs_%s_%s.png" % [name, _viewport.size.x]
	ContactSheet.save_capture(_viewport.get_texture().get_image(), path)
