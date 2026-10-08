extends Node
## Bontago-1pi.11.67: off-screen GPU frame-cost harness. Loads the real Main scene
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
## Output: one machine-readable line per run starting with "GPU_BENCH ". Only run it
## when no other app is using the GPU: the timestamps include contention.

const DEFAULT_BLOCKS: int = 150
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
const FEATURES: PackedStringArray = [
	"volumetric_fog", "ssr", "glow", "msaa", "shadows", "sky_radiance", "probe",
	"overlay", "clouds", "outline", "birds", "sky_bg", "depth_fog", "islands",
	"cloud_shadows", "sun_flare", "blocks", "fog_volume", "scale50", "aurora",
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
	var preset_id: StringName = DEFAULT_PRESET
	var blocks: int = DEFAULT_BLOCKS
	var frames: int = DEFAULT_FRAMES
	var warmup: int = DEFAULT_WARMUP
	var off: PackedStringArray = PackedStringArray()
	var sweep: PackedStringArray = PackedStringArray()
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
		elif arg.begins_with("--sweep="):
			var value: String = arg.trim_prefix("--sweep=")
			sweep = FEATURES if value == "all" else value.split(",", false)
	Settings.set_graphics_preset(preset_id)
	_main = (load("res://game/Main.tscn") as PackedScene).instantiate()
	_render_vp = AgentProbe.make_render_viewport(self, DEFAULT_RENDER_SIZE)
	_render_vp.add_child.call_deferred(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	_main.call(&"_start_sandbox_match_with_args", PackedStringArray(["sandbox", "players=%d" % PLAYERS]))
	while Match.state() != Match.State.PLAYING:
		await get_tree().process_frame
	_field = _main.get_node("Field") as Field
	_env = (_main.get("_world_environment") as WorldEnvironment).environment
	RenderingServer.viewport_set_measure_render_time(_render_vp.get_viewport_rid(), true)
	_spawn_blocks(blocks)
	await get_tree().create_timer(SETTLE_SECONDS).timeout
	(_main.get("_sandbox") as Sandbox)._set_block_physics_frozen(true)
	if sweep.is_empty():
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
	for i: int in range(frames):
		await get_tree().process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu_sum += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	gpu.sort()
	var total: float = 0.0
	for value: float in gpu:
		total += value
	var count: float = maxf(float(gpu.size()), 1.0)
	print("GPU_BENCH preset=%s off=%s blocks=%d res=%dx%d frames=%d gpu_ms_median=%.3f gpu_ms_p90=%.3f gpu_ms_mean=%.3f render_cpu_ms=%.3f draws=%d objects=%d prims=%d" % [
		preset_id, ",".join(off) if not off.is_empty() else "none", blocks, _render_vp.size.x, _render_vp.size.y,
		gpu.size(), gpu[gpu.size() / 2], gpu[mini(int(count * P90), gpu.size() - 1)], total / count, cpu_sum / count,
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
		"overlay":
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
		"islands":
			_toggle_all(feature, HorizonIslands, "visible", false, on)
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
