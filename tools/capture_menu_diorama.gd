extends Node

const MOMENTS_S: Array[float] = [0.2, 1.2, 3.8, 7.3]


func _ready() -> void:
	var output_dir: String = OS.get_environment("TEMP").path_join("captures")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var menu: MainMenu = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	viewport.add_child(menu)
	var elapsed: float = 0.0
	for index: int in range(MOMENTS_S.size()):
		var delay: float = MOMENTS_S[index] - elapsed
		await get_tree().create_timer(delay).timeout
		elapsed = MOMENTS_S[index]
		await RenderingServer.frame_post_draw
		var path: String = output_dir.path_join("main_menu_diorama_%d.png" % index)
		var error: Error = ContactSheet.save_capture(viewport.get_texture().get_image(), path)
		print("DIORAMA_CAPTURE %s error=%d" % [path, error])
	get_tree().quit()
