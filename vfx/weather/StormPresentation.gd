class_name StormPresentation
extends WeatherPresentation
## Bontago-22y.4: client-side wind visuals -- cartoon wind swooshes and drifting
## dust/leaf motes flowing along the seeded wind heading (core/WindField.gd,
## the same direction the host pushes blocks). Bontago-mp0.81 swapped the looks:
## the streaks are the curled swoosh strokes (shaders/gust_swoosh.gdshader, strokes
## scattered through the weather box) that a Breeze gust used to draw; the motes
## stay on shaders/wind_streak.gdshader. The script only integrates the gusting
## travel distance and feeds uniforms. Presentation only: no physics.
## Density follows the ramped intensity; the Low graphics preset thins both.

const MOTE_SHADER: Shader = preload("res://shaders/wind_streak.gdshader")
const SWOOSH_SHADER: Shader = preload("res://shaders/gust_swoosh.gdshader")
const TUNING: StormTuning = preload("res://config/weather/storm.tres")
const KIND_STREAK: int = 0
const KIND_MOTE: int = 1
# DECISION: these are degenerate-mesh guards, not look tunables: a curl tightening
# of 1.0 would close to zero radius, the curl may not eat more than this share of
# the arc (the lead-in keeps the rest), and fewer than this many segments cannot bend.
const MAX_CURL_TIGHTEN: float = 0.95
const MAX_CURL_ARC_FRAC: float = 0.8
const MIN_RIBBON_SEGMENTS: int = 8
# DECISION: the swoosh shader divides by these, so keep them off zero.
const MIN_CYCLE_S: float = 0.1
const MIN_PHASE_FRAC: float = 0.01
const MIN_SPEED_MS: float = 0.01
# DECISION: the weather box is scattered evenly (the swoosh shader's gust volume
# maps onto it one to one), so the height bias and height-dependent length of a
# gust volume are switched off with their neutral values.
const FULL_SPREAD: float = 1.0
const NEUTRAL_HEIGHT_BIAS: float = 1.0
const NO_HEIGHT_LENGTH_GAIN: float = 0.0

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


## CPU mirror of the shader's hash (used for the spawn-position test).
static func _hash11(n: float) -> float:
	return fposmod(sin(n * 127.1 + 311.7) * 43758.5453, 1.0)


## Cycle time of one swoosh stroke: draw-on, hold and draw-off seconds (Bontago-mp0.131).
static func stroke_cycle_s(wind_tuning: StormTuning) -> float:
	return maxf(wind_tuning.streak_draw_on_s + wind_tuning.streak_hold_s + wind_tuning.streak_draw_off_s, MIN_CYCLE_S)


## Metres a stroke drifts downwind over one cycle (slow: the reveal sweep is the motion).
static func stroke_drift_m(wind_tuning: StormTuning) -> float:
	return wind_tuning.streak_speed_ms * stroke_cycle_s(wind_tuning)


## Share of the cycle spent drawing on (x) and drawing off (y).
static func phase_fracs(wind_tuning: StormTuning) -> Vector2:
	var cycle: float = stroke_cycle_s(wind_tuning)
	return Vector2(maxf(wind_tuning.streak_draw_on_s / cycle, MIN_PHASE_FRAC), maxf(wind_tuning.streak_draw_off_s / cycle, MIN_PHASE_FRAC))


## Pure mirror of the shader's reveal window at cycle phase c (0..1): x is the tail edge,
## y the head edge, in stroke arc fraction (feather `softness` beyond 0..1 so the ends
## fully clear). The head sweeps 0 -> 1 + softness during draw-on; the tail then sweeps
## -softness -> 1 during draw-off, so a stroke is drawn along the wind and wiped the same way.
static func reveal_window(c: float, draw_frac: float, erase_frac: float, softness: float) -> Vector2:
	var head: float = smoothstep(0.0, 1.0, clampf(c / maxf(draw_frac, MIN_PHASE_FRAC), 0.0, 1.0))
	var tail: float = smoothstep(0.0, 1.0, clampf((c - (1.0 - erase_frac)) / maxf(erase_frac, MIN_PHASE_FRAC), 0.0, 1.0))
	return Vector2(tail * (1.0 + softness) - softness, head * (1.0 + softness))


