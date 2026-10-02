extends Node
## Bontago-mp0.27: windowed shot mid-countdown (own beacon camera, HUD up, big
## "2"/"1"). Run (agent probe rules, docs/AGENT_WORKFLOW.md):
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_countdown.tscn -- --agent-probe --render-size=1280x720

const OUTPUT_PATH: String = "user://countdown_candidate.png"
const WAIT_LIMIT_FRAMES: int = 60 * 40
const SHOT_REMAINING_S: float = 2.0
const SETTLE_FRAMES: int = 6

var _shot_viewport: SubViewport = null


func _ready() -> void:
	_shot_viewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_shot_viewport.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	Events.match_state_changed.connect(func(a: int, b: int) -> void: print("CDSHOT state %d -> %d" % [a, b]))
	main._loading_screen.readiness_timed_out.connect(func() -> void: print("CDSHOT loading timed out"))
	main.start_bots_from_menu("Tester")
	var config: MatchConfig = (load("res://config/match_defaults.tres") as MatchConfig).duplicate(true) as MatchConfig
	config.player_count = 2
	config.ai_count = 1
	config.hot_seat = false
	main._on_lobby_start_requested(config)
	var frames: int = 0
	while frames < WAIT_LIMIT_FRAMES:
		await get_tree().physics_frame
		frames += 1
		if Match.state() == Match.State.COUNTDOWN and Match.countdown_remaining() <= SHOT_REMAINING_S and not main._loading_screen.visible:
			break
	for _i: int in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = _shot_viewport.get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("CDSHOT saved=%s state=%d remaining=%.2f frames=%d loading_visible=%s" % [
		ProjectSettings.globalize_path(OUTPUT_PATH), Match.state(), Match.countdown_remaining(), frames, main._loading_screen.visible])
	get_tree().quit()
