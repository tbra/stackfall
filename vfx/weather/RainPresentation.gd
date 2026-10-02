class_name RainPresentation
extends WeatherPresentation
## Cel-styled rain streaks (Bontago-22y.5), presentation only on every peer. One
## MultiMeshInstance3D of quads animated in shaders/rain_streaks.gdshader; the
## script only feeds the camera position (the rain volume follows the view, not
## the whole map) and the ramped intensity as density. Tunables:
## config/weather/rain.tres (RainTuning). Low preset (ambient life off) draws
## RainTuning.low_preset_density of the streaks.

const SHADER: Shader = preload("res://shaders/rain_streaks.gdshader")
const TUNING: RainTuning = preload("res://config/weather/rain.tres")
## The volume's AABB is unbounded for culling: the vertex shader relocates it.
const CULL_EXTENT_M: float = 2000.0
## Render layer the mirror camera skips (game/DiscMirror.gd): reflected streaks
## rendered at mirror resolution read as dotted chains. Distinct from CloudSea.
const RENDER_LAYER_BIT: int = 1 << 17

var _instance: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
var _tuning: RainTuning = TUNING
var _density_scale: float = 1.0


func _ready() -> void:
	_build()
	# Bontago-1pi.11.37: the adaptive governor thins the rain without a rebuild.
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


## Test seam.
func configure(tuning: RainTuning, density_scale: float) -> void:
	_tuning = tuning
	_density_scale = density_scale
	_build()


func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	if _instance != null:
		var total: int = _instance.multimesh.instance_count
		_instance.multimesh.visible_instance_count = int(roundf(float(total) * preset.weather_density_scale))


func streak_instance() -> MultiMeshInstance3D:
	return _instance


func shader_density() -> float:
	return float(_material.get_shader_parameter(&"density")) if _material != null else 0.0


func _preset_scale() -> float:
	var preset: GraphicsPreset = Settings.current_graphics_preset() if Engine.get_main_loop() != null else null
	if preset != null and not preset.ambient_life_enabled:
		return _tuning.low_preset_density * preset.weather_density_scale
	return preset.weather_density_scale if preset != null else 1.0


func _build() -> void:
	if _instance != null:
		remove_child(_instance)
		_instance.free()
		_instance = null
	var count: int = int(roundf(float(_tuning.streak_count) * _density_scale * _preset_scale()))
	if count <= 0:
		set_process(false)
		return
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 22005
	for index: int in range(count):
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		# w is index-ordered so the density cull thins the rain evenly.
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), (float(index) + 0.5) / float(count)))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"half_size", _tuning.area_radius_m)
	_material.set_shader_parameter(&"box_height", _tuning.area_height_m)
	_material.set_shader_parameter(&"fall_speed", _tuning.fall_speed_mps)
	_material.set_shader_parameter(&"streak_length", _tuning.streak_length_m)
	_material.set_shader_parameter(&"streak_width", _tuning.streak_width_m)
	_material.set_shader_parameter(&"slant", Vector2(_tuning.slant_mps, 0.0))
	_material.set_shader_parameter(&"streak_color", _tuning.streak_color)
	_material.set_shader_parameter(&"streak_alpha", _tuning.streak_alpha)
	_material.set_shader_parameter(&"fade_far", _tuning.fade_far_m)
	_material.set_shader_parameter(&"near_fade", _tuning.near_fade_m)
	_material.set_shader_parameter(&"min_screen_length", _tuning.min_screen_length)
	_material.set_shader_parameter(&"density", intensity)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Streaks"
	_instance.layers = RENDER_LAYER_BIT
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = AABB(Vector3.ONE * -CULL_EXTENT_M, Vector3.ONE * CULL_EXTENT_M * 2.0)
	add_child(_instance)
	set_process(true)


func set_intensity(value: float) -> void:
	super.set_intensity(value)
	if _material != null:
		_material.set_shader_parameter(&"density", value)
	_apply_mood(value)


func _exit_tree() -> void:
	_apply_mood(0.0)


## Overcast and wet disc: presentation only, owned by Skybox/TerritoryOverlay
## (see Skybox.set_overcast for the theme-switch DECISION). Amount 0 restores.
func _apply_mood(amount: float) -> void:
	if not is_inside_tree() and amount > 0.0:
		return
	var tree: SceneTree = get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if tree == null:
		return
	for node: Node in tree.get_nodes_in_group(Skybox.OVERCAST_GROUP):
		(node as Skybox).set_overcast(amount, _tuning.overcast_light_scale, _tuning.overcast_ambient_scale,
			_tuning.overcast_sky_exposure_scale, _tuning.overcast_fog_color, _tuning.overcast_fog_strength)
	for node: Node in tree.get_nodes_in_group(TerritoryOverlay.WET_GROUP):
		(node as TerritoryOverlay).set_wet(amount, _tuning.wet_sheen_add, _tuning.wet_roughness_scale)


func _process(_delta: float) -> void:
	if _material == null or not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera != null:
		_material.set_shader_parameter(&"center", camera.global_position)
