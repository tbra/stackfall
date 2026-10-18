extends Node
## off-screen GPU frame-cost harness. Loads the real Main scene
## into a SubViewport of --render-size (default 3440x1440), starts the sandbox with
## territory active and --blocks placed blocks, then reports the median GPU ms of that
## viewport (RenderingServer.viewport_get_measured_render_time_gpu) per configuration.
##
##   godot --windowed --position 10000,10000 --resolution 320x180 --audio-driver Dummy \
##     --path . res://tests/bench/bench_gpu_frame.tscn -- --agent-probe \
##     --render-size=3440x1440 --preset=high [--gpu-off=ssr,glow] [--sweep=all|a,b,c]
##
## User args: --preset=low|medium|high, --blocks=N, --frames=N, --warmup=N,
## --gpu-off=<features> (applied together for the single run), --sweep=<features|all>
## (baseline, each feature alone, baseline again; one GPU_BENCH line each), --list.
## Steady mode (--steady, used by tools/measure_gpu_steady.py): after --warmup-seconds the
## bench prints "STEADY_BEGIN", holds the configuration for --steady-seconds at
## Engine.max_fps=--max-fps (0 = uncapped) with vsync off, then prints "STEADY_END" and one
## "GPU_STEADY" line (achieved fps, viewport-timer GPU ms, draws). The driver samples
## nvidia-smi between the markers: that is the whole-GPU number, which unlike the viewport
## timer also covers reflection-probe and sky-radiance passes (engine source: render_probes()
## runs in RenderingServerDefault::_draw outside the vp_begin/vp_end timestamps).
## Sky state (before the blocks spawn): --sky=day|dawn|night|cycle and --phase=<0..1>. day/dawn/night
## lock the cycle at 0.25/0.0/0.75; --phase=<p> alone locks at p; --sky=cycle runs it (from --phase
## when given). Sky toggles (see --list): sky_radiance_frozen (Skybox.set_cycle_writes_frozen; keeps
## REALTIME radiance, unlike sky_radiance), puff_sea/puff_banks/puff_far (zero that layer's clump
## count on the live cycle theme, then re-apply it), puff_upper, puff_billboard (preset billboard
## distance 0), puff_detail, puff_fade_sky, sea_noise, decals_only, disc_term, sun_flare_rect,
## sun_flare_cpu, probe_interval4, probe_interval05, storm_fade_writes (starts a storm fade-in on the
## CloudCeiling; compare locked vs running sky) and the CPU toggles cpu_sun_flare, cpu_cloud_shadows,
## cpu_cloud_ceiling (process_mode disabled). Every GPU_BENCH line carries process_ms, the mean
## Performance.TIME_PROCESS: run --frames=600 for the CPU comparison.
## Output: one machine-readable line per run starting with "GPU_BENCH ". Only run it
## when no other app is using the GPU: the timestamps include contention.

# DECISION: owner's perf log shows a median of 8 blocks on the field; 40 is a busy-but-real sandbox.
const DEFAULT_BLOCKS: int = 40
const DEFAULT_FRAMES: int = 90
const DEFAULT_WARMUP: int = 40
const DEFAULT_PRESET: StringName = &"high"
const DEFAULT_RENDER_SIZE: Vector2i = Vector2i(3440, 1440)
const PLAYERS: int = 2
const SETTLE_SECONDS: float = 4.0
const PILE_CENTER_X: float = 13.0
const PILE_SPREAD: float = 4.0
const DROP_MIN_M: float = 2.0
const DROP_MAX_M: float = 14.0
const SEED: int = 20261008
const P90: float = 0.9
const REDUCED_SCALE: float = 0.5
const DEFAULT_MAX_FPS: int = 144
const DEFAULT_WARMUP_SECONDS: float = 12.0
const DEFAULT_STEADY_SECONDS: float = 12.0
const USEC_PER_SEC: float = 1000000.0
const SSR_STEPS_HALF: int = 32
const SSR_STEPS_QUARTER: int = 16
const SSR_FADE_OUT_SHORT: float = 1.0
const SKY_PHASES: Dictionary = {"day": 0.25, "dawn": 0.0, "night": 0.75}
const SKY_CYCLE: String = "cycle"
const PROBE_INTERVAL_SLOW_S: float = 4.0
const PROBE_INTERVAL_FAST_S: float = 0.5
const STORM_FADE_INTENSITY: float = 1.0
const MS_PER_SEC: float = 1000.0
const NO_PHASE: float = -1.0
const FEATURES: PackedStringArray = [
	"volumetric_fog", "ssr", "glow", "msaa", "shadows", "sky_radiance", "probe",
	"overlay", "clouds", "outline", "birds", "sky_bg", "depth_fog",
	"cloud_shadows", "sun_flare", "blocks", "fog_volume", "scale50", "aurora",
	"probe_once", "ssao", "ssil", "sdfgi", "lights", "ssao_on",
	"ssr_steps32", "ssr_steps16", "ssr_fade1",
	"sky_radiance_frozen", "puff_sea", "puff_banks", "puff_far", "puff_upper", "puff_billboard",
	"puff_detail", "puff_fade_sky", "sea_noise", "decals_only", "disc_term", "sun_flare_rect",
	"sun_flare_cpu", "storm_fade_writes", "probe_interval4", "probe_interval05",
	"cpu_sun_flare", "cpu_cloud_shadows", "cpu_cloud_ceiling",
]

