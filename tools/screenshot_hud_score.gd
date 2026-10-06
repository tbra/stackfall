extends Node
## Bontago-1pi.80/.82 probe: the top-left HUD box, the in-round score card and
## the results card, each saved as a PNG. Run windowed with the agent-probe flags
## (docs/AGENT_WORKFLOW.md) and --render-size=1920x1080.

const SETTLE_FRAMES: int = 10
const FALLBACK_SIZE: Vector2i = Vector2i(1920, 1080)

var _vp: SubViewport


func _payload(live: bool) -> Dictionary:
	var rows: Array = []
	var names: PackedStringArray = ["Tonyflow", "Pixel", "Cosmos", "Friction"]
	for i: int in range(names.size()):
		rows.append({
			"slot_id": i, "name": names[i], "is_bot": i > 0, "team_id": i, "blocks_placed": 120 - i * 9,
			"blocks_lost": i * 20, "specials_used": 3 - i if i < 3 else 0, "height": 33.7 - i * 7.0,
			"territory_share": 0.58 - i * 0.15, "peak_territory": 0.6, "wins": 2 - i if i < 2 else 0,
			"eliminated_at": MatchStats.NOT_ELIMINATED if (live or i == 0) else 400.0 + i * 40.0,
			"is_winner": i == 0 and not live,
		})
	return {
		"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": 0, "winner_name": "Tonyflow", "live": live,
		"match_duration": 524.0, "rows": rows,
		"mode": {"mode_id": MatchConfig.GameMode.ELIMINATION, "scores": [1.0, 0.0, 0.0, 0.0], "winners": "0", "order": "3,2,1"},
	}


func _shot(name: String) -> void:
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _vp.get_texture().get_image()
	image.save_png("user://hud_score_%s.png" % name)
	print("SHOT %s %s %dx%d" % [name, ProjectSettings.globalize_path("user://hud_score_%s.png" % name), image.get_width(), image.get_height()])


func _ready() -> void:
	_vp = AgentProbe.make_render_viewport(self, FALLBACK_SIZE)
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = Color(0.35, 0.3, 0.35)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vp.add_child(backdrop)
	var hud: HUD = (load("res://ui/HUD.tscn") as PackedScene).instantiate()
	_vp.add_child(hud)
	await get_tree().process_frame
	hud.set_territory_shares(PackedFloat32Array([0.58, 0.31, 0.08, 0.02]))
	hud.set_height(3.0)
	hud.set_locked(true)
	hud._gift_toast_label.text = "Special queued: Jumping Bean"
	hud._gift_toast_label.modulate.a = 1.0
	await _shot("hud")
	var overlay: ScoreboardOverlay = (load("res://ui/ScoreboardOverlay.tscn") as PackedScene).instantiate()
	_vp.add_child(overlay)
	await get_tree().process_frame
	var live: Dictionary = _payload(true)
	overlay._mode_title.text = ResultsScreen.mode_title(live)
	ScoreTable.populate(overlay._rows_list, live, overlay.tuning)
	overlay.set_process(false)
	overlay._root.visible = true
	await _shot("scores_live")
	overlay.queue_free()
	var results: ResultsScreen = (load("res://ui/ResultsScreen.tscn") as PackedScene).instantiate()
	_vp.add_child(results)
	await get_tree().process_frame
	results.show_results(_payload(false))
	await _shot("results")
	get_tree().quit()
