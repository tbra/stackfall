class_name DistantBirds
extends Node3D
## Bontago-adt.1 / 470.5: occasional small flocks of birds that cross the far
## sky. Not a permanent fixture: a few "slots" each wait a long random gap,
## then launch a flight (core/ambient/FlockPlanner.gd: 1-7 birds entering from
## the far ring, crossing past the disc at a distance and leaving the far side).
## One MultiMeshInstance3D holds every slot's birds; all motion (path, glide,
## flap bursts, bank, sway) is done in shaders/distant_birds.gdshader from a
## `flight_clock` uniform this node advances, so the script only schedules
## flights and rewrites a flock's instance data when it launches.
##
## Instance encoding (read by the shader): transform origin = path start;
## basis column 0 = flock velocity, column 1 = formation offset (right, up,
## back), column 2 = (duration, sway amplitude, flock phase); custom data =
## (start clock, bird seed, size, flap-rate multiplier). Parked instances get a
## start clock far in the future and are not drawn.

const SHADER: Shader = preload("res://shaders/distant_birds.gdshader")
const CLOCK_PARAMETER: StringName = &"flight_clock"
## Start clock of a parked (not flying) instance.
const PARKED_START: float = 1.0e9
## Wing half-span in mesh units (the instance size is the bird size in m).
const HALF_SPAN: float = 1.0
## Wing outline along the span (fractions of HALF_SPAN, root to tip): x of the
## leading and trailing edge at each station. The wing sweeps back and tapers
## to a pointed tip, so a bird reads as a bird, not a triangle.
const WING_STATIONS: PackedFloat32Array = [0.0, 0.25, 0.5, 0.75, 1.0]
const WING_LEADING_X: PackedFloat32Array = [0.3, 0.24, 0.08, -0.2, -0.55]
const WING_TRAILING_X: PackedFloat32Array = [-0.3, -0.3, -0.34, -0.44, -0.72]
## UV.x (flap weight) = station^this: the inner wing barely moves, the tip
## swings most, so the wing bends like an arm rather than hinging flat.
const WING_FLAP_CURVE: float = 1.6
## Body rings (x, half-width, top y, bottom y) nose to tail, then the nose and
## tail-tip x, and the tail fan (x of its end, half-width there).
const BODY_RINGS: Array[Vector4] = [
	Vector4(0.45, 0.075, 0.09, -0.07),
	Vector4(0.05, 0.11, 0.14, -0.12),
	Vector4(-0.35, 0.06, 0.07, -0.05),
]
const BODY_NOSE_X: float = 0.78
const BODY_TAIL_X: float = -0.5
const TAIL_FAN_END_X: float = -1.0
const TAIL_FAN_HALF_WIDTH: float = 0.22
## Per-bird flap-rate multiplier range.
const FLAP_RATE_MIN: float = 0.9
const FLAP_RATE_MAX: float = 1.12

class _Slot:
	extends RefCounted
	var first_index: int = 0
	var timer_s: float = 0.0
	var end_clock: float = 0.0
	var flying: bool = false
	var birds: int = 0
	var flight: FlockPlanner.Flight = null

var _instance: MultiMeshInstance3D = null
var _material: ShaderMaterial = null
var _theme: SkyThemeDef = null
var _slots: Array[_Slot] = []
var _per_slot: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _clock: float = 0.0