var _main: Node = null
var _field: Field = null
var _render_vp: SubViewport = null
var _env: Environment = null
## feature -> original value, so a sweep can restore each suspect after measuring it off.
var _saved: Dictionary = {}


func _ready() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has("--list"):
		print("GPU_BENCH features=%s" % ",".join(FEATURES))
		get_tree().quit()
		return
	if args.has("--help") or args.has("-h"):
		print("GPU_BENCH usage: --preset= --blocks= --frames= --warmup= --gpu-off=a,b --sweep=all|a,b --steady "
			+ "--max-fps= --warmup-seconds= --steady-seconds= --sky=day|dawn|night|cycle --phase=<0..1> --shot=<png> --list")
		get_tree().quit()
		return
	var preset_id: StringName = DEFAULT_PRESET
	var blocks: int = DEFAULT_BLOCKS
	var frames: int = DEFAULT_FRAMES
	var warmup: int = DEFAULT_WARMUP
	var off: PackedStringArray = PackedStringArray()
	var sweep: PackedStringArray = PackedStringArray()
	var steady: bool = false
	var max_fps: int = DEFAULT_MAX_FPS
	var warmup_seconds: float = DEFAULT_WARMUP_SECONDS
	var steady_seconds: float = DEFAULT_STEADY_SECONDS
	var sky_mode: String = ""
	var sky_phase: float = NO_PHASE
	for arg: String in args:
		if arg.begins_with("--preset="):
			preset_id = StringName(arg.trim_prefix("--preset="))
		elif arg.begins_with("--blocks="):
			blocks = int(arg.trim_prefix("--blocks="))
		elif arg.begins_with("--frames="):
			frames = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--warmup="):
			warmup = int(arg.trim_prefix("--warmup="))
		elif arg.begins_with("--gpu-off="):
			off = arg.trim_prefix("--gpu-off=").split(",", false)
		elif arg == "--steady":
			steady = true
		elif arg.begins_with("--max-fps="):
			max_fps = int(arg.trim_prefix("--max-fps="))
		elif arg.begins_with("--warmup-seconds="):
			warmup_seconds = float(arg.trim_prefix("--warmup-seconds="))
		elif arg.begins_with("--steady-seconds="):
			steady_seconds = float(arg.trim_prefix("--steady-seconds="))
		elif arg.begins_with("--sky="):
			sky_mode = arg.trim_prefix("--sky=")
		elif arg.begins_with("--phase="):
			sky_phase = float(arg.trim_prefix("--phase="))
		elif arg.begins_with("--sweep="):
			var value: String = arg.trim_prefix("--sweep=")
			sweep = FEATURES if value == "all" else value.split(",", false)
	if not sky_mode.is_empty() and sky_mode != SKY_CYCLE and not SKY_PHASES.has(sky_mode):
		print("GPU_BENCH error bad --sky=%s (want day|dawn|night|cycle)" % sky_mode)
		get_tree().quit(1)
		return
	Settings.set_graphics_preset(preset_id)
	_main = (load("res://game/main/Main.tscn") as PackedScene).instantiate()
	_render_vp = AgentProbe.make_render_viewport(self, DEFAULT_RENDER_SIZE)
	_render_vp.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	# The real menu path: clears the main menu + its diorama (the first harness left the
	# menu on screen, so every earlier reading measured the menu scene, not the match).
	_main.call(&"start_sandbox_from_menu")
	while Match.state() != Match.State.PLAYING:
		await get_tree().process_frame
	_field = _main.get_node("Field") as Field
	_env = (_main.get("_world_environment") as WorldEnvironment).environment
	RenderingServer.viewport_set_measure_render_time(_render_vp.get_viewport_rid(), true)
	_apply_sky_state(sky_mode, sky_phase)
	_spawn_blocks(blocks)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	(_main.get("_sandbox") as Sandbox)._set_block_physics_frozen(true)
	if args.has("--prims-audit"):
		for i: int in range(3):
			await get_tree().process_frame
		_prims_audit()
		get_tree().quit()
		return
	if steady:
		for feature: String in off:
			_set_feature(feature, false)
		await _steady(preset_id, off, max_fps, warmup_seconds, steady_seconds)
	elif sweep.is_empty():
		for feature: String in off:
			_set_feature(feature, false)
		await _measure(preset_id, off, blocks, frames, warmup)
	else:
		await _measure(preset_id, PackedStringArray(), blocks, frames, warmup)
		for feature: String in sweep:
			_set_feature(feature, false)
			await _measure(preset_id, PackedStringArray([feature]), blocks, frames, warmup)
			_set_feature(feature, true)
		await _measure(preset_id, PackedStringArray(), blocks, frames, warmup)
	get_tree().quit()


## Pins the cycle before measuring (the bench otherwise measures whatever phase the match opened at).
func _apply_sky_state(sky_mode: String, phase: float) -> void:
	if sky_mode.is_empty() and phase < 0.0:
		return
	var skybox: Skybox = _skybox()
	if skybox == null:
		print("GPU_BENCH warning sky_state_no_skybox")
		return
	if sky_mode == SKY_CYCLE:
		skybox.start_cycle(NO_PHASE, phase)
	else:
		var lock: float = float(SKY_PHASES[sky_mode]) if SKY_PHASES.has(sky_mode) else phase
		skybox.start_cycle(lock, NO_PHASE)
	print("GPU_BENCH sky=%s phase=%.3f" % [sky_mode if not sky_mode.is_empty() else "locked", skybox.cycle_phase_at(MatchContext.current().shared_clock_seconds())])


func _skybox() -> Skybox:
	return _main.get("_skybox") as Skybox


## The live cycle theme (the one apply_theme re-applies), or null outside CYCLE mode.
func _cycle_theme() -> SkyThemeDef:
	var skybox: Skybox = _skybox()
	return skybox.get("_cycle_theme") as SkyThemeDef if skybox != null else null


## Overrides one SkyThemeDef/GraphicsPreset property (off) or restores it (on), then rebuilds the
## puffs by re-applying the cycle theme; the layers share one MultiMesh, so a node toggle cannot isolate them.
func _toggle_rebuild(feature: String, target: Object, property: String, off_value: Variant, on: bool) -> void:
	if target == null:
		print("GPU_BENCH warning feature=%s no_target" % feature)
		return
	_toggle(feature, target, property, off_value, on)
	var skybox: Skybox = _skybox()
	if skybox != null and _cycle_theme() != null:
		skybox.apply_theme(_cycle_theme())


## Sets a shader parameter on `material` (off) or restores it (on).
func _toggle_param(feature: String, material: ShaderMaterial, parameter: StringName, off_value: Variant, on: bool) -> void:
	if material == null:
		print("GPU_BENCH warning feature=%s no_material" % feature)
		return
	if on:
		if _saved.has(feature):
			material.set_shader_parameter(parameter, _saved[feature])
		return
	if not _saved.has(feature):
		_saved[feature] = material.get_shader_parameter(parameter)
	material.set_shader_parameter(parameter, off_value)


func _puff_material() -> ShaderMaterial:
	var skybox: Skybox = _skybox()
	var sea: Object = skybox.get("_cloud_sea") as Object if skybox != null else null
	return sea.get("_material") as ShaderMaterial if sea != null else null


