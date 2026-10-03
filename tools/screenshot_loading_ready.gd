extends Node
## Bontago-1pi.32 L2: windowed off-screen capture of the loading screen's ready
## prompt, status line and player ready list. Not part of the running game
## (CLAUDE.md). Run (agent probe rules, docs/AGENT_WORKFLOW.md):
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 \
##     --audio-driver Dummy res://tools/screenshot_loading_ready.tscn \
##     -- --agent-probe --render-size=1280x720 --mode=main --out=<file.png>
## --mode=main  the real Main flow vs 7 bots (8 rows), prompt not pressed yet.
## --mode=fake  an isolated overlay on a fake 4-human host, local player pressed
##              and one other human ready (waiting line, disabled prompt, cap).

const MODE_ARG: String = "--mode="
const OUT_ARG: String = "--out="
const VARIANT_ARG: String = "--variant="
const MODE_FAKE: String = "fake"
const DEFAULT_OUT: String = "user://loading_ready.png"
const WAIT_LIMIT_FRAMES: int = 60 * 40
const SETTLE_FRAMES: int = 12
const FAKE_PLAYERS: int = 4
const FAKE_BOTS: int = 1
const MAIN_PLAYERS: int = 8
const MAIN_BOTS: int = 7
const TINY_FIELD_RADIUS: float = 20.0
const FAKE_OTHER_READY_PEER: int = 2

var _shot_viewport: SubViewport = null


func _ready() -> void:
	var mode: String = _arg_value(MODE_ARG, "main")
	var out_path: String = _arg_value(OUT_ARG, DEFAULT_OUT)
	_shot_viewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var screen: LoadingScreen = null
	if mode == MODE_FAKE:
		screen = await _fake_overlay()
	else:
		screen = await _main_overlay()
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _shot_viewport.get_texture().get_image()
	var err: Error = image.save_png(out_path)
	print("LOADREADY saved=%s err=%d mode=%s size=%s status='%s' cap='%s' prompt=%s glyphs=%s" % [
		ProjectSettings.globalize_path(out_path) if out_path.begins_with("user://") else out_path,
		err, mode, _shot_viewport.size, screen._status_label.text, screen._cap_label.text,
		screen._ready_button.visible, screen.prompt_glyph_texts()])
	get_tree().quit()


func _main_overlay() -> LoadingScreen:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_shot_viewport.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	main.start_bots_from_menu("Tester")
	# Bontago-1pi.32 L3: a probe run never arms the ready gate on its own (review,
	# MatchLifecycle.arm_loading_ready_gate), so this tool forces it.
	Match._lifecycle.set_loading_gate_forced(true)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.player_count = MAIN_PLAYERS
	config.ai_count = MAIN_BOTS
	config.hot_seat = false
	# Bontago-mp0.96: optional --variant=<round|oval|ring|twin|cross> picks the arena plate.
	var variant_name: String = _arg_value(VARIANT_ARG, "").to_upper()
	if MatchConfig.MapVariant.has(variant_name):
		config.map_variant = MatchConfig.MapVariant[variant_name] as MatchConfig.MapVariant
	main._on_lobby_start_requested(config)
	var screen: LoadingScreen = main._loading_screen
	var frames: int = 0
	while frames < WAIT_LIMIT_FRAMES and not screen.accepts_ready_input():
		await get_tree().process_frame
		frames += 1
	return screen


func _fake_overlay() -> LoadingScreen:
	var map: MapDef = (load("res://config/maps/round_medium.tres") as MapDef).duplicate(true) as MapDef
	map.field_radius = TINY_FIELD_RADIUS
	var field: Field = Field.new()
	field.map_def = map
	add_child(field)
	var blocks_root: Node3D = Node3D.new()
	add_child(blocks_root)
	var registry: BlockRegistry = BlockRegistry.new()
	add_child(registry)
	Match.register_world(field, registry, blocks_root)
	var peers: Dictionary = {}
	for i: int in range(FAKE_PLAYERS - FAKE_BOTS):
		peers[i + 1] = i
	Match.set_net_provider(FakeNet.host(peers, [0] as Array[int]))
	Match._lifecycle.set_loading_gate_forced(true)
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.set_script(load("res://tests/unit/support/TinyMapMatchConfig.gd"))
	(config as TinyMapMatchConfig).set_tiny_map(map)
	config.player_count = FAKE_PLAYERS
	config.ai_count = FAKE_BOTS
	config.gifts_enabled = false
	Match.start_match(config)
	var screen: LoadingScreen = (load("res://ui/LoadingScreen.tscn") as PackedScene).instantiate() as LoadingScreen
	_shot_viewport.add_child(screen)
	var slots: Array[PlayerSlot] = []
	for slot_id: int in range(Match.slot_count()):
		slots.append(Match.slot(slot_id))
	screen.show_for_match(Match.config, slots)
	screen.fade_out()
	await get_tree().process_frame
	screen.press_ready()
	Events.net_loading_ready_received.emit(FAKE_OTHER_READY_PEER)
	return screen


func _arg_value(prefix: String, fallback: String) -> String:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.trim_prefix(prefix)
	return fallback
