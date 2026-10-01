extends Node
## Windowed smoke-shot of the Bontago-1pi.7 restyled pause menu (owner:
## "In-game pause menu doesn't match the rest of the menu graphically, also
## remove quit game as an option") -- confirms the cream-card/pastel-pill
## look now matches ui/MainMenu.tscn/ui/Lobby.tscn and that Quit game is gone.
## Not part of the running game (CLAUDE.md: tools/); adapted from
## tools/screenshot_m7p7_menu.gd.
##
## Run windowed, off-screen (owner convention: never on-screen, never
## --always-on-top/--maximized):
## godot --path . res://tools/screenshot_pt7_pause.tscn --windowed --position 10000,10000 --quit-after 60

const OUTPUT_PATH: String = "res://feedback/pt7-pause.png"
## Frames to let the panel lay out before the shot.
const SETTLE_FRAMES: int = 20
## Off-screen windows get clamped to a tiny size by Windows, so the scene is
## rendered inside a fixed-size SubViewport and that texture is captured.
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)

var _shot_viewport: SubViewport = null


func _ready() -> void:
	_shot_viewport = SubViewport.new()
	_shot_viewport.size = SHOT_SIZE
	_shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot_viewport)

	var menu: PauseMenu = (load("res://ui/PauseMenu.tscn") as PackedScene).instantiate() as PauseMenu
	_shot_viewport.add_child(menu)
	menu._open()
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(OUTPUT_PATH)
	get_tree().quit()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _shot_viewport.get_texture().get_image()
	var globalized: String = ProjectSettings.globalize_path(path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))
	ContactSheet.save_capture(image, globalized)
	print("SCREENSHOT saved=%s size=%dx%d" % [globalized, image.get_width(), image.get_height()])


func _wait_frames(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame
