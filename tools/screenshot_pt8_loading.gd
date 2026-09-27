extends Node
## Windowed off-screen capture for Bontago-1pi.8 (owner playtest: "add a
## proper loading screen instead" of the idle centre-beacon camera shot).
## Not part of the running game (CLAUDE.md); run as:
##   godot --windowed --position 10000,10000 --path . --scene res://tools/screenshot_pt8_loading.tscn
##
## One piece of evidence (probe-ceiling discipline, docs/AGENT_WORKFLOW.md):
## ui/LoadingScreen.gd shown with a representative map name, player list and
## bot marker, and the spinner label mid-animation -- proving the styled
## overlay (ui/theme/stackfall_theme.tres + MenuStyleFactory's card) actually
## renders, fully opaque, with no 3D content visible behind it.

const OUTPUT: String = "res://feedback/pt8-loading.png"


func _ready() -> void:
	var screen: LoadingScreen = (load("res://ui/LoadingScreen.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(screen)
	await get_tree().process_frame
	await get_tree().process_frame

	var config: MatchConfig = MatchConfig.new()
	config.map_variant = MatchConfig.MapVariant.ROUND
	config.map_size = MapDef.MapSize.MEDIUM
	var slots: Array[PlayerSlot] = [
		PlayerSlot.new(0, 0, "Player 1", Color.RED),
		PlayerSlot.new(1, 1, "Player 2", Color.BLUE),
		PlayerSlot.new(2, 2, "Player 3", Color.GREEN),
	]
	slots[2].is_bot = true
	screen.show_for_match(config, slots)

	await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var full: Image = get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://feedback"))
	full.save_png(OUTPUT)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(OUTPUT), full.get_width(), full.get_height(),
	])
	get_tree().quit()
