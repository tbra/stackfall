class_name GustPresentation
extends Node3D
## Bontago-59o.6 / mp0.81: one gust's visual, a handful of soft wind wisps (bowed,
## feathered, banded ribbons) scattered in a heading-aligned box around the gust's
## centre, drifting along its heading (shaders/wind_streak.gdshader does all per-wisp
## motion: draw-on, hold, erase from the tail, respawn). Frees itself when the gust
## ends. The Low graphics preset draws a fraction of the wisps. Presentation only.
## Bontago-mp0.81 swapped the looks: a gust used to draw the curled swoosh strokes
## that now belong to the ambient Storm wind (StormPresentation.build_swoosh_ribbon).

const SHADER: Shader = preload("res://shaders/wind_streak.gdshader")
const RENDER_LAYER_BIT: int = 1 << 17
## Segments along a wisp ribbon (enough for a smooth bow and waver).
const RIBBON_SEGMENTS: int = 14
# DECISION: the shader divides by the metres a wisp drifts over one life, so keep it off zero.
const MIN_LIFE_M: float = 0.1
const MIN_PHASE_FRAC: float = 0.01

var _gust: Dictionary = {}
var _tuning: BreezeTuning = null
var _age: float = 0.0
var _material: ShaderMaterial = null
var _instances: Array[MultiMeshInstance3D] = []


func configure(gust: Dictionary, tuning: BreezeTuning) -> void:
	_gust = gust
	_tuning = tuning


## World-space unit vector the wisps travel along: the gust's wire heading,
## the same vector BreezeField.push_direction turns (by swirl_deg) for physics.
static func travel_direction(gust: Dictionary) -> Vector3:
	var heading: Vector2 = BreezeField.heading(float(gust["a"]))
	return Vector3(heading.x, 0.0, heading.y)


func material() -> ShaderMaterial:
	return _material


func streak_count() -> int:
	var total: int = 0
	for instance: MultiMeshInstance3D in _instances:
		total += instance.multimesh.instance_count
	return total


## A flat strip along x (-0.5..0.5) with UV.x = fraction along it, so the shader
## can taper, bow and draw it on. VERTEX.y = +-0.5 marks the two edges. Static so
## tests can inspect the shape.
static func build_wisp_ribbon() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	for i: int in range(RIBBON_SEGMENTS + 1):
		var t: float = float(i) / float(RIBBON_SEGMENTS)
		vertices.append(Vector3(t - 0.5, -0.5, 0.0))
		uvs.append(Vector2(t, 0.0))
		vertices.append(Vector3(t - 0.5, 0.5, 0.0))
		uvs.append(Vector2(t, 1.0))
	for i: int in range(RIBBON_SEGMENTS):
		var a: int = i * 2
		indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(_gust["id"]) * 7919 + 17
	var radius: float = float(_gust["r"])
	var half: Vector3 = Vector3(radius * _tuning.gust_spread_along_frac, radius * _tuning.gust_spread_up_frac, radius * _tuning.gust_spread_side_frac)
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"wind_dir", travel_direction(_gust))
	_material.set_shader_parameter(&"box_center", Vector3(float(_gust["x"]), float(_gust["y"]), float(_gust["z"])))
	_material.set_shader_parameter(&"box_align", true)
	_material.set_shader_parameter(&"box_half", half)
	_material.set_shader_parameter(&"box_base_y", -half.y)
	_material.set_shader_parameter(&"height_bias", _tuning.gust_height_bias)
	_material.set_shader_parameter(&"height_length_gain", _tuning.gust_height_length_gain)
	_material.set_shader_parameter(&"length_m", _tuning.gust_streak_length_m)
	_material.set_shader_parameter(&"length_min_m", _tuning.gust_streak_length_min_m)
	_material.set_shader_parameter(&"width_m", _tuning.gust_streak_width_m)
	_material.set_shader_parameter(&"mote_mix", 0.0)
	_material.set_shader_parameter(&"tint", _tuning.gust_color)
	_material.set_shader_parameter(&"band_tint", _tuning.gust_band_color)
	_material.set_shader_parameter(&"band_width", _tuning.gust_band_width)
	_material.set_shader_parameter(&"edge_softness", _tuning.gust_edge_softness)
	_material.set_shader_parameter(&"fade_far_m", _tuning.fade_far_m)
	_material.set_shader_parameter(&"near_fade_m", Vector2(_tuning.streak_near_fade_start_m, _tuning.streak_near_fade_end_m))
	_material.set_shader_parameter(&"life_m", wisp_life_m(_tuning))
	_material.set_shader_parameter(&"draw_frac", maxf(_tuning.gust_draw_on_frac, MIN_PHASE_FRAC))
	_material.set_shader_parameter(&"erase_frac", maxf(_tuning.gust_erase_frac, MIN_PHASE_FRAC))
	_material.set_shader_parameter(&"tip_taper", _tuning.gust_tip_taper_frac)
	_material.set_shader_parameter(&"bow_m", _tuning.gust_bow_m)
	_material.set_shader_parameter(&"wobble_m", _tuning.gust_wobble_m)
	_material.set_shader_parameter(&"opacity_min", _tuning.gust_opacity_min)
	_material.set_shader_parameter(&"density", 1.0)
	_material.set_shader_parameter(&"life", 0.0)
	_material.set_shader_parameter(&"travel", 0.0)
	var extent: float = radius * 4.0 + _tuning.gust_streak_speed_ms * _tuning.gust_stroke_cycle_s + _tuning.wire_max_coord_m
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.multimesh = _build_multimesh(build_wisp_ribbon(), count, rng)
	instance.material_override = _material
	instance.layers = RENDER_LAYER_BIT
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.custom_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	add_child(instance)
	_instances.append(instance)


## Metres a wisp drifts over one life: the gust's drift speed over its stroke cycle,
## so each wisp cycles in gust_stroke_cycle_s as the swoosh strokes did.
static func wisp_life_m(tuning: BreezeTuning) -> float:
	return maxf(tuning.gust_streak_speed_ms * tuning.gust_stroke_cycle_s, MIN_LIFE_M)


## INSTANCE_CUSTOM = (cycle offset, unused, unused, stratified rank 0..1).
func _build_multimesh(mesh: ArrayMesh, count: int, rng: RandomNumberGenerator) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	for index: int in range(count):
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		var rank: float = (float(index) + rng.randf()) / float(count)
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rank))
	return multimesh


func _process(delta: float) -> void:
	_age += delta
	var duration: float = float(_gust.get("d", 0.0))
	if _age >= duration:
		queue_free()
		return
	if _material != null:
		_material.set_shader_parameter(&"life", BreezeField.envelope(_age, duration))
		_material.set_shader_parameter(&"travel", _age * _tuning.gust_streak_speed_ms)
