extends Node
## Bontago-1pi.10: off-screen smoke-shots of the redesigned Options menu's
## Controls page, once in each device mode -- keyboard/mouse (the default)
## and gamepad (forced via Settings.set_active_input_device_for_test(), the
## same test seam tests/unit/test_input_device.gd uses, since a real gamepad
## is not available headlessly). Not part of the running game (CLAUDE.md:
## tools/); adapted from tools/screenshot_m7p7_menu.gd's own SubViewport
## capture convention (an off-screen window gets clamped to a tiny size by
## Windows, so this renders into a fixed-size SubViewport instead).
##
## Run windowed, off-screen (owner convention: never on-screen, never
## --always-on-top/--maximized), quitting right after both captures are saved:
## godot --path . res://tools/screenshot_pt10_options_controls.tscn --windowed --position 10000,10000 --quit-after 90

const KBM_OUTPUT_PATH: String = "res://feedback/pt10-controls-kbm.png"
const GAMEPAD_OUTPUT_PATH: String = "res://feedback/pt10-controls-pad.png"
const SHOT_SIZE: Vector2i = Vector2i(1280, 900)
const SETTLE_FRAMES: int = 20

var _shot_viewport: SubViewport = null
var _menu: OptionsMenu = null


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))

	_shot_viewport = SubViewport.new()
	_shot_viewport.size = SHOT_SIZE
	_shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_shot_viewport)

	_menu = (load("res://ui/OptionsMenu.tscn") as PackedScene).instantiate() as OptionsMenu
	_shot_viewport.add_child(_menu)
	await _wait_frames(SETTLE_FRAMES)

	(_menu.get_node("%ControlsTabButton") as Button).button_pressed = true
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(KBM_OUTPUT_PATH)

	Settings.set_active_input_device_for_test(Settings.DEVICE_GAMEPAD)
	await _wait_frames(SETTLE_FRAMES)
	await _shoot(GAMEPAD_OUTPUT_PATH)

	Settings.set_active_input_device_for_test(Settings.DEFAULT_ACTIVE_DEVICE)
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