## Centre of the weather box the swoosh strokes are scattered through (before the
## per-frame shift that keeps the downwind drift centred on the disc).
static func box_center(wind_tuning: StormTuning) -> Vector3:
	return Vector3(0.0, (wind_tuning.area_min_height_m + wind_tuning.area_max_height_m) * 0.5, 0.0)


## World position where stroke `seed_rank` starts its life number `cycle_index`
## for a wind blowing along `heading` (mirrors the shader's respawn scatter, before
## the wind drift is added).
static func streak_spawn(seed_rank: float, cycle_index: int, wind_tuning: StormTuning, heading: Vector2 = Vector2.RIGHT) -> Vector3:
	var key: float = seed_rank * 91.7 + float(cycle_index) * 13.3
	var half: float = wind_tuning.area_half_extent_m
	var half_y: float = (wind_tuning.area_max_height_m - wind_tuning.area_min_height_m) * 0.5
	var along_dir: Vector3 = Vector3(heading.x, 0.0, heading.y)
	var side_dir: Vector3 = Vector3(-heading.y, 0.0, heading.x)
	return box_center(wind_tuning) \
		+ along_dir * ((_hash11(key + 1.0) * 2.0 - 1.0) * half) \
		+ side_dir * ((_hash11(key + 2.0) * 2.0 - 1.0) * half) \
		+ Vector3.UP * ((_hash11(key + 3.0) * 2.0 - 1.0) * half_y)


## Opacity multiplier (0..1) of a streak `distance_m` from the camera: zero
## inside the near-fade start, rising to one at its end.
static func streak_near_weight(distance_m: float, wind_tuning: StormTuning) -> float:
	return smoothstep(wind_tuning.streak_near_fade_start_m, wind_tuning.streak_near_fade_end_m, distance_m)


func streak_material() -> ShaderMaterial:
	if _materials.size() <= KIND_STREAK or _instances.is_empty() or _instances[0].name != &"Streaks":
		return null
	return _materials[KIND_STREAK]


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
		_materials[i].set_shader_parameter(&"wind_dir", dir)
		if i == KIND_STREAK:
			# Swoosh strokes take the travel as time (cycle = travel / cycle_s); the box is
			# shifted upwind by half a life so the downwind drift stays centred on the disc.
			_materials[i].set_shader_parameter(&"travel", _travel)
			_materials[i].set_shader_parameter(&"center", box_center(tuning) - dir * (stroke_drift_m(tuning) * 0.5))
		else:
			_materials[i].set_shader_parameter(&"travel", _travel * tuning.mote_speed_ms)


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
	var preset: GraphicsPreset = Settings.current_graphics_preset() if is_inside_tree() else null
	if preset != null:
		scale_factor *= preset.weather_density_scale
	_add_kind(KIND_STREAK, int(round(float(tuning.streak_count) * scale_factor)))
	_add_kind(KIND_MOTE, int(round(float(tuning.mote_count) * scale_factor)))


func _add_kind(kind: int, count: int) -> void:
	if count <= 0:
		return
	if kind == KIND_STREAK:
		_add_streaks(count)
		return
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _quad_mesh()
	multimesh.instance_count = count
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tuning.scatter_seed + kind
	for index: int in range(count):
		multimesh.set_instance_transform(index, Transform3D.IDENTITY)
		# The rank is stratified so any prefix of densities is evenly spread.
		var rank: float = (float(index) + rng.randf()) / float(count)
		multimesh.set_instance_custom_data(index, Color(rng.randf(), rng.randf(), rng.randf(), rank))
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = MOTE_SHADER
	var half: float = tuning.area_half_extent_m
	var half_y: float = (tuning.area_max_height_m - tuning.area_min_height_m) * 0.5
	material.set_shader_parameter(&"box_half", Vector3(half, half_y, half))
	material.set_shader_parameter(&"box_base_y", tuning.area_min_height_m)
	material.set_shader_parameter(&"length_m", tuning.mote_size_m)
	material.set_shader_parameter(&"length_min_m", tuning.mote_size_m)
	material.set_shader_parameter(&"width_m", tuning.mote_size_m)
	material.set_shader_parameter(&"mote_mix", 1.0)
	material.set_shader_parameter(&"tint", tuning.mote_color)
	material.set_shader_parameter(&"fade_far_m", tuning.fade_far_m)
	material.set_shader_parameter(&"near_fade_m", Vector2(tuning.mote_near_fade_start_m, tuning.mote_near_fade_end_m))
	material.set_shader_parameter(&"density", intensity)
	_add_instance("Motes", multimesh, material)
	_materials.append(material)


## The curled swoosh strokes: leaders (the curl at the head) and plain lines are two
## MultiMeshes sharing one material, scattered in clusters of parallel strokes.
func _add_streaks(count: int) -> void:
	var leaders: int = clampi(int(round(float(count) * tuning.swoosh_curl_lead_frac)), 0, count)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = tuning.scatter_seed + KIND_STREAK
	var material: ShaderMaterial = _swoosh_material()
	var meshes: Array[ArrayMesh] = [build_swoosh_ribbon(tuning, false), build_swoosh_ribbon(tuning, true)]
	var counts: Array[int] = [count - leaders, leaders]
	for i: int in range(meshes.size()):
		if counts[i] <= 0:
			continue
		var instance_name: String = "Streaks" if _instances.is_empty() else "StreakLeaders"
		_add_instance(instance_name, _build_swoosh_multimesh(meshes[i], counts[i], rng), material)
	_materials.append(material)


func _swoosh_material() -> ShaderMaterial:
	var half: float = maxf(tuning.area_half_extent_m, 0.01)
	var half_y: float = (tuning.area_max_height_m - tuning.area_min_height_m) * 0.5
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SWOOSH_SHADER
	# The shader's gust volume (centre, radius, per-axis spread) is the weather box.
	material.set_shader_parameter(&"center", box_center(tuning))
	material.set_shader_parameter(&"radius", half)
	material.set_shader_parameter(&"spread_along", FULL_SPREAD)
	material.set_shader_parameter(&"spread_side", FULL_SPREAD)
	material.set_shader_parameter(&"spread_up", half_y / half)
	material.set_shader_parameter(&"height_bias", NEUTRAL_HEIGHT_BIAS)
	material.set_shader_parameter(&"height_length_gain", NO_HEIGHT_LENGTH_GAIN)
	material.set_shader_parameter(&"length_m", tuning.streak_length_m)
	material.set_shader_parameter(&"width_m", tuning.streak_width_m)
	material.set_shader_parameter(&"speed", tuning.streak_speed_ms)
	material.set_shader_parameter(&"tint", tuning.streak_color)
	material.set_shader_parameter(&"spacing_m", tuning.swoosh_parallel_spacing_m)
	material.set_shader_parameter(&"cycle_s", stroke_cycle_s(tuning))
	var fracs: Vector2 = phase_fracs(tuning)
	material.set_shader_parameter(&"draw_frac", fracs.x)
	material.set_shader_parameter(&"erase_frac", fracs.y)
	material.set_shader_parameter(&"reveal_softness", tuning.streak_reveal_softness)
	material.set_shader_parameter(&"tip_taper", tuning.streak_tip_taper)
	material.set_shader_parameter(&"peak_bias", tuning.swoosh_width_peak_bias)
	material.set_shader_parameter(&"min_foreshorten", tuning.swoosh_min_foreshorten)
	material.set_shader_parameter(&"length_variation", tuning.swoosh_length_variation)
	material.set_shader_parameter(&"parallel_shrink", tuning.swoosh_parallel_shrink)
	material.set_shader_parameter(&"parallel_lag", tuning.swoosh_parallel_lag_frac)
	material.set_shader_parameter(&"anchor_frac", tuning.swoosh_anchor_frac)
	material.set_shader_parameter(&"life", 1.0)
	material.set_shader_parameter(&"density", intensity)
	material.set_shader_parameter(&"near_fade_m", Vector2(tuning.streak_near_fade_start_m, tuning.streak_near_fade_end_m))
	material.set_shader_parameter(&"fade_far_m", tuning.fade_far_m)
	return material


