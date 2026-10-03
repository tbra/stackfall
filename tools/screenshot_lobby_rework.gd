extends Node
## Off-screen contact sheet of the reworked lobby (Bontago-1pi.53, S1a/S1b, docs/
## LOBBY_REWORK_PLAN.md section 6): the host view with every Advanced block collapsed,
## then the same lobby in Reach the Sky with the GAME Advanced block open (shows the
## Team height toggle and the gravity/tilt/hole/turn-based/mid-join controls). Both shots
## are rendered into one 1280x720 SubViewport each and stitched side by side into a
## single PNG. Not part of the running game (CLAUDE.md: tools/).
##
## Run (owner convention: off-screen, dummy audio, quits itself):
## godot --path . res://tools/screenshot_lobby_rework.tscn --windowed --position 10000,10000 \
##   --resolution 320x180 --audio-driver Dummy -- --agent-probe [--out=<png path>]

const DEFAULT_OUTPUT_PATH: String = "user://lobby_rework_sheet.png"
const OUT_ARG_PREFIX: String = "--out="
const LOBBY_SCENE: String = "res://ui/Lobby.tscn"
## Frames to let the panel lay out and the diorama settle before each shot.
const SETTLE_FRAMES: int = 30
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)

var _viewport: SubViewport = null


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = SHOT_SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var lobby: Lobby = (load(LOBBY_SCENE) as PackedScene).instantiate() as Lobby
	_viewport.add_child(lobby)
	await _wait_frames(SETTLE_FRAMES)
	var collapsed: Image = await _shoot()

	var mode_option: OptionButton = lobby.get_node("%GameModeOption") as OptionButton
	mode_option.select(MatchConfig.GameMode.REACH_THE_SKY)
	mode_option.item_selected.emit(MatchConfig.GameMode.REACH_THE_SKY)
	(lobby.get_node("%GameSection") as LobbySection).set_advanced_open(true)
	await _wait_frames(SETTLE_FRAMES)
	var opened: Image = await _shoot()

	var sheet: Image = Image.create(SHOT_SIZE.x * 2, SHOT_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.blit_rect(collapsed, Rect2i(Vector2i.ZERO, SHOT_SIZE), Vector2i.ZERO)
	sheet.blit_rect(opened, Rect2i(Vector2i.ZERO, SHOT_SIZE), Vector2i(SHOT_SIZE.x, 0))
	var path: String = _output_path()
	sheet.save_png(path)
	print("SCREENSHOT saved=%s size=%dx%d" % [ProjectSettings.globalize_path(path), sheet.get_width(), sheet.get_height()])
	get_tree().quit()


func _output_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG_PREFIX):
			return arg.substr(OUT_ARG_PREFIX.length())
	return DEFAULT_OUTPUT_PATH


func _shoot() -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _wait_frames(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame
