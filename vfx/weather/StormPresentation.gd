class_name StormPresentation
extends WeatherPresentation
## Bontago-22y.4: client-side wind visuals -- cel wind streaks and drifting
## dust/leaf motes flowing along the seeded wind heading (core/WindField.gd,
## the same direction the host pushes blocks). Two MultiMeshes share
## shaders/wind_streak.gdshader; the script only integrates the gusting
## travel distance and feeds uniforms. Presentation only: no physics.
## Density follows the ramped intensity; the Low graphics preset thins both.

const SHADER: Shader = preload("res://shaders/wind_streak.gdshader")
const TUNING: StormTuning = preload("res://config/weather/storm.tres")
const KIND_STREAK: int = 0
const KIND_MOTE: int = 1

var tuning: StormTuning = TUNING
var _seed: int = 0
## True once configure() fixed the seed (tests, probes); otherwise it follows
## the replicated match seed.
var _seed_locked: bool = false
var _elapsed: float = 0.0
var _travel: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _instances: Array[MultiMeshInstance3D] = []


func _ready() -> void:
	_build()
	Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)


func _exit_tree() -> void:
	Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


func _on_graphics_preset_changed(_preset: GraphicsPreset) -> void:
	_build()


## Rebuilds for `seed_value`; tests and the screenshot probe call it directly.
func configure(seed_value: int, wind_tuning: StormTuning = null) -> void:
	_seed = seed_value
	_seed_locked = true
	if wind_tuning != null:
		tuning = wind_tuning
	_build()


func heading() -> Vector2:
	return WindField.direction(_seed, _elapsed, tuning)


func total_instances() -> int:
	var total: int = 0
	for instance: MultiMeshInstance3D in _instances:
		total += instance.multimesh.instance_count
	return total


func set_intensity(value: float) -> void:
	super.set_intensity(value)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(&"density", value)


func _process(delta: float) -> void:
	if not visible:
		return
	if _materials.is_empty():
		return
	if not _seed_locked and is_inside_tree():
		_seed = WindField.event_seed(Match.weather().seed_value(), Match.weather().event_index())
	_elapsed += delta
	var dir2: Vector2 = heading()
	var gust_mult: float = WindField.gust(_seed, _elapsed, tuning)
	_travel += delta * gust_mult * lerpf(0.5, 1.0, intensity)
	var dir: Vector3 = Vector3(dir2.x, 0.0, dir2.y)
	for i: int in range(_materials.size()):
		var speed: float = tuning.streak_speed_ms if i == KIND_STREAK else tuning.mote_speed_ms
		_materials[i].set_shader_parameter(&"wind_dir", dir)
		_materials[i].set_shader_parameter(&"travel", _travel * speed)


func _reduced() -> bool:
	var preset: GraphicsPreset = Settings.current_graphics_preset() if is_inside_tree() else null
	return preset != null and not preset.ambient_life_enabled


func _clear() -> void:
	for instance: MultiMeshInstance3D in _instances:
		remove_child(instance)
		instance.free()
	_instances.clear()
	_materials.clear()


func _build() -> void:
	_clear()
	var scale_factor: float = tuning.low_preset_density if _reduced() else 1.0
	_add_kind(KIND_STREAK, int(round(float(tuning.streak_count) * scale_factor)))
	_add_kind(KIND_MOTE, int(round(float(tuning.mote_count) * scale_factor)))


func _add_kind(kind: int, count: int) -> void:
	if count <= 0:
		return
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tuning.scatter_seed + kind
	for index: int in range(count):
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		# The rank is stratified so any prefix of densities is evenly spread.
		var rank: float = (float(index) + rng.randf()) / float(count)
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rank))
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	var half: float = tuning.area_half_extent_m
	var half_y: float = (tuning.area_max_height_m - tuning.area_min_height_m) * 0.5
	material.set_shader_parameter(&"box_half", Vector3(half, half_y, half))
	material.set_shader_parameter(&"box_base_y", tuning.area_min_height_m)
	material.set_shader_parameter(&"length_m", tuning.streak_length_m if kind == KIND_STREAK else tuning.mote_size_m)
	material.set_shader_parameter(&"width_m", tuning.streak_width_m if kind == KIND_STREAK else tuning.mote_size_m)
	material.set_shader_parameter(&"mote_mix", 0.0 if kind == KIND_STREAK else 1.0)
	material.set_shader_parameter(&"tint", tuning.streak_color if kind == KIND_STREAK else tuning.mote_color)
	material.set_shader_parameter(&"band_tint", tuning.streak_band_color)
	material.set_shader_parameter(&"band_width", tuning.streak_band_width)
	material.set_shader_parameter(&"edge_softness", tuning.streak_edge_softness)
	material.set_shader_parameter(&"fade_far_m", tuning.fade_far_m)
	material.set_shader_parameter(&"near_fade_m", Vector2(tuning.mote_near_fade_start_m, tuning.mote_near_fade_end_m))
	material.set_shader_parameter(&"density", intensity)
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = "Streaks" if kind == KIND_STREAK else "Motes"
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# DECISION: share rain's weather-presentation render layer, which
	# DiscMirror's cull mask excludes; mirrored streaks aimed at the camera
	# read as grey squares on the disc.
	instance.layers = RainPresentation.RENDER_LAYER_BIT
	var extent: float = maxf(half, half_y) * 2.0
	instance.custom_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	add_child(instance)
	_instances.append(instance)
	_materials.append(material)