## INSTANCE_CUSTOM = (stratified cluster rank 0..1, cycle phase, parallel index in the
## cluster (-1, 0, 1 ...), per-stroke variation). A cluster of 1..swoosh_group_max
## parallel strokes shares a spot, a rank and a phase.
func _build_swoosh_multimesh(mesh: ArrayMesh, count: int, rng: RandomNumberGenerator) -> MultiMesh:
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = count
	var sizes: Array[int] = []
	var placed: int = 0
	while placed < count:
		var size: int = mini(rng.randi_range(1, maxi(tuning.swoosh_group_max, 1)), count - placed)
		sizes.append(size)
		placed += size
	var index: int = 0
	for group: int in range(sizes.size()):
		var rank: float = (float(group) + rng.randf()) / float(sizes.size())
		var phase: float = rng.randf()
		for k: int in range(sizes[group]):
			var parallel: float = float(k) - float(sizes[group] - 1) * 0.5
			multimesh.set_instance_transform(index, Transform3D.IDENTITY)
			multimesh.set_instance_custom_data(index, Color(rank, phase, parallel, rng.randf()))
			index += 1
	return multimesh


func _add_instance(instance_name: String, multimesh: MultiMesh, material: ShaderMaterial) -> void:
	var half: float = tuning.area_half_extent_m
	var half_y: float = (tuning.area_max_height_m - tuning.area_min_height_m) * 0.5
	var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
	instance.name = instance_name
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# DECISION: share rain's weather-presentation render layer, which
	# DiscMirror's cull mask excludes; mirrored streaks aimed at the camera
	# read as grey squares on the disc.
	instance.layers = RainPresentation.RENDER_LAYER_BIT
	# The swoosh strokes drift up to a life downwind of the box.
	var extent: float = (maxf(half, half_y) + stroke_drift_m(tuning)) * 2.0
	instance.custom_aabb = AABB(Vector3.ONE * -extent, Vector3.ONE * extent * 2.0)
	add_child(instance)
	_instances.append(instance)


func _quad_mesh() -> QuadMesh:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	return quad


## Builds the unit-arc-length swoosh ribbon: a gently waving lead-in then a
## curling hook. VERTEX = centerline (x, y, 0), NORMAL = (nx, ny, 0), UV = (arc
## fraction, side -1/+1). Static so tests can inspect the shape.
static func build_swoosh_ribbon(wind_tuning: StormTuning, curled: bool = true) -> ArrayMesh:
	var segments: int = maxi(wind_tuning.swoosh_ribbon_segments, MIN_RIBBON_SEGMENTS)
	var radius: float = maxf(wind_tuning.swoosh_curl_radius_frac, 0.01)
	var tighten: float = clampf(wind_tuning.swoosh_curl_tighten, 0.0, MAX_CURL_TIGHTEN)
	var total_angle: float = maxf(wind_tuning.swoosh_curl_turns, 0.05) * TAU
	# DECISION: the curl arc is analytic (R * angle * (1 - tighten / 2)); the
	# lead-in takes whatever arc remains of the unit length (at least a fifth).
	var curl_arc: float = minf(radius * total_angle * (1.0 - tighten * 0.5), MAX_CURL_ARC_FRAC) if curled else 0.0
	var body_arc: float = 1.0 - curl_arc
	var body_count: int = clampi(int(round(float(segments) * body_arc)), 2, segments - 2) if curled else segments
	var curl_count: int = segments - body_count
	var points: Array[Vector2] = [Vector2.ZERO]
	var pos: Vector2 = Vector2.ZERO
	var step: float = body_arc / float(body_count)
	for i: int in range(body_count):
		var u: float = (float(i) + 0.5) / float(body_count)
		var theta: float = wind_tuning.swoosh_body_swing_rad * sin(TAU * u)
		pos += Vector2(cos(theta), sin(theta)) * step
		points.append(pos)
	var d_phi: float = total_angle / float(maxi(curl_count, 1))
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
