extends Node
## Bontago-1pi.79 probe: real Main on a host with one bot; captures the match-start
## framing (camera + HUD) while the 3-2-1 runs, for comparison with
## feedback/ref_camera_start.png. Windowed off-screen, quits after the capture.

const OUTPUT_NAME: String = "pt79_start.png"
const MAX_FRAMES: int = 1800
const MAX_SHOTS: int = 14
const SHOT_INTERVAL_MS: int = 450
const POST_GO_MS: int = 2000
const RENDER_FALLBACK: Vector2i = Vector2i(1720, 720)

var _viewport: SubViewport = null


func _ready() -> void:
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_viewport = AgentProbe.make_render_viewport(self, RENDER_FALLBACK)
	_viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	Net.host_game(AgentProbe.free_udp_port(), "Tonyflow")
	main._start_headless_bot_match_with_args(PackedStringArray(["--bots=1", "--players=2"]))
	var rig: CameraRig = main._camera_rig
	var frames: int = 0
	var shots: int = 0
	var go_time_ms: int = -1
	var last_shot_ms: int = -1000000
	while frames < MAX_FRAMES and shots < MAX_SHOTS:
		await get_tree().process_frame
		frames += 1
		var state: int = Match.state()
		if state != Match.State.COUNTDOWN and state != Match.State.PLAYING:
			continue
		if state == Match.State.COUNTDOWN and Match._lifecycle.is_countdown_held():
			continue
		if state == Match.State.PLAYING and go_time_ms < 0:
			go_time_ms = Time.get_ticks_msec()
		if go_time_ms >= 0 and Time.get_ticks_msec() - go_time_ms > POST_GO_MS:
			break
		if Time.get_ticks_msec() - last_shot_ms < SHOT_INTERVAL_MS:
			continue
		last_shot_ms = Time.get_ticks_msec()
		await RenderingServer.frame_post_draw
		var path: String = "user://pt84_%02d.png" % shots
		_viewport.get_texture().get_image().save_png(path)
		var xf: Transform3D = rig.get_camera().global_transform
		print("PT84 shot=%d state=%d rem=%.2f pos=%s basis=%s file=%s" % [shots, state, Match.countdown_remaining(), xf.origin, xf.basis.get_euler(), ProjectSettings.globalize_path(path)])
		shots += 1
	get_tree().quit()
