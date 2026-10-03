extends Node
## Bontago-1pi.37 evidence probe: the pause menu (one coral, one cream, one
## dark-slate pill, each with an icon) once with the cream Options pill focused
## and once with the dark Leave pill focused, so the focused icon colour on a
## light and on a dark pill can be judged. Run off-screen:
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/capture_menu_icons.tscn -- --agent-probe --render-size=1280x720 [--capture-dir=<dir>]

const SETTLE_FRAMES: int = 4
const DEFAULT_SIZE: Vector2i = Vector2i(1280, 720)
const CAPTURE_DIR_PREFIX: String = "--capture-dir="


func _ready() -> void:
	var output_dir: String = OS.get_environment("TEMP").path_join("captures")
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(CAPTURE_DIR_PREFIX):
			output_dir = arg.trim_prefix(CAPTURE_DIR_PREFIX)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, DEFAULT_SIZE)
	var pause: PauseMenu = (load("res://ui/PauseMenu.tscn") as PackedScene).instantiate() as PauseMenu
	viewport.add_child(pause)
	pause.visible = true
	await _settle()
	var focus_targets: Dictionary = {
		"pause_focus_light_options": pause.get_node("%OptionsButton") as Button,
		"pause_focus_dark_leave": pause.get_node("%LeaveButton") as Button,
	}
	for capture_name: String in focus_targets:
		(focus_targets[capture_name] as Button).grab_focus()
		await _settle()
		await _capture(viewport, output_dir, capture_name)
	get_tree().quit()


func _settle() -> void:
	for index: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _capture(viewport: SubViewport, output_dir: String, capture_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s.png" % [output_dir, capture_name]
	var error: Error = ContactSheet.save_capture(viewport.get_texture().get_image(), path)
	print("MENU_ICON_CAPTURE %s error=%d" % [path, error])
