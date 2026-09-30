class_name GustPresentation
extends Node3D
## Bontago-470.2: one gust's visual, a brief local swirl of cel streaks around
## the gust's centre travelling along its heading (shaders/gust_swirl.gdshader
## does all per-streak motion). Frees itself when the gust ends. The Low
## graphics preset draws a fraction of the streaks. Presentation only.

const SHADER: Shader = preload("res://shaders/gust_swirl.gdshader")
const RENDER_LAYER_BIT: int = 1 << 17

var _gust: Dictionary = {}
var _tuning: BreezeTuning = null
var _age: float = 0.0
var _material: ShaderMaterial = null
var _instance: MultiMeshInstance3D = null


func configure(gust: Dictionary, tuning: BreezeTuning) -> void:
	_gust = gust
	_tuning = tuning


func streak_count() -> int:
	return _instance.multimesh.instance_count if _instance != null else 0


func _ready() -> void:
	if _tuning == null or _gust.is_empty():
		queue_free()
		return
	var count: int = _tuning.gust_streak_count
	var preset: GraphicsPreset = Settings.current_graphics_preset() if Engine.get_main_loop() != null else null
	if preset != null and not preset.ambient_life_enabled:
		count = int(round(float(count) * _tuning.gust_low_preset_density))
	if count <= 0:
		queue_free()
		return
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(_gust["id"]) * 7919 + 17
	for index: int in range(count):
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	var angle: float = float(_gust["a"])
	_material.set_shader_parameter(&"center", Vector3(float(_gust["x"]), float(_gust["y"]), float(_gust["z"])))
	_material.set_shader_parameter(&"heading", Vector3(cos(angle), 0.0, sin(angle)))
	_material.set_shader_parameter(&"radius", float(_gust["r"]))
	_material.set_shader_parameter(&"length_m", _tuning.gust_streak_length_m)
	_material.set_shader_parameter(&"width_m", _tuning.gust_streak_width_m)
	_material.set_shader_parameter(&"speed", _tuning.gust_streak_speed_ms)
	_material.set_shader_parameter(&"tint", _tuning.gust_color)
	_material.set_shader_parameter(&"life", 0.0)
	_instance = MultiMeshInstance3D.new()
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.layers = RENDER_LAYER_BIT
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var extent: float = float(_gust["r"]) * 4.0 + 1000.0
	_instance.custom_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	add_child(_instance)


func _process(delta: float) -> void:
	_age += delta
	var duration: float = float(_gust.get("d", 0.0))
	if _age >= duration:
		queue_free()
		return
	if _material != null:
		_material.set_shader_parameter(&"life", BreezeField.envelope(_age, duration))
		_material.set_shader_parameter(&"travel", _age)
