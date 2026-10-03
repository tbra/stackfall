extends Node
## Bontago-1pi.46 R1 visual pair (docs/MATCH_RESET_AUDIT.md G1/G2): match B started
## after match A (Night + rain, then a storm) must look like match B started first.
## One process plays: fresh B, A, leave, B again (reset listeners live), leave, A
## again, leave, B once more with the sky/weather reset listeners DISCONNECTED (the
## pre-R1 behaviour, to show the fault). Each B is captured at the same point of
## its run. Prints per-capture sky numbers and the pixel difference to the fresh B,
## and saves a contact sheet: top row A end state | fresh B, bottom row B after A
## (fixed) | B after A (reset listeners disconnected).
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/probe_reset_sky.tscn -- --agent-probe --render-size=640x360
const CAPTURE_SIZE: Vector2i = Vector2i(640, 360)
const SETTLE_SECONDS: float = 1.5
const WAIT_STATE_TIMEOUT_S: float = 40.0
const PLAYING_EXTRA_PHYSICS_FRAMES: int = 30
const A_RAIN_SECONDS: float = 10.0
const A_STORM_SECONDS: float = 8.0
const HARD_DEADLINE_S: float = 300.0
const PLAYER_COUNT: int = 2
const RNG_SEED: int = 777
const DIFF_THRESHOLD: float = 8.0 / 255.0
const SHEET_GAP_PX: int = 4

var _main: Node = null
var _viewport: SubViewport = null


func _ready() -> void:
	get_tree().create_timer(HARD_DEADLINE_S).timeout.connect(_deadline)
	call_deferred("_run")


func _deadline() -> void:
	printerr("PROBE hard deadline reached; quitting")
	get_tree().quit(1)


func _run() -> void:
	_viewport = AgentProbe.make_render_viewport(self, CAPTURE_SIZE)
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_viewport.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var fresh: Image = await _play_b("fresh_b")
	await _leave()
	var a_end: Image = await _play_a()
	await _leave()
	var fixed: Image = await _play_b("b_after_a_fixed")
	await _leave()
	_disconnect_sky_reset_listeners()
	await _play_a()
	await _leave()
	var broken: Image = await _play_b("b_after_a_no_reset")
	await _leave()
	_report("fixed", fresh, fixed)
	_report("no_reset", fresh, broken)
	_save_sheet([a_end, fresh, fixed, broken])
	get_tree().quit()


func _config(sky_mode: MatchConfig.SkyThemeMode, weather: MatchConfig.WeatherMode) -> MatchConfig:
	var config: MatchConfig = load("res://config/match_defaults.tres").duplicate(true) as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.player_count = PLAYER_COUNT
	config.hot_seat = false
	config.rng_seed = RNG_SEED
	config.sky_theme_mode = sky_mode
	config.weather_mode = weather
	return config


func _start(config: MatchConfig) -> void:
	var result: int = Net.host_game(AgentProbe.free_udp_port(), "Probe")
	if result != OK:
		printerr("PROBE host_game failed: %s" % result)
	await get_tree().process_frame
	_main.call("_on_lobby_start_requested", config)


func _wait_playing() -> void:
	var waited: float = 0.0
	while Match.state() != Match.State.PLAYING and waited < WAIT_STATE_TIMEOUT_S:
		await get_tree().physics_frame
		waited += 1.0 / Engine.physics_ticks_per_second
	for _i: int in range(PLAYING_EXTRA_PHYSICS_FRAMES):
		await get_tree().physics_frame


func _play_b(label: String) -> Image:
	await _start(_config(MatchConfig.SkyThemeMode.CYCLE, MatchConfig.WeatherMode.OFF))
	await _wait_playing()
	return await _capture(label)


func _play_a() -> Image:
	await _start(_config(MatchConfig.SkyThemeMode.NIGHT, MatchConfig.WeatherMode.RAIN))
	await _wait_playing()
	print("PROBE a: rain start=%s" % Match.weather().start_event(&"rain"))
	await get_tree().create_timer(A_RAIN_SECONDS).timeout
	print("PROBE a: storm start=%s" % Match.weather().start_event(&"storm"))
	await get_tree().create_timer(A_STORM_SECONDS).timeout
	return await _capture("a_end")


func _leave() -> void:
	Net.leave()
	await get_tree().process_frame
	await get_tree().process_frame


func _capture(label: String) -> Image:
	for _i: int in range(4):
		await RenderingServer.frame_post_draw
	var skybox: Skybox = _main.get_node("Skybox") as Skybox
	var presenter: WeatherPresenter = get_tree().root.find_child("WeatherPresenter", true, false) as WeatherPresenter
	var ceiling: CloudCeiling = presenter.cloud_ceiling() if presenter != null else null
	print("PROBE %s: state=%s cycle=%s locked=%.2f storm=%.3f overcast=%.3f cloud_overcast=%.3f wfog=%.3f ceiling=%.3f/%.3f/%.3f theme=%s" % [
		label, Match.State.find_key(Match.state()), skybox.is_cycle_active(), skybox.locked_phase(),
		skybox.storm_sky_amount(), skybox.overcast_amount(), skybox.cloud_overcast_amount(), skybox.weather_fog_amount(),
		ceiling.amount() if ceiling != null else -1.0, ceiling.storm_amount() if ceiling != null else -1.0,
		ceiling.overcast() if ceiling != null else -1.0, skybox.config.theme_name])
	var image: Image = _viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGBA8)
	image.save_png("user://reset_sky_%s.png" % label)
	return image


## Pre-R1 behaviour for the sky half: the Skybox, cloud ceiling and presenter no longer
## hear the reset (Main's own camera / puddle reset keeps running).
func _disconnect_sky_reset_listeners() -> void:
	for connection: Dictionary in Events.match_scope_reset.get_connections():
		var callable: Callable = connection["callable"] as Callable
		var target: Object = callable.get_object()
		if target is Skybox or target is CloudCeiling or target is WeatherPresenter:
			Events.match_scope_reset.disconnect(callable)
			print("PROBE disconnected %s" % target.get_class())


func _report(label: String, reference: Image, candidate: Image) -> void:
	var sum: float = 0.0
	var differing: int = 0
	var count: int = reference.get_width() * reference.get_height()
	for y: int in range(reference.get_height()):
		for x: int in range(reference.get_width()):
			var a: Color = reference.get_pixel(x, y)
			var b: Color = candidate.get_pixel(x, y)
			var delta: float = (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			sum += delta
			if delta > DIFF_THRESHOLD:
				differing += 1
	print("PROBE diff_vs_fresh %s: mean_abs=%.5f differing_px=%.2f%%" % [label, sum / float(count), 100.0 * float(differing) / float(count)])


func _save_sheet(images: Array[Image]) -> void:
	var width: int = CAPTURE_SIZE.x
	var height: int = CAPTURE_SIZE.y
	var sheet: Image = Image.create(width * 2 + SHEET_GAP_PX, height * 2 + SHEET_GAP_PX, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.MAGENTA)
	for index: int in range(images.size()):
		var column: int = index % 2
		var row: int = floori(float(index) / 2.0)
		var source: Image = images[index]
		sheet.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i(column * (width + SHEET_GAP_PX), row * (height + SHEET_GAP_PX)))
	var path: String = "user://reset_sky_sheet.png"
	sheet.save_png(path)
	print("PROBE sheet=%s" % ProjectSettings.globalize_path(path))
