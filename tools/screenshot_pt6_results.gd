extends Node
## Windowed smoke-shot of ui/ResultsScreen.tscn (Bontago-1pi.6) with sample
## match-results data, for visual review only. Not part of the running game
## (CLAUDE.md: tools/); adapted from tools/screenshot_m7p7_menu.gd's own
## off-screen SubViewport-capture technique.
##
## Run windowed and off-screen (owner convention: never on-screen):
##   godot --path . res://tools/screenshot_pt6_results.tscn --windowed --position 10000,10000 --quit-after 5

const OUTPUT_PATH: String = "res://feedback/pt6-results.png"
const SETTLE_FRAMES: int = 20
const SHOT_SIZE: Vector2i = Vector2i(1280, 720)


func _ready() -> void:
	var shot_viewport: SubViewport = SubViewport.new()
	shot_viewport.size = SHOT_SIZE
	shot_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(shot_viewport)

	var screen: ResultsScreen = (load("res://ui/ResultsScreen.tscn") as PackedScene).instantiate()
	shot_viewport.add_child(screen)
	# Offline is_host() is true (autoload/Net.gd), so the real Net/MatchNet
	# singletons already give the host-enabled button state this sample shot
	# wants to show. Nothing else needs a fake provider.
	screen.show_results(_sample_results())

	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var image: Image = shot_viewport.get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("SCREENSHOT saved=%s size=%dx%d" % [
		ProjectSettings.globalize_path(OUTPUT_PATH), image.get_width(), image.get_height()
	])
	get_tree().quit()


func _sample_results() -> Dictionary:
	return {
		"winner_kind": MatchStats.WINNER_KIND_SLOT,
		"winner_id": 0,
		"winner_name": "Alice",
		"match_duration": 245.0,
		"rows": [
			{
				"slot_id": 0, "name": "Alice", "team_id": 0, "is_bot": false,
				"blocks_placed": 18, "blocks_lost": 2, "gifts_claimed": 3, "specials_used": 2,
				"territory_share": 0.52, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
			{
				"slot_id": 1, "name": "Bob", "team_id": 1, "is_bot": false,
				"blocks_placed": 14, "blocks_lost": 4, "gifts_claimed": 1, "specials_used": 1,
				"territory_share": 0.31, "eliminated_at": MatchStats.NOT_ELIMINATED,
			},
			{
				"slot_id": 2, "name": "Bot 1", "team_id": 2, "is_bot": true,
				"blocks_placed": 9, "blocks_lost": 6, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.17, "eliminated_at": 140.0,
			},
			{
				"slot_id": 3, "name": "Bot 2", "team_id": 3, "is_bot": true,
				"blocks_placed": 6, "blocks_lost": 7, "gifts_claimed": 0, "specials_used": 0,
				"territory_share": 0.0, "eliminated_at": 60.0,
			},
		],
	}
