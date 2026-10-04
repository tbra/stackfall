extends Node
## Bontago-1pi.79 probe: real Main on a host with one bot; captures the match-start
## framing (camera + HUD) while the 3-2-1 runs, for comparison with
## feedback/ref_camera_start.png. Windowed off-screen, quits after the capture.

const OUTPUT_NAME: String = "pt79_start.png"
const MAX_FRAMES: int = 1800
const CAPTURE_COUNTDOWN_S: float = 2.2
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
	var frames: int = 0
	while frames < MAX_FRAMES and not _ready_to_shoot():
		await get_tree().process_frame
		frames += 1
	await RenderingServer.frame_post_draw
	var rig: CameraRig = main._camera_rig
	print("PT79 state=%d rem=%.2f start=%s cam=%s" % [Match.state(), Match.countdown_remaining(), rig.is_start_framing(), rig.get_camera().global_position])
	var image: Image = _viewport.get_texture().get_image()
	var path: String = "user://%s" % OUTPUT_NAME
	image.save_png(path)
	print("PT79 saved=%s" % ProjectSettings.globalize_path(path))
	get_tree().quit()


func _ready_to_shoot() -> bool:
	if Match.state() == Match.State.PLAYING:
		return true
	return Match.state() == Match.State.COUNTDOWN and not Match._lifecycle.is_countdown_held() and Match.countdown_remaining() < CAPTURE_COUNTDOWN_S
