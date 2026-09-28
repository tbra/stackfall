extends Node
## Bontago (options package): off-screen smoke-shots of the two Options menu
## tabs this package adds rows to -- the Settings tab (Master/Music/SFX
## volume + mute, rumble on/off + intensity) and the Controls tab (the
## device-aware mouse/stick move-speed slider, keyboard/mouse mode). Not part
## of the running game (CLAUDE.md: tools/); adapted from
## tools/screenshot_pt10_options_controls.gd's own SubViewport capture
## convention (an off-screen window gets clamped to a tiny size by Windows,
## so this renders into a fixed-size SubViewport instead).
##
## Run windowed, off-screen (owner convention: never on-screen, never
## --always-on-top/--maximized), quitting right after both captures are saved:
## godot --path . res://tools/screenshot_options_audio_rumble.tscn --windowed --position 10000,10000 --quit-after 90

const SETTINGS_OUTPUT_PATH: String = "res://docs/art_mockups/options_audio_rumble.png"
const CONTROLS_OUTPUT_PATH: String = "res://docs/art_mockups/options_controls_move_speed.png"
const SHOT_SIZE: Vector2i = Vector2i(1280, 900)
const SETTLE_FRAMES: int = 20

var _shot_viewport: SubViewport = null
var _menu: OptionsMenu = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://docs/art_mockups"))

	_shot_viewport = SubViewport.new()
	_shot_viewport.size = SHOT_SIZE
	_shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot_viewport)

	_menu = (load("res://ui/OptionsMenu.tscn") as PackedScene).instantiate() as OptionsMenu
	_shot_viewport.add_child(_menu)
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(SETTINGS_OUTPUT_PATH)

	(_menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(CONTROLS_OUTPUT_PATH)

	get_tree().quit()


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