## Rebuilds the scheduler from `theme` (birds hidden when it has none or
## `enabled` is false). Safe to call repeatedly.
func configure(theme: SkyThemeDef, enabled: bool) -> void:
	if _instance != null:
		_instance.queue_free()
		_instance = null
	_material = null
	_slots.clear()
	_theme = null
	set_process(false)
	if theme == null or theme.bird_material == null or theme.bird_flock_count <= 0 or not enabled:
		visible = false
		return
	_material = theme.bird_material.duplicate() as ShaderMaterial
	if _material == null:
		visible = false
		return
	visible = true
	_theme = theme
	if theme.bird_seed == 0:
		_rng.randomize()
	else:
		_rng.seed = theme.bird_seed
	_clock = 0.0
	_material.set_shader_parameter(CLOCK_PARAMETER, _clock)
	_per_slot = maxi(maxi(theme.bird_flock_size_max, theme.bird_flock_size_min), 1)
	var multimesh: MultiMesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = build_bird_mesh()
	multimesh.instance_count = theme.bird_flock_count * _per_slot
	for index: int in range(multimesh.instance_count):
		_park(multimesh, index)
	for slot_index: int in range(theme.bird_flock_count):
		var slot: _Slot = _Slot.new()
		slot.first_index = slot_index * _per_slot
		slot.timer_s = _rng.randf_range(theme.bird_first_delay_min_s, maxf(theme.bird_first_delay_max_s, theme.bird_first_delay_min_s))
		_slots.append(slot)
	_instance = MultiMeshInstance3D.new()
	_instance.name = "Flocks"
	_instance.multimesh = multimesh
	_instance.material_override = _material
	add_to_group(WeatherFogShader.GROUP)
	WeatherFogShader.apply(_material)
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader moves vertices far from the instance origins, so the culling
	# box must cover the whole sky volume.
	var extent: float = theme.bird_path_radius_m + theme.bird_altitude_max_m + theme.bird_spacing_m * float(_per_slot)
	_instance.custom_aabb = AABB(Vector3(-extent, -extent, -extent), Vector3.ONE * extent * 2.0)
	add_child(_instance)
	set_process(true)


func _process(delta: float) -> void:
	advance(delta)


## Advances the flight clock and the launch/finish schedule by `delta` seconds
## (called by _process; tests call it directly).
func advance(delta: float) -> void:
	if _theme == null or _instance == null:
		return
	_clock += delta
	var any_flying: bool = false
	for slot: _Slot in _slots:
		if slot.flying:
			if _clock >= slot.end_clock:
				_finish(slot)
			else:
				any_flying = true
			continue
		slot.timer_s -= delta
		if slot.timer_s <= 0.0:
			_launch(slot)
			any_flying = true
	if any_flying:
		_material.set_shader_parameter(CLOCK_PARAMETER, _clock)


## Test/debug: launches slot `index` now (no-op while it is flying).
func launch_now(index: int) -> void:
	if index >= 0 and index < _slots.size() and not _slots[index].flying:
		_launch(_slots[index])
		_material.set_shader_parameter(CLOCK_PARAMETER, _clock)


func _launch(slot: _Slot) -> void:
	var count: int = FlockPlanner.pick_flock_size(_theme, _rng)
	count = mini(count, _per_slot)
	var flight: FlockPlanner.Flight = FlockPlanner.plan(_theme, _rng, count)
	var multimesh: MultiMesh = _instance.multimesh
	var flock_basis_velocity: Vector3 = flight.velocity
	for bird: int in range(_per_slot):
		var index: int = slot.first_index + bird
		if bird >= count:
			_park(multimesh, index)
			continue
		var basis: Basis = Basis(
			flock_basis_velocity,
			flight.offsets[bird],
			Vector3(flight.duration_s, flight.sway_m, flight.phase))
		multimesh.set_instance_transform(index, Transform3D(basis, flight.start))
		multimesh.set_instance_custom_data(index, Color(
			_clock, _rng.randf(), flight.size_m * _rng.randf_range(0.92, 1.08),
			_rng.randf_range(FLAP_RATE_MIN, FLAP_RATE_MAX)))
	slot.flying = true
	slot.birds = count
	slot.flight = flight
	slot.end_clock = _clock + flight.duration_s


func _finish(slot: _Slot) -> void:
	for bird: int in range(_per_slot):
		_park(_instance.multimesh, slot.first_index + bird)
	slot.flying = false
	slot.birds = 0
	slot.flight = null
	slot.timer_s = _rng.randf_range(_theme.bird_gap_min_s, maxf(_theme.bird_gap_max_s, _theme.bird_gap_min_s))


