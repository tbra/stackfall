class_name GustPresentation
extends Node3D
## Bontago-59o.6: one gust's visual, a handful of cartoon wind-swoosh ribbons
## (white, flat, tapered, ending in a curl) around the gust's centre drifting
## along its heading (shaders/gust_swoosh.gdshader does all per-stroke motion:
## draw-on, hold, erase from the tail, respawn). Frees itself when the gust
## ends. The Low graphics preset draws a fraction of the strokes. Presentation only.

const SHADER: Shader = preload("res://shaders/gust_swoosh.gdshader")
const RENDER_LAYER_BIT: int = 1 << 17
# DECISION: these are degenerate-mesh guards, not look tunables: a curl tightening
# of 1.0 would close to zero radius, the curl may not eat more than this share of
# the arc (the lead-in keeps the rest), and fewer than this many segments cannot bend.
const MAX_CURL_TIGHTEN: float = 0.95
const MAX_CURL_ARC_FRAC: float = 0.8
const MIN_RIBBON_SEGMENTS: int = 8
# DECISION: shader divides by these, so keep them off zero.
const MIN_CYCLE_S: float = 0.1
const MIN_PHASE_FRAC: float = 0.01

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


## Builds the unit-arc-length swoosh ribbon: a gently waving lead-in then a
## curling hook. VERTEX = centerline (x, y, 0), NORMAL = (nx, ny, 0), UV = (arc
## fraction, side -1/+1). Static so tests can inspect the shape.
static func build_ribbon(tuning: BreezeTuning) -> ArrayMesh:
	var segments: int = maxi(tuning.gust_ribbon_segments, MIN_RIBBON_SEGMENTS)
	var radius: float = maxf(tuning.gust_curl_radius_frac, 0.01)
	var tighten: float = clampf(tuning.gust_curl_tighten, 0.0, MAX_CURL_TIGHTEN)
	var total_angle: float = maxf(tuning.gust_curl_turns, 0.05) * TAU
	# DECISION: the curl arc is analytic (R * angle * (1 - tighten / 2)); the
	# lead-in takes whatever arc remains of the unit length (at least a fifth).
	var curl_arc: float = minf(radius * total_angle * (1.0 - tighten * 0.5), MAX_CURL_ARC_FRAC)
	var body_arc: float = 1.0 - curl_arc
	var body_count: int = clampi(int(round(float(segments) * body_arc)), 2, segments - 2)
	var curl_count: int = segments - body_count
	var points: Array[Vector2] = [Vector2.ZERO]
	var pos: Vector2 = Vector2.ZERO
	var step: float = body_arc / float(body_count)
	for i: int in range(body_count):
		var u: float = (float(i) + 0.5) / float(body_count)
		var theta: float = tuning.gust_body_swing_rad * sin(TAU * u)
		pos += Vector2(cos(theta), sin(theta)) * step
		points.append(pos)
	var d_phi: float = total_angle / float(curl_count)
	for i: int in range(curl_count):
		var phi_mid: float = (float(i) + 0.5) * d_phi
		var r: float = radius * (1.0 - tighten * phi_mid / total_angle)
		pos += Vector2(cos(phi_mid), sin(phi_mid)) * r * d_phi
		points.append(pos)
	var lengths: PackedFloat32Array = PackedFloat32Array([0.0])
	for i: int in range(1, points.size()):
		lengths.append(lengths[i - 1] + points[i].distance_to(points[i - 1]))
	var verts: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	var last: int = points.size() - 1
	for i: int in range(points.size()):
		var tangent: Vector2 = (points[mini(i + 1, last)] - points[maxi(i - 1, 0)]).normalized()
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		var t: float = lengths[i] / lengths[last]
		for side: float in [-1.0, 1.0]:
			verts.append(Vector3(points[i].x, points[i].y, 0.0))
			normals.append(Vector3(normal.x, normal.y, 0.0))
			uvs.append(Vector2(t, side))
		if i < last:
			var a: int = i * 2
			indices.append_array(PackedInt32Array([a, a + 1, a + 2, a + 1, a + 3, a + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
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
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = build_ribbon(_tuning)
	multimesh.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(_gust["id"]) * 7919 + 17
	var index: int = 0
	while index < count:
		# A cluster of 1..gust_group_max parallel strokes sharing a spot and phase.
		var size: int = mini(rng.randi_range(1, maxi(_tuning.gust_group_max, 1)), count - index)
		var seed_value: float = rng.randf()
		var phase: float = rng.randf()
		for k: int in range(size):
			var parallel: float = float(k) - float(size - 1) * 0.5
			multimesh.set_instance_transform(index, Transform3D.IDENTITY)
			multimesh.set_instance_custom_data(index, Color(seed_value, phase, parallel, rng.randf()))
			index += 1
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
	_material.set_shader_parameter(&"spacing_m", _tuning.gust_parallel_spacing_m)
	_material.set_shader_parameter(&"cycle_s", maxf(_tuning.gust_stroke_cycle_s, 0.1))
	_material.set_shader_parameter(&"draw_frac", maxf(_tuning.gust_draw_on_frac, MIN_PHASE_FRAC))
	_material.set_shader_parameter(&"erase_frac", maxf(_tuning.gust_erase_frac, MIN_PHASE_FRAC))
	_material.set_shader_parameter(&"tip_taper", _tuning.gust_tip_taper_frac)
	_material.set_shader_parameter(&"peak_bias", _tuning.gust_width_peak_bias)
	_material.set_shader_parameter(&"spread_along", _tuning.gust_spread_along_frac)
	_material.set_shader_parameter(&"spread_side", _tuning.gust_spread_side_frac)
	_material.set_shader_parameter(&"spread_up", _tuning.gust_spread_up_frac)
	_material.set_shader_parameter(&"min_foreshorten", _tuning.gust_min_foreshorten)
	_material.set_shader_parameter(&"length_variation", _tuning.gust_length_variation)
	_material.set_shader_parameter(&"parallel_shrink", _tuning.gust_parallel_shrink)
	_material.set_shader_parameter(&"parallel_lag", _tuning.gust_parallel_lag_frac)
	_material.set_shader_parameter(&"anchor_frac", _tuning.gust_anchor_frac)
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
