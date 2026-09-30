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
const BODY_LENGTH_FRONT: float = 0.55
const BODY_LENGTH_BACK: float = 0.4
const WING_ROOT_X: float = 0.1
const WING_TIP_X: float = -0.25
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


## A flat V: nose, tail and two wing tips. UV.x = 0 on the body, 1 at the tips.
static func build_bird_mesh() -> ArrayMesh:
	var vertices: PackedVector3Array = PackedVector3Array([
		Vector3(BODY_LENGTH_FRONT, 0.0, 0.0),
		Vector3(-BODY_LENGTH_BACK, 0.0, 0.0),
		Vector3(WING_ROOT_X, 0.0, -HALF_SPAN),
		Vector3(WING_ROOT_X, 0.0, HALF_SPAN),
		Vector3(WING_TIP_X, 0.0, -HALF_SPAN),
		Vector3(WING_TIP_X, 0.0, HALF_SPAN),
	])
	var uvs: PackedVector2Array = PackedVector2Array([
		Vector2.ZERO, Vector2.ZERO, Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE,
	])
	# Left wing: nose-tip_root-tail; right wing mirrored. Tips use UV.x = 1.
	var indices: PackedInt32Array = PackedInt32Array([0, 2, 1, 0, 1, 3, 2, 4, 1, 3, 1, 5])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


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
