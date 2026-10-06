extends Node
## Off-screen contact sheet of the reworked lobby (Bontago-1pi.53, S1a/S1b, docs/
## LOBBY_REWORK_PLAN.md section 6): the host view with every Advanced block collapsed;
## then the same lobby in Reach the Sky with EVERY section's Advanced block open (GAME:
## gravity/tilt/hole/turn-based/mid-join, GIFTS: the per-gift checkboxes, EXPERIMENTS:
## the opt-in checks; ROUND shows Team height); and, when the settings column scrolls at
## this size, the same state scrolled to its end. Each shot is rendered into its own
## SubViewport-sized frame and the shots are stitched side by side into one PNG (scaled
## down when wider than MAX_SHEET_WIDTH). Not part of the running game (CLAUDE.md: tools/).
##
## Run (owner convention: off-screen, dummy audio, quits itself):
## godot --path . res://tools/screenshot_lobby_rework.tscn --windowed --position 10000,10000 \
##   --resolution 320x180 --audio-driver Dummy -- --agent-probe [--shot-size=1280x720] [--out=<png path>]

const DEFAULT_OUTPUT_PATH: String = "user://lobby_rework_sheet.png"
const OUT_ARG_PREFIX: String = "--out="
const SIZE_ARG_PREFIX: String = "--shot-size="
const LOBBY_SCENE: String = "res://ui/Lobby.tscn"
## Frames to let the panel lay out and the diorama settle before each shot.
const SETTLE_FRAMES: int = 30
const DEFAULT_SHOT_SIZE: Vector2i = Vector2i(1280, 720)
## A sheet wider than this is scaled down (keeps the PNG readable in the review tools).
const MAX_SHEET_WIDTH: int = 3840

var _viewport: SubViewport = null
var _shot_size: Vector2i = DEFAULT_SHOT_SIZE


func _ready() -> void:
	_shot_size = _requested_shot_size()
	_viewport = SubViewport.new()
	_viewport.size = _shot_size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)
	var lobby: Lobby = (load(LOBBY_SCENE) as PackedScene).instantiate() as Lobby
	_viewport.add_child(lobby)
	await _wait_frames(SETTLE_FRAMES)
	var shots: Array[Image] = [await _shoot()]

	var mode_option: CycleSelector = lobby.get_node("%GameModeOption") as CycleSelector
	mode_option.select(MatchConfig.GameMode.REACH_THE_SKY)
	mode_option.item_selected.emit(MatchConfig.GameMode.REACH_THE_SKY)
	for section: LobbySection in lobby._sections():
		section.set_advanced_open(true)
	await _wait_frames(SETTLE_FRAMES)
	shots.append(await _shoot())

	var scroll: ScrollContainer = lobby.get_node("%SettingsScroll") as ScrollContainer
	var scroll_end: int = int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
	if scroll_end > 0:
		scroll.scroll_vertical = scroll_end
		await _wait_frames(SETTLE_FRAMES)
		shots.append(await _shoot())

	var sheet: Image = Image.create(_shot_size.x * shots.size(), _shot_size.y, false, Image.FORMAT_RGBA8)
	for i: int in range(shots.size()):
		sheet.blit_rect(shots[i], Rect2i(Vector2i.ZERO, _shot_size), Vector2i(_shot_size.x * i, 0))
	if sheet.get_width() > MAX_SHEET_WIDTH:
		var scaled_height: int = int(float(sheet.get_height()) * MAX_SHEET_WIDTH / float(sheet.get_width()))
		sheet.resize(MAX_SHEET_WIDTH, scaled_height, Image.INTERPOLATE_BILINEAR)
	var path: String = _output_path()
	sheet.save_png(path)
	print("SCREENSHOT saved=%s size=%dx%d shots=%d scroll_end=%d" % [
		ProjectSettings.globalize_path(path), sheet.get_width(), sheet.get_height(), shots.size(), scroll_end,
	])
	get_tree().quit()


func _output_path() -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG_PREFIX):
			return arg.substr(OUT_ARG_PREFIX.length())
	return DEFAULT_OUTPUT_PATH


## --shot-size=WxH (e.g. 3440x1440); anything malformed keeps the default.
func _requested_shot_size() -> Vector2i:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(SIZE_ARG_PREFIX):
			var parts: PackedStringArray = arg.substr(SIZE_ARG_PREFIX.length()).split("x")
			if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
				return Vector2i(maxi(1, int(parts[0])), maxi(1, int(parts[1])))
	return DEFAULT_SHOT_SIZE


func _shoot() -> Image:
	await RenderingServer.frame_post_draw
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	return image


func _wait_frames(frames: int) -> void:
	for _i: int in range(frames):
		await get_tree().process_frame