## Puff MultiMeshInstance3Ds under every CloudSea by node name (Puffs, PuffsFar, UpperPuffs, UpperPuffsFar).
func _toggle_puff_nodes(feature: String, names: PackedStringArray, on: bool) -> void:
	var hits: int = 0
	for sea: Node in _main.find_children("*", "CloudSea", true, false):
		for child: Node in sea.get_children():
			if names.has(str(child.name)):
				hits += 1
				var key: String = "%s#%d" % [feature, child.get_instance_id()]
				if on:
					if _saved.has(key):
						child.set("visible", _saved[key])
				else:
					if not _saved.has(key):
						_saved[key] = child.get("visible")
					child.set("visible", false)
	if hits == 0 and not on:
		print("GPU_BENCH warning feature=%s matched_no_nodes" % feature)


## CloudShadows split: decals_only hides the Decal projectors but leaves the disc term as last pushed;
## disc_term clears the disc term but leaves the decals. Either stops CloudShadows._process (CPU too).
func _toggle_cloud_shadow_part(disc: bool, on: bool) -> void:
	for node: Node in _main.find_children("*", "CloudShadows", true, false):
		node.set("_enabled", on)
		if on:
			continue
		if disc:
			node.call("_push_disc", [] as Array[Texture2D], [] as Array[Transform3D], [] as Array[float])
		else:
			for decal: Decal in node.get("_decals") as Array[Decal]:
				decal.visible = false


## Listing storm_fade_writes starts a storm fade-in; restoring snaps the weather clear.
func _toggle_storm_fade(on: bool) -> void:
	for node: Node in _main.find_children("*", "CloudCeiling", true, false):
		var ceiling: CloudCeiling = node as CloudCeiling
		if on:
			ceiling.snap_clear()
		else:
			ceiling.set_weather_intensity(WeatherIds.STORM, STORM_FADE_INTENSITY)


func _toggle_probe_interval(feature: String, interval_s: float, on: bool) -> void:
	_toggle(feature, Settings.current_graphics_preset(), "reflection_probe_interval_s", interval_s, on)
	if _skybox() != null:
		_skybox().configure_reflection_probe()


