extends Node
## Windowed smoke-shot of the M3a main menu and lobby (integrator
## verification step, docs/M3a_PLAN.md integration order step 5: "a windowed
## 2-instance pass for feel" starts here with a look at the screens
## themselves). Not part of the running game (CLAUDE.md: tools/).
##
## Run windowed (not headless, or the image is whatever the dummy rasterizer
## produces): godot --path . res://tools/screenshot_m3a_menu.tscn

const MENU_OUTPUT_PATH: String = "user://m3a_menu.png"
const LOBBY_OUTPUT_PATH: String = "user://m3a_lobby.png"
## Frames to let the menu lay out / the lobby populate before each shot.
const SETTLE_FRAMES: int = 20


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(main)
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(MENU_OUTPUT_PATH)

	# The same thing clicking Host on the menu does (autoload/Net.gd), so the
	# lobby comes up exactly as game/Main.gd's Events.net_mode_changed
	# handler would show it to a real player.
	Net.host_game(0, "Screenshot")
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(LOBBY_OUTPUT_PATH)

	get_tree().quit()


func _shoot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(path), image.get_width(), image.get_height()
	])


func _wait_frames(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame
