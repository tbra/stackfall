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
## Shared overcast (rain/snow/storm each at their own tuned amount), faded like
## the ceiling and published to every Skybox so all cloud layers grade together.
var _overcast: float = 0.0
var _pushed_overcast: float = -1.0
var _layers: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _drift: Vector2 = Vector2.ZERO
var _storm_theme: SkyThemeDef = null
## Cached Skybox lookups (refreshed whenever the storm value changes).
var _skyboxes: Array[Skybox] = []
var _pushed_storm: float = -1.0
## Bontago-mp0.29: the shared cloud lighting (palette, light, cycle, weather
## grade) every cloud layer reads; Skybox's instance once one is found, a neutral
## local one before that (isolated tests, menus).
var _lighting: CloudLighting = CloudLighting.new()
var _lighting_bound: bool = false


func _ready() -> void:
	_build()
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	visible = false


func _exit_tree() -> void:
	if _lighting != null and _lighting.changed.is_connected(_apply_lighting):
		_lighting.changed.disconnect(_apply_lighting)
	_lighting_bound = false
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)
	_overcast = 0.0
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


## Overcast the active weathers drive right now (the strongest one wins).
func target_overcast() -> float:
	var best: float = 0.0
	for weather_id: Variant in _targets.keys():
		best = maxf(best, tuning.overcast_for(weather_id as StringName, float(_targets[weather_id])))
	return best


func overcast() -> float:
	return _overcast


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
	var overcast_target: float = target_overcast()
	var overcast_s: float = tuning.fade_in_s if overcast_target > _overcast else tuning.fade_out_s
	_overcast = move_toward(_overcast, overcast_target, delta / maxf(overcast_s, 0.001))
	visible = _amount > 0.0
	_drift += tuning.drift_direction.normalized() * tuning.drift_speed_mps * delta
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"amount", _amount)
		material.set_shader_parameter(&"drift", _drift)
	_push_storm(_storm_amount)


func _process(delta: float) -> void:
	# Idle early-out: nothing to fade, draw or push.
	if _amount <= 0.0 and _storm_amount <= 0.0 and _overcast <= 0.0 and _targets.is_empty():
		return
	step(delta)
	if not visible or not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	var camera_pos: Vector3 = camera.global_position if camera != null else Vector3.ZERO
	global_position = Vector3(camera_pos.x, tuning.ceiling_y(camera_pos.y), camera_pos.z)


func _push_storm(value: float) -> void:
	if is_equal_approx(value, _pushed_storm) and _overcast == _pushed_overcast and not _skyboxes.is_empty():
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
	var overcast_changed: bool = _overcast != _pushed_overcast
	_pushed_overcast = _overcast
	for skybox: Skybox in _skyboxes:
		if is_instance_valid(skybox):
			skybox.set_storm_sky(value, _storm_theme)
			if overcast_changed:
				skybox.set_weather_cloud_overcast(_overcast)
	_bind_lighting()


## Reads the shared lighting from the first Skybox found (all peers publish the
## same state; the ceiling never derives its own).
func _bind_lighting() -> void:
	if _lighting_bound:
		return
	for skybox: Skybox in _skyboxes:
		if is_instance_valid(skybox):
			set_lighting(skybox.cloud_lighting())
			return


## Test/production seam: use `state` as the lighting source.
func set_lighting(state: CloudLighting) -> void:
	if _lighting != null and _lighting.changed.is_connected(_apply_lighting):
		_lighting.changed.disconnect(_apply_lighting)
	_lighting = state
	_lighting_bound = true
	_lighting.changed.connect(_apply_lighting)
	_apply_lighting()


func lighting() -> CloudLighting:
	return _lighting


func layer_material(index: int) -> ShaderMaterial:
	return _materials[index]


## Writes the shared lighting to every layer: the puff palette under the weather
## grade, the light direction/colour, the cycle's night mix and the storm darkness.
func _apply_lighting() -> void:
	var l: CloudLighting = _lighting
	var dim: float = clampf(l.dim + tuning.darkness, 0.0, 1.0)
	var desaturate: float = maxf(l.desaturate, tuning.min_desaturate)
	var shadow: Color = CloudLighting.grade(l.shadow_color, 0.0, desaturate)
	var mid: Color = CloudLighting.grade(l.mid_color, 0.0, desaturate)
	var lit: Color = CloudLighting.grade(l.lit_color, 0.0, desaturate)
	var rim: Color = CloudLighting.grade(l.rim_color, 0.0, desaturate)
	var strength: float = lerpf(1.0, tuning.night_light_scale, l.night_mix) * tuning.sun_side_bias
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"shadow_color", shadow)
		material.set_shader_parameter(&"mid_color", mid)
		material.set_shader_parameter(&"lit_color", lit)
		material.set_shader_parameter(&"rim_color", rim)
		material.set_shader_parameter(&"light_direction", l.light_direction)
		material.set_shader_parameter(&"light_color", Vector3(l.light_color.r, l.light_color.g, l.light_color.b))
		material.set_shader_parameter(&"night_mix", l.night_mix)
		material.set_shader_parameter(&"sun_side_strength", strength)
		material.set_shader_parameter(&"darkness", dim)


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
	# DECISION: Low = one layer (the cel body costs five noise taps per layer).
	var count: int = maxi(tuning.layer_count_low if _is_low() else tuning.layer_count, 1)
	for index: int in range(count):
		var plane: PlaneMesh = PlaneMesh.new()
		plane.size = Vector2.ONE * tuning.size_m
		var material: ShaderMaterial = ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter(&"cloud_noise", CLOUD_NOISE)
		material.set_shader_parameter(&"coverage", tuning.coverage)
		material.set_shader_parameter(&"edge_softness", tuning.edge_softness)
		material.set_shader_parameter(&"noise_scale", tuning.noise_scale)
		material.set_shader_parameter(&"layer_seed", float(index))
		material.set_shader_parameter(&"fade_far_start", tuning.fade_far_start_m)
		material.set_shader_parameter(&"fade_far_end", tuning.fade_far_end_m)
		material.set_shader_parameter(&"layer_alpha", 1.0 - tuning.upper_layer_alpha_drop * float(index) / float(count))
		material.set_shader_parameter(&"amount", _amount)
		material.set_shader_parameter(&"band_softness", tuning.band_softness)
		material.set_shader_parameter(&"cel_bands", float(tuning.cel_bands))
		material.set_shader_parameter(&"light_contrast", tuning.light_contrast)
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
	_apply_lighting()