static func _park(multimesh: MultiMesh, index: int) -> void:
	multimesh.set_instance_transform(index, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	multimesh.set_instance_custom_data(index, Color(PARKED_START, 0.0, 1.0, 1.0))


## Bird silhouette: a spindle body with head and tail fan, and two swept,
## tapering wings that flap. UV.x = 0 on the body, rising to 1 at the wing tips
## (the shader flaps by UV.x). Double-sided in the shader, so winding is free.
static func build_bird_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var indices: PackedInt32Array = PackedInt32Array()
	# Body: rings of (top, bottom, left, right) plus nose and tail-tip points.
	var nose: int = _add_vertex(vertices, uvs, Vector3(BODY_NOSE_X, 0.0, 0.0), 0.0)
	var rings: Array[PackedInt32Array] = []
	for ring: Vector4 in BODY_RINGS:
		rings.append(PackedInt32Array([
			_add_vertex(vertices, uvs, Vector3(ring.x, ring.z, 0.0), 0.0),
			_add_vertex(vertices, uvs, Vector3(ring.x, ring.w, 0.0), 0.0),
			_add_vertex(vertices, uvs, Vector3(ring.x, 0.0, -ring.y), 0.0),
			_add_vertex(vertices, uvs, Vector3(ring.x, 0.0, ring.y), 0.0),
		]))
	var tail_tip: int = _add_vertex(vertices, uvs, Vector3(BODY_TAIL_X, 0.0, 0.0), 0.0)
	# Ring order around the body: top, left, bottom, right.
	var around: PackedInt32Array = PackedInt32Array([0, 2, 1, 3])
	for k: int in range(4):
		var a: int = around[k]
		var b: int = around[(k + 1) % 4]
		indices.append_array(PackedInt32Array([nose, rings[0][a], rings[0][b]]))
		for r: int in range(rings.size() - 1):
			_add_quad(indices, rings[r][a], rings[r][b], rings[r + 1][a], rings[r + 1][b])
		indices.append_array(PackedInt32Array([tail_tip, rings[rings.size() - 1][b], rings[rings.size() - 1][a]]))
	# Tail fan: flat, from the last ring's width out to the fan end.
	var last: Vector4 = BODY_RINGS[BODY_RINGS.size() - 1]
	var fan_root_l: int = _add_vertex(vertices, uvs, Vector3(last.x, 0.0, -last.y), 0.0)
	var fan_root_r: int = _add_vertex(vertices, uvs, Vector3(last.x, 0.0, last.y), 0.0)
	var fan_end_l: int = _add_vertex(vertices, uvs, Vector3(TAIL_FAN_END_X, 0.0, -TAIL_FAN_HALF_WIDTH), 0.0)
	var fan_end_r: int = _add_vertex(vertices, uvs, Vector3(TAIL_FAN_END_X, 0.0, TAIL_FAN_HALF_WIDTH), 0.0)
	_add_quad(indices, fan_root_l, fan_root_r, fan_end_l, fan_end_r)
	# Wings: a strip of quads per side; the root stations sit on the body.
	for side: float in [-1.0, 1.0]:
		var previous_lead: int = -1
		var previous_trail: int = -1
		for station: int in range(WING_STATIONS.size()):
			var t: float = WING_STATIONS[station]
			var flap: float = pow(t, WING_FLAP_CURVE)
			var z: float = side * t * HALF_SPAN
			var lead: int = _add_vertex(vertices, uvs, Vector3(WING_LEADING_X[station], 0.0, z), flap)
			var trail: int = _add_vertex(vertices, uvs, Vector3(WING_TRAILING_X[station], 0.0, z), flap)
			if previous_lead >= 0:
				_add_quad(indices, previous_lead, previous_trail, lead, trail)
			previous_lead = lead
			previous_trail = trail
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _add_vertex(vertices: PackedVector3Array, uvs: PackedVector2Array, at: Vector3, flap: float) -> int:
	vertices.append(at)
	uvs.append(Vector2(flap, 0.0))
	return vertices.size() - 1


## Quad a-b (one edge) to c-d (the next edge), as two triangles.
static func _add_quad(indices: PackedInt32Array, a: int, b: int, c: int, d: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c, b, d, c]))


## Weather fog changed (vfx/weather/WeatherFogShader.gd).
func refresh_weather_fog() -> void:
	if _instance != null:
		WeatherFogShader.apply(_instance.material_override as ShaderMaterial)


func flock_instance() -> MultiMeshInstance3D:
	return _instance


func flight_material() -> ShaderMaterial:
	return _material


func slot_count() -> int:
	return _slots.size()


## Flocks currently in flight.
func active_flock_count() -> int:
	var count: int = 0
	for slot: _Slot in _slots:
		if slot.flying:
			count += 1
	return count


## Birds in slot `index`'s current flight (0 when it is quiet).
func birds_in_slot(index: int) -> int:
	return _slots[index].birds if index >= 0 and index < _slots.size() else 0


## Slot `index`'s current flight, or null.
func flight_of(index: int) -> FlockPlanner.Flight:
	return _slots[index].flight if index >= 0 and index < _slots.size() else null


func flight_clock() -> float:
	return _clock
