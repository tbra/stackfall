class_name RainPuddles
extends Node3D
## Bontago-mp0.21: rain puddles on the disc top, presentation only on every
## peer. A child of the Field, so the patches follow its tilt. One MultiMesh of
## flat quads drawn by shaders/rain_puddles.gdshader; the script only integrates
## a `wetness` 0..1 (fills while it rains, dries after) and feeds the shader.
## RainPresentation creates it and feeds the ramped intensity; it outlives the
## presentation (which is freed when the weather stops) so the disc dries
## gradually. Tunables: config/weather/rain.tres (RainTuning, "Puddles").

const SHADER: Shader = preload("res://shaders/rain_puddles.gdshader")
const TUNING: RainTuning = preload("res://config/weather/rain.tres")
const NODE_NAME: String = "RainPuddles"
const SEED: int = 21021
## Placement tries per patch, and how far in from the rim a patch must stay
## (fraction of its radius probed along each axis).
const PLACE_TRIES: int = 24
const EDGE_PROBE: float = 0.8
## Patch squash range (z radius / x radius).
const ASPECT_MIN: float = 0.6
const CULL_EXTENT_M: float = 2000.0

var _tuning: RainTuning = TUNING
var _material: ShaderMaterial = null
var _instance: MultiMeshInstance3D = null
var _wetness: float = 0.0
var _rain: float = 0.0
var _map_def: MapDef = null


## Finds or builds the puddle layer on `field_node`.
static func ensure_on(field_node: Node3D, map_def: MapDef, tuning: RainTuning, count_scale: float) -> RainPuddles:
	var existing: RainPuddles = field_node.get_node_or_null(NODE_NAME) as RainPuddles
	if existing != null:
		return existing
	var puddles: RainPuddles = RainPuddles.new()
	puddles.name = NODE_NAME
	field_node.add_child(puddles)
	puddles.build(map_def, tuning, count_scale)
	return puddles


## Patch-count scale for a graphics preset (Low presets draw fewer).
static func count_scale_for(preset: GraphicsPreset, tuning: RainTuning) -> float:
	if preset == null:
		return 1.0
	var factor: float = preset.weather_density_scale
	if not preset.ambient_life_enabled:
		factor *= tuning.puddle_low_preset_scale
	return factor


func _exit_tree() -> void:
	if Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.disconnect(_on_graphics_preset_changed)


## The count scale is baked into the MultiMesh, so a preset change rebuilds it
## (same seed: the surviving patches keep their places).
func _on_graphics_preset_changed(preset: GraphicsPreset) -> void:
	if _map_def != null:
		build(_map_def, _tuning, count_scale_for(preset, _tuning))


func wetness() -> float:
	return _wetness


func patch_count() -> int:
	return _instance.multimesh.instance_count if _instance != null else 0


func set_rain(intensity: float) -> void:
	_rain = clampf(intensity, 0.0, 1.0)
	set_process(true)


## Pure integration step (also the test seam).
func advance(delta: float) -> void:
	if _rain > 0.0:
		_wetness = minf(_wetness + _rain * delta / maxf(_tuning.puddle_fill_time_s, 0.001), 1.0)
	else:
		_wetness = maxf(_wetness - delta / maxf(_tuning.puddle_dry_time_s, 0.001), 0.0)
	if _material != null:
		_material.set_shader_parameter(&"wetness", _wetness)
		_material.set_shader_parameter(&"rain_density", _rain)
	if _instance != null:
		_instance.visible = _wetness > 0.0
	if _wetness <= 0.0 and _rain <= 0.0:
		set_process(false)


func _process(delta: float) -> void:
	advance(delta)


func build(map_def: MapDef, tuning: RainTuning, count_scale: float) -> void:
	_tuning = tuning
	_map_def = map_def
	if not Settings.graphics_preset_changed.is_connected(_on_graphics_preset_changed):
		Settings.graphics_preset_changed.connect(_on_graphics_preset_changed)
	if _instance != null:
		remove_child(_instance)
		_instance.queue_free()
		_instance = null
	var wanted: int = int(roundf(float(tuning.puddle_count) * count_scale))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = SEED
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	for _index: int in range(wanted):
		var radius: float = rng.randf_range(tuning.puddle_radius_min_m, maxf(tuning.puddle_radius_max_m, tuning.puddle_radius_min_m))
		var spin: float = rng.randf() * TAU
		var aspect: float = rng.randf_range(ASPECT_MIN, 1.0)
		var centre: Vector2 = Vector2.INF
		for _try: int in range(PLACE_TRIES):
			var candidate: Vector2 = Vector2.from_angle(rng.randf() * TAU) * map_def.field_radius * sqrt(rng.randf())
			if _fits(map_def, candidate, radius):
				centre = candidate
				break
		if centre == Vector2.INF:
			continue
		var basis: Basis = Basis(Vector3.UP, spin) * Basis.from_scale(Vector3(radius, 1.0, radius * aspect))
		transforms.append(Transform3D(basis, Vector3(centre.x, tuning.puddle_lift_m, centre.y)))
		customs.append(Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.orientation = PlaneMesh.FACE_Y
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	for index: int in range(transforms.size()):
		multimesh.set_instance_transform(index, transforms[index])
		multimesh.set_instance_custom_data(index, customs[index])
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"water_color", tuning.puddle_color)
	_material.set_shader_parameter(&"rim_color", tuning.puddle_rim_color)
	_material.set_shader_parameter(&"glint_color", tuning.puddle_glint_color)
	_material.set_shader_parameter(&"alpha_scale", tuning.puddle_alpha)
	_material.set_shader_parameter(&"ripples", 1.0 if tuning.puddle_ripples_enabled else 0.0)
	_material.set_shader_parameter(&"wetness", _wetness)
	_material.set_shader_parameter(&"rain_density", _rain)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Patches"
	_instance.multimesh = multimesh
	_instance.material_override = _material
	_instance.layers = RainPresentation.RENDER_LAYER_BIT
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.custom_aabb = AABB(Vector3.ONE * -CULL_EXTENT_M, Vector3.ONE * CULL_EXTENT_M * 2.0)
	_instance.visible = _wetness > 0.0
	add_child(_instance)


## True when a patch of `radius` at `centre` stays on the disc: the centre and
## four probes inside the rim all lie in the map shape.
static func _fits(map_def: MapDef, centre: Vector2, radius: float) -> bool:
	if not map_def.shape_contains(centre):
		return false
	var reach: float = radius * EDGE_PROBE
	for probe: Vector2 in [Vector2(reach, 0.0), Vector2(-reach, 0.0), Vector2(0.0, reach), Vector2(0.0, -reach)]:
		if not map_def.shape_contains(centre + probe):
			return false
	return true
