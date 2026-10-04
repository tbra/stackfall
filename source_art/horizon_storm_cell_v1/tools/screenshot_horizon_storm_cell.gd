extends Node3D
## Owner preview for the standalone horizon storm cell. Capture in a small
## isolated project window; does not load or modify game Skybox/weather state.

const OUTPUT_DIR: String = "res://docs/art_mockups/horizon_storm_cell_v1/"


func _ready() -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await get_tree().create_timer(0.45).timeout
	var storm: Node = get_node("HorizonStormCell")
	for style_index: int in range(3):
		storm.call("set_silhouette_style", style_index)
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await _save_capture("storm_silhouette_%d.png" % (style_index + 1))
	var camera: Camera3D = get_node("Camera3D")
	camera.position.z = 140.0
	storm.call("_start_flash")
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await _save_capture("storm_cell_lightning.png")
	get_tree().quit()


func _save_capture(file_name: String) -> void:
	var image: Image = get_viewport().get_texture().get_image()
	var absolute_dir: String = ProjectSettings.globalize_path(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(absolute_dir)
	var output_path: String = OUTPUT_DIR + file_name
	var error: Error = image.save_png(output_path)
	if error != OK:
		push_error("Could not save storm cell preview %s: %s" % [output_path, error_string(error)])
	else:
		print("STORM_CELL_PREVIEW saved=%s size=%s" % [ProjectSettings.globalize_path(output_path), image.get_size()])
