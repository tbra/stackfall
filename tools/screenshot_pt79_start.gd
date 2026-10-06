extends Node
## Match-start camera probe (Bontago-1pi.79/84, redone for Bontago-1pi.90): real
## Main on a host, started through the lobby's own start path
## (Main._on_lobby_start_pressed) as a 2-player match against one bot, so the
## loading hand-off, the held countdown and its release all run as in the game.
## (The previous version started a headless bot match, whose config skips the
## countdown entirely.) Captures exactly two frames -- the first countdown frame
## after the loading screen is gone, and the first PLAYING frame -- prints both
## camera transforms, and quits. Windowed off-screen with --agent-probe.

const COUNTDOWN_OUTPUT: String = "user://pt90_countdown.png"
const PLAY_OUTPUT: String = "user://pt90_play.png"
const MAX_FRAMES: int = 3600
const RENDER_FALLBACK: Vector2i = Vector2i(1920, 1080)
const LOCAL_NAME: String = "Tonyflow"
const PLAYERS: int = 2
const BOTS: int = 1

var _viewport: SubViewport = null


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_viewport = AgentProbe.make_render_viewport(self, RENDER_FALLBACK)
	_viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	Net.host_game(AgentProbe.free_udp_port(), LOCAL_NAME)
	await get_tree().process_frame
	var config: MatchConfig = (main.match_config as MatchConfig).duplicate(true)
	config.player_count = PLAYERS
	config.ai_count = BOTS
	main._on_lobby_start_pressed(config)
	var rig: CameraRig = main._camera_rig
	var countdown_xf: Transform3D = Transform3D()
	var shot_countdown: bool = false
	for _frame: int in range(MAX_FRAMES):
		await get_tree().process_frame
		var state: int = Match.state()
		if not shot_countdown and state == Match.State.COUNTDOWN and not Match._lifecycle.is_countdown_held() and not main._loading_screen.visible:
			countdown_xf = await _capture(rig, COUNTDOWN_OUTPUT, "countdown")
			shot_countdown = true
		elif shot_countdown and state == Match.State.PLAYING:
			var play_xf: Transform3D = await _capture(rig, PLAY_OUTPUT, "play")
			print("PT90 shift_m=%.5f" % play_xf.origin.distance_to(countdown_xf.origin))
			break
	get_tree().quit()


func _capture(rig: CameraRig, path: String, label: String) -> Transform3D:
	var xf: Transform3D = rig.get_camera().global_transform
	await RenderingServer.frame_post_draw
	_viewport.get_texture().get_image().save_png(path)
	print("PT90 %s state=%d rem=%.2f pos=%s basis=%s target=%s file=%s" % [label, Match.state(), Match.countdown_remaining(), xf.origin, xf.basis.get_euler(), rig.get_target(), ProjectSettings.globalize_path(path)])
	return xf
