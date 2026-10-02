extends Node
## Bontago-1pi.23 evidence capture: main menu, lobby, HUD over a bright backdrop
## and the results screen, rendered through UiScale's real-window emulation.
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tools/capture_hud_fix.tscn -- --agent-probe --render-size=3440x1440

const SETTLE_FRAMES: int = 6
const OUT_DIR: String = "M:/Bontago/feedback/screenshots"
const SKY_TOP: Color = Color(0.62, 0.78, 0.92)
const GROUND: Color = Color(0.82, 0.70, 0.52)


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var menu: MainMenu = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	viewport.add_child(menu)
	menu.net_provider = _fake_net(false)
	await _settle()
	await _capture(viewport, "menu")
	menu.queue_free()
	await _settle()
	var lobby: Lobby = (load("res://ui/Lobby.tscn") as PackedScene).instantiate() as Lobby
	viewport.add_child(lobby)
	lobby.net_provider = _fake_net(true)
	lobby._update_host_only_state()
	await _settle()
	await _capture(viewport, "lobby")
	lobby.queue_free()
	await _settle()
	var backdrop: ColorRect = ColorRect.new()
	backdrop.color = SKY_TOP
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(backdrop)
	var ground: ColorRect = ColorRect.new()
	ground.color = GROUND
	ground.anchor_top = 0.55
	ground.anchor_right = 1.0
	ground.anchor_bottom = 1.0
	viewport.add_child(ground)
	var hud: HUD = (load("res://ui/HUD.tscn") as PackedScene).instantiate() as HUD
	viewport.add_child(hud)
	hud.set_territory_shares(PackedFloat32Array([0.4, 0.25, 0.2, 0.1]))
	hud.set_local_slot(0)
	hud.set_held_shape(load("res://config/blocks/L4.tres") as BlockShape)
	hud.set_next_shape(load("res://config/blocks/T4.tres") as BlockShape)
	hud.set_feed_seconds(4.0)
	hud.set_tower_and_block_height(7.9, 1.1)
	await _settle()
	await _capture(viewport, "hud")
	var results: ResultsScreen = (load("res://ui/ResultsScreen.tscn") as PackedScene).instantiate() as ResultsScreen
	viewport.add_child(results)
	results.net_provider = _fake_net(true)
	var rows: Array[Dictionary] = []
	for i: int in 4:
		rows.append({
			"slot_id": i, "name": "Player %d" % (i + 1), "team_id": i, "is_bot": i > 0,
			"blocks_placed": 20 + i, "blocks_lost": i, "gifts_claimed": 1, "specials_used": 1,
			"territory_share": 0.25, "eliminated_at": MatchStats.NOT_ELIMINATED,
		})
	Events.match_results_ready.emit({
		"winner_kind": MatchStats.WINNER_KIND_SLOT, "winner_id": 0, "winner_name": "Player 1",
		"match_duration": 120.0, "rows": rows,
		"mode": {"mode_id": MatchConfig.GameMode.CAPTURE_THE_FLAG, "scores": [499.7, 0.0, 0.0, 0.0]},
	})
	await _settle()
	await _capture(viewport, "results")
	get_tree().quit()


func _fake_net(host: bool) -> Variant:
	var script: GDScript = load("res://tests/unit/support/FakeNet.gd") as GDScript
	var fake: Variant = script.new()
	fake.is_host_value = host
	fake.is_offline_value = host
	return fake


func _settle() -> void:
	for _i: int in SETTLE_FRAMES:
		await get_tree().process_frame


func _capture(viewport: SubViewport, screen: String) -> void:
	await RenderingServer.frame_post_draw
	var size: Vector2i = viewport.size
	var path: String = "%s/hud_fix_%s_%dx%d.png" % [OUT_DIR, screen, size.x, size.y]
	var error: Error = viewport.get_texture().get_image().save_png(path)
	print("HUDFIX_CAPTURE %s error=%d" % [path, error])
