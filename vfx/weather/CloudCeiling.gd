class_name CloudCeiling
extends Node3D
## Bontago-mp0.19: broad cel-style cloud layer above the disc while it rains,
## snows or storms (the disc floats above a cloud sea, so precipitation needs
## clouds overhead). Presentation only, derived from the replicated weather
## intensities WeatherPresenter feeds in, so every peer renders the same.
## Also drives the storm sky blend (Skybox.set_storm_sky). Tunables:
## config/weather/ceiling.tres (WeatherCeilingTuning).

const SHADER: Shader = preload("res://shaders/weather_cloud_ceiling.gdshader")
const CLOUD_NOISE: Texture2D = preload("res://config/sky_themes/cloud_noise.tres")
const TUNING: WeatherCeilingTuning = preload("res://config/weather/ceiling.tres")

var tuning: WeatherCeilingTuning = TUNING
var _targets: Dictionary = {}
var _amount: float = 0.0
var _storm_amount: float = 0.0
var _layers: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _drift: Vector2 = Vector2.ZERO
var _storm_theme: SkyThemeDef = null
## Cached Skybox lookups (refreshed whenever the storm value changes).
var _skyboxes: Array[Skybox] = []
var _pushed_storm: float = -1.0


func _ready() -> void:
	_build()
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	visible = false


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	_push_storm(0.0)


## Weather `weather_id` now has `intensity` (0 on stop).
func set_weather_intensity(weather_id: StringName, intensity: float) -> void:
	if not tuning.weather_ids.has(weather_id):
		return
	if intensity <= 0.0:
		_targets.erase(weather_id)
	else:
		_targets[weather_id] = clampf(intensity, 0.0, 1.0)


func target_amount() -> float:
	var best: float = 0.0
	for value: Variant in _targets.values():
		best = maxf(best, float(value))
	return best


func target_storm() -> float:
	return float(_targets.get(tuning.storm_id, 0.0)) * tuning.storm_sky_blend


func amount() -> float:
	return _amount


func storm_amount() -> float:
	return _storm_amount


func layer_count() -> int:
	return _layers.size()


## Advances the fades by `delta` (also the test seam).
func step(delta: float) -> void:
	var target: float = target_amount()
	var fade_s: float = tuning.fade_in_s if target > _amount else tuning.fade_out_s
	_amount = move_toward(_amount, target, delta / maxf(fade_s, 0.001))
	var storm_target: float = target_storm()
	var storm_s: float = tuning.fade_in_s if storm_target > _storm_amount else tuning.fade_out_s
	_storm_amount = move_toward(_storm_amount, storm_target, delta / maxf(storm_s, 0.001))
	visible = _amount > 0.0
	_drift += tuning.drift_direction.normalized() * tuning.drift_speed_mps * delta
	var dark: float = clampf(tuning.darkness + tuning.storm_darkness_add * _storm_amount, 0.0, 1.0)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"amount", _amount)
		material.set_shader_parameter(&"drift", _drift)
		material.set_shader_parameter(&"darkness", dark)
	_push_storm(_storm_amount)


func _process(delta: float) -> void:
	# Idle early-out: nothing to fade, draw or push.
	if _amount <= 0.0 and _storm_amount <= 0.0 and _targets.is_empty():
		return
	step(delta)
	if not visible or not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_pos: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	global_position = Vector3(camera_pos.x, tuning.ceiling_y(camera_pos.y), camera_pos.z)


func _push_storm(value: float) -> void:
	if is_equal_approx(value, _pushed_storm) and not _skyboxes.is_empty():
		return
	var tree: SceneTree = get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return
	if value > 0.0 and _storm_theme == null:
		_storm_theme = Skybox.load_theme(tuning.storm_theme_id)
	if _skyboxes.is_empty() or not is_equal_approx(value, _pushed_storm):
		_skyboxes.clear()
		for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
			_skyboxes.append(node as Skybox)
	_pushed_storm = value
	for skybox: Skybox in _skyboxes:
		if is_instance_valid(skybox):
			skybox.set_storm_sky(value, _storm_theme)


func _on_graphics_preset_changed(_preset: GraphicsPreset) -> void:
	_build()


func _is_low() -> bool:
	var preset: GraphicsPreset = Settings.current_graphics_preset()
	return preset != null and not preset.ambient_life_enabled


func _build() -> void:
	for layer: MeshInstance3D in _layers:
		remove_child(layer)
		layer.free()
	_layers.clear()
	_materials.clear()
	# DECISION: Low = one layer and fewer noise octaves (no texture cost).
	var low: bool = _is_low()
	var count: int = maxi(tuning.layer_count_low if low else tuning.layer_count, 1)
	var octaves: int = tuning.noise_octaves_low if low else tuning.noise_octaves
	for index: int in range(count):
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2.ONE * tuning.size_m
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"cloud_noise", CLOUD_NOISE)
		material.set_shader_parameter(&"coverage", tuning.coverage)
		material.set_shader_parameter(&"edge_softness", tuning.edge_softness)
		material.set_shader_parameter(&"noise_scale", tuning.noise_scale)
		material.set_shader_parameter(&"octaves", octaves)
		material.set_shader_parameter(&"layer_seed", float(index))
		material.set_shader_parameter(&"shadow_color", tuning.shadow_color)
		material.set_shader_parameter(&"mid_color", tuning.mid_color)
		material.set_shader_parameter(&"lit_color", tuning.lit_color)
		material.set_shader_parameter(&"mid_threshold", tuning.mid_threshold)
		material.set_shader_parameter(&"shadow_threshold", tuning.shadow_threshold)
		material.set_shader_parameter(&"fade_far_start", tuning.fade_far_start_m)
		material.set_shader_parameter(&"fade_far_end", tuning.fade_far_end_m)
		material.set_shader_parameter(&"layer_alpha", 1.0 - tuning.upper_layer_alpha_drop * float(index) / float(count))
		material.set_shader_parameter(&"amount", _amount)
		material.set_shader_parameter(&"lobe_mix", tuning.lobe_mix)
		material.set_shader_parameter(&"lobe_scale", tuning.lobe_scale)
		material.set_shader_parameter(&"band_softness", tuning.band_softness)
		material.set_shader_parameter(&"horizon_fade", tuning.horizon_fade)
		material.set_shader_parameter(&"full_opacity_amount", tuning.full_opacity_amount)
		var layer: MeshInstance3D = MeshInstance3D.new()
		layer.name = "Layer%d" % index
		layer.mesh = plane
		layer.material_override = material
		layer.position = Vector3(0.0, tuning.layer_spacing_m * float(index), 0.0)
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Weather layer: the disc mirror skips it (see RainPresentation).
		layer.layers = RainPresentation.RENDER_LAYER_BIT
		add_child(layer)
		_layers.append(layer)
		_materials.append(material)