func _steady(preset_id: StringName, off: PackedStringArray, max_fps: int, warmup_seconds: float, steady_seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = max_fps
	var rid: RID = _render_vp.get_viewport_rid()
	var warm_end: int = Time.get_ticks_usec() + int(warmup_seconds * USEC_PER_SEC)
	while Time.get_ticks_usec() < warm_end:
		await get_tree().process_frame
	var gpu: Array[float] = []
	var frames: int = 0
	var begin: int = Time.get_ticks_usec()
	print("STEADY_BEGIN")
	var end: int = begin + int(steady_seconds * USEC_PER_SEC)
	while Time.get_ticks_usec() < end:
		await get_tree().process_frame
		frames += 1
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
	var elapsed: float = float(Time.get_ticks_usec() - begin) / USEC_PER_SEC
	print("STEADY_END")
	var shot: String = ""
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
	if not shot.is_empty():
		_render_vp.get_texture().get_image().save_png(shot)
	for info_type: int in [RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW]:
		print("VP_INFO type=%d objects=%d prims=%d draws=%d" % [
			info_type,
			RenderingServer.viewport_get_render_info(rid, info_type, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, info_type, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
			RenderingServer.viewport_get_render_info(rid, info_type, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		])
	print("PERF_MON prims=%d draws=%d objects=%d" % [
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
	])
	gpu.sort()
	print("GPU_STEADY preset=%s off=%s max_fps=%d fps=%.1f vp_gpu_ms_median=%.3f vp_gpu_ms_p90=%.3f draws=%d objects=%d prims=%d" % [
		preset_id, ",".join(off) if not off.is_empty() else "none", max_fps, float(frames) / elapsed,
		gpu[gpu.size() / 2], gpu[mini(int(float(gpu.size()) * P90), gpu.size() - 1)],
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	])
	get_tree().quit()


## Static triangle inventory (no GPU timing): every MeshInstance3D / MultiMeshInstance3D under
## the scene, with triangles per submission, how many passes can draw it (main + shadow splits +
## probe faces by cull mask) and flags, sorted by triangles x passes.
func _prims_audit() -> void:
	# Menu leftovers after the real menu -> sandbox flow (question).
	for node: Node in get_tree().root.find_children("*", "SubViewport", true, false):
		var sv: SubViewport = node as SubViewport
		print("TREE_AUDIT subviewport=%s size=%s update=%d visible_in_tree=%s" % [str(sv.get_path()), sv.size, sv.render_target_update_mode, sv.is_inside_tree()])
	for node: Node in get_tree().root.find_children("*", "", true, false):
		var cls: String = node.get_class()
		var script: Script = node.get_script() as Script
		var global_name: String = script.get_global_name() if script != null else ""
		if global_name in ["MainMenu", "MenuBackdrop", "Lobby", "SplashScreen"]:
			print("TREE_AUDIT menu_node=%s class=%s queued_for_deletion=%s" % [str(node.get_path()), global_name, node.is_queued_for_deletion()])
	print("TREE_AUDIT root_disable_3d=%s max_fps=%d" % [get_tree().root.disable_3d, Engine.max_fps])
	var rows: Array[Dictionary] = []
	var probe_mask: int = 0
	for node: Node in _main.find_children("*", "ReflectionProbe", true, false):
		probe_mask = (node as ReflectionProbe).cull_mask
	for node: Node in _main.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = node as GeometryInstance3D
		var mesh: Mesh = null
		var count: int = 1
		if gi is MeshInstance3D:
			mesh = (gi as MeshInstance3D).mesh
		elif gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh != null:
			var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
			mesh = mm.mesh
			count = mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
		if mesh == null:
			continue
		var tris: int = 0
		for surf: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surf)
			var idx: Variant = arrays[Mesh.ARRAY_INDEX]
			if idx != null and (idx as PackedInt32Array).size() > 0:
				tris += (idx as PackedInt32Array).size() / 3
			else:
				tris += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		var visible: bool = gi.is_visible_in_tree()
		rows.append({
			"path": str(_main.get_path_to(gi)), "tris": tris * count, "visible": visible,
			"shadow": gi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
			"in_probe": (gi.layers & probe_mask) != 0, "layers": gi.layers,
		})
	rows.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["tris"]) > int(y["tris"]))
	var total: int = 0
	for row: Dictionary in rows:
		if row["visible"]:
			total += int(row["tris"])
	print("PRIMS_AUDIT preset=%s visible_total_tris=%d probe_mask=%d nodes=%d" % [Settings.current_graphics_preset().id, total, probe_mask, rows.size()])
	for i: int in range(mini(rows.size(), 30)):
		var row: Dictionary = rows[i]
		print("PRIMS_AUDIT_ROW tris=%d vis=%s shadow=%s in_probe=%s layers=%d %s" % [row["tris"], row["visible"], row["shadow"], row["in_probe"], row["layers"], row["path"]])


func _spawn_blocks(count: int) -> void:
	var shapes: Array[BlockShape] = BlockShape.load_all_shapes()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	for i: int in range(count):
		var slot_id: int = i % PLAYERS
		var center_x: float = -PILE_CENTER_X if slot_id == 0 else PILE_CENTER_X
		var local: Vector2 = Vector2(
			center_x + rng.randf_range(-PILE_SPREAD, PILE_SPREAD), rng.randf_range(-PILE_SPREAD, PILE_SPREAD)
		)
		var height: float = _field.surface_y() + rng.randf_range(DROP_MIN_M, DROP_MAX_M)
		var shape: BlockShape = shapes[rng.randi_range(0, shapes.size() - 1)]
		var block: Block = BlockFactory.build(shape, Match._physics_tuning, slot_id, Match.slot(slot_id).color)
		Match.blocks_parent().add_child(block)
		block.global_position = _field.world_from_disk_local(local, height)
		Events.block_placed.emit(block, shape.id)


func _measure(preset_id: StringName, off: PackedStringArray, blocks: int, frames: int, warmup: int) -> void:
	for i: int in range(warmup):
		await get_tree().process_frame
	var rid: RID = _render_vp.get_viewport_rid()
	var gpu: Array[float] = []
	var cpu_sum: float = 0.0
	var process_sum: float = 0.0
	for i: int in range(frames):
		await get_tree().process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		process_sum += Performance.get_monitor(Performance.TIME_PROCESS)
	gpu.sort()
	var total: float = 0.0
	for value: float in gpu:
		total += value
	var count: float = maxf(float(gpu.size()), 1.0)
	print("GPU_BENCH preset=%s off=%s blocks=%d res=%dx%d frames=%d gpu_ms_median=%.3f gpu_ms_p90=%.3f gpu_ms_mean=%.3f render_cpu_ms=%.3f process_ms=%.3f draws=%d objects=%d prims=%d" % [
		preset_id, ",".join(off) if not off.is_empty() else "none", blocks, _render_vp.size.x, _render_vp.size.y,
		gpu.size(), gpu[gpu.size() / 2], gpu[mini(int(count * P90), gpu.size() - 1)], total / count, cpu_sum / count,
		process_sum / count * MS_PER_SEC,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	])


## Turns one suspect off (on = false) or restores it (on = true). Unknown names print a
## warning line so a typo cannot silently measure the baseline.
func _set_feature(feature: String, on: bool) -> void:
	match feature:
		"volumetric_fog":
			_toggle(feature, _env, "volumetric_fog_enabled", false, on)
		"ssr":
			_toggle(feature, _env, "ssr_enabled", false, on)
		"glow":
			_toggle(feature, _env, "glow_enabled", false, on)
		"depth_fog":
			_toggle(feature, _env, "fog_enabled", false, on)
		"sky_bg":
			_toggle(feature, _env, "background_mode", Environment.BG_COLOR, on)
		"msaa":
			_toggle(feature, _render_vp, "msaa_3d", Viewport.MSAA_DISABLED, on)
		"scale50":
			_toggle(feature, _render_vp, "scaling_3d_scale", REDUCED_SCALE, on)
		"sky_radiance":
			# Off = radiance cubemap rendered once (QUALITY) instead of incrementally each frame.
			_toggle(feature, _env.sky, "process_mode", Sky.PROCESS_MODE_QUALITY, on)
		"probe_once":
			_toggle_all(feature, ReflectionProbe, "update_mode", ReflectionProbe.UPDATE_ONCE, on)
		"ssao":
			_toggle(feature, _env, "ssao_enabled", false, on)
		"ssao_on":
			# Meaning inverted: listing it in the off set ENABLES SSAO;
			# restoring (on = true) puts the saved value back (false by default).
			_toggle(feature, _env, "ssao_enabled", true, on)
		"ssr_steps32":
			# Pseudo-feature: listing it sets ssr_max_steps to 32.
			_toggle(feature, _env, "ssr_max_steps", SSR_STEPS_HALF, on)
		"ssr_steps16":
			_toggle(feature, _env, "ssr_max_steps", SSR_STEPS_QUARTER, on)
		"ssr_fade1":
			_toggle(feature, _env, "ssr_fade_out", SSR_FADE_OUT_SHORT, on)
		"ssil":
			_toggle(feature, _env, "ssil_enabled", false, on)
		"sdfgi":
			_toggle(feature, _env, "sdfgi_enabled", false, on)
		"lights":
			_toggle_all(feature, OmniLight3D, "visible", false, on)
			_toggle_all(feature + "_spot", SpotLight3D, "visible", false, on)
		"overlay":
			# the arena is one mesh node, so this hides the
			# whole arena (top, chamfer, band, bottom), not just the top surface.
			_toggle(feature, _field.overlay(), "visible", false, on)
		"blocks":
			_toggle(feature, Match.blocks_parent(), "visible", false, on)
		"shadows":
			_toggle_all(feature, DirectionalLight3D, "shadow_enabled", false, on)
		"probe":
			_toggle_all(feature, ReflectionProbe, "visible", false, on)
		"clouds":
			_toggle_all(feature, CloudSea, "visible", false, on)
		"birds":
			_toggle_all(feature, DistantBirds, "visible", false, on)
			_toggle_all(feature + "_perching", PerchingBirds, "visible", false, on)
			_toggle_all(feature + "_fireflies", Fireflies, "visible", false, on)
		"cloud_shadows":
			_toggle_all(feature, CloudShadows, "visible", false, on)
		"sun_flare":
			_toggle_all(feature, SunFlare, "visible", false, on)
		"fog_volume":
			_toggle_all(feature, FogVolume, "visible", false, on)
		"outline":
			var materials: Dictionary = BlockFactory._materials_by_color
			for color: Variant in materials.keys():
				var material: ShaderMaterial = materials[color] as ShaderMaterial
				material.next_pass = BlockFactory._outline_material_for_color(color as Color) if on else null
		"aurora":
			# Aurora draws only in the sky background pass; zero the visibility uniform.
			var sky_material: ShaderMaterial = _env.sky.sky_material as ShaderMaterial
			if sky_material != null:
				if not on:
					_saved[feature] = sky_material.get_shader_parameter(&"aurora_visibility")
				sky_material.set_shader_parameter(&"aurora_visibility", 0.0 if not on else _saved.get(feature, 0.0))
		"sky_radiance_frozen":
			# The cycle's 10 Hz material writes stop; radiance stays REALTIME (no GGX refilter).
			if _skybox() != null:
				_skybox().set_cycle_writes_frozen(not on)
		"puff_sea":
			_toggle_rebuild(feature, _cycle_theme(), "cloud_clump_count", 0, on)
		"puff_banks":
			_toggle_rebuild(feature, _cycle_theme(), "cloud_bank_count", 0, on)
		"puff_far":
			_toggle_rebuild(feature, _cycle_theme(), "proc_far_count", 0, on)
		"puff_upper":
			_toggle_puff_nodes(feature, PackedStringArray(["UpperPuffs", "UpperPuffsFar"]), on)
		"puff_billboard":
			_toggle_rebuild(feature, Settings.current_graphics_preset(), "cloud_billboard_distance_m", 0.0, on)
		"puff_detail":
			_toggle_param(feature, _puff_material(), &"lump_detail_weight", 0.0, on)
		"puff_fade_sky":
			_toggle_param(feature, _puff_material(), &"far_fade_cap", 0.0, on)
		"sea_noise":
			_toggle_param(feature, _env.sky.sky_material as ShaderMaterial, &"procedural_sea_mix", 0.0, on)
		"decals_only":
			_toggle_cloud_shadow_part(false, on)
		"disc_term":
			_toggle_cloud_shadow_part(true, on)
		"sun_flare_rect":
			# The GPU pass only: hides the flare CanvasLayer while SunFlare._process keeps running.
			_toggle_all(feature, SunFlare, "visible", false, on)
		"sun_flare_cpu":
			# The CPU rays only: the rect keeps drawing its last state.
			_toggle_all(feature, SunFlare, "process_mode", Node.PROCESS_MODE_DISABLED, on)
		"storm_fade_writes":
			_toggle_storm_fade(on)
		"probe_interval4":
			_toggle_probe_interval(feature, PROBE_INTERVAL_SLOW_S, on)
		"probe_interval05":
			_toggle_probe_interval(feature, PROBE_INTERVAL_FAST_S, on)
		"cpu_sun_flare":
			_toggle_all(feature, SunFlare, "process_mode", Node.PROCESS_MODE_DISABLED, on)
		"cpu_cloud_shadows":
			_toggle_all(feature, CloudShadows, "process_mode", Node.PROCESS_MODE_DISABLED, on)
		"cpu_cloud_ceiling":
			_toggle_all(feature, CloudCeiling, "process_mode", Node.PROCESS_MODE_DISABLED, on)
		_:
			print("GPU_BENCH warning unknown_feature=%s" % feature)


func _toggle(feature: String, target: Object, property: String, off_value: Variant, on: bool) -> void:
	if on:
		if _saved.has(feature):
			target.set(property, _saved[feature])
		return
	if not _saved.has(feature):
		_saved[feature] = target.get(property)
	target.set(property, off_value)


func _toggle_all(feature: String, type: Variant, property: String, off_value: Variant, on: bool) -> void:
	var hits: int = 0
	for node: Node in _main.find_children("*", "", true, false):
		if not is_instance_of(node, type):
			continue
		var key: String = "%s#%d" % [feature, node.get_instance_id()]
		hits += 1
		if on:
			if _saved.has(key):
				node.set(property, _saved[key])
		else:
			if not _saved.has(key):
				_saved[key] = node.get(property)
			node.set(property, off_value)
	if hits == 0 and not on:
		print("GPU_BENCH warning feature=%s matched_no_nodes" % feature)
