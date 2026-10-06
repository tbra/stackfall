extends Node
## Bontago-1pi.11.52: idle main-menu frame cost. Off-screen probe:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_menu_idle.tscn -- --agent-probe --render-size=1920x1080
## Prints one MENU_IDLE line per variant: GPU ms (menu viewport + diorama
## viewport, summed per rendered frame), renderer CPU ms, script/process ms and
## the frames per second the menu actually achieved. Variants toggle parts of
## the live menu so a ranked cost table falls out of one run.

const WARMUP_FRAMES: int = 30
const MEASURE_FRAMES: int = 120
const CAPTURE_ARG_PREFIX: String = "capture="

var _menu: MainMenu = null
var _viewport: SubViewport = null
var _diorama: MenuDiorama = null


func _ready() -> void:
	_viewport = AgentProbe.make_render_viewport(self, Vector2i(1920, 1080))
	_menu = (load("res://ui/MainMenu.tscn") as PackedScene).instantiate() as MainMenu
	_viewport.add_child(_menu)
	_diorama = _menu.find_child("Diorama", true, false) as MenuDiorama
	await _run()
	get_tree().quit()


func _run() -> void:
	var inner: SubViewport = _diorama.find_child("DioramaViewport", true, false) as SubViewport
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(inner.get_viewport_rid(), true)
	await _measure("as_shipped", inner)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with(CAPTURE_ARG_PREFIX):
			await RenderingServer.frame_post_draw
			var path: String = arg.trim_prefix(CAPTURE_ARG_PREFIX)
			_viewport.get_texture().get_image().save_png(path)
			print("MENU_IDLE_CAPTURE ", path)
	var saved_msaa: Viewport.MSAA = inner.msaa_3d
	inner.msaa_3d = Viewport.MSAA_DISABLED
	await _measure("diorama_msaa_off", inner)
	inner.msaa_3d = saved_msaa
	_diorama.visible = false
	await _measure("diorama_hidden", inner)
	_diorama.visible = true
	await _measure("as_shipped_again", inner)


func _measure(label: String, inner: SubViewport) -> void:
	for i: int in range(WARMUP_FRAMES):
		await get_tree().process_frame
	var gpu_main: float = 0.0
	var gpu_inner: float = 0.0
	var cpu_render: float = 0.0
	var process_ms: float = 0.0
	var start_us: int = Time.get_ticks_usec()
	for i: int in range(MEASURE_FRAMES):
		await get_tree().process_frame
		gpu_main += RenderingServer.viewport_get_measured_render_time_gpu(_viewport.get_viewport_rid())
		gpu_inner += RenderingServer.viewport_get_measured_render_time_gpu(inner.get_viewport_rid())
		cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(_viewport.get_viewport_rid())
		cpu_render += RenderingServer.viewport_get_measured_render_time_cpu(inner.get_viewport_rid())
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var elapsed_s: float = float(Time.get_ticks_usec() - start_us) / 1000000.0
	var frames: float = float(MEASURE_FRAMES)
	print("MENU_IDLE %s fps=%.1f gpu_menu_ms=%.3f gpu_diorama_ms=%.3f gpu_total_ms=%.3f render_cpu_ms=%.3f process_ms=%.3f" % [
		label, frames / elapsed_s, gpu_main / frames, gpu_inner / frames,
		(gpu_main + gpu_inner) / frames, cpu_render / frames, process_ms / frames,
	])
