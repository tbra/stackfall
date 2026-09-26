extends Node
## Windowed smoke-shot of the M7 P7 reskinned main menu and lobby
## (docs/M7_PLAN.md "P7 -- Main menu / lobby reskin", Bontago-xtq.32): the
## stackfall_theme.tres Theme applied to ui/MainMenu.tscn and ui/Lobby.tscn
## plus each scene's MenuDiorama SubViewport background rendering behind the
## panel. Not part of the running game (CLAUDE.md: tools/); adapted from
## tools/screenshot_m3a_menu.gd.
##
## Run windowed, off-screen (owner convention: never on-screen, never
## --always-on-top/--maximized; --windowed keeps it off-screen now the project
## defaults to borderless fullscreen, Bontago-xtq.45, and --quit-after 3 was
## too short to reach both captures -- review finding #3):
## godot --path . res://tools/screenshot_m7p7_menu.tscn --windowed --position 10000,10000 --quit-after 90

const MENU_OUTPUT_PATH: String = "user://m7p7_menu.png"
const LOBBY_OUTPUT_PATH: String = "user://m7p7_lobby.png"
## Frames to let each panel lay out and its diorama camera settle before the shot.
const SETTLE_FRAMES: int = 30
## Off-screen windows get clamped to a tiny size by Windows, so each scene is
## rendered inside a fixed-size SubViewport and that texture is captured.
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)

var _shot_viewport: SubViewport = null


func _ready() -> void:
	_shot_viewport = SubViewport.new()
	_shot_viewport.size = SHOT_SIZE
	_shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot_viewport)

	await _capture_scene("res://ui/MainMenu.tscn", MENU_OUTPUT_PATH)
	await _capture_scene("res://ui/Lobby.tscn", LOBBY_OUTPUT_PATH)
	get_tree().quit()


func _capture_scene(scene_path: String, output_path: String) -> void:
	var instance: Control = (load(scene_path) as PackedScene).instantiate()
	_shot_viewport.add_child(instance)
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(output_path)
	_shot_viewport.remove_child(instance)
	instance.queue_free()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = _shot_viewport.get_texture().get_image()
	image.save_png(path)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(path), image.get_width(), image.get_height()
	])


func _wait_frames(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame
