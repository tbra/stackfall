extends Node

var output_dir: String = ""
const SETTLE_FRAMES: int = 4

func _ready() -> void:
	output_dir = OS.get_environment("TEMP").path_join("captures")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	for render_size: Vector2i in [viewport.size]:
		var menu: MainMenu = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
		viewport.add_child(menu)
		await _settle()
		await _capture(viewport, "main")
		menu._on_host_pressed()
		await _settle()
		await _capture(viewport, "host")
		menu._host_dialog.hide()
		menu._set_page(MainMenu.PAGE_JOIN)
		await _settle()
		await _capture(viewport, "join")
		menu._set_page(MainMenu.PAGE_LOCAL)
		await _settle()
		await _capture(viewport, "local")
		menu._on_options_pressed()
		await _settle()
		await _capture(viewport, "options_settings")
		var options: OptionsMenu = menu._options_menu
		options._controls_tab_button.button_pressed = true
		await _settle()
		await _capture(viewport, "options_controls")
		menu.queue_free()
		await _settle()
		var pause: PauseMenu = (load("res://ui/PauseMenu.tscn") as PackedScene).instantiate() as PauseMenu
		viewport.add_child(pause)
		pause.visible = true
		await _settle()
		await _capture(viewport, "pause")
		pause.queue_free()
		await _settle()
	get_tree().quit()

func _settle() -> void:
	for index: int in SETTLE_FRAMES:
		await get_tree().process_frame

func _capture(viewport: SubViewport, name: String) -> void:
	await RenderingServer.frame_post_draw
	var size: Vector2i = viewport.size
	var path: String = "%s/%d_%d_%s.png" % [output_dir, size.x, size.y, name]
	var image: Image = viewport.get_texture().get_image()
	var error: Error = ContactSheet.save_capture(image, path)
	print("MENU_CAPTURE %s error=%d" % [ProjectSettings.globalize_path(path), error])
