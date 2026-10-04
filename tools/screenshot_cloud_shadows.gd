extends Node
## Bontago-mp0.127: day / dusk captures of the cloud shadows plus a GPU-time A/B (shadows off
## vs on, 3 alternating sample blocks each, medians printed). One process:
##   godot --path . --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy res://tools/screenshot_cloud_shadows.tscn -- --agent-probe --render-size=1280x720 out=<dir>
const SETTLE_SECONDS: float = 1.5
const DRAW_FRAMES: int = 6
const DAY_PHASE: float = 0.2
const DUSK_PHASE: float = 0.44
const SWEEP_WAIT_S: float = 9.0
const SAMPLE_FRAMES: int = 90
const SAMPLE_BLOCKS: int = 3

var _out_dir: String = "user://"


func _ready() -> void:
	call_deferred("_capture")


func _capture() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("out="):
			_out_dir = arg.trim_prefix("out=").trim_suffix("/") + "/"
	Settings.set_graphics_preset(&"high")
	var viewport: SubViewport = AgentProbe.make_render_viewport(self, Vector2i(1280, 720))
	var main: Node = (load("res://game/Main.tscn") as PackedScene).instantiate()
	viewport.add_child.call_deferred(main)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var config: MatchConfig = main.get("match_config") as MatchConfig
	config.map_size = MapDef.MapSize.SMALL
	config.sky_theme_mode = MatchConfig.SkyThemeMode.CYCLE
	main.call("start_sandbox_from_menu")
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	var skybox: Skybox = main.get_node("Skybox") as Skybox
	skybox.configure_match_sky(config)
	skybox.set_process(false)
	var shadows: CloudShadows = main.get_node("CloudShadows") as CloudShadows
	skybox.set_cycle_phase(DAY_PHASE)
	await _frames()
	shadows._on_graphics_preset_changed(_preset(false))
	await _frames()
	_save(viewport, "day_off")
	shadows._on_graphics_preset_changed(_preset(true))
	await _frames()
	_save(viewport, "day_a")
	var tex: Image = shadows.decals()[0].texture_albedo.get_image()
	var opaque: int = 0
	for y: int in range(0, tex.get_height(), 4):
		for x: int in range(0, tex.get_width(), 4):
			if tex.get_pixel(x, y).a > 0.5:
				opaque += 1
	for layer: int in range(2):
		var decal: Decal = shadows.decals()[layer]
		var inv: Transform3D = decal.global_transform.affine_inverse()
		var covered: int = 0
		var total: int = 0
		for gx: int in range(-10, 11):
			for gz: int in range(-10, 11):
				var world: Vector3 = Vector3(gx, 0.0, gz) * (shadows._field_radius / 10.0)
				var local: Vector3 = inv * world
				var uv: Vector2 = Vector2(local.x / decal.size.x + 0.5, local.z / decal.size.z + 0.5)
				total += 1
				if uv.x >= 0.0 and uv.x < 1.0 and uv.y >= 0.0 and uv.y < 1.0 and tex.get_pixel(int(uv.x * 255.0), int(uv.y * 255.0)).a > 0.5:
					covered += 1
		print("CSHADOW layer %d radius=%.1f size=%s disc_points_in_shadow=%d/%d" % [layer, shadows._field_radius, decal.size, covered, total])
	var ov: TerritoryOverlay = get_tree().get_first_node_in_group(TerritoryOverlay.WET_GROUP) as TerritoryOverlay
	print("CSHADOW param alpha_a=%s alpha_b=%s tex=%s m=%s" % [ov._material.get_shader_parameter(&"cshadow_a_alpha"), ov._material.get_shader_parameter(&"cshadow_b_alpha"), ov._material.get_shader_parameter(&"cshadow_tex_b"), ov._material.get_shader_parameter(&"cshadow_b_m")])
	print("CSHADOW diag sun=%s daylight=%.2f visible=%s,%s alpha=%.3f,%.3f texture_opaque_samples=%d of %d overlay=%s" % [skybox.sun_direction(), skybox.daylight(),
		shadows.decals()[0].visible, shadows.decals()[1].visible, shadows.decals()[0].modulate.a, shadows.decals()[1].modulate.a,
		opaque, (tex.get_width() / 4) * (tex.get_height() / 4), get_tree().get_first_node_in_group(TerritoryOverlay.WET_GROUP)])
	await get_tree().create_timer(SWEEP_WAIT_S).timeout
	await _frames()
	_save(viewport, "day_b")
	skybox.set_cycle_phase(DUSK_PHASE)
	await _frames()
	_save(viewport, "dusk")
	skybox.set_cycle_phase(DAY_PHASE)
	await _frames()
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var off: Array[float] = []
	var on: Array[float] = []
	for block: int in range(SAMPLE_BLOCKS):
		shadows._on_graphics_preset_changed(_preset(false))
		off.append(await _gpu_ms(viewport))
		shadows._on_graphics_preset_changed(_preset(true))
		on.append(await _gpu_ms(viewport))
	print("CSHADOW gpu_ms off=%s on=%s median_off=%.3f median_on=%.3f" % [off, on, _median(off), _median(on)])
	get_tree().quit()


func _preset(enabled: bool) -> GraphicsPreset:
	var preset: GraphicsPreset = Settings.current_graphics_preset().duplicate() as GraphicsPreset
	preset.cloud_shadows_enabled = enabled
	return preset


func _gpu_ms(viewport: SubViewport) -> float:
	for _i: int in range(DRAW_FRAMES):
		await get_tree().process_frame
	var total: float = 0.0
	for _i: int in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		total += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())
	return total / float(SAMPLE_FRAMES)


func _median(values: Array[float]) -> float:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


func _frames() -> void:
	for _i: int in range(DRAW_FRAMES):
		await get_tree().process_frame


func _save(viewport: SubViewport, label: String) -> void:
	var path: String = _out_dir + "cloud_shadows_%s.png" % label
	viewport.get_texture().get_image().save_png(path)
	print("CSHADOW saved %s" % ProjectSettings.globalize_path(path))
