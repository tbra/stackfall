class_name Fireflies
extends Node3D
## Bontago-adt.3: night-theme fireflies -- soft glowing warm yellow-green motes
## drifting and blinking around the disc rim, over the cloud sea just below it
## and, sparsely, above the outer band of the disc. One MultiMeshInstance3D of
## billboard quads; all motion and blinking is computed in shaders/fireflies
## .gdshader from TIME, so there is no per-frame script cost beyond noticing a
## map change. Purely cosmetic and local. Tunables: config/AmbientLifeConfig.gd.

const SHADER: Shader = preload("res://shaders/fireflies.gdshader")
const EXTENT_M: float = 400.0

var _instance: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
var _field: Field = null
var _disc_radius: float = -1.0
var _config: AmbientLifeConfig = null


func _ready() -> void:
	set_process(false)


func bind_field(field: Field) -> void:
	_field = field


## Rebuilds the swarm from `life` (nothing when null, fireflies_count is 0 or
## `enabled` is false). Safe to call repeatedly: never leaves duplicates.
func configure(life: AmbientLifeConfig, enabled: bool, radius_m: float = 30.0) -> void:
	if _instance != null:
		remove_child(_instance)
		_instance.free()
		_instance = null
	_config = life
	if life == null or life.fireflies_count <= 0 or not enabled:
		visible = false
		set_process(false)
		return
	visible = true
	_disc_radius = radius_m
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = life.fireflies_count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = life.fireflies_seed
	for index: int in range(life.fireflies_count):
		var above: bool = rng.randf() < life.fireflies_above_disc_fraction
		# The transform origin's x carries the "hovers above the disc" flag.
		multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3(1.0 if above else 0.0, 0.0, 0.0)))
		multimesh.set_instance_custom_data(index, Color(rng.randf() * TAU, rng.randf(), rng.randf(), rng.randf()))
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_apply_uniforms()
	add_to_group(WeatherFogShader.GROUP)
	WeatherFogShader.apply(_material)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Motes"
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = AABB(Vector3(-EXTENT_M, -EXTENT_M, -EXTENT_M), Vector3.ONE * EXTENT_M * 2.0)
	add_child(_instance)
	# The disc radius follows the map (a lobby map change rebuilds the Field).
	set_process(_field != null)


func _process(_delta: float) -> void:
	if _field == null or not is_instance_valid(_field) or _material == null:
		return
	var radius: float = _field.map_definition().field_radius
	if not is_equal_approx(radius, _disc_radius):
		_disc_radius = radius
		_material.set_shader_parameter(&"disc_radius", radius)


func mote_instance() -> MultiMeshInstance3D:
	return _instance


## Weather fog changed (vfx/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	WeatherFogShader.apply(_material)


func _apply_uniforms() -> void:
	var life: AmbientLifeConfig = _config
	_material.set_shader_parameter(&"disc_radius", _disc_radius)
	_material.set_shader_parameter(&"rim_offset", Vector2(life.fireflies_rim_offset_min_m, life.fireflies_rim_offset_max_m))
	_material.set_shader_parameter(&"rim_height", Vector2(life.fireflies_rim_height_min_m, life.fireflies_rim_height_max_m))
	_material.set_shader_parameter(&"above_inset", life.fireflies_above_inset_m)
	_material.set_shader_parameter(&"above_height", Vector2(life.fireflies_above_height_min_m, life.fireflies_above_height_max_m))
	_material.set_shader_parameter(&"drift_radius", life.fireflies_drift_radius_m)
	_material.set_shader_parameter(&"drift_speed", life.fireflies_drift_speed)
	_material.set_shader_parameter(&"blink_hz", life.fireflies_blink_hz)
	_material.set_shader_parameter(&"size_m", life.fireflies_size_m)
	_material.set_shader_parameter(&"glow_color", life.fireflies_color)
	_material.set_shader_parameter(&"energy", life.fireflies_emission_energy)
	_material.set_shader_parameter(&"fade_far_m", life.fireflies_fade_far_m)
